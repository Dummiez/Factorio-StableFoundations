-- control.lua
-- Dummiez 2026/04/01

require 'shared'

-- Declare constants
local ENTITIES_PER_TICK = SETTING.EntityRefreshCount or settings.startup["sf-entity-tick-count"].default_value
local ENEMY_FORCE = "enemy"
local PLAYER_FORCE = "player"
local SF_TEXT_SPEED = 1.6
local SF_TIME_TO_LIVE = 100
local SF_TEXT_COLOR = { r = 0.9, g = 0.9, b = 0.7, a = 0.9 }

local nextEntityIndex = nil

local tileReinforcementCache = {}
local instanceCache = {}
local EFFECT_KEYS = { "productivity", "efficiency", "speed" }

-- Add tiles to cache
for tileName, tileRate in pairs(SF_TILES) do
	tileReinforcementCache[tileName] = tileRate
end

-- Initialize global lists
local function initGlobalProperties()
	storage.sfEntity = storage.sfEntity or {}
	storage.sfHealth = storage.sfHealth or {}
	storage.reinforcedChunks = storage.reinforcedChunks or {}
	storage.bonusBeacons = storage.bonusBeacons or {}
end

-- Remove entity from global list
local function clearEntityTracking(entityUID)
	if storage.sfEntity then
		storage.sfEntity[entityUID] = nil
	end
	if storage.sfHealth then
		storage.sfHealth[entityUID] = nil
	end
end

-- Get tile data for reinforcing
local function getTileReinforcement(tileName)
	if not tileName then return nil end
	if tileReinforcementCache[tileName] ~= nil then
		return tileReinforcementCache[tileName]
	end

	for pattern, rate in pairs(tileReinforcementCache) do
		if string.find(tileName, pattern) then
			tileReinforcementCache[tileName] = rate
			return rate
		end
	end

	-- Cache negative result so this tile never pattern-matches again
	tileReinforcementCache[tileName] = false
	return nil
end

-- Clear all modules on a specific reinforced tile
local function removeAllModules(entity)
	local moduleInventory = entity.get_module_inventory()
	if not moduleInventory or moduleInventory.is_empty() then return end
	for i = 1, #moduleInventory do
		if moduleInventory[i].valid_for_read then
			moduleInventory[i].clear()
		end
	end
end

-- Function to remove bonuses from a structure
local function removeBuildingBonus(entity)
	if not entity.valid then return end
	local uid = entity.unit_number
	if storage.bonusBeacons and storage.bonusBeacons[uid] then
		local beacon = storage.bonusBeacons[uid]
		if beacon and beacon.valid then
			beacon.destroy()
		end
		storage.bonusBeacons[uid] = nil
	else
		-- Hard fallback: spatial search in case bonusBeacons entry was missing.
		-- This should rarely fire; if it fires often, bonusBeacons is going out of
		-- sync somewhere upstream and should be investigated.
		local hiddenBeacons = entity.surface.find_entities_filtered {
			name = "sf-tile-bonus",
			position = entity.position,
			radius = 0.9
		}
		if hiddenBeacons and #hiddenBeacons > 0 then
			for _, beacon in pairs(hiddenBeacons) do
				beacon.destroy()
			end
		end
	end
end

-- Function to apply bonuses to structures
local function applyBuildingBonus(surface, entity, tileType)
	if not entity.valid or not entity.prototype.allowed_effects then return end
	if tileType == nil then
		removeBuildingBonus(entity)
		return
	end

	local bonus = getTileReinforcement(tileType.name)
	if not bonus then return end

	local uid = entity.unit_number
	local beacon = storage.bonusBeacons and storage.bonusBeacons[uid]

	-- Validate cached beacon reference before trusting it
	if beacon and not beacon.valid then
		beacon = nil
		storage.bonusBeacons[uid] = nil
	end

	-- Fall back to spatial search only if cache missed
	if not beacon then
		local found = entity.surface.find_entities_filtered {
			name = "sf-tile-bonus",
			position = entity.position,
			radius = 0.9
		}
		beacon = found[1]
	end

	if bonus.tier then
		local moduleInventory = beacon and beacon.get_module_inventory()

		if not beacon then
			beacon = surface.create_entity {
				name = "sf-tile-bonus",
				position = entity.position,
				force = entity.force
			}
			beacon.destructible = false
			beacon.minable = false
			beacon.operable = false
			moduleInventory = beacon.get_module_inventory()
			storage.bonusBeacons[uid] = beacon
		else
			removeAllModules(beacon)
		end

		for _, key in ipairs(EFFECT_KEYS) do
			local moduleName = "sf-tile-module-" .. bonus.tier .. "-" .. key
			if prototypes.item[moduleName] then
				moduleInventory.insert({ name = moduleName, count = 1 })
			end
		end
	end
end

-- Invulnerability checking from game settings
local function toggleInvulnerabilities(entityBuilding, toggleValue)
	if not entityBuilding or not entityBuilding.valid then return false end
	local entityName = entityBuilding.name
	local entityType = entityBuilding.type

	if instanceCache[entityName] ~= nil then
		goto apply_toggle
	end

	if (SETTING.SafeRails and (entityType == "rail" or entityName:find("rail") or entityType == "rail-signal" or entityType == "rail-chain-signal"))
		or (SETTING.SafePoles and (entityName:find("big") and entityName:find("pole")))
		or (SETTING.SafeLights and (entityName:find("lamp") and entityBuilding.prototype.get_max_energy_usage() > 2)) then
		instanceCache[entityName] = entityType
	else
		return false
	end

	::apply_toggle::
	entityBuilding.destructible = toggleValue
	entityBuilding.health = not toggleValue and entityBuilding.max_health or entityBuilding.health
	return true
end

-- Whether to allow structure or unit reinforcement
local function canReinforceBuilding(entityBuilding)
	if not (entityBuilding and entityBuilding.valid and entityBuilding.destructible and entityBuilding.max_health > 0) then
		return false
	end

	local isPlayer = entityBuilding.type == "character"
	local isBuilding = entityBuilding.prototype.is_building
	local isWallEntity = entityBuilding.type == "wall" or entityBuilding.type == "gate"
		or entityBuilding.name:find("wall") or entityBuilding.name:find("gate")

	if isPlayer then
		return SETTING.ReinforcePlayers
	end

	if not entityBuilding.minable then
		return false
	end

	if not isBuilding then return SETTING.ReinforceUnits end
	if isWallEntity then return SETTING.ReinforceWalls end
	if entityBuilding.prototype.is_military_target then return SETTING.ReinforceMiltBuildings end

	return isBuilding
end

-- Chunk indexing for faster damage-event filtering
local function markChunkReinforced(surface, position)
	if not surface or not position then return end
	if not storage.reinforcedChunks then initGlobalProperties() end
	local chunkX = math.floor(position.x / 32)
	local chunkY = math.floor(position.y / 32)
	storage.reinforcedChunks[surface.index] = storage.reinforcedChunks[surface.index] or {}
	storage.reinforcedChunks[surface.index][chunkX .. "," .. chunkY] = true
end

local function unmarkChunkIfEmpty(surface, position)
	if not surface or not position or not storage.reinforcedChunks then return end
	local chunkX = math.floor(position.x / 32)
	local chunkY = math.floor(position.y / 32)
	local chunkKey = chunkX .. "," .. chunkY
	if not (storage.reinforcedChunks[surface.index] and storage.reinforcedChunks[surface.index][chunkKey]) then return end

	local area = {
		{ chunkX * 32, chunkY * 32 },
		{ chunkX * 32 + 32, chunkY * 32 + 32 }
	}
	local tilesInChunk = surface.find_tiles_filtered({ area = area })
	for _, tile in pairs(tilesInChunk) do
		if getTileReinforcement(tile.name) then
			return
		end
	end
	storage.reinforcedChunks[surface.index][chunkKey] = nil
end

local function isChunkReinforced(surface, position)
	if not surface or not position or not storage.reinforcedChunks then return false end
	local chunkX = math.floor(position.x / 32)
	local chunkY = math.floor(position.y / 32)
	return storage.reinforcedChunks[surface.index] and
		storage.reinforcedChunks[surface.index][chunkX .. "," .. chunkY] or false
end

local function showPopupText(entityUser, entityBuilding, caption)
	if SETTING.ReinforcePopupToggle and entityUser.force and entityUser.force.players then else return end
	for _, player in pairs(entityUser.force.players) do
		if player and player.valid and player.character and entityBuilding.last_user and entityBuilding.surface == player.surface then
			player.create_local_flying_text {
				text = caption,
				position = entityBuilding.position,
				create_at_cursor = false,
				speed = SF_TEXT_SPEED,
				time_to_live = SF_TIME_TO_LIVE,
				color = SF_TEXT_COLOR,
			}
		end
	end
end

-- Check if structure matches checks, also display popup text
local function getMatchingBuilding(entityUser, entityBuilding, tileType)
	if not entityUser or not entityBuilding or not entityBuilding.valid or not tileType then return end
	if not (canReinforceBuilding(entityBuilding) and entityBuilding.force == entityUser.force) then return end

	local tileRate = getTileReinforcement(tileType.name)
	if not tileRate then return end

	local uid = entityBuilding.unit_number
	local existing = storage.sfEntity[uid]
	local isNewReinforcement = not existing or (existing.tileRate ~= tileRate)

	storage.sfEntity[uid] = { entity = entityBuilding, tileRate = tileRate }
	if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.max_health then
		storage.sfHealth[uid] = entityBuilding.health
	end

	markChunkReinforced(entityBuilding.surface, entityBuilding.position)
	local invCaption = toggleInvulnerabilities(entityBuilding, false)

	if isNewReinforcement then
		showPopupText(entityUser, entityBuilding, not invCaption and
			{ "",
				entityBuilding.localised_name or { "entity-name." .. entityBuilding.name },
				" ", { "sf-mod.reinforced-with" }, " ", tileType.localised_name or { "entity-name." .. tileType.name },
				" (" .. (entityBuilding.quality.level > 0 and
					tileRate.percent + (entityBuilding.quality.level * SETTING.ReinforceQuality) .. "%)" or
					tileRate.percent .. "%)") }
			or
			{ "",
				entityBuilding.localised_name or { "entity-name." .. entityBuilding.name },
				" ", { "sf-mod.reinforced" } })
	end
end

-- Compute integer bounding box coords from entity, returns left, top, right, bottom, width, height
-- NOTE: Epsilon offsets (+0.1 / -0.1) strip Factorio's fractional bounding box padding (usually ±0.4).
local function getBoundingBox(entityBuilding)
	local box = entityBuilding.bounding_box
	local left = math.floor(box.left_top.x + 0.1)
	local top = math.floor(box.left_top.y + 0.1)
	local right = math.ceil(box.right_bottom.x - 0.1)
	local bottom = math.ceil(box.right_bottom.y - 0.1)
	return left, top, right, bottom, right - left, bottom - top
end

-- Shared tighter tile search area.
-- Keeping this in one place prevents tile-built and script-set-tiles from drifting apart again.
local function getTileSearchArea(position)
	return {
		{ position.x, position.y },
		{ position.x + 1, position.y + 1 }
	}
end

-- Returns true if every tile under the entity's footprint matches tileType.
-- For 1x1 entities the tile is already known (cheapPath=true skips count_tiles_filtered).
local function isFootprintUniform(surface, entityBuilding, tileType, cheapPath)
	if not tileType then return false end

	if cheapPath then
		return getTileReinforcement(tileType.name) ~= nil
	end

	local left, top, right, bottom, w, h = getBoundingBox(entityBuilding)
	local expectedArea = w * h
	if expectedArea <= 0 then return false end

	local tileCount = surface.count_tiles_filtered {
		area = { { left, top }, { right, bottom } },
		name = tileType.name
	}
	return tileCount == expectedArea
end

-- Returns the reinforced tile prototype only if the entire footprint is uniformly covered.
local function getUniformReinforcedTile(surface, entityBuilding)
	if not (surface and entityBuilding and entityBuilding.valid) then return nil end

	local left, top, _, _, w, h = getBoundingBox(entityBuilding)
	if w <= 0 or h <= 0 then return nil end

	if w == 1 and h == 1 then
		local centerTile = surface.get_tile({
			math.floor(entityBuilding.position.x),
			math.floor(entityBuilding.position.y)
		}).prototype
		return getTileReinforcement(centerTile.name) and centerTile or nil
	end

	local candidateTile = surface.get_tile({ left, top }).prototype
	if not candidateTile or not getTileReinforcement(candidateTile.name) then
		return nil
	end

	return isFootprintUniform(surface, entityBuilding, candidateTile, false) and candidateTile or nil
end

local function clearBuildingReinforcement(surface, entityBuilding)
	if not (surface and entityBuilding and entityBuilding.valid and entityBuilding.unit_number) then return end

	local pos = entityBuilding.position

	clearEntityTracking(entityBuilding.unit_number)
	toggleInvulnerabilities(entityBuilding, true)
	applyBuildingBonus(surface, entityBuilding, nil)

	-- Use the cached position here
	unmarkChunkIfEmpty(surface, pos)
end

-- Check if structure is reinforced and apply appropriate changes
local function entityStructureReinforced(entityUser, tileList, tileType)
	if not entityUser or not entityUser.surface then return end
	local mainSurface = entityUser.surface

	-- Single entity placement / clone / revive
	if tileList == nil then
		local entityBuilding = tileType
		local reinforcedTile = getUniformReinforcedTile(mainSurface, entityBuilding)

		if reinforcedTile then
			getMatchingBuilding(entityUser, entityBuilding, reinforcedTile)
			applyBuildingBonus(mainSurface, entityBuilding, reinforcedTile)
		else
			clearBuildingReinforcement(mainSurface, entityBuilding)
		end
		return
	end

	local uniqueBuildings = {}

	for _, eventTile in ipairs(tileList) do
		local findEntityArea = getTileSearchArea(eventTile.position)
		for _, entityBuilding in pairs(mainSurface.find_entities(findEntityArea)) do
			if entityBuilding.valid and entityBuilding.unit_number then
				uniqueBuildings[entityBuilding.unit_number] = entityBuilding
			end
		end
	end

	for _, entityBuilding in pairs(uniqueBuildings) do
		-- Added canReinforceBuilding check so we ignore invisible beacons, items on belts, etc.
		if entityBuilding.valid and canReinforceBuilding(entityBuilding) then
			local reinforcedTile = getUniformReinforcedTile(mainSurface, entityBuilding)
			if reinforcedTile then
				getMatchingBuilding(entityUser, entityBuilding, reinforcedTile)
				applyBuildingBonus(mainSurface, entityBuilding, reinforcedTile)
			else
				clearBuildingReinforcement(mainSurface, entityBuilding)
			end
		end
	end
end

local function getQualityDamageReduction(entityBuilding)
	if not entityBuilding.quality then return 0 end
	local quality_level = entityBuilding.quality.level or 0
	return quality_level * SETTING.ReinforceQuality
end

-- Recalculate damage on foundations
local function entityStructureDamaged(entityBuilding, attackingEntity, attackingForce, finalDamage, finalHealth, damageType)
	if not (entityBuilding and entityBuilding.valid and finalDamage > 0 and entityBuilding.surface and entityBuilding.position) then return end
	if not isChunkReinforced(entityBuilding.surface, entityBuilding.position) then return end
	if not canReinforceBuilding(entityBuilding) or not entityBuilding.force.name:find(PLAYER_FORCE) then return end

	local tileRate = nil
	local entityUID = entityBuilding.unit_number

	if entityBuilding.prototype.is_building then
		if not entityUID then return end
		local entityData = storage.sfEntity[entityUID]
		tileRate = entityData and entityData.tileRate
		if not tileRate then return end
	else
		-- Moving units live-check
		local buildTileType = entityBuilding.surface.get_tile(entityBuilding.position)
		if not buildTileType then return end
		tileRate = getTileReinforcement(buildTileType.name)

		if not tileRate then return end

		if not entityUID then
			if entityBuilding.type == "character" and entityBuilding.player then
				entityUID = "player_" .. entityBuilding.player.name
			else
				entityUID = "moving_" .. math.floor(entityBuilding.position.x) .. "_" .. math.floor(entityBuilding.position.y)
			end
		end
	end

	-- Ensure entity enters sfHealth tracking the first time it takes damage
	if not storage.sfHealth[entityUID] then
		-- Use the post-hit health + damage to accurately seed the first hit,
		if finalHealth > 0 then
			storage.sfHealth[entityUID] = finalHealth + finalDamage
		else
			storage.sfHealth[entityUID] = entityBuilding.max_health
		end
	end

	toggleInvulnerabilities(entityBuilding, false)
	if not entityBuilding.destructible then return end

	local tileReducePercent = tileRate.percent
	local tileReduceFlat = tileRate.flat
	local effectReduce = 1

	local qualityReducePercent = getQualityDamageReduction(entityBuilding)
	local totalReducePercent = tileReducePercent + qualityReducePercent

	if (attackingForce == entityBuilding.force) and attackingEntity then
		if not SETTING.FriendlyDamageReduction then
			tileReduceFlat = 0
			totalReducePercent = 0
		end
		effectReduce = (damageType == "explosion" and SETTING.FriendlyExplosionDamage / 100
			or damageType == "impact" and SETTING.FriendlyImpactDamage / 100
			or damageType == "physical" and SETTING.FriendlyPhysicalDamage / 100 or effectReduce)
	end

	if totalReducePercent > 100 then totalReducePercent = 100 end

	local finalFlatDamage = (finalDamage - tileReduceFlat) > 0 and (finalDamage - tileReduceFlat) or
		1 / (tileReduceFlat - finalDamage + 2)
	local mitigatedDamage = (finalFlatDamage * effectReduce) * (1 - (totalReducePercent / 100))

	-- Use the safely cached pre-hit health
	local preHealth = storage.sfHealth[entityUID]
	local updatedHealth = preHealth - mitigatedDamage

	if updatedHealth > 0 then
		entityBuilding.health = updatedHealth
		if updatedHealth >= entityBuilding.max_health then
			storage.sfHealth[entityUID] = nil
		else
			storage.sfHealth[entityUID] = updatedHealth
		end
	else
		entityBuilding.health = 0
		storage.sfHealth[entityUID] = nil
	end
end

-- Clear entity stuff when buildings or units are destroyed or mined
local function entityStructureDestroyed(entityBuilding)
	if entityBuilding and entityBuilding.valid and entityBuilding.unit_number then
		clearEntityTracking(entityBuilding.unit_number)
		removeBuildingBonus(entityBuilding)
	end
end

-- Fired when another mod changes tiles via raise_script_set_tiles
local function handleScriptSetTiles(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end
	if not (event.tiles and #event.tiles > 0) then return end

	for _, tile in ipairs(event.tiles) do
		local tileProto = surface.get_tile(tile.position).prototype
		if tileProto and getTileReinforcement(tileProto.name) then
			markChunkReinforced(surface, tile.position)
		else
			-- If it was overwritten with a normal tile, check if we need to unmark
			unmarkChunkIfEmpty(surface, tile.position)
		end
	end

	local uniqueBuildings = {}

	for _, tile in ipairs(event.tiles) do
		local findArea = getTileSearchArea(tile.position)
		for _, entityBuilding in pairs(surface.find_entities(findArea)) do
			if entityBuilding.valid and entityBuilding.unit_number then
				uniqueBuildings[entityBuilding.unit_number] = entityBuilding
			end
		end
	end

	for _, entityBuilding in pairs(uniqueBuildings) do
		if entityBuilding.valid and canReinforceBuilding(entityBuilding) then
			local user = { surface = surface, force = entityBuilding.force }
			local reinforcedTile = getUniformReinforcedTile(surface, entityBuilding)

			if reinforcedTile then
				getMatchingBuilding(user, entityBuilding, reinforcedTile)
				applyBuildingBonus(surface, entityBuilding, reinforcedTile)
			else
				clearBuildingReinforcement(surface, entityBuilding)
			end
		end
	end
end

-- Iterate through tracked entities to sync health and remove stale entries
local function periodicEntityCheck()
	if not storage.sfHealth then
		initGlobalProperties()
		return
	end

	local count = 0
	local currentIndex = nextEntityIndex
	local entitiesToRemove = {}

	if currentIndex and not storage.sfHealth[currentIndex] then
		currentIndex = nil
	end

	while count < ENTITIES_PER_TICK do
		local storedHealth
		currentIndex, storedHealth = next(storage.sfHealth, currentIndex)
		if not currentIndex then
			nextEntityIndex = nil
			break
		end

		if type(storedHealth) == "number" then
			local entityData = storage.sfEntity[currentIndex]
			if not entityData then
				table.insert(entitiesToRemove, currentIndex)
			else
				local entity = entityData.entity
				if not entity or not entity.valid then
					table.insert(entitiesToRemove, currentIndex)
				else
					local health = entity.health
					local maxHealth = entity.max_health
					if health == maxHealth or health == 0 then
						table.insert(entitiesToRemove, currentIndex)
					elseif entity.minable and health ~= storedHealth then
						if health >= maxHealth then
							table.insert(entitiesToRemove, currentIndex)
						else
							storage.sfHealth[currentIndex] = health
						end
					end
				end
			end
		else
			table.insert(entitiesToRemove, currentIndex)
		end

		count = count + 1
	end

	if currentIndex then
		nextEntityIndex = currentIndex
	end

	for _, entityUID in ipairs(entitiesToRemove) do
		storage.sfHealth[entityUID] = nil
	end
end

-- Event handlers
script.on_init(initGlobalProperties)

-- Resolves the acting user across all build sources, including
-- script-raised events and cloning which carry no player/robot
local function handleEntityBuilt(event)
	local entity = event.destination_entity or event.entity
	if not (entity and entity.valid) then return end

	local user = (event.player_index and game.players[event.player_index])
		or event.robot
		or { surface = entity.surface, force = entity.force }

	entityStructureReinforced(user, nil, entity)
end

for _, eventName in pairs({
	"on_built_entity",
	"on_robot_built_entity",
	"on_entity_cloned",
	"script_raised_built",
	"script_raised_revive",
}) do
	script.on_event(defines.events[eventName], handleEntityBuilt)
end

local function handleEntityRemoved(event)
	if event.entity then
		entityStructureDestroyed(event.entity)
	end
end

for _, eventName in pairs({
	"on_entity_died",
	"on_player_mined_entity",
	"on_robot_mined_entity",
	"script_raised_destroy",
}) do
	script.on_event(defines.events[eventName], handleEntityRemoved)
end

script.on_event(defines.events.on_entity_damaged, function(event)
	entityStructureDamaged(
		event.entity,
		event.cause,
		event.force,
		event.final_damage_amount,
		event.final_health,
		event.damage_type.name
	)
end)

local function handleTileBuilt(event)
	local user = (event.player_index and game.players[event.player_index]) or event.robot
	local surface = user and user.surface

	if surface and event.tile and getTileReinforcement(event.tile.name) then
		for _, tile in ipairs(event.tiles) do
			markChunkReinforced(surface, tile.position)
		end
	end

	entityStructureReinforced(user, event.tiles, event.tile)
end

for _, eventName in pairs({
	"on_player_built_tile",
	"on_robot_built_tile",
}) do
	script.on_event(defines.events[eventName], handleTileBuilt)
end

local function handleTileMined(event)
	local user = (event.player_index and game.players[event.player_index]) or event.robot
	entityStructureReinforced(user, event.tiles, nil)

	if user and user.surface then
		for _, tile in ipairs(event.tiles) do
			unmarkChunkIfEmpty(user.surface, tile.position)
		end
	end
end

for _, eventName in pairs({
	"on_player_mined_tile",
	"on_robot_mined_tile",
}) do
	script.on_event(defines.events[eventName], handleTileMined)
end

script.on_event(defines.events.script_raised_set_tiles, handleScriptSetTiles)

-- Periodic check & config
script.on_nth_tick(SETTING.EntityTickRefresh, periodicEntityCheck)

script.on_configuration_changed(function(data)
	local changes = data.mod_changes and data.mod_changes["StableFoundations"]
	if not changes then return end

	if storage.sfHealth then
		for uid, value in pairs(storage.sfHealth) do
			if type(value) ~= "number" then
				storage.sfHealth[uid] = nil
			end
		end
	end

	if storage.sfEntity then
		for uid, value in pairs(storage.sfEntity) do
			if type(value) ~= "table" or not value.entity or not value.tileRate then
				storage.sfEntity[uid] = nil
			end
		end
	end

	-- Wipe the tile reinforcement cache on config change.
	tileReinforcementCache = {}
	for tileName, tileRate in pairs(SF_TILES) do
		tileReinforcementCache[tileName] = tileRate
	end

	-- Re-resolve existing tracked entities against current tile coverage.
	if storage.sfEntity then
		for uid, data in pairs(storage.sfEntity) do
			local entity = data.entity
			if entity and entity.valid then
				local reinforcedTile = getUniformReinforcedTile(entity.surface, entity)
				if reinforcedTile then
					local tileRate = getTileReinforcement(reinforcedTile.name)
					if tileRate then
						data.tileRate = tileRate
						applyBuildingBonus(entity.surface, entity, reinforcedTile)
					else
						clearBuildingReinforcement(entity.surface, entity)
					end
				else
					clearBuildingReinforcement(entity.surface, entity)
				end
			else
				storage.sfEntity[uid] = nil
			end
		end
	end
end)
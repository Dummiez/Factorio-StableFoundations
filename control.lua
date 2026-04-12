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
	-- Direct cache hit
	if tileReinforcementCache[tileName] ~= nil then
		return tileReinforcementCache[tileName]
	end
	-- Fall back to pattern matching for modded tile names, then cache the result
	for pattern, rate in pairs(tileReinforcementCache) do
		if string.find(tileName, pattern) then
			tileReinforcementCache[tileName] = rate
			return rate
		end
	end
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
		local hiddenBeacons = entity.surface.find_entities_filtered { name = "sf-tile-bonus", position = entity.position, radius = 0.9 }
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
        local found = entity.surface.find_entities_filtered { name = "sf-tile-bonus", position = entity.position, radius = 0.9 }
        beacon = found[1]
    end

    if bonus.tier then
        local moduleInventory = beacon and beacon.get_module_inventory()

        -- Create beacon if it doesn't exist yet
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
            -- Beacon already exists — clear old modules before reinserting
            removeAllModules(beacon)
        end

        -- Insert one module per effect type (only if non-zero)
        local effectKeys = { "productivity", "efficiency", "speed" }
        for _, key in ipairs(effectKeys) do
            local moduleName = "sf-tile-module-" .. bonus.tier .. "-" .. key
            -- prototypes check ensures we don't insert a module that wasn't created
            -- (data-final-fixes skips zero-value modules, so they won't exist in prototypes)
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
	if instanceCache[entityName] ~= nil then goto apply_toggle end
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
	if not (entityBuilding and entityBuilding.valid and entityBuilding.minable and entityBuilding.destructible and entityBuilding.unit_number and entityBuilding.max_health > 0) then
		return false
	end

	local isPlayer = entityBuilding.type == "character"
	local isBuilding = entityBuilding.prototype.is_building
	local isWallEntity = entityBuilding.type == "wall" or entityBuilding.type == "gate"
		or entityBuilding.name:find("wall") or entityBuilding.name:find("gate")

	if isPlayer then return SETTING.ReinforcePlayers end
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

	-- Scan all tiles in the chunk and check each against the reinforcement cache
	local area = {
		{ chunkX * 32, chunkY * 32 },
		{ chunkX * 32 + 32, chunkY * 32 + 32 }
	}
	local tilesInChunk = surface.find_tiles_filtered({ area = area })
	for _, tile in pairs(tilesInChunk) do
		if getTileReinforcement(tile.name) then
			return -- At least one reinforced tile remains
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
    storage.sfEntity[uid] = { entity = entityBuilding, tileRate = tileRate }
    if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.max_health then
        storage.sfHealth[uid] = entityBuilding.health
    end

    markChunkReinforced(entityBuilding.surface, entityBuilding.position)
    local invCaption = toggleInvulnerabilities(entityBuilding, false)
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

-- Check if structure is reinforced and apply appropriate changes
local function entityStructureReinforced(entityUser, tileList, tileType)
	if not entityUser or not entityUser.surface then return end
	local mainSurface = entityUser.surface

	if tileList == nil then
		local entityBuilding = tileType
		tileType = mainSurface.get_tile({ math.floor(tileType.position.x), math.floor(tileType.position.y) }).prototype
		getMatchingBuilding(entityUser, entityBuilding, tileType)
		applyBuildingBonus(mainSurface, entityBuilding, tileType)
		return
	end
	for _, eventTile in pairs(tileList) do
		local findEntityArea = { { eventTile.position.x, eventTile.position.y}, { eventTile.position.x, eventTile.position.y } }
		local areaBuilding = mainSurface.find_entities(findEntityArea)
		local eventTileX = math.floor(eventTile.position.x)
		local eventTileY = math.floor(eventTile.position.y)
		local searchTileX = 0
		local searchTileY = 0
		local TileMismatch = false

		for _, entityBuilding in pairs(areaBuilding) do
			if entityBuilding.valid then
				TileMismatch = false
				-- Ensure that the entire bounding box is covered uniformly. If not, remove building bonuses.
				for searchTileX=math.floor(entityBuilding.bounding_box.left_top.x),math.floor(entityBuilding.bounding_box.right_bottom.x) do
					for searchTileY=math.floor(entityBuilding.bounding_box.left_top.y),math.floor(entityBuilding.bounding_box.right_bottom.y) do
						if tileType ~= mainSurface.get_tile({ searchTileX, searchTileY }).prototype then
							TileMismatch = true
							break
						end
					end
					if TileMismatch then
						break
					end
				end

				-- If everything checks out, apply the proper bonus. If not, remove building bonuses.
				if TileMismatch then
					getMatchingBuilding(entityUser, entityBuilding, nil)
					applyBuildingBonus(mainSurface, entityBuilding, nil)
				else
					getMatchingBuilding(entityUser, entityBuilding, tileType)
					applyBuildingBonus(mainSurface, entityBuilding, tileType)
                end
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

    local entityUID = entityBuilding.unit_number
    if not entityUID or not canReinforceBuilding(entityBuilding) or not entityBuilding.force.name:find(PLAYER_FORCE) then return end

    local entityData = storage.sfEntity[entityUID]
    local tileRate = entityData and entityData.tileRate
    if not tileRate then
        local buildTileType = entityBuilding.surface.get_tile(entityBuilding.position)
        if not buildTileType then return end
        tileRate = getTileReinforcement(buildTileType.name)
        if not tileRate then return end
        storage.sfEntity[entityUID] = { entity = entityBuilding, tileRate = tileRate }
    end

    -- Ensure entity enters sfHealth tracking the first time it takes damage
    if not storage.sfHealth[entityUID] then
        storage.sfHealth[entityUID] = entityBuilding.max_health
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

    local preHealth = storage.sfHealth[entityUID]
    local updatedHealth = (preHealth - mitigatedDamage) > 0 and (preHealth - mitigatedDamage) or 0

    entityBuilding.health = updatedHealth

    if updatedHealth <= 0 or updatedHealth >= entityBuilding.max_health then
        storage.sfHealth[entityUID] = nil  -- Remove from damaged tracking, sfEntity stays intact
    else
        storage.sfHealth[entityUID] = updatedHealth
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

    for _, tile in pairs(event.tiles) do
        local tileProto = surface.get_tile(tile.position).prototype
        if tileProto then
            local findArea = {
                { tile.position.x - 1, tile.position.y - 1 },
                { tile.position.x + 1, tile.position.y + 1 }
            }
            for _, entityBuilding in pairs(surface.find_entities(findArea)) do
                if entityBuilding.valid then
                    local bx = math.floor(entityBuilding.position.x)
                    local by = math.floor(entityBuilding.position.y)
                    if bx == math.floor(tile.position.x) and by == math.floor(tile.position.y) then
                        -- Fix: resolve force per-entity so the force check in getMatchingBuilding passes
                        local user = { surface = surface, force = entityBuilding.force }
                        getMatchingBuilding(user, entityBuilding, tileProto)
                        applyBuildingBonus(surface, entityBuilding, tileProto)
                    end
                end
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
    local entity = event.destination_entity or event.entity  -- on_entity_cloned uses destination_entity
    if not (entity and entity.valid) then return end

    -- script-raised events so entityStructureReinforced still has a .surface
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

-- script_raised_destroy carries no actor; entity is all we need
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

    -- Unmark chunks that no longer contain any reinforced tiles.
    if user and user.surface then
        for _, tile in pairs(event.tiles) do
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
end)

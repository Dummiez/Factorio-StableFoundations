-- control.lua
-- Dummiez 2024/06/27

require 'shared'

-- Declare constants
local ENTITIES_PER_TICK = SETTING.EntityRefreshCount or settings.startup["sf-entity-tick-count"].default_value
local ENEMY_FORCE = "enemy"
local PLAYER_FORCE = "player"
local SF_TEXT_SPEED = 0.8
local SF_TIME_TO_LIVE = 50
local SF_TEXT_COLOR = { r = 0.5, g = 0.8, b = 0.5, a = 0.8 }

local nextEntityIndex = nil

local tileReinforcementCache = {}
local instanceCache = {}

-- Add tiles to cache
for tileName, tileRate in pairs(SF_TILES) do
	tileReinforcementCache[tileName] = tileRate
end

-- local entityMetatable = {
-- 	__index = function(t, k)
-- 		if k == "health" then
-- 			return t.entity.valid and t.entity.health or 0
-- 		end
-- 	end
-- }

-- Initialize global lists
local function initGlobalProperties()
	global.sfEntity = global.sfEntity or {}
	global.sfHealth = global.sfHealth or {}
	global.reinforcedChunks = global.reinforcedChunks or {}
	global.bonusBeacons = global.bonusBeacons or {}
end

-- Remove entity from global list
local function clearEntityTracking(entityUID)
	if global.sfEntity then
		global.sfEntity[entityUID] = nil
	end
	if global.sfHealth then
		global.sfHealth[entityUID] = nil
	end
end

-- Get tile data for reinforcing
local function getTileReinforcement(tileName)
	if not tileName then return nil end
	-- Internal name checking
	if tileReinforcementCache[tileName] ~= nil then
		return tileReinforcementCache[tileName]
	end
	-- No internal name in cache?
	for pattern, rate in pairs(tileReinforcementCache) do
		if string.find(tileName, pattern) then
			-- cache this result
			tileReinforcementCache[tileName] = rate
			return rate
		end
	end
	return nil
end

-- Clear all modules on a specific reinforced tile
local function removeAllModules(entity)
	local moduleInventory = entity.get_module_inventory()
	if moduleInventory and not moduleInventory.is_empty() then else return end
	for i = 1, #moduleInventory do
		if moduleInventory[i].valid_for_read then
			moduleInventory[i].clear()
		end
	end
end

-- Function to remove bonuses from a structure
local function removeBuildingBonus(entity)
	if not entity.valid then return end
	if global.bonusBeacons and global.bonusBeacons[entity.unit_number] then
		local beacon = global.bonusBeacons[entity.unit_number]
		if beacon and beacon.valid then
			beacon.destroy()
		end
		global.bonusBeacons[entity.unit_number] = nil
	else -- Hard remove in case no beacons were found
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
	local hiddenBeacons = entity.surface.find_entities_filtered { name = "sf-tile-bonus", position = entity.position, radius = 0.9 }
	local beacon = hiddenBeacons[1]
	-- Create ephemeral beacon to give buff to building on foundation
	if not beacon and bonus.tier then
		beacon = surface.create_entity {
			name = "sf-tile-bonus",
			position = entity.position,
			force = entity.force
		}
		beacon.destructible = false
		beacon.minable = false
		beacon.operable = false
		beacon.get_module_inventory().insert({ name = "sf-tile-module-" .. bonus.tier, count = 1 })
		global.bonusBeacons[entity.unit_number] = beacon
	elseif beacon and bonus.tier then
		removeAllModules(beacon) --beacon.get_module_inventory().remove({ name = "sf-tile-module-".. })
		beacon.get_module_inventory().insert({ name = "sf-tile-module-" .. bonus.tier, count = 1 })
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
		or (SETTING.SafeLights and (entityName:find("lamp") and entityBuilding.prototype.max_energy_usage > 2)) then
		instanceCache[entityName] = entityType
	else 
		return false
	end
	::apply_toggle::
	entityBuilding.destructible = toggleValue
	entityBuilding.health = not toggleValue and entityBuilding.prototype.max_health or entityBuilding.health
	return true
end

-- Whether to allow structure or unit reinforcement
local function canReinforceBuilding(entityBuilding)
	if not (entityBuilding and entityBuilding.valid and entityBuilding.minable and entityBuilding.destructible and entityBuilding.unit_number and entityBuilding.prototype.max_health > 0) then
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

-- Chunk indexing for faster comparison
local function markChunkReinforced(surface, position)
	if not surface or not position then return end
	if not global.reinforcedChunks then initGlobalProperties() end
	local chunkPos = { x = math.floor(position.x / 32), y = math.floor(position.y / 32) }
	global.reinforcedChunks[surface.index] = global.reinforcedChunks[surface.index] or {}
	global.reinforcedChunks[surface.index][chunkPos.x .. "," .. chunkPos.y] = true
end

local function isChunkReinforced(surface, position)
	if not surface or not position or not global.reinforcedChunks then return false end
	local chunkPos = { x = math.floor(position.x / 32), y = math.floor(position.y / 32) }
	return global.reinforcedChunks[surface.index] and
		global.reinforcedChunks[surface.index][chunkPos.x .. "," .. chunkPos.y] or false
end

local function showPopupText(entityUser, entityBuilding, caption)
	if SETTING.ReinforcePopupToggle and entityUser.force and entityUser.force.players then else return end
	for _, player in pairs(entityUser.force.players) do
		if player and player.valid and player.character and entityBuilding.last_user then
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
	if not (canReinforceBuilding(entityBuilding) and entityBuilding.force == entityUser.force) then return end -- todo: needs work
	local tileRate = getTileReinforcement(tileType.name)
	if not tileRate then return end
	if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.prototype.max_health then
		global.sfHealth[entityBuilding.unit_number] = entityBuilding.health
		global.sfEntity[entityBuilding.unit_number] = entityBuilding
		--setmetatable({ entity = entityBuilding }, entityMetatable)
	end
	markChunkReinforced(entityBuilding.surface, entityBuilding.position)
	local invCaption = toggleInvulnerabilities(entityBuilding, false)
	showPopupText(entityUser, entityBuilding, not invCaption and
	{ "", entityBuilding.localised_name or ("entity-name." .. entityBuilding.name),
		" reinforced with ", tileType.localised_name or ("entity-name." .. tileType.name),
		" (" .. tileRate.percent .. "%)" } or
	{ "", entityBuilding.localised_name or ("entity-name." .. entityBuilding.name),
		" reinforced. " })
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
		local findEntityArea = { { eventTile.position.x - 1, eventTile.position.y - 1 }, { eventTile.position.x + 1, eventTile.position.y + 1 } }
		local areaBuilding = mainSurface.find_entities(findEntityArea)
		local eventTileX = math.floor(eventTile.position.x)
		local eventTileY = math.floor(eventTile.position.y)

		for _, entityBuilding in pairs(areaBuilding) do
		    if entityBuilding.valid then
		        local buildPositionX = math.floor(entityBuilding.position.x)
		        local buildPositionY = math.floor(entityBuilding.position.y)
		        if (eventTileX == buildPositionX) and (eventTileY == buildPositionY) then
		            getMatchingBuilding(entityUser, entityBuilding, tileType)
		            applyBuildingBonus(mainSurface, entityBuilding, tileType)
		        end
		    end
		end
	end
end

-- Recalculate damage on foundations
local function entityStructureDamaged(entityBuilding, attackingEntity, attackingForce, finalDamage, finalHealth,
									  damageType)
	if not (entityBuilding and entityBuilding.valid and finalDamage > 0 and entityBuilding.surface and entityBuilding.position) then return end
	if not isChunkReinforced(entityBuilding.surface, entityBuilding.position) then return end

	local entityUID = entityBuilding.unit_number
	if not entityUID or not canReinforceBuilding(entityBuilding) or not entityBuilding.force.name:find(PLAYER_FORCE) then return end

	local buildTileType = entityBuilding.surface.get_tile(entityBuilding.position)
	if not buildTileType then return end

	local tileRate = getTileReinforcement(buildTileType.name)
	if not tileRate then return end

	toggleInvulnerabilities(entityBuilding, false)
	if not entityBuilding.destructible then return end

	local tileReducePercent = tileRate.percent
	local tileReduceFlat = tileRate.flat
	local effectReduce = 1

	if (attackingForce == entityBuilding.force) and attackingEntity then
		if not SETTING.FriendlyDamageReduction then
			tileReduceFlat = 0
			tileReducePercent = 0
		end
		effectReduce = (damageType == "explosion" and SETTING.FriendlyExplosionDamage / 100
			or damageType == "impact" and SETTING.FriendlyImpactDamage / 100
			or damageType == "physical" and SETTING.FriendlyPhysicalDamage / 100 or effectReduce)
	end
	local finalFlatDamage = (finalDamage - tileReduceFlat) > 0 and (finalDamage - tileReduceFlat) or
		1 / (tileReduceFlat - finalDamage + 2)
	local mitigatedDamage = (finalFlatDamage * effectReduce) * (1 - (tileReducePercent / 100))
	local entityData = global.sfEntity[entityUID]
	if not entityData then -- Unlogged entity, index it
		global.sfHealth[entityBuilding.unit_number] = entityBuilding.prototype.max_health
		global.sfEntity[entityBuilding.unit_number] = entityBuilding
	end
	local updatedHealth = (finalDamage < entityBuilding.health) and 
	(finalHealth + finalDamage) - mitigatedDamage or (global.sfHealth[entityUID] - mitigatedDamage)

	entityBuilding.health = updatedHealth

	if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.prototype.max_health then
		--setmetatable({ entity = entityBuilding }, entityMetatable)
		global.sfHealth[entityBuilding.unit_number] = entityBuilding.health
		global.sfEntity[entityBuilding.unit_number] = entityBuilding
	elseif updatedHealth <= 0 or updatedHealth >= entityBuilding.prototype.max_health then
		clearEntityTracking(entityUID)
	end
end

-- Clear entity stuff when buildings or units destroyed
local function entityStructureDestroyed(entityBuilding)
	if entityBuilding and entityBuilding.valid and entityBuilding.unit_number then
		clearEntityTracking(entityBuilding.unit_number)
		removeBuildingBonus(entityBuilding)
	end
end

-- Iterate through global entities that are logged
local function periodicEntityCheck()
    if not global.sfEntity then 
        initGlobalProperties() 
        return
    end

    local entityData
    local count = 0
    local currentIndex = nextEntityIndex
    local entitiesToRemove = {}

    -- Check if currentIndex is valid
    if currentIndex and not global.sfEntity[currentIndex] then
        currentIndex = nil
    end

    while count < ENTITIES_PER_TICK do
        currentIndex, entityData = next(global.sfEntity, currentIndex)
        if not currentIndex then
            nextEntityIndex = nil
            break
        end

        if global.sfHealth[currentIndex] ~= nil and entityData.valid and entityData.minable and entityData.health ~= global.sfHealth[currentIndex] then
            global.sfHealth[currentIndex] = entityData.health
        end

        if not entityData.valid or entityData.health == entityData.prototype.max_health or entityData.health == 0 then
            table.insert(entitiesToRemove, currentIndex)
        end

        count = count + 1
    end

    if currentIndex then
        nextEntityIndex = currentIndex
    end

    -- Clear invalid entities after iteration
    for _, entityUID in ipairs(entitiesToRemove) do
        clearEntityTracking(entityUID)
    end
end

-- Event handlers
script.on_init(initGlobalProperties)

script.on_event(
	{ defines.events.on_entity_died, defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity },
	function(event)
		if event.entity then
			entityStructureDestroyed(event.entity)
		end
	end)

script.on_event({ defines.events.on_entity_damaged },
	function(event)
		entityStructureDamaged(event.entity, event.cause, event.force, event.final_damage_amount, event.final_health,
			event.damage_type.name)
	end)

script.on_event({ defines.events.on_player_built_tile, defines.events.on_robot_built_tile },
	function(event)
		local user = event.player_index and game.players[event.player_index] or event.robot
		entityStructureReinforced(user, event.tiles, event.tile)
	end)

script.on_event({ defines.events.on_player_mined_tile, defines.events.on_robot_mined_tile },
	function(event)
		local user = event.player_index and game.players[event.player_index] or event.robot
		entityStructureReinforced(user, event.tiles, nil)
	end)

script.on_event({ defines.events.on_built_entity, defines.events.on_robot_built_entity },
	function(event)
		local user = event.player_index and game.players[event.player_index] or event.robot
		entityStructureReinforced(user, nil, event.created_entity)
	end)

script.on_nth_tick(SETTING.EntityTickRefresh,
	periodicEntityCheck)
-- control.lua

-- Default world properties

--local SURFACE_NAME = "nauvis"
local ENEMY_FORCE = "enemy"

local SF_TEXT_SPEED = 0.8
local SF_TIME_TO_LIVE = 30
local SF_TEXT_COLOR = {r = 0.5, g = 0.8, b = 0.5, a = 0.8}

local SF_TILES = {
		["reinforced"] = {percent = settings.startup["sf-refined-reduction-percent"], flat = settings.startup["sf-refined-reduction-flat"]}, --KR2
		["refined"] = {percent = settings.startup["sf-refined-reduction-percent"], flat = settings.startup["sf-refined-reduction-flat"]},

		["concrete"] = {percent = settings.startup["sf-concrete-reduction-percent"], flat = settings.startup["sf-concrete-reduction-flat"]},
		["tarmac"] = {percent = settings.startup["sf-concrete-reduction-percent"], flat = settings.startup["sf-concrete-reduction-flat"]}, --IR3
		["asphalt"] = {percent = settings.startup["sf-concrete-reduction-percent"], flat = settings.startup["sf-concrete-reduction-flat"]}, --Roads

		["stone"] = {percent = settings.startup["sf-stone-reduction-percent"], flat = settings.startup["sf-stone-reduction-flat"]},
	}

function initGlobalProperties()
	global.sfEntityDS = {}
	global.sfEntityID = {}
end

local function clearGlobalIndex(entityUID)
	global.sfEntityID[tostring(entityUID)] = nil
	global.sfEntityDS[tostring(entityUID)] = nil
end

-- Check settings if target entity can be reinforced

local function canReinforceBuilding(entityBuilding)
	if (entityBuilding.valid and entityBuilding.minable and entityBuilding.destructible and entityBuilding.unit_number and entityBuilding.prototype.max_health > 0) then
		local isPlayer = entityBuilding.prototype.type == "character" or nil
		local isBuilding = entityBuilding.prototype.is_building
		local isWallEntity = (entityBuilding.prototype.type:find("wall") or entityBuilding.prototype.name:find("wall") or entityBuilding.prototype.type:find("gate") or entityBuilding.prototype.name:find("gate"))
		local isWallEnabled = settings.startup["sf-reinforce-wall-toggle"].value
		local isUnitsEnabled = settings.startup["sf-reinforce-units-toggle"].value
		local isPlayersEnabled = settings.startup["sf-reinforce-players-toggle"].value
		local isMilitaryEnabled = settings.startup["sf-military-target-toggle"].value
		if isPlayersEnabled and isPlayer then return true
		elseif not isPlayersEnabled and isPlayer then return false
		end
		if isUnitsEnabled and not isBuilding then return true
		elseif not isUnitsEnabled and not isBuilding then return false
		end
		if isWallEnabled and isWallEntity then return true
		elseif not isWallEnabled and isWallEntity then return false
		end
		if isMilitaryEnabled and entityBuilding.prototype.is_military_target then return true
		elseif not isMilitaryEnabled and entityBuilding.prototype.is_military_target then return false
		end
		if isBuilding then return true
		end
	end
		return false
end

-- Displaying text reinforce if enabled

local function getMatchingBuilding(player, entityBuilding, tileType)
	local checkMatch = canReinforceBuilding(entityBuilding)
	local entityUID = tostring(entityBuilding.unit_number)
	if (checkMatch and entityBuilding.force == player.force and SF_TILES) then
		for tileName, tileRate in pairs(SF_TILES) do
			if tileType.name:find(tileName) then
				if settings.startup["sf-reinforce-popup-toggle"].value then
					local caption = {"", entityBuilding.localised_name == nil and "entity-name."..entityBuilding.name or entityBuilding.localised_name, 
					" reinforced with ", tileType.localised_name == nil and "entity-name."..tileType.name or tileType.localised_name, " ("..tileRate.percent.value.."%)"} 
					player.create_local_flying_text{
						text = caption,
						position = entityBuilding.position,
						create_at_cursor = false,
						speed = SF_TEXT_SPEED,
						time_to_live = SF_TIME_TO_LIVE,
						color = SF_TEXT_COLOR,
					}
				end
				if (entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.prototype.max_health) then
					global.sfEntityID[entityUID] = entityBuilding.health
					global.sfEntityDS[entityUID] = entityBuilding
				end
				break
			end
		end
	end
end

-- Check to see if structure or entity can be reinforced after placing tile

local entityStructureReinforced = function(player, tileList, tileType)
	local mainSurface = player.surface or nil --game.surfaces[SURFACE_NAME] or nil
	if not player or not mainSurface then return end
	local caption = {"", tileType.localised_name == nil and "entity-name."..tileType.name or tileType.localised_name, " - "..tileType.name} 
	if tileList == nil then
		local entityBuilding = tileType
		tileType = mainSurface.get_tile({math.floor(tileType.position.x), math.floor(tileType.position.y)}).prototype
		getMatchingBuilding(player, entityBuilding, tileType)
	else
	for _, eventTile in pairs(tileList) do
		local findEntityArea = {{eventTile.position.x - 1, eventTile.position.y - 1}, {eventTile.position.x + 1, eventTile.position.y + 1}}
		local areaBuilding = mainSurface.find_entities(findEntityArea)
		for _, entityBuilding in pairs(areaBuilding) do
			local tilePosition = math.floor(eventTile.position.x)..","..math.floor(eventTile.position.y)
			local buildPosition = math.floor(entityBuilding.position.x)..","..math.floor(entityBuilding.position.y)
			if (tilePosition == buildPosition) then
				getMatchingBuilding(player, entityBuilding, tileType)
				break
			end
		end
	end 
	end
end

-- Apply damage reduction if possible on structures/entities on foundations

local entityStructureDamaged = function(entityBuilding, attackingEntity, attackingForce, finalDamage, finalHealth, damageType)
	local mainSurface = entityBuilding.surface or nil --game.surfaces[SURFACE_NAME] or nil
	if not mainSurface or not entityBuilding or finalDamage == 0 or not global.sfEntityID then return end
	local entityUID = tostring(entityBuilding.unit_number)
	if (canReinforceBuilding(entityBuilding) and entityBuilding.force.name ~= ENEMY_FORCE) then --or (global.sfEntityID[entityUID]) then
		local buildPosition = {math.floor(entityBuilding.position.x), math.floor(entityBuilding.position.y)}
		local buildTileType = mainSurface.get_tile(buildPosition)
		if buildTileType and SF_TILES then
			local foundTile = false
			local finalFlatDamage = finalDamage
			local tileReducePercent = 0
			local tileReduceFlat = 0
			local effectReduce = 1
			for tileName, tileRate in pairs(SF_TILES) do
				if buildTileType.name:find(tileName) then
					tileReducePercent = tileRate.percent.value
					tileReduceFlat = tileRate.flat.value
					foundTile = true
					break
				end
			end
			if foundTile then
				if (attackingForce == entityBuilding.force) and attackingEntity then
				 	if not settings.startup["sf-friendly-reduction-toggle"].value and attackingForce == entityBuilding.force then
				 		tileReduceFlat = 0
				 		tileReducePercent = 0
				 	end
				 	if (damageType == "explosion" or damageType == "impact" or damageType == "physical") then
				 		effectReduce = (settings.startup["sf-friendly-"..damageType.."-reduction"].value / 100)
				 	end
				end
				finalFlatDamage = (finalDamage - tileReduceFlat) > 0 and (finalDamage - tileReduceFlat) or 1 / (tileReduceFlat - finalDamage + 2)
				local mitigatedDamage = (finalFlatDamage * effectReduce) * (1 - (tileReducePercent / 100)) 
				if global.sfEntityID[entityUID] == nil then
					global.sfEntityID[entityUID] = entityBuilding.prototype.max_health --{hp = entityBuilding.prototype.max_health, max = entityBuilding.prototype.max_health}
				end
				entityBuilding.health = (finalDamage < entityBuilding.health) and (finalHealth + finalDamage) - mitigatedDamage or (global.sfEntityID[entityUID] - mitigatedDamage)
				global.sfEntityID[entityUID] = entityBuilding.health -- = {hp = entityBuilding.health, max = entityMaxHealth}
				if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.prototype.max_health then
					global.sfEntityDS[entityUID] = entityBuilding
				end
			end
		end
	end
end

-- Detect health changes not dealt by damage (healing, robots etc) and update entity list

local entityStructureState = function()
	for entityUID, entityBuilding in pairs(global.sfEntityDS) do
		if (entityBuilding.valid and entityBuilding.minable and global.sfEntityID[tostring(entityUID)] and global.sfEntityID[tostring(entityUID)] ~= entityBuilding.health) then
			global.sfEntityID[tostring(entityUID)] = entityBuilding.health
			if entityBuilding.health == entityBuilding.prototype.max_health then
				clearGlobalIndex(entityUID)
			end
		elseif not entityBuilding.valid or (entityBuilding.health == entityBuilding.prototype.max_health or entityBuilding.health == 0) then
			clearGlobalIndex(entityUID)
		end
	end
end

-- Remove the entity from the tag list

local entityStructureDestroyed = function(entityBuilding)
	if entityBuilding.valid then
		local entityUID = entityBuilding.unit_number or nil
		if (entityUID and global.sfEntityID and global.sfEntityID[tostring(entityUID)]) then
			clearGlobalIndex(entityUID)
		end
	else
		clearGlobalIndex(entityUID)
	end
end

-- Event handling

script.on_event(
	{defines.events.on_entity_died,
	defines.events.on_player_mined_entity,
	defines.events.on_robot_mined_entity},
	function(event)
		entityStructureDestroyed(event.entity)
	end
)

script.on_event(
	{defines.events.on_entity_damaged},
	function(event)
		entityStructureDamaged(event.entity, event.cause, event.force, event.final_damage_amount, event.final_health, event.damage_type.name)
	end
)

script.on_event(
	{defines.events.on_player_built_tile},
	function(event)
		entityStructureReinforced(game.players[event.player_index], event.tiles, event.tile)
	end
)

script.on_event(
	{defines.events.on_robot_built_entity,
	defines.events.on_robot_built_tile},
	function(event)
		entityStructureReinforced(event.robot, event.tiles, event.tile)
	end
)

script.on_event(
	{defines.events.on_built_entity},
	function(event)
		entityStructureReinforced(game.players[event.player_index], nil, event.created_entity)
	end
)

script.on_nth_tick(settings.startup["sf-entity-refresh"].value, entityStructureState)
-- script.on_event(
-- 	{defines.events.on_tick},
-- 	function(event)
-- 		entityStructureState()
-- 	end
-- )

script.on_init(initGlobalProperties)
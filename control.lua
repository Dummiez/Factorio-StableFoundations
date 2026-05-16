-- control.lua
-- Dummiez 2026/04/01

local Shared = require("shared")
local State = require("scripts.state")
local Config = require("scripts.config")

local Tiles = require("scripts.tiles")(Shared, State)
local Invulnerability = require("scripts.invulnerability")(Shared)
local BuildingBonus = require("scripts.building_bonus")(Shared, Tiles)
local Indicators = require("scripts.indicators")(Shared, Tiles, Invulnerability)
local Reinforcement = require("scripts.reinforcement")(
	Shared,
	State,
	Tiles,
	Invulnerability,
	BuildingBonus,
	Indicators
)
local Damage = require("scripts.damage")(Shared, State, Tiles, Invulnerability, Reinforcement)

local SF_INDICATOR_REFRESH_TICKS = 30

remote.add_interface("stable-foundations", Damage.makeRemoteInterface())

-- loadGameConfigs and refreshDamageIndicatorAvailability are NOT registered in on_load
-- because remote.call and remote.interfaces lookups from on_load are not multiplayer-safe.
-- They run from on_init (new save) and on_configuration_changed (mod added/removed/changed).
script.on_init(function()
	State.initGlobalProperties()
	Config.loadGameConfigs()
	Damage.refreshDamageIndicatorAvailability()
end)

-- Resolves the acting user across all build sources, including
-- script-raised events and cloning which carry no player/robot.
local function handleEntityBuilt(event)
	local entity = event.destination_entity or event.entity

	if not (entity and entity.valid) then return end

	local user = (event.player_index and game.players[event.player_index])
		or event.robot
		or { surface = entity.surface, force = entity.force }

	Reinforcement.queuePostBuildRecheck(entity)
	Reinforcement.entityStructureReinforced(user, nil, entity)
end

-- Space Exploration compatibility: when a real beacon is placed, SE validates
-- every receiver in the beacon's range and may overload-disable any that also
-- have our hidden sf-tile-bonus beacon (because SE counts both as overloaders).
-- Re-notify SE for each affected receiver with ignore_count=1 so the disable
-- gets cleared. Skip work entirely when SE isn't loaded.
local function handleBeaconBuilt(beacon)
	if not script.active_mods["space-exploration"] then return end
	if not (beacon and beacon.valid and beacon.type == "beacon") then return end
	if beacon.name == "sf-tile-bonus" then return end
	if not (storage.bonusBeacons and next(storage.bonusBeacons)) then return end

	-- Use the beacon's own supply distance to find receivers in range.
	local distance = beacon.prototype.get_supply_area_distance and
		beacon.prototype.get_supply_area_distance() or 0
	local bb = beacon.bounding_box
	local area = {
		{ bb.left_top.x - distance,     bb.left_top.y - distance },
		{ bb.right_bottom.x + distance, bb.right_bottom.y + distance },
	}
	local receivers = beacon.surface.find_entities_filtered {
		type = { "assembling-machine", "furnace", "lab", "mining-drill", "rocket-silo" },
		area = area,
		force = beacon.force,
	}
	for _, receiver in pairs(receivers) do
		if receiver.unit_number and storage.bonusBeacons[receiver.unit_number] then
			BuildingBonus.notifySpaceExplorationBeaconException(receiver)
		end
	end
end

local function handleEntityBuiltDispatch(event)
	handleEntityBuilt(event)

	-- Also fire SE re-validation for nearby foundation receivers when the new
	-- entity is itself a real beacon. Done in the same dispatcher because
	-- script.on_event only allows one handler per event per mod.
	local entity = event.destination_entity or event.entity
	if entity and entity.valid and entity.type == "beacon" then
		handleBeaconBuilt(entity)
	end
end

for _, eventName in pairs({
	"on_built_entity",
	"on_robot_built_entity",
	"on_entity_cloned",
	"on_space_platform_built_entity",
	"script_raised_built",
	"script_raised_revive",
}) do
	if defines.events[eventName] then
		script.on_event(defines.events[eventName], handleEntityBuiltDispatch)
	end
end

local function handleEntityRemoved(event)
	if event.entity then
		Reinforcement.entityStructureDestroyed(event.entity)
	end
end

-- Space Exploration compatibility: when a real beacon is removed, SE re-validates
-- nearby receivers with ignore_count=1 (to discount the about-to-vanish beacon),
-- but our hidden sf-tile-bonus beacon still bumps the count by 1, so a receiver
-- with hidden + remaining real + departing real = 3 stays overloaded under SE's
-- check. Re-notify with our own ignore_count=1 on the next tick (after the
-- beacon is truly gone) so the math becomes hidden + remaining real = 2 and the
-- disable gets cleared.
local function handleBeaconRemoved(beacon)
	if not script.active_mods["space-exploration"] then return end
	if not (beacon and beacon.valid and beacon.type == "beacon") then return end
	if beacon.name == "sf-tile-bonus" then return end
	if not (storage.bonusBeacons and next(storage.bonusBeacons)) then return end

	local distance = beacon.prototype.get_supply_area_distance and
		beacon.prototype.get_supply_area_distance() or 0
	local bb = beacon.bounding_box
	local area = {
		{ bb.left_top.x - distance,     bb.left_top.y - distance },
		{ bb.right_bottom.x + distance, bb.right_bottom.y + distance },
	}
	local receivers = beacon.surface.find_entities_filtered {
		type = { "assembling-machine", "furnace", "lab", "mining-drill", "rocket-silo" },
		area = area,
		force = beacon.force,
	}
	for _, receiver in pairs(receivers) do
		if receiver.unit_number and storage.bonusBeacons[receiver.unit_number] then
			BuildingBonus.notifySpaceExplorationBeaconException(receiver)
		end
	end
end

local function handleEntityRemovedDispatch(event)
	local entity = event.entity
	-- Capture beacon info before the standard handler in case it invalidates state.
	local isBeacon = entity and entity.valid and entity.type == "beacon"
	if isBeacon then
		handleBeaconRemoved(entity)
	end

	handleEntityRemoved(event)
end

for _, eventName in pairs({
	"on_entity_died",
	"on_player_mined_entity",
	"on_robot_mined_entity",
	"on_space_platform_mined_entity",
	"script_raised_destroy",
}) do
	if defines.events[eventName] then
		script.on_event(defines.events[eventName], handleEntityRemovedDispatch)
	end
end

script.on_event(defines.events.on_selected_entity_changed, function(event)
	Indicators.updateSelectionIndicator(game.players[event.player_index])
end)

script.on_event(defines.events.on_player_toggled_alt_mode, function(event)
	Indicators.updateSelectionIndicator(game.players[event.player_index])
end)

script.on_event(defines.events.on_player_left_game, function(event)
	Indicators.clearSelectionIndicator(event.player_index)
end)

script.on_event(defines.events.on_entity_damaged, function(event)
	Damage.entityStructureDamaged(
		event.entity,
		event.cause,
		event.force,
		event.final_damage_amount,
		event.final_health,
		event.damage_type.name
	)
end, {
	{ filter = "final-damage-amount", comparison = ">", value = 0 }
})

script.on_event(defines.events.on_player_repaired_entity, Damage.handlePlayerRepairedEntity)

local function applyTileBuilt(surface, user, event)
	if surface and event.tile and Tiles.getTileReinforcement(event.tile.name) then
		Tiles.markChunksFromTiles(surface, event.tiles)
	end

	Reinforcement.entityStructureReinforced(user, event.tiles, event.tile)
end

local function handleTileBuilt(event)
	local user = (event.player_index and game.players[event.player_index]) or event.robot
	local surface = user and user.surface

	applyTileBuilt(surface, user, event)
end

for _, eventName in pairs({
	"on_player_built_tile",
	"on_robot_built_tile",
}) do
	script.on_event(defines.events[eventName], handleTileBuilt)
end

local function applyTileMined(surface, user, event)
	Reinforcement.entityStructureReinforced(user, event.tiles, nil)

	if surface then
		Tiles.unmarkChunksIfEmpty(surface, event.tiles)
	end
end

local function handleTileMined(event)
	local user = (event.player_index and game.players[event.player_index]) or event.robot
	local surface = user and user.surface

	applyTileMined(surface, user, event)
end

for _, eventName in pairs({
	"on_player_mined_tile",
	"on_robot_mined_tile",
}) do
	script.on_event(defines.events[eventName], handleTileMined)
end

local function makePlatformUser(event, surface)
	local platform = event.platform
	if not (platform and surface) then return nil end
	return { surface = surface, force = platform.force }
end

local function handlePlatformTileBuilt(event)
	local surface = game.surfaces[event.surface_index]
	local user = makePlatformUser(event, surface)

	applyTileBuilt(surface, user, event)
end

local function handlePlatformTileMined(event)
	local surface = game.surfaces[event.surface_index]
	local user = makePlatformUser(event, surface)

	applyTileMined(surface, user, event)
end

if defines.events.on_space_platform_built_tile then
	script.on_event(defines.events.on_space_platform_built_tile, handlePlatformTileBuilt)
end

if defines.events.on_space_platform_mined_tile then
	script.on_event(defines.events.on_space_platform_mined_tile, handlePlatformTileMined)
end

script.on_event(defines.events.script_raised_set_tiles, Reinforcement.handleScriptSetTiles)

-- Factorio allows one on_nth_tick handler per interval per mod, so merge the
-- handlers when the user setting happens to equal the indicator refresh rate.
if Shared.SETTING.EntityTickRefresh == SF_INDICATOR_REFRESH_TICKS then
	script.on_nth_tick(SF_INDICATOR_REFRESH_TICKS, function()
		Damage.periodicEntityCheck()
		Indicators.refreshMovableSelectionIndicators()
	end)
else
	script.on_nth_tick(Shared.SETTING.EntityTickRefresh, Damage.periodicEntityCheck)
	script.on_nth_tick(SF_INDICATOR_REFRESH_TICKS, Indicators.refreshMovableSelectionIndicators)
end

-- Per-tick cross-mod compatibility work. Two responsibilities:
--   1. Drain the SE re-notify queue (handler-order race protection for SE).
--   2. On the first tick of each session, re-register the Beacon Rebalance
--      whitelist for "sf-tile-bonus". Rebalance keeps its whitelist in a Lua
--      local that's reset every script load; without this, after a save load
--      rebalance counts our hidden beacon as a real overloader and refuses to
--      clear the overload state when a real beacon is removed nearby.
--      We do this on the first tick (not on_load) because remote.call is not
--      multiplayer-safe from on_load.
-- The handler is only registered when at least one of those mods is present.
-- sfFirstTickDone is a module-local (not storage) so it resets on every script
-- load — exactly what we need to mirror rebalance's local-whitelist reset.
local sfFirstTickDone = false

local function hasRelevantBeaconMod()
	return script.active_mods["space-exploration"]
		or script.active_mods["wret-beacon-rebalance-mod"]
end

if hasRelevantBeaconMod() then
	script.on_event(defines.events.on_tick, function()
		if not sfFirstTickDone then
			Config.loadGameConfigs()
			sfFirstTickDone = true
		end
		Reinforcement.processPostBuildRecheckQueue()
		BuildingBonus.processSeReNotifyQueue()
	end)
end

script.on_configuration_changed(function(configChange)
	-- Re-resolve cross-mod state on every configuration change. Other mods may have
	-- been added/removed/updated even if StableFoundations itself didn't change.
	Config.loadGameConfigs()
	Damage.refreshDamageIndicatorAvailability()

	local changes = configChange.mod_changes and configChange.mod_changes["StableFoundations"]
	if not (changes or configChange.mod_startup_settings_changed or configChange.migration_applied) then return end

	State.initGlobalProperties()

	if storage.sfHealth then
		for uid, value in pairs(storage.sfHealth) do
			if type(value) ~= "number" then
				State.clearHealthTracking(uid)
			end
		end
	end

	if storage.sfHealthEntities then
		for uid, entity in pairs(storage.sfHealthEntities) do
			if not storage.sfHealth[uid] or not entity or not entity.valid then
				storage.sfHealthEntities[uid] = nil
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

	if storage.sfDestructibleState then
		for uid, value in pairs(storage.sfDestructibleState) do
			if type(value) ~= "table" or not value.entity or not value.entity.valid then
				storage.sfDestructibleState[uid] = nil
			end
		end
	end

	if storage.sfDamageReports then
		Damage.cleanupDamageReports(game.tick, true)
	end

	-- Migration for saves created before Stable Foundations tracked ownership
	-- of safe invulnerability overrides.
	if storage.sfEntity then
		for uid, value in pairs(storage.sfEntity) do
			local entity = value.entity
			if entity and entity.valid and not entity.destructible
				and Invulnerability.matchesSafeInvulnerabilityType(entity)
				and not storage.sfDestructibleState[uid] then
				storage.sfDestructibleState[uid] = {
					entity = entity,
					destructible = true
				}
			end
		end
	end

	Tiles.resetTileReinforcementCache()
	Invulnerability.resetCache()

	-- Reconnect orphan beacons before re-applying bonuses so we adopt existing
	-- beacons instead of creating duplicates next to them.
	BuildingBonus.recoverOrphanBeacons()

	if storage.sfEntity then
		for uid, entry in pairs(storage.sfEntity) do
			local entity = entry.entity
			if entity and entity.valid then
				local reinforcedTile = Tiles.getUniformReinforcedTile(entity.surface, entity)
				if reinforcedTile then
					local tileRate = Tiles.getTileReinforcement(reinforcedTile.name)
					if tileRate then
						entry.tileRate = tileRate
						BuildingBonus.applyBuildingBonus(entity.surface, entity, reinforcedTile)
					else
						Reinforcement.clearBuildingReinforcement(entity.surface, entity)
					end
				else
					Reinforcement.clearBuildingReinforcement(entity.surface, entity)
				end
			else
				storage.sfEntity[uid] = nil
			end
		end
	end

	for _, player in pairs(game.connected_players) do
		Indicators.updateSelectionIndicator(player)
	end
end)

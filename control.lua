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
local Removal = require("scripts.removal")(State, Invulnerability, Indicators)

local SF_INDICATOR_REFRESH_TICKS = 30

local function rebuildExistingReinforcement()
	storage.reinforcedChunks = {}
	storage.sfCoverageCheckTick = {}
	BuildingBonus.recoverOrphanBeacons()
	-- Reuse the tooltip recovery scan to cover factories already in the save.
	Indicators.recoverEntityTooltips(function(entity)
		Reinforcement.entityStructureReinforced(
			{ surface = entity.surface, force = entity.force }, nil, entity, true
		)
	end)
end

local function onActiveEvent(event, handler, filters)
	script.on_event(event, function(...)
		if storage.sfRemovalPrepared then return end
		-- Another mod can raise an event during configuration changes before
		-- our handler initializes newly added tracking maps.
		if not storage.sfRegisteredEntities then State.initGlobalProperties() end
		return handler(...)
	end, filters)
end

local function onActiveNthTick(interval, handler)
	script.on_nth_tick(interval, function(...)
		if not storage.sfRemovalPrepared then return handler(...) end
	end)
end

local remoteInterface = Damage.makeRemoteInterface()
remoteInterface.prepare_for_removal = Removal.prepareForRemoval
remote.add_interface("stable-foundations", remoteInterface)

commands.add_command("stable-foundations-prepare-removal", { "sf-mod.prepare-removal-help" }, function(event)
	local player = event.player_index and game.get_player(event.player_index)
	if player and game.is_multiplayer() and not player.admin then
		player.print({ "sf-mod.prepare-removal-admin" })
		return
	end
	local result = Removal.prepareForRemoval()
	game.print({ "sf-mod.removal-complete", result.tooltip_fields, result.bonus_beacons, result.invulnerability_overrides })
end)

-- loadGameConfigs and refreshDamageIndicatorAvailability are NOT registered in on_load
-- because remote.call and remote.interfaces lookups from on_load are not multiplayer-safe.
-- Refresh on init/configuration changes and the first runtime tick after load.
script.on_init(function()
	State.initGlobalProperties()
	if storage.sfRemovalPrepared then return end
	Config.loadGameConfigs(true)
	rebuildExistingReinforcement()
	Damage.refreshDamageIndicatorAvailability()
end)

-- Resolves the acting user across all build sources, including
-- script-raised events and cloning which carry no player/robot.
local function getBuiltEntity(event)
	return event.destination or event.entity
end

local function handleEntityBuilt(event)
	local entity = getBuiltEntity(event)

	if not (entity and entity.valid) then return end

	-- Area/entity cloning also clones our hidden bonus beacon. Discard that copy;
	-- the destination receiver's build event creates and tracks exactly one.
	if event.source and entity.name == "sf-tile-bonus" then
		entity.destroy()
		return
	end
	if event.source and event.source.valid then
		Invulnerability.inheritSafeOverride(event.source.unit_number, entity)
	end

	local user = (event.player_index and game.players[event.player_index])
		or event.robot
		or { surface = entity.surface, force = entity.force }

	Reinforcement.entityStructureReinforced(user, nil, entity)
	Reinforcement.queuePostBuildRecheck(entity)
end

onActiveEvent(defines.events.on_chunk_deleted, function(event)
	local chunks = storage.reinforcedChunks[event.surface_index]
	if chunks then
		for _, position in ipairs(event.positions) do
			chunks[position.x .. "," .. position.y] = nil
		end
	end
end)

-- Destruction registrations also catch other mods calling destroy() without
-- raising a build/remove event, which would otherwise strand bonus beacons.
onActiveEvent(defines.events.on_object_destroyed, function(event)
	local uid = event.useful_id
	if storage.sfRegisteredEntities[uid] == event.registration_number then
		BuildingBonus.destroyBonusBeacon(uid)
		State.clearEntityTracking(uid)
	end
end)

for _, eventName in ipairs({ "on_surface_deleted", "on_surface_cleared" }) do
	onActiveEvent(defines.events[eventName], function(event)
		storage.reinforcedChunks[event.surface_index] = nil
	end)
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
	local entity = getBuiltEntity(event)
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
		onActiveEvent(defines.events[eventName], handleEntityBuiltDispatch)
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
		onActiveEvent(defines.events[eventName], handleEntityRemovedDispatch)
	end
end

onActiveEvent(defines.events.on_selected_entity_changed, function(event)
	Indicators.updateSelectionIndicator(game.players[event.player_index])
end)

onActiveEvent(defines.events.on_player_toggled_alt_mode, function(event)
	Indicators.updateSelectionIndicator(game.players[event.player_index])
end)

onActiveEvent(defines.events.on_player_left_game, function(event)
	Indicators.clearSelectionIndicator(event.player_index)
end)

onActiveEvent(defines.events.on_entity_damaged, function(event)
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

onActiveEvent(defines.events.on_player_repaired_entity, Damage.handlePlayerRepairedEntity)

local function applyTileBuilt(surface, user, event)
	if surface and event.tile and Tiles.getTileReinforcement(event.tile.name) then
		Tiles.markChunksFromTiles(surface, event.tiles)
	end

	Reinforcement.entityStructureReinforced(user, event.tiles, event.tile)
end

-- Use the event's surface: a player in remote view or the map editor can change
-- tiles on a surface other than the one their character stands on.
local function makeTileUser(event)
	local actor = (event.player_index and game.players[event.player_index]) or event.robot
	local surface = game.surfaces[event.surface_index]
	if not (actor and surface) then return nil, surface end
	return { surface = surface, force = actor.force }, surface
end

local function handleTileBuilt(event)
	local user, surface = makeTileUser(event)

	applyTileBuilt(surface, user, event)
end

for _, eventName in pairs({
	"on_player_built_tile",
	"on_robot_built_tile",
}) do
	onActiveEvent(defines.events[eventName], handleTileBuilt)
end

local function applyTileMined(surface, user, event)
	Reinforcement.entityStructureReinforced(user, event.tiles, nil)

	if surface then
		Tiles.unmarkChunksIfEmpty(surface, event.tiles)
	end
end

local function handleTileMined(event)
	local user, surface = makeTileUser(event)

	applyTileMined(surface, user, event)
end

for _, eventName in pairs({
	"on_player_mined_tile",
	"on_robot_mined_tile",
}) do
	onActiveEvent(defines.events[eventName], handleTileMined)
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
	onActiveEvent(defines.events.on_space_platform_built_tile, handlePlatformTileBuilt)
end

if defines.events.on_space_platform_mined_tile then
	onActiveEvent(defines.events.on_space_platform_mined_tile, handlePlatformTileMined)
end

onActiveEvent(defines.events.script_raised_set_tiles, Reinforcement.handleScriptSetTiles)

onActiveEvent(defines.events.on_player_rotated_entity, function(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end
	Reinforcement.entityStructureReinforced(
		{ surface = entity.surface, force = entity.force },
		nil,
		entity
	)
end)

if defines.events.script_raised_teleported then
	onActiveEvent(defines.events.script_raised_teleported, function(event)
		local entity = event.entity
		if not (entity and entity.valid and entity.unit_number) then return end
		if entity.name == "sf-tile-bonus" then return end

		-- The tracked hidden beacon does not move with its receiver. Remove it at
		-- the old position, then re-evaluate reinforcement at the destination.
		BuildingBonus.destroyBonusBeacon(entity.unit_number)
		if Invulnerability.canReinforceBuilding(entity, true) then
			Reinforcement.entityStructureReinforced(
				{ surface = entity.surface, force = entity.force },
				nil,
				entity
			)
		else
			Invulnerability.toggleInvulnerabilities(entity, true)
			Indicators.clearEntityTooltipBonus(entity)
			State.clearEntityTracking(entity.unit_number)
			Indicators.refreshSelectionIndicatorsForEntity(entity, false)
		end
	end)
end

-- Factorio allows one on_nth_tick handler per interval per mod, so merge the
-- handlers when the user setting happens to equal the indicator refresh rate.
if Shared.SETTING.EntityTickRefresh == SF_INDICATOR_REFRESH_TICKS then
	onActiveNthTick(SF_INDICATOR_REFRESH_TICKS, function()
		Damage.periodicEntityCheck()
		Indicators.refreshMovableSelectionIndicators()
	end)
else
	onActiveNthTick(Shared.SETTING.EntityTickRefresh, Damage.periodicEntityCheck)
	onActiveNthTick(SF_INDICATOR_REFRESH_TICKS, Indicators.refreshMovableSelectionIndicators)
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
-- Register the handler unconditionally so a Beacon Rebalance continuation can
-- be discovered by its remote interface after every mod has loaded control.lua.
-- Keep it registered even without SE: multiplayer clients must restore the same
-- event subscriptions that the server had when it saved their joining map.
-- sfFirstTickDone is a module-local (not storage) so it resets on every script
-- load — exactly what we need to mirror rebalance's local-whitelist reset.
local sfFirstTickDone = false
-- active_mods is fixed for a loaded session, so read it once instead of per tick.
local seActive = script.active_mods["space-exploration"] ~= nil

onActiveEvent(defines.events.on_tick, function()
	if not sfFirstTickDone then
		Config.loadGameConfigs()
		Damage.refreshDamageIndicatorAvailability()
		sfFirstTickDone = true
	end

	if not seActive then
		return
	end

	Reinforcement.processPostBuildRecheckQueue()
	BuildingBonus.processSeReNotifyQueue()
end)

script.on_configuration_changed(function(configChange)
	State.initGlobalProperties()
	if storage.sfRemovalPrepared then return end

	-- Re-resolve cross-mod state on every configuration change. Other mods may have
	-- been added/removed/updated even if StableFoundations itself didn't change.
	Config.loadGameConfigs(true)
	Damage.refreshDamageIndicatorAvailability()
	Tiles.resetTileReinforcementCache()
	Invulnerability.resetCache()
	local bonusReceiversToRepair = BuildingBonus.cleanupInvalidBonusBeacons()
	State.pruneInvalidEntityReferences()

	local changes = configChange.mod_changes and configChange.mod_changes["StableFoundations"]
	if not (changes or configChange.mod_startup_settings_changed or configChange.migration_applied) then
		for _, entity in ipairs(bonusReceiversToRepair) do
			if entity.valid and storage.sfEntity[entity.unit_number] then
				Reinforcement.entityStructureReinforced(
					{ surface = entity.surface, force = entity.force },
					nil,
					entity
				)
			end
		end
		return
	end

	if storage.sfDamageReports then
		Damage.cleanupDamageReports(game.tick, true)
	end

	-- Migration for saves created before Stable Foundations tracked ownership
	-- of safe invulnerability overrides.
	local oldVersion = changes and changes.old_version
	local major, minor, patch = string.match(oldVersion or "", "^(%d+)%.(%d+)%.(%d+)$")
	major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
	local needsLegacyOwnership = major and (major < 1 or (major == 1 and (minor < 6 or (minor == 6 and patch < 1))))
	if needsLegacyOwnership and storage.sfEntity then
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

	-- Addition already performed this scan in on_init.
	if not (changes and not changes.old_version) then rebuildExistingReinforcement() end

	for _, player in pairs(game.connected_players) do
		Indicators.updateSelectionIndicator(player)
	end
end)

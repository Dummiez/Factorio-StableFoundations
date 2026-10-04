return function(Shared, Tiles)
	local BuildingBonus = {}

	local EFFECT_KEYS = { "productivity", "efficiency", "speed" }
	local EFFECT_TYPES = { productivity = "productivity", efficiency = "consumption", speed = "speed" }

	local function beaconMatchesReceiver(beacon, entity)
		return beacon and beacon.valid
			and beacon.surface == entity.surface
			and beacon.force == entity.force
			and math.abs(beacon.position.x - entity.position.x) < 0.01
			and math.abs(beacon.position.y - entity.position.y) < 0.01
	end

	local function hiddenBeaconCount(entity)
		local beacon = storage.bonusBeacons and storage.bonusBeacons[entity.unit_number]
		return beaconMatchesReceiver(beacon, entity) and 1 or 0
	end

	-- Space Exploration compatibility: SE's beacon overload script counts our
	-- hidden sf-tile-bonus beacon as a regular beacon when computing whether a
	-- receiver has more than one beacon affecting it. Call SE's remote to
	-- re-validate with ignore_count=1 while our beacon exists, or 0 after
	-- removal. Only our own hidden beacon is discounted.
	--
	-- We call SE's remote both immediately AND queue a deferred re-notify on
	-- the next tick. This handles the case where SE's own on_built_entity
	-- handler runs AFTER ours and re-applies the overload disable. The queued
	-- second call clears it.
	local function notifySpaceExplorationBeaconException(entity)
		if not (entity and entity.valid) then return end
		if not script.active_mods["space-exploration"] then return end
		if not (remote.interfaces["space-exploration"]
			and remote.interfaces["space-exploration"]["on_entity_activated"]) then return end
		remote.call("space-exploration", "on_entity_activated", {
			mod = "StableFoundations",
			entity = entity,
			ignore_count = hiddenBeaconCount(entity),
		})
		-- Queue for deferred re-notification next tick to defeat handler-order races.
		if entity.unit_number then
			storage.sfSeReNotifyQueue = storage.sfSeReNotifyQueue or {}
			storage.sfSeReNotifyQueue[entity.unit_number] = entity
		end
	end

	-- Process the deferred SE re-notify queue. Called from control.lua's
	-- on_tick handler. Drains the queue each tick.
	function BuildingBonus.processSeReNotifyQueue()
		if not script.active_mods["space-exploration"] then return end
		if not (storage.sfSeReNotifyQueue and next(storage.sfSeReNotifyQueue)) then return end
		if not (remote.interfaces["space-exploration"]
			and remote.interfaces["space-exploration"]["on_entity_activated"]) then
			storage.sfSeReNotifyQueue = {}
			return
		end
		for uid, entity in pairs(storage.sfSeReNotifyQueue) do
			if entity and entity.valid then
				remote.call("space-exploration", "on_entity_activated", {
					mod = "StableFoundations",
					entity = entity,
					ignore_count = hiddenBeaconCount(entity),
				})
			end
			storage.sfSeReNotifyQueue[uid] = nil
		end
	end

	-- Exposed so other modules (e.g. control.lua's real-beacon handler) can
	-- request SE re-validation for a receiver after a nearby beacon event.
	BuildingBonus.notifySpaceExplorationBeaconException = notifySpaceExplorationBeaconException

	function BuildingBonus.transferBonusBeacon(oldUid, newUid)
		if not (oldUid and newUid and oldUid ~= newUid and storage.bonusBeacons) then return end

		local beacon = storage.bonusBeacons[oldUid]
		if beacon and beacon.valid then
			storage.bonusBeacons[newUid] = beacon
			storage.bonusBeacons[oldUid] = nil
			return true
		end
		storage.bonusBeacons[oldUid] = nil
	end

	function BuildingBonus.destroyBonusBeacon(uid)
		if not (uid and storage.bonusBeacons) then return end

		local beacon = storage.bonusBeacons[uid]
		if beacon and beacon.valid then
			beacon.destroy()
		end
		storage.bonusBeacons[uid] = nil
	end

	function BuildingBonus.removeBuildingBonus(entity)
		if not entity.valid then return end
		local uid = entity.unit_number
		local hadHiddenBeacon = false
		if storage.bonusBeacons and storage.bonusBeacons[uid] then
			local beacon = storage.bonusBeacons[uid]
			if beacon and beacon.valid then
				beacon.destroy()
				hadHiddenBeacon = true
			end
			storage.bonusBeacons[uid] = nil
		end

		-- Tell SE to re-validate now that our hidden beacon is gone, so any
		-- existing overload disable on this receiver gets cleared promptly
		-- instead of waiting for SE's 600-tick periodic recheck.
		if hadHiddenBeacon then
			notifySpaceExplorationBeaconException(entity)
		end
	end

	function BuildingBonus.applyBuildingBonus(surface, entity, tileType)
		if not entity.valid then return end
		if tileType == nil then
			BuildingBonus.removeBuildingBonus(entity)
			return
		end

		if Shared.isBuildingBonusExcluded(entity) then
			BuildingBonus.removeBuildingBonus(entity)
			return
		end
		-- Skip beacons entirely. Beacons have allowed_effects (for the modules they
		-- transmit) but don't receive external beacon effects, so a hidden bonus
		-- beacon on top of one does nothing useful. It also confuses overload
		-- mechanics in SE / Beacon Rebalance which then incorrectly treat the
		-- real beacon as part of an overloaded group.
		if entity.type == "beacon" then
			BuildingBonus.removeBuildingBonus(entity)
			return
		end
		local bonus = Tiles.getTileReinforcement(tileType.name)
		local allowed = entity.prototype.allowed_effects
		local receiver = entity.prototype.effect_receiver
		local modules = {}
		if bonus and bonus.tier and allowed and receiver and receiver.uses_beacon_effects then
			for _, key in ipairs(EFFECT_KEYS) do
				local name = "sf-tile-module-" .. bonus.tier .. "-" .. key
				if allowed[EFFECT_TYPES[key]] and prototypes.item[name] then
					modules[#modules + 1] = name
				end
			end
		end
		-- Zero bonuses and receivers that cannot use them need no hidden entity.
		if #modules == 0 then
			BuildingBonus.removeBuildingBonus(entity)
			return
		end

		local uid = entity.unit_number
		local beacon = storage.bonusBeacons and storage.bonusBeacons[uid]

		if beacon and not beaconMatchesReceiver(beacon, entity) then
			if beacon.valid then beacon.destroy() end
			beacon = nil
			storage.bonusBeacons[uid] = nil
		end

		local moduleInventory = beacon and beacon.get_module_inventory()

		if not beacon then
			beacon = surface.create_entity {
				name = "sf-tile-bonus",
				position = entity.position,
				force = entity.force
			}
			if not beacon then return end
			beacon.destructible = false
			beacon.minable_flag = false
			beacon.operable = false
			moduleInventory = beacon.get_module_inventory()
			storage.bonusBeacons[uid] = beacon
		end

		if not moduleInventory then
			BuildingBonus.removeBuildingBonus(entity)
			return
		end
		local unchanged = true
		for i = 1, #moduleInventory do
			local stack = moduleInventory[i]
			if modules[i] then
				if not stack.valid_for_read or stack.name ~= modules[i] or stack.count ~= 1 then
					unchanged = false
					break
				end
			elseif stack.valid_for_read then
				unchanged = false
				break
			end
		end
		if not unchanged then
			moduleInventory.clear()
			for _, moduleName in ipairs(modules) do
				moduleInventory.insert({ name = moduleName, count = 1 })
			end
		end

		-- Tell SE to ignore our hidden beacon when counting overloaders.
		notifySpaceExplorationBeaconException(entity)
	end

	-- Remove mappings and hidden beacons whose owning receiver no longer exists.
	-- This is lightweight enough to run after every mod configuration change.
	function BuildingBonus.cleanupInvalidBonusBeacons()
		storage.bonusBeacons = storage.bonusBeacons or {}
		local receiversToRepair = {}

		for uid, beacon in pairs(storage.bonusBeacons) do
			local entry = storage.sfEntity and storage.sfEntity[uid]
			local entity = type(entry) == "table" and entry.entity
			local validReceiver = entity and entity.valid and entry.tileRate
			if not validReceiver or not beaconMatchesReceiver(beacon, entity) then
				if beacon and beacon.valid then
					beacon.destroy()
				end
				storage.bonusBeacons[uid] = nil
				if validReceiver then
					receiversToRepair[#receiversToRepair + 1] = entity
				end
			end
		end

		return receiversToRepair
	end

	-- Reconnect storage.bonusBeacons with any orphan beacons left in the world.
	-- Runs at configuration_changed; the hot apply path above no longer scans, so
	-- this is the only place orphans get adopted (or duplicates pruned).
	function BuildingBonus.recoverOrphanBeacons()
		if not storage.sfEntity then return end
		BuildingBonus.cleanupInvalidBonusBeacons()
		local claimed = {}

		for uid, entry in pairs(storage.sfEntity) do
			local entity = entry.entity
			local known = storage.bonusBeacons[uid]

			if entity and entity.valid then
				local found = entity.surface.find_entities_filtered {
					name = "sf-tile-bonus",
					position = entity.position,
					radius = 0.9
				}
				for _, beacon in ipairs(found) do
					if beaconMatchesReceiver(beacon, entity) then
						if not known then
							known = beacon
							storage.bonusBeacons[uid] = known
						elseif beacon ~= known then
							beacon.destroy()
						end
					end
				end
				if known and known.valid then claimed[known.unit_number] = true end
			end

			-- Re-notify SE for any receiver that already has a hidden beacon, so
			-- existing saves get their machines un-disabled after a mod update.
			if entity and entity.valid and storage.bonusBeacons[uid] then
				notifySpaceExplorationBeaconException(entity)
			end
		end
		-- Unowned leftovers are handled once per rebuild, so placing ordinary
		-- entities never needs a nearby-beacon search.
		for _, surface in pairs(game.surfaces) do
			for _, beacon in pairs(surface.find_entities_filtered { name = "sf-tile-bonus" }) do
				if not claimed[beacon.unit_number] then beacon.destroy() end
			end
		end
	end

	return BuildingBonus
end

return function(Shared, Tiles)
	local BuildingBonus = {}

	local EFFECT_KEYS = { "productivity", "efficiency", "speed" }

	-- Space Exploration compatibility: SE's beacon overload script counts our
	-- hidden sf-tile-bonus beacon as a regular beacon when computing whether a
	-- receiver has more than one beacon affecting it. Call SE's remote to
	-- re-validate the receiver with ignore_count=1 so SE permits one extra
	-- beacon (ours) before triggering its overload disable.
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
			ignore_count = 1,
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
					ignore_count = 1,
				})
			end
			storage.sfSeReNotifyQueue[uid] = nil
		end
	end

	-- Exposed so other modules (e.g. control.lua's real-beacon handler) can
	-- request SE re-validation for a receiver after a nearby beacon event.
	BuildingBonus.notifySpaceExplorationBeaconException = notifySpaceExplorationBeaconException

	local function removeAllModules(entity)
		local moduleInventory = entity.get_module_inventory()
		if not moduleInventory or moduleInventory.is_empty() then return end
		for i = 1, #moduleInventory do
			if moduleInventory[i].valid_for_read then
				moduleInventory[i].clear()
			end
		end
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
		else
			local hiddenBeacons = entity.surface.find_entities_filtered {
				name = "sf-tile-bonus",
				position = entity.position,
				radius = 0.9
			}
			if hiddenBeacons and #hiddenBeacons > 0 then
				for _, beacon in pairs(hiddenBeacons) do
					beacon.destroy()
				end
				hadHiddenBeacon = true
			end
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
		if not entity.prototype.allowed_effects then return end

		local bonus = Tiles.getTileReinforcement(tileType.name)
		if not bonus then return end

		local uid = entity.unit_number
		local beacon = storage.bonusBeacons and storage.bonusBeacons[uid]

		if beacon and not beacon.valid then
			beacon = nil
			storage.bonusBeacons[uid] = nil
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

			-- Tell SE to ignore our hidden beacon when counting overloaders.
			-- Safe to call every apply; SE simply re-runs validate_entity.
			notifySpaceExplorationBeaconException(entity)
		end
	end

	-- Reconnect storage.bonusBeacons with any orphan beacons left in the world.
	-- Runs at configuration_changed; the hot apply path above no longer scans, so
	-- this is the only place orphans get adopted (or duplicates pruned).
	function BuildingBonus.recoverOrphanBeacons()
		if not storage.sfEntity then return end
		storage.bonusBeacons = storage.bonusBeacons or {}

		for uid, entry in pairs(storage.sfEntity) do
			local entity = entry.entity
			local known = storage.bonusBeacons[uid]
			if known and not known.valid then
				storage.bonusBeacons[uid] = nil
				known = nil
			end

			if entity and entity.valid and not known then
				local found = entity.surface.find_entities_filtered {
					name = "sf-tile-bonus",
					position = entity.position,
					radius = 0.9
				}
				for i, beacon in ipairs(found) do
					if i == 1 then
						storage.bonusBeacons[uid] = beacon
					else
						beacon.destroy()
					end
				end
			end

			-- Re-notify SE for any receiver that already has a hidden beacon, so
			-- existing saves get their machines un-disabled after a mod update.
			if entity and entity.valid and storage.bonusBeacons[uid] then
				notifySpaceExplorationBeaconException(entity)
			end
		end
	end

	return BuildingBonus
end

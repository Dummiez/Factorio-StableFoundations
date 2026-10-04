return function(State, Invulnerability, Indicators)
	local Removal = {}
	local Tooltip = require("scripts.tooltip")

	function Removal.prepareForRemoval()
		State.initGlobalProperties()
		-- This flag survives save/load and configuration changes. Event handlers
		-- must stay idle until the mod is removed, or they could recreate bonuses.
		storage.sfRemovalPrepared = true
		local result = { tooltip_fields = 0, invulnerability_overrides = 0, bonus_beacons = 0 }
		local receivers = {}
		for uid in pairs(storage.bonusBeacons) do
			local entry = storage.sfEntity[uid]
			if entry and entry.entity and entry.entity.valid then
				receivers[#receivers + 1] = entry.entity
			end
		end

		-- Restore only overrides we own, including an originally false value.
		-- Never make arbitrary indestructible entities destructible.
		for _, state in pairs(storage.sfDestructibleState) do
			local entity = type(state) == "table" and state.entity
			if entity and entity.valid and Invulnerability.toggleInvulnerabilities(entity, true) then
				result.invulnerability_overrides = result.invulnerability_overrides + 1
			end
		end

		-- A one-time surface scan also catches copied/orphaned fields and beacons
		-- whose IDs are no longer in storage. Preserve every other mod's fields.
		for _, surface in pairs(game.surfaces) do
			for _, entity in pairs(surface.find_entities()) do
				if entity.valid then
					if entity.name == "sf-tile-bonus" then
						entity.destroy()
						result.bonus_beacons = result.bonus_beacons + 1
					else
						result.tooltip_fields = result.tooltip_fields + Tooltip.clearFoundationFields(entity)
					end
				end
			end
		end

		for playerIndex in pairs(storage.sfSelectionIndicators) do
			Indicators.clearSelectionIndicator(playerIndex)
		end
		rendering.clear("StableFoundations")
		State.resetGlobalProperties()

		-- With our beacon gone, SE must count all remaining real beacons.
		local seInterface = remote.interfaces["space-exploration"]
		if script.active_mods["space-exploration"] and seInterface and seInterface.on_entity_activated then
			for _, entity in ipairs(receivers) do
				if entity.valid then
					remote.call("space-exploration", "on_entity_activated", {
						mod = "StableFoundations", entity = entity, ignore_count = 0
					})
				end
			end
		end
		return result
	end

	return Removal
end

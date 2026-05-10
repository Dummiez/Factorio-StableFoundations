-- data-final-fixes.lua
-- Dummiez 2026/03/31

local Shared = require("shared")

-- Create beacon module effects
local bonus_modules = {}

-- Create beacon to add modifiers
local tile_beacon = {
	type = "beacon",
	name = "sf-tile-bonus",
	icon = "__base__/graphics/icons/beacon.png",
	icon_size = 64,
	hidden = true,
	selectable_in_game = false,
	allow_copy_paste = false,
	protected_from_tile_building = false,
	minable = nil,
	energy_usage = "1W",
	supply_area_distance = 0,
	distribution_effectivity = 1,
	distribution_effectivity_bonus_per_quality_level = 0,
	graphics_set = nil,
	selection_box = { { 0, 0 }, { 0, 0 } },
	collision_box = { { 0, 0 }, { 0, 0 } },
	profile = { 1 },
	beacon_counter = "same_type",
	collision_mask = { layers = {} },
	energy_source = { type = "void" },
	module_slots = 3,
	render_layer = "floor-chain-render-layer",
	allowed_effects = { "speed", "productivity", "consumption", "pollution", "quality" },
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-blueprintable",
		"not-deconstructable",
		"hide-alt-info",
		"no-copy-paste",
		"no-automated-item-insertion",
		"no-automated-item-removal",
		"not-repairable",
		"not-flammable",
		"not-selectable-in-game",
		"not-in-made-in",
		"not-in-kill-statistics",
		"not-upgradable",
		"not-rotatable"
	}
}

-- Space exploration mod support for the tile bonus effects
if mods["space-exploration"] then
	tile_beacon.se_allow_in_space = true
	tile_beacon.se_allow_productivity_in_space = true
end

-- Beacon overload mod compatibility: several mods (Beacon Rebalance, Space
-- Exploration, etc.) set profile = {1, 0} on beacons to enforce a single-beacon-
-- per-machine rule via diminishing returns. That same mechanic also zeroes out
-- the player's beacon when our hidden sf-tile-bonus beacon is also affecting the
-- receiver. Sweep every beacon prototype and replace zero entries in profile
-- arrays with 1 so additional beacons (specifically our hidden sf-tile-bonus)
-- don't collapse the effect. Each mod's runtime overload script still enforces
-- its single-beacon rule by disabling the receiver, so this only changes the
-- effect-stacking math, not the gameplay rule.
if data.raw["beacon"] then
	for _, beacon_proto in pairs(data.raw["beacon"]) do
		if beacon_proto.profile then
			for i = 1, #beacon_proto.profile do
				if beacon_proto.profile[i] == 0 then
					beacon_proto.profile[i] = 1
				end
			end
		end
	end
end

-- TEMPORARY DEBUG: log the patched profiles for SE beacons
if mods["space-exploration"] then
	for _, name in pairs({ "se-wide-beacon", "se-compact-beacon", "se-compact-beacon-2" }) do
		local p = data.raw["beacon"] and data.raw["beacon"][name]
		if p then
			log("[StableFoundations DEBUG] " .. name .. " profile = " .. serpent.line(p.profile))
		else
			log("[StableFoundations DEBUG] " .. name .. " NOT FOUND in data.raw.beacon")
		end
	end
end

local effect_types = {
	{ key = "productivity", field = "productivity", multiplier = 1 },
	{ key = "efficiency",   field = "consumption",  multiplier = -1 },
	{ key = "speed",        field = "speed",        multiplier = 1 },
}

-- Generate modules for each foundation tier
for index, tier_tiles in ipairs(Shared.SF_NAMES) do
	if tier_tiles then
		for _, effect in ipairs(effect_types) do
			local base_value = Shared.parseBonus(settings.startup[Shared.SF_LIST[effect.key]], index)
			local value = (base_value / 100) * effect.multiplier

			-- Skip creating a module if the value is zero (no point inserting a no-op module)
			if value ~= 0 then
				local new_bonus = {
					type = "module",
					name = "sf-tile-module-" .. index .. "-" .. effect.key,
					icon = "__base__/graphics/icons/speed-module.png",
					icon_size = 64,
					hidden = true,
					flags = { "hide-from-bonus-gui" },
					subgroup = "module",
					category = effect.key,
					tier = 0,
					order = "z" .. index .. "-" .. effect.key,
					stack_size = 1,
					effect = {
						[effect.field] = value
					},
					limitation = {},
					limitation_message_key = "tile-bonus-module-usable-only-on-beacons",
				}
				table.insert(bonus_modules, new_bonus)
			end
		end
	end
end

-- Update allowed effects for specified buildings
if Shared.SETTING.BuildingBonusEffects then
	local allowedTypes = Shared.parseTiles(Shared.SETTING.BuildingBonusList)

	if allowedTypes then
		local extraEffects = { "speed", "productivity", "consumption", "pollution", "quality" }

		-- Helper function to update allowed effects on a data object
		local function updateAllowedEffects(dataObject, effect)
			dataObject.allowed_effects = dataObject.allowed_effects or {}

			if dataObject.effect_receiver then
				dataObject.effect_receiver.uses_module_effects = true
				dataObject.effect_receiver.uses_beacon_effects = true
			else
				dataObject.effect_receiver = {
					uses_module_effects = true,
					uses_beacon_effects = true,
				}
			end

			-- Check if effect already exists in the array
			for _, existing in ipairs(dataObject.allowed_effects) do
				if existing == effect then
					return -- Already present, nothing to do
				end
			end

			table.insert(dataObject.allowed_effects, effect)
		end

		-- Go through existing models and apply extra effects
		for _, dataType in pairs(allowedTypes) do
			if data.raw[dataType] then
				for _, dataObject in pairs(data.raw[dataType]) do
					if not Shared.isBuildingBonusExcluded(dataObject) then
						for _, effect in pairs(extraEffects) do
							updateAllowedEffects(dataObject, effect)
						end
					end
				end
			end
		end
	end
end

-- Reduce particle counts in damage/death triggers to mitigate lag from
-- excessive particle generation. Operates on walls, gates, and military structures.
if settings.startup["sf-particle-reduction-toggle"].value then
	local DAMAGED_CAP = 2
	local DYING_CAP = 5

	-- Base types that are inherently military/defensive
	local DEFENSE_TYPES = {
		["wall"] = true,
		["gate"] = true,
	}

	local function clampParticleTriggers(triggerArray, cap)
		if not triggerArray then return end
		-- Trigger fields can be a single trigger or an array; normalize
		local items = triggerArray[1] and triggerArray or { triggerArray }
		for _, item in pairs(items) do
			if item.type == "create-particle" then
				if cap == 0 then
					-- Zero cap: neutralize by setting probability to 0
					item.probability = 0
				else
					if item.repeat_count and item.repeat_count > cap then
						item.repeat_count = cap
					end
					if item.repeat_count_deviation and item.repeat_count_deviation > 1 then
						item.repeat_count_deviation = 1
					end
				end
			end
			-- Some triggers nest action_delivery -> target_effects with create-particle
			if item.action_delivery then
				local deliveries = item.action_delivery[1] and item.action_delivery or { item.action_delivery }
				for _, delivery in pairs(deliveries) do
					if delivery.target_effects then
						clampParticleTriggers(delivery.target_effects, cap)
					end
				end
			end
		end
	end

	for type_name, prototypes in pairs(data.raw) do
		for _, prototype in pairs(prototypes) do
			if DEFENSE_TYPES[type_name] or prototype.is_military_target then
				clampParticleTriggers(prototype.damaged_trigger_effect, DAMAGED_CAP)
				clampParticleTriggers(prototype.dying_trigger_effect, DYING_CAP)
			end
		end
	end
end
local added_types = {}

table.insert(added_types, tile_beacon)

if #bonus_modules > 0 then
	for _, mod in ipairs(bonus_modules) do
		table.insert(added_types, mod)
	end
end

if #added_types > 0 then
	data:extend(added_types)
end

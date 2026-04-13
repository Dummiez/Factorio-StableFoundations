-- data-final-fixes.lua
-- Dummiez 2026/03/31

local Shared = require("shared")

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
	graphics_set = nil,
	selection_box = { {0, 0}, {0, 0} },
	collision_box = { {0, 0}, {0, 0} },
	collision_mask = { layers = {} },
	energy_source = { type = "void" },
	module_slots = 3,
	allowed_effects = { "speed", "productivity", "consumption" },
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

-- Create beacon module effects
local bonus_modules = {}

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
					for _, effect in pairs(extraEffects) do
						updateAllowedEffects(dataObject, effect)
					end
				end
			end
		end
	end
end

-- Extend the data dictionary with our new entities and items
data:extend(bonus_modules)
data:extend({ tile_beacon })
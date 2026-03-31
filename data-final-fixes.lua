-- data-final-fixes.lua
-- Dummiez 2026/03/31

require 'shared'

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
    --{ { -0.1, -0.1 }, { 0.1, 0.1 } },
    --collision_mask = { "colliding-with-tiles-only" },
    collision_mask = { layers = {} },
    energy_source = { type = "void" },
    module_slots = 3,
    --module_specification = { module_slots = 1 },
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

-- Create beacon module effect
local bonus_modules = {}

local effect_types = {
    { key = "productivity", field = "productivity",  multiplier =  1 },
    { key = "efficiency",   field = "consumption",   multiplier = -1 },
    { key = "speed",        field = "speed",         multiplier =  1 },
}

for index, tiletype in ipairs(SF_NAMES) do
    if tiletype then
        for _, effect in ipairs(effect_types) do
            local value = parseBonus(settings.startup[SF_LIST[effect.key]], index) / 100 * effect.multiplier

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

if SETTING.BuildingBonusEffects then
    local allowedTypes = parseTiles(SETTING.BuildingBonusList)
    local excludedTypes = parseTiles(SETTING.BuildingExcludeList)
    local extraEffects = { "speed", "productivity", "consumption", "pollution", "quality" }

    -- Create set of excluded types
    local excludedSet = {}
    for _, name in ipairs(excludedTypes) do
        excludedSet[name] = true
    end

    -- Update allowed effects
    local function updateAllowedEffects(dataObject, effect)
        dataObject.allowed_effects = dataObject.allowed_effects or {}

        -- Reset any existing similar effects
        if dataObject.allowed_effects[effect] then
            table.remove(dataObject.allowed_effects, effect)
        end
        table.insert(dataObject.allowed_effects, effect)
    end

    -- Go through existing models
    for _, dataType in pairs(allowedTypes) do
        if data.raw[dataType] then
            for _, dataObject in pairs(data.raw[dataType]) do
                if not excludedSet[dataObject.name] then
                    for _, effect in pairs(extraEffects) do
                        updateAllowedEffects(dataObject, effect)
                    end
                end
            end
        end
    end
    -- Force recipes to allow bonuses (currently causes an issue with items' rocket stack size being adjusted)
    -- for _, recipe in pairs(data.raw.recipe) do
    --     recipe.allow_productivity = true
    --     recipe.allow_consumption = true
    --     recipe.allow_speed = true
    --     recipe.allow_pollution = true
    --     recipe.allow_quality = true
    --     recipe.allowed_module_categories = nil
    -- end
end

data:extend(bonus_modules)
data:extend({ tile_beacon })
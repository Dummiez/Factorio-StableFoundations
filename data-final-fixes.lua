-- data-final-fixes.lua
-- Dummiez 2024/06/27

require 'shared'

-- Create beacon to add modifiers
local tile_beacon = {
    type = "beacon",
    name = "sf-tile-bonus",
    energy_usage = "1W",
    supply_area_distance = 0,
    distribution_effectivity = 1,
    graphics_set = nil,
    selection_box = { {0, 0}, {0, 0} },
    collision_box = { {0, 0}, {0, 0} },
    --{ { -0.1, -0.1 }, { 0.1, 0.1 } },
    collision_mask = { "colliding-with-tiles-only" },
    energy_source = { type = "void" },
    module_specification = { module_slots = 1 },
    allowed_effects = { "speed", "productivity", "consumption" },
    flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", 
        "hidden", "hide-alt-info", "no-copy-paste", "no-automated-item-insertion",
        "no-automated-item-removal", "not-repairable", "not-flammable", "not-selectable-in-game", "not-in-made-in",
        "not-in-kill-statistics", "not-upgradable" }
}

-- Create beacon module effect
local bonus_modules = {}

for index, tiletype in ipairs(SF_NAMES) do
    if tiletype then
        local new_bonus = {
            type = "module",
            name = "sf-tile-module-" .. index,
            icon = "__base__/graphics/icons/speed-module.png",
            icon_size = 1,
            flags = { "hidden", "hide-from-bonus-gui" },
            subgroup = "module",
            category = "productivity",
            tier = 0,
            order = "z" .. index,
            stack_size = 1,
            effect = {
                speed = { bonus = parseBonus(settings.startup[SF_LIST.speed], index) / 100 },
                productivity = { bonus = parseBonus(settings.startup[SF_LIST.productivity], index) / 100 },
                consumption = { bonus = (parseBonus(settings.startup[SF_LIST.efficiency], index) / 100) * -1 }
            },
            limitation = {},
            limitation_message_key = "tile-bonus-module-usable-only-on-beacons"
        }
        table.insert(bonus_modules, new_bonus)
    end
end

if SETTING.BuildingBonusEffects then
    local allowedTypes = parseTiles(SETTING.BuildingBonusList)
    local excludedTypes = parseTiles(SETTING.BuildingExcludeList)
    local extraEffects = { "productivity", "speed", "consumption", "pollution" }
    
    -- Create set of excluded types
    local excludedSet = {}
    for _, name in ipairs(excludedTypes) do
        excludedSet[name] = true
    end

    -- Update allowed effects
    local function updateAllowedEffects(dataObject, effect)
        dataObject.allowed_effects = dataObject.allowed_effects or {}

        -- Reset any existing similar effects (necessary because allowed_effects has some weird internal issues)
        if dataObject.allowed_effects[effect] then
            table.remove(dataObject.allowed_effects, effect)
        end
        table.insert(dataObject.allowed_effects, effect)
    end

    -- Data type checking
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
end


data:extend(bonus_modules)
data:extend({ tile_beacon })
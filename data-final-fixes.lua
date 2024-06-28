-- data-final-fixes.lua
-- Dummiez 2024/06/27

require 'shared'

-- Create beacon to add modifiers
local invisible_beacon = table.deepcopy(data.raw["beacon"]["beacon"])
invisible_beacon.name = "sf-tile-bonus"
invisible_beacon.energy_usage = "1W"
invisible_beacon.supply_area_distance = 0
invisible_beacon.distribution_effectivity = 1
invisible_beacon.graphics_set = nil
invisible_beacon.selection_box = nil
invisible_beacon.collision_mask = {}
invisible_beacon.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
invisible_beacon.energy_source = { type = "void" }
invisible_beacon.allowed_effects = { "speed", "productivity", "consumption" }
invisible_beacon.flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
    "not-upgradable", "hidden", "hide-alt-info", "no-copy-paste", "no-automated-item-insertion",
    "no-automated-item-removal", "not-repairable", "not-flammable", "not-selectable-in-game", "not-in-made-in",
    "not-in-kill-statistics" }

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
    local allowedTypes = parseTiles(SETTING.BuildingBonusList) --{ "assembling-machine", "furnace", "mining-drill" }
    local extraEffects = { "productivity", "speed", "consumption", "pollution" }

    -- Modify allowed effects to enable buffs
    for _, dataType in pairs(allowedTypes) do
        if data.raw[dataType] ~= nil then
            for _, dataObject in pairs(data.raw[dataType]) do
                dataObject.allowed_effects = extraEffects
            end
        end
    end
end


data:extend(bonus_modules)
data:extend({ invisible_beacon })

-- shared.lua
-- Dummiez 2024/06/27

-- Min-max clamp numbers
function math.clamp(x, min, max)
    return x < min and min or (x > max and max or x)
end

-- Parse the bonus production value strings
function parseBonus(bonusSetting, tierIndex)
    local defaultValues = bonusSetting.default_value
    -- Find all numbers in the string (including those with decimals)
    local numbers = {}
    for num in string.gmatch(bonusSetting.value, "[%d%.]+") do
        table.insert(numbers, math.clamp(math.floor(tonumber(num) + 0.5), 0, 200))
    end
    return (numbers == nil or #numbers == 0) and defaultValues[tierIndex] or
        (#numbers < 3 and numbers[1] or numbers[tierIndex])
end

-- Parse the tile value strings
function parseTiles(tileSetting)
    local tiles = {}
    -- Check if tileSetting.value is empty or contains only whitespace
    if not tileSetting.value or tileSetting.value:match('^%s*$') then
        return { tileSetting.default_value }
    end
    -- Find all words separated by commas
    for tile in tileSetting.value:gmatch('([^,%s]+)') do
        tiles[#tiles + 1] = tile:match('^%s*(.-)%s*$')
    end

    return tiles
end

-- Setting variables
SETTING = {
    ReinforcePopupToggle = settings.startup["sf-reinforce-popup-toggle"].value,
    FriendlyDamageReduction = settings.startup["sf-friendly-reduction-toggle"].value,
    FriendlyPhysicalDamage = settings.startup["sf-friendly-physical-reduction"].value,
    FriendlyExplosionDamage = settings.startup["sf-friendly-explosion-reduction"].value,
    FriendlyImpactDamage = settings.startup["sf-friendly-impact-reduction"].value,
    ReinforceMiltBuildings = settings.startup["sf-military-target-toggle"].value,
    ReinforceWalls = settings.startup["sf-reinforce-wall-toggle"].value,
    ReinforceUnits = settings.startup["sf-reinforce-units-toggle"].value,
    ReinforcePlayers = settings.startup["sf-reinforce-players-toggle"].value,
    SafePoles = settings.startup["sf-invulnerable-poles-toggle"].value,
    SafeRails = settings.startup["sf-invulnerable-rails-toggle"].value,
    SafeLights = settings.startup["sf-invulnerable-lamps-toggle"].value,
    -- ProductionBonus = settings.startup["sf-production-bonus-toggle"].value,
    -- EfficiencyBonus = settings.startup["sf-efficiency-bonus-toggle"].value,
    -- SpeedBonus = settings.startup["sf-speed-bonus-toggle"].value,
    EntityRefreshCount = settings.startup["sf-entity-tick-count"].value,
    EntityTickRefresh = settings.startup["sf-entity-refresh"].value,
    BuildingBonusEffects = settings.startup["sf-building-bonus-toggle"].value,
    BuildingBonusList = settings.startup["sf-list-bonus"],
    BuildingExcludeList = settings.startup["sf-list-exclude"],
    IdentifiedList = {"default"}
}

-- Setting names
SF_LIST = {
    percent_1 = "sf-refined-reduction-percent",
    flat_1 = "sf-refined-reduction-flat",
    percent_2 = "sf-concrete-reduction-percent",
    flat_2 = "sf-concrete-reduction-flat",
    percent_3 = "sf-stone-reduction-percent",
    flat_3 = "sf-stone-reduction-flat",
    productivity = "sf-production-list",
    efficiency = "sf-efficiency-list",
    speed = "sf-speed-list",
    tier3 = "sf-list-tier3",
    tier2 = "sf-list-tier2",
    tier1 = "sf-list-tier1",
}

-- Foundation tier string parser
SF_NAMES = {
    [1] = parseTiles(settings.startup[SF_LIST.tier3]),
    [2] = parseTiles(settings.startup[SF_LIST.tier2]),
    [3] = parseTiles(settings.startup[SF_LIST.tier1]),
}

SF_TILES = {}

-- Store foundation tiles into the list
for index, tier in ipairs(SF_NAMES) do
    for _, tile in pairs(tier) do
        SF_TILES[tile] = {
            tier = index,
            percent = settings.startup[SF_LIST["percent_" .. index]].value,
            flat = settings.startup[SF_LIST["flat_" .. index]].value,
            productivity = parseBonus(settings.startup[SF_LIST.productivity], index),
            efficiency = parseBonus(settings.startup[SF_LIST.efficiency], index),
            speed = parseBonus(settings.startup[SF_LIST.speed], index)
        }
    end
end

-- shared.lua
-- Dummiez 2024/06/27

local Shared = {}

function Shared.clamp(x, min, max)
	return x < min and min or (x > max and max or x)
end

-- Parse the bonus production value strings
function Shared.parseBonus(bonusSetting, tierIndex)
	local numbers = {}
	local source = bonusSetting.value

	-- Find all numbers in the string (including those with decimals)
	for num in tostring(source):gmatch("[%d%.]+") do
		local value = tonumber(num)
		if value then
			table.insert(numbers, Shared.clamp(math.floor(value + 0.5), 0, 200))
		end
	end

	if #numbers == 0 then
		for num in tostring(bonusSetting.default_value):gmatch("[%d%.]+") do
			local value = tonumber(num)
			if value then
				table.insert(numbers, Shared.clamp(math.floor(value + 0.5), 0, 200))
			end
		end
	end

	return #numbers < 3 and numbers[1] or numbers[tierIndex] or numbers[#numbers] or 0
end

-- Parse the tile value strings
function Shared.parseTiles(tileSetting)
	local tiles = {}
	local source = tileSetting.value

	-- Check if tileSetting.value is empty or contains only whitespace
	if not source or source:match('^%s*$') then
		source = tileSetting.default_value
	end

	-- Find all words separated by commas
	for tile in tostring(source):gmatch('([^,]+)') do
		local trimmed = tile:match('^%s*(.-)%s*$')
		if trimmed ~= "" then
			tiles[#tiles + 1] = trimmed
		end
	end

	return tiles
end

-- Setting variables
Shared.SETTING = {
	ReinforcePopupToggle    = settings.startup["sf-reinforce-popup-toggle"].value,
	FriendlyDamageReduction = settings.startup["sf-friendly-reduction-toggle"].value,
	FriendlyPhysicalDamage  = settings.startup["sf-friendly-physical-reduction"].value,
	FriendlyExplosionDamage = settings.startup["sf-friendly-explosion-reduction"].value,
	FriendlyImpactDamage    = settings.startup["sf-friendly-impact-reduction"].value,
	ReinforceMiltBuildings  = settings.startup["sf-military-target-toggle"].value,
	ReinforceWalls          = settings.startup["sf-reinforce-wall-toggle"].value,
	ReinforceUnits          = settings.startup["sf-reinforce-units-toggle"].value,
	ReinforcePlayers        = settings.startup["sf-reinforce-players-toggle"].value,
	ReinforceQuality        = settings.startup["sf-quality-damage-reduction"].value,
	SafePoles               = settings.startup["sf-invulnerable-poles-toggle"].value,
	SafeRails               = settings.startup["sf-invulnerable-rails-toggle"].value,
	SafeLights              = settings.startup["sf-invulnerable-lamps-toggle"].value,
	EntityRefreshCount      = settings.startup["sf-entity-tick-count"].value,
	EntityTickRefresh       = settings.startup["sf-entity-refresh"].value,
	BuildingBonusEffects    = settings.startup["sf-building-bonus-toggle"].value,
	BuildingBonusList       = settings.startup["sf-list-bonus"],
	BuildingExcludeList     = settings.startup["sf-list-exclude"],
	IdentifiedList          = {"default"}
}

-- Setting names map
Shared.SF_LIST = {
	percent_1    = "sf-refined-reduction-percent",
	flat_1       = "sf-refined-reduction-flat",
	percent_2    = "sf-concrete-reduction-percent",
	flat_2       = "sf-concrete-reduction-flat",
	percent_3    = "sf-stone-reduction-percent",
	flat_3       = "sf-stone-reduction-flat",
	productivity = "sf-production-list",
	efficiency   = "sf-efficiency-list",
	speed        = "sf-speed-list",
	tier3        = "sf-list-tier3",
	tier2        = "sf-list-tier2",
	tier1        = "sf-list-tier1",
}

-- Foundation tier string parser
Shared.SF_NAMES = {
	[1] = Shared.parseTiles(settings.startup[Shared.SF_LIST.tier3]),
	[2] = Shared.parseTiles(settings.startup[Shared.SF_LIST.tier2]),
	[3] = Shared.parseTiles(settings.startup[Shared.SF_LIST.tier1]),
}

Shared.SF_TILES = {}

Shared.BUILDING_EXCLUDE_SET = {}

for _, name in ipairs(Shared.parseTiles(Shared.SETTING.BuildingExcludeList)) do
	Shared.BUILDING_EXCLUDE_SET[name] = true
end

function Shared.isBuildingBonusExcluded(object)
	return object
		and (Shared.BUILDING_EXCLUDE_SET[object.name]
			or Shared.BUILDING_EXCLUDE_SET[object.type])
end

-- Store foundation tiles into the list
for index, tier in ipairs(Shared.SF_NAMES) do
	for _, tile in pairs(tier) do
		Shared.SF_TILES[tile] = {
			tier         = index,
			percent      = settings.startup[Shared.SF_LIST["percent_" .. index]].value,
			flat         = settings.startup[Shared.SF_LIST["flat_" .. index]].value,
			productivity = Shared.parseBonus(settings.startup[Shared.SF_LIST.productivity], index),
			efficiency   = Shared.parseBonus(settings.startup[Shared.SF_LIST.efficiency], index),
			speed        = Shared.parseBonus(settings.startup[Shared.SF_LIST.speed], index)
		}
	end
end

return Shared

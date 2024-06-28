-- settings.lua
-- Dummiez 2024/06/27

data:extend {
	-- toggle settings
	{
		type = "bool-setting",
		name = "sf-building-bonus-toggle",
		setting_type = "startup",
		default_value = true,
		order = "aaa"
	},
	{
		type = "bool-setting",
		name = "sf-friendly-reduction-toggle",
		setting_type = "startup",
		default_value = true,
		order = "aab"
	},
	{
		type = "bool-setting",
		name = "sf-reinforce-popup-toggle",
		setting_type = "startup",
		default_value = true,
		order = "aac"
	},
	{
		type = "bool-setting",
		name = "sf-military-target-toggle",
		setting_type = "startup",
		default_value = true,
		order = "ab"
	},
	{
		type = "bool-setting",
		name = "sf-reinforce-wall-toggle",
		setting_type = "startup",
		default_value = true,
		order = "ac"
	},
	{
		type = "bool-setting",
		name = "sf-reinforce-units-toggle",
		setting_type = "startup",
		default_value = false,
		order = "ad"
	},
	{
		type = "bool-setting",
		name = "sf-reinforce-players-toggle",
		setting_type = "startup",
		default_value = false,
		order = "ae"
	},
	{
		type = "bool-setting",
		name = "sf-invulnerable-poles-toggle",
		setting_type = "startup",
		default_value = false,
		order = "af"
	},
	{
		type = "bool-setting",
		name = "sf-invulnerable-rails-toggle",
		setting_type = "startup",
		default_value = false,
		order = "ag"
	},
	{
		type = "bool-setting",
		name = "sf-invulnerable-lamps-toggle",
		setting_type = "startup",
		default_value = false,
		order = "ah"
	},
	-- {
	-- 	type = "bool-setting",
	-- 	name = "sf-production-bonus-toggle",
	-- 	setting_type = "startup",
	-- 	default_value = false,
	-- 	order = "ai"
	-- },
	-- {
	-- 	type = "bool-setting",
	-- 	name = "sf-efficiency-bonus-toggle",
	-- 	setting_type = "startup",
	-- 	default_value = false,
	-- 	order = "aj"
	-- },
	-- {
	-- 	type = "bool-setting",
	-- 	name = "sf-speed-bonus-toggle",
	-- 	setting_type = "startup",
	-- 	default_value = false,
	-- 	order = "ak"
	-- },
	-- percent settings
	{
		type = "int-setting",
		name = "sf-entity-refresh",
		setting_type = "startup",
		default_value = 3,
		minimum_value = 1,
		maximum_value = 60,
		order = "aha"
	},
	{
		type = "int-setting",
		name = "sf-entity-tick-count",
		setting_type = "startup",
		default_value = 200,
		minimum_value = 100,
		maximum_value = 10000,
		order = "ahb"
	},
	{
		type = "string-setting",
		name = "sf-production-list",
		setting_type = "startup",
		default_value = "5, 3, 2",
		order = "al"
	},
	{
		type = "string-setting",
		name = "sf-speed-list",
		setting_type = "startup",
		default_value = "10, 7, 4",
		order = "am"
	},
	{
		type = "string-setting",
		name = "sf-efficiency-list",
		setting_type = "startup",
		default_value = "15, 10, 5",
		order = "an"
	},
	{
		type = "int-setting",
		name = "sf-friendly-physical-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "ba"
	},
	{
		type = "int-setting",
		name = "sf-friendly-explosion-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "bb"
	},
	{
		type = "int-setting",
		name = "sf-friendly-impact-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "bc"
	},
	{
		type = "int-setting",
		name = "sf-refined-reduction-percent",
		setting_type = "startup",
		default_value = 40,
		minimum_value = 0,
		maximum_value = 100,
		order = "ca"
	},
	{
		type = "int-setting",
		name = "sf-refined-reduction-flat",
		setting_type = "startup",
		default_value = 10,
		minimum_value = 0,
		maximum_value = 1000,
		order = "cd"
	},
	{
		type = "int-setting",
		name = "sf-concrete-reduction-percent",
		setting_type = "startup",
		default_value = 30,
		minimum_value = 0,
		maximum_value = 100,
		order = "cb"
	},
	{
		type = "int-setting",
		name = "sf-concrete-reduction-flat",
		setting_type = "startup",
		default_value = 5,
		minimum_value = 0,
		maximum_value = 1000,
		order = "ce"
	},
	{
		type = "int-setting",
		name = "sf-stone-reduction-percent",
		setting_type = "startup",
		default_value = 20,
		minimum_value = 0,
		maximum_value = 100,
		order = "cc"
	},
	{
		type = "int-setting",
		name = "sf-stone-reduction-flat",
		setting_type = "startup",
		default_value = 2,
		minimum_value = 0,
		maximum_value = 1000,
		order = "cf"
	},
	{
		type = "string-setting",
		name = "sf-list-tier3",
		setting_type = "startup",
		default_value = "refined, reinforced, spaceship",
		order = "ea"
	},
	{
		type = "string-setting",
		name = "sf-list-tier2",
		setting_type = "startup",
		default_value = "concrete, tarmac, asphalt",
		order = "eb"
	},
	{
		type = "string-setting",
		name = "sf-list-tier1",
		setting_type = "startup",
		default_value = "stone, gravel, wood",
		order = "ec"
	},
	{
		type = "string-setting",
		name = "sf-list-bonus",
		setting_type = "startup",
		default_value = "furnace, assembling-machine, mining-drill",
		order = "ed"
	},
}

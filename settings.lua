data:extend {
	-- toggle settings
	{
		type = "bool-setting",
		name = "sf-reinforce-popup-toggle",
		setting_type = "startup",
		default_value = true,
		order = "aa"
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

	-- percent settings
	{
		type = "int-setting",
		name = "sf-friendly-physical-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "aea"
	},
	{
		type = "int-setting",
		name = "sf-friendly-explosion-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "aeb"
	},
	{
		type = "int-setting",
		name = "sf-friendly-impact-reduction",
		setting_type = "startup",
		default_value = 100,
		minimum_value = 0,
		maximum_value = 200,
		order = "aec"
	},
	{
		type = "int-setting",
		name = "sf-refined-reduction-percent",
		setting_type = "startup",
		default_value = 40,
		minimum_value = 0,
		maximum_value = 100,
		order = "ba"
	},
	{
		type = "int-setting",
		name = "sf-refined-reduction-flat",
		setting_type = "startup",
		default_value = 10,
		minimum_value = 0,
		maximum_value = 999,
		order = "bab"
	},
	{
		type = "int-setting",
		name = "sf-concrete-reduction-percent",
		setting_type = "startup",
		default_value = 30,
		minimum_value = 0,
		maximum_value = 100,
		order = "bb"
	},
	{
		type = "int-setting",
		name = "sf-concrete-reduction-flat",
		setting_type = "startup",
		default_value = 5,
		minimum_value = 0,
		maximum_value = 999,
		order = "bba"
	},
	{
		type = "int-setting",
		name = "sf-stone-reduction-percent",
		setting_type = "startup",
		default_value = 20,
		minimum_value = 0,
		maximum_value = 100,
		order = "bc"
	},
	{
		type = "int-setting",
		name = "sf-stone-reduction-flat",
		setting_type = "startup",
		default_value = 2,
		minimum_value = 0,
		maximum_value = 999,
		order = "bca"
	},
	{
		type = "int-setting",
		name = "sf-entity-refresh",
		setting_type = "startup",
		default_value = 6,
		minimum_value = 1,
		maximum_value = 120,
		order = "bcb"
	}
  }
local Config = {}

function Config.loadGameConfigs()
	-- Mod support for Beacon Rebalance
	if script.active_mods["wret-beacon-rebalance-mod"]
		and settings.startup["wret-overload-disable-overloaded"].value == true
		and remote.interfaces["wr-beacon-rebalance"] then
		remote.call("wr-beacon-rebalance", "add_whitelisted_beacon", "sf-tile-bonus")
	end
end

return Config

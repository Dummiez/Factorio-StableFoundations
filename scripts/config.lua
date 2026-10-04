local Config = {}

function Config.loadGameConfigs(revalidate)
	-- Support any Beacon Rebalance continuation that implements the same remote
	-- interface instead of coupling compatibility to a specific mod name.
	local beaconRebalance = remote.interfaces["wr-beacon-rebalance"]
	local overloadSetting = settings.startup["wret-overload-disable-overloaded"]
	if beaconRebalance
		and beaconRebalance["add_whitelisted_beacon"]
		and overloadSetting
		and overloadSetting.value == true then
		remote.call("wr-beacon-rebalance", "add_whitelisted_beacon", "sf-tile-bonus")

		-- Only the overload mod knows which disables it owns. Let its API
		-- revalidate receivers instead of clearing arbitrary script disables.
		-- Revalidate only during init/configuration changes; a joining client's
		-- first tick must not perform world mutations absent on the server.
		if revalidate and beaconRebalance.reset_beacons then
			remote.call("wr-beacon-rebalance", "reset_beacons")
		end
	end
end

return Config

local Config = {}

function Config.loadGameConfigs()
	-- Mod support for Beacon Rebalance
	if script.active_mods["wret-beacon-rebalance-mod"]
		and settings.startup["wret-overload-disable-overloaded"].value == true
		and remote.interfaces["wr-beacon-rebalance"] then
		remote.call("wr-beacon-rebalance", "add_whitelisted_beacon", "sf-tile-bonus")

		-- Rebalance keeps its whitelist in a Lua local that resets every script
		-- load. Receivers that got stuck overloaded during the previous session
		-- (when our hidden beacon was wrongly counted) won't auto-recover, so
		-- walk tracked foundation receivers and re-enable any whose real beacon
		-- count is <= 1 now that the whitelist is restored. reset_beacons is
		-- not enough — it only re-runs the disable path, never the enable.
		if storage.bonusBeacons then
			for uid, bonusBeacon in pairs(storage.bonusBeacons) do
				local entry = storage.sfEntity and storage.sfEntity[uid]
				local receiver = entry and entry.entity
				if receiver and receiver.valid and receiver.active == false
					and receiver.get_beacons then
					local realBeaconCount = 0
					local beacons = receiver.get_beacons()
					if beacons then
						for _, beacon in pairs(beacons) do
							if beacon.valid and beacon.name ~= "sf-tile-bonus" then
								realBeaconCount = realBeaconCount + 1
							end
						end
					end
					if realBeaconCount <= 1 then
						receiver.active = true
					end
				end
			end
		end
	end
end

return Config

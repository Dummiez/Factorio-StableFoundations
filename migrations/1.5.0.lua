-- migrations/1.5.0.lua
--
-- Position-based fallback UIDs now include surface index (entity_S_X_Y) and
-- player UIDs use player.index instead of player.name. Old string-keyed entries
-- in sfHealth / sfHealthEntities / sfSmokeCleanupTick can never be looked up
-- under the new format, so clear them. Tracking re-establishes naturally on
-- the next damage event.
--
-- Numeric (unit_number) keys are unaffected and stay intact.

local function purgeStringKeys(tbl)
	if not tbl then return end
	for uid in pairs(tbl) do
		if type(uid) == "string" then
			tbl[uid] = nil
		end
	end
end

purgeStringKeys(storage.sfHealth)
purgeStringKeys(storage.sfHealthEntities)
purgeStringKeys(storage.sfSmokeCleanupTick)

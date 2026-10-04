local State = {}
local Tooltip = require("scripts.tooltip")

function State.resetGlobalProperties()
	for _, key in ipairs({
		"sfEntity", "sfHealth", "sfHealthEntities", "reinforcedChunks", "bonusBeacons",
		"sfDestructibleState", "sfSelectionIndicators", "sfTooltipFieldIds", "sfDamageReports",
		"sfSmokeCleanupTick", "sfSeReNotifyQueue", "sfPostBuildRecheckQueue", "sfCoverageCheckTick", "sfRegisteredEntities"
	}) do
		storage[key] = {}
	end
	storage.sfLastDamageReportCleanup = 0
	storage.sfHealthCursor = nil
end

function State.initGlobalProperties()
	storage.sfEntity = storage.sfEntity or {}
	storage.sfHealth = storage.sfHealth or {}
	storage.sfHealthEntities = storage.sfHealthEntities or {}
	storage.reinforcedChunks = storage.reinforcedChunks or {}
	storage.bonusBeacons = storage.bonusBeacons or {}
	storage.sfDestructibleState = storage.sfDestructibleState or {}
	storage.sfSelectionIndicators = storage.sfSelectionIndicators or {}
	storage.sfTooltipFieldIds = storage.sfTooltipFieldIds or {}
	storage.sfDamageReports = storage.sfDamageReports or {}
	storage.sfSmokeCleanupTick = storage.sfSmokeCleanupTick or {}
	storage.sfLastDamageReportCleanup = storage.sfLastDamageReportCleanup or 0
	storage.sfSeReNotifyQueue = storage.sfSeReNotifyQueue or {}
	storage.sfPostBuildRecheckQueue = storage.sfPostBuildRecheckQueue or {}
	storage.sfCoverageCheckTick = storage.sfCoverageCheckTick or {}
	storage.sfRegisteredEntities = storage.sfRegisteredEntities or {}
end

function State.registerEntity(entity)
	local uid = entity.unit_number
	if uid and not storage.sfRegisteredEntities[uid] then
		storage.sfRegisteredEntities[uid] = script.register_on_object_destroyed(entity)
	end
end

function State.clearHealthTracking(entityUID)
	if storage.sfHealth then
		storage.sfHealth[entityUID] = nil
	end
	if storage.sfHealthEntities then
		storage.sfHealthEntities[entityUID] = nil
	end
	if storage.sfSmokeCleanupTick then
		storage.sfSmokeCleanupTick[entityUID] = nil
	end
end

function State.clearEntityTracking(entityUID)
	if storage.sfEntity then
		storage.sfEntity[entityUID] = nil
	end
	State.clearHealthTracking(entityUID)
	if storage.sfDestructibleState then
		storage.sfDestructibleState[entityUID] = nil
	end
	if storage.sfTooltipFieldIds then
		storage.sfTooltipFieldIds[entityUID] = nil
	end
	if storage.sfCoverageCheckTick then storage.sfCoverageCheckTick[entityUID] = nil end
	if storage.sfRegisteredEntities then storage.sfRegisteredEntities[entityUID] = nil end
	if storage.sfSeReNotifyQueue then storage.sfSeReNotifyQueue[entityUID] = nil end
end

-- Prune invalid LuaObjects and stale per-entity values after any mod changes.
-- This intentionally avoids surface scans or reapplying bonuses.
function State.pruneInvalidEntityReferences()
	if storage.sfHealth then
		for uid, value in pairs(storage.sfHealth) do
			if type(value) ~= "number" then
				State.clearHealthTracking(uid)
			end
		end
	end

	if storage.sfHealthEntities then
		for uid, entity in pairs(storage.sfHealthEntities) do
			if not storage.sfHealth[uid] or not entity or not entity.valid then
				storage.sfHealthEntities[uid] = nil
			end
		end
	end

	if storage.sfEntity then
		for uid, value in pairs(storage.sfEntity) do
			local entity = type(value) == "table" and value.entity
			if not entity or not entity.valid or not value.tileRate then
				if entity and entity.valid then
					Tooltip.clearFoundationFields(entity)
				end
				State.clearEntityTracking(uid)
			end
		end
	end

	if storage.sfDestructibleState then
		for uid, value in pairs(storage.sfDestructibleState) do
			if type(value) ~= "table" or not value.entity or not value.entity.valid then
				storage.sfDestructibleState[uid] = nil
			end
		end
	end

	if storage.sfTooltipFieldIds then
		for uid in pairs(storage.sfTooltipFieldIds) do
			local tracked = storage.sfEntity and storage.sfEntity[uid]
			if not (tracked and tracked.entity and tracked.entity.valid) then
				storage.sfTooltipFieldIds[uid] = nil
			end
		end
	end
end

return State

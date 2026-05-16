local State = {}

function State.initGlobalProperties()
	storage.sfEntity = storage.sfEntity or {}
	storage.sfHealth = storage.sfHealth or {}
	storage.sfHealthEntities = storage.sfHealthEntities or {}
	storage.reinforcedChunks = storage.reinforcedChunks or {}
	storage.bonusBeacons = storage.bonusBeacons or {}
	storage.sfDestructibleState = storage.sfDestructibleState or {}
	storage.sfSelectionIndicators = storage.sfSelectionIndicators or {}
	storage.sfDamageReports = storage.sfDamageReports or {}
	storage.sfSmokeCleanupTick = storage.sfSmokeCleanupTick or {}
	storage.sfLastDamageReportCleanup = storage.sfLastDamageReportCleanup or 0
	storage.sfSeReNotifyQueue = storage.sfSeReNotifyQueue or {}
	storage.sfPostBuildRecheckQueue = storage.sfPostBuildRecheckQueue or {}
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
end

return State

return function(Shared, State, Tiles, Invulnerability, Reinforcement)
	local Damage = {}

	local DAMAGE_REPORT_TTL_TICKS = 120
	local ENTITIES_PER_TICK = Shared.SETTING.EntityRefreshCount
	local SMOKE_CLEANUP_COOLDOWN_TICKS = 60
	local MAX_SMOKE_ENTITIES = 3
	local MAX_SMOKE_RADIUS = 5

	local damageIndicatorAvailable = false
	local nextEntityIndex = nil

	function Damage.refreshDamageIndicatorAvailability()
		local iface = remote.interfaces["damage-indicator"]
		damageIndicatorAvailable = (iface and iface["record_stable_foundations_damage_reduction"]) and true or false
	end

	local function getQualityDamageReduction(entityBuilding)
		if not entityBuilding.quality then return 0 end
		local quality_level = entityBuilding.quality.level or 0
		return quality_level * Shared.SETTING.ReinforceQuality
	end

	local function damageReportKey(entity)
		if entity.unit_number then
			return entity.unit_number
		end

		local position = entity.position
		return string.format("p:%d:%d:%d", entity.surface.index, math.floor(position.x * 4), math.floor(position.y * 4))
	end

	local function copyDamageReport(report)
		if not report then return nil end
		return {
			source = report.source,
			entity = report.entity,
			tick = report.tick,
			original_damage = report.original_damage,
			final_damage = report.final_damage,
			reduced_damage = report.reduced_damage,
			damage_type = report.damage_type
		}
	end

	local function notifyDamageIndicator(report)
		if not damageIndicatorAvailable then return end
		remote.call("damage-indicator", "record_stable_foundations_damage_reduction", report)
	end

	function Damage.cleanupDamageReports(currentTick, force)
		if not storage.sfDamageReports then return end
		if not force and currentTick - (storage.sfLastDamageReportCleanup or 0) < 60 then return end
		storage.sfLastDamageReportCleanup = currentTick

		local cutoff = currentTick - DAMAGE_REPORT_TTL_TICKS
		for key, report in pairs(storage.sfDamageReports) do
			if type(report) ~= "table" or not report.entity or not report.entity.valid or (report.tick or 0) < cutoff then
				storage.sfDamageReports[key] = nil
			end
		end
	end

	local function recordDamageReductionReport(entityBuilding, originalDamage, mitigatedDamage, damageType)
		local reducedDamage = originalDamage - mitigatedDamage
		if reducedDamage <= 0 then return end

		if not storage.sfDamageReports then State.initGlobalProperties() end
		Damage.cleanupDamageReports(game.tick)

		local report = {
			source = "StableFoundations",
			entity = entityBuilding,
			tick = game.tick,
			original_damage = originalDamage,
			final_damage = mitigatedDamage,
			reduced_damage = reducedDamage,
			damage_type = damageType
		}
		storage.sfDamageReports[damageReportKey(entityBuilding)] = report
		notifyDamageIndicator(report)
	end

	function Damage.entityStructureDamaged(entityBuilding, attackingEntity, attackingForce, finalDamage, finalHealth, damageType)
		if not (entityBuilding and entityBuilding.valid and finalDamage > 0 and entityBuilding.surface and entityBuilding.position) then return end
		if not Tiles.isChunkReinforced(entityBuilding.surface, entityBuilding.position) then return end
		if not Invulnerability.canReinforceBuilding(entityBuilding) then return end

		local tileRate = nil
		local entityUID = entityBuilding.unit_number

		if entityBuilding.prototype.is_building then
			if not entityUID then return end
			local entityData = storage.sfEntity[entityUID]
			tileRate = entityData and entityData.tileRate
			if not tileRate then return end

			-- Cheap drift check: weapons like atom bombs can clear the tile under a
			-- building without firing any tile-mined event, leaving stale reinforcement
			-- in storage. A single get_tile on the bounding-box corner catches the
			-- common case (large blasts that destroy the whole footprint) without
			-- running surface.count_tiles_filtered. Partial damage that leaves the
			-- corner intact will be caught on a subsequent damage event.
			local left, top = Tiles.getBoundingBox(entityBuilding)
			local cornerTile = entityBuilding.surface.get_tile(left, top)
			if not (cornerTile and Tiles.getTileReinforcement(cornerTile.name)) then
				Reinforcement.clearBuildingReinforcement(entityBuilding.surface, entityBuilding)
				return
			end
		else
			local buildTileType = entityBuilding.surface.get_tile(entityBuilding.position)
			if not buildTileType then return end
			tileRate = Tiles.getTileReinforcement(buildTileType.name)

			if not tileRate then return end

			if not entityUID then
				if entityBuilding.type == "character" and entityBuilding.player then
					entityUID = "player_" .. entityBuilding.player.index
				else
					entityUID = string.format("entity_%d_%d_%d",
						entityBuilding.surface.index,
						math.floor(entityBuilding.position.x),
						math.floor(entityBuilding.position.y))
				end
			end

			storage.sfHealthEntities = storage.sfHealthEntities or {}
			storage.sfHealthEntities[entityUID] = entityBuilding
		end

		if not storage.sfHealth[entityUID] then
			if finalHealth > 0 then
				storage.sfHealth[entityUID] = finalHealth + finalDamage
			else
				storage.sfHealth[entityUID] = entityBuilding.max_health
			end
		end

		Invulnerability.toggleInvulnerabilities(entityBuilding, false)
		if Shared.SETTING.SmokeCleanupEnabled and damageType == "poison" or damageType == "acid" then
			-- Per-entity throttle: poison ticks fire every few ticks per cloud, so without
			-- this every hit triggers a radius-5 find_entities_filtered. Capped at one scan
			-- per entity per cooldown window.
			local currentTick = game.tick
			storage.sfSmokeCleanupTick = storage.sfSmokeCleanupTick or {}
			local lastTick = storage.sfSmokeCleanupTick[entityUID]
			if not lastTick or currentTick - lastTick >= SMOKE_CLEANUP_COOLDOWN_TICKS then
				storage.sfSmokeCleanupTick[entityUID] = currentTick
				local smokes = entityBuilding.surface.find_entities_filtered {
					type = "smoke-with-trigger",
					position = entityBuilding.position,
					radius = MAX_SMOKE_RADIUS
				}
				if #smokes > MAX_SMOKE_ENTITIES then
					for i = MAX_SMOKE_ENTITIES + 1, #smokes do
						if smokes[i] and smokes[i].valid then
							smokes[i].destroy()
						end
					end
				end
			end
		end
		if not entityBuilding.destructible then return end

		local tileReducePercent = tileRate.percent
		local tileReduceFlat = tileRate.flat
		local effectReduce = 1

		local qualityReducePercent = getQualityDamageReduction(entityBuilding)
		local totalReducePercent = tileReducePercent + qualityReducePercent

		if (attackingForce == entityBuilding.force) and attackingEntity then
			if not Shared.SETTING.FriendlyDamageReduction then
				tileReduceFlat = 0
				totalReducePercent = 0
			end
			effectReduce = (damageType == "explosion" and Shared.SETTING.FriendlyExplosionDamage / 100
				or damageType == "impact" and Shared.SETTING.FriendlyImpactDamage / 100
				or damageType == "physical" and Shared.SETTING.FriendlyPhysicalDamage / 100
				or Shared.SETTING.FriendlyOtherDamage / 100)
		end

		local maxReducePercent = Shared.SETTING.MaxReductionPercent
		if totalReducePercent > maxReducePercent then totalReducePercent = maxReducePercent end

		local finalFlatDamage = (finalDamage - tileReduceFlat) > 0 and (finalDamage - tileReduceFlat) or
			1 / (tileReduceFlat - finalDamage + 2)
		local mitigatedDamage = (finalFlatDamage * effectReduce) * (1 - (totalReducePercent / 100))
		recordDamageReductionReport(entityBuilding, finalDamage, mitigatedDamage, damageType)

		local preHealth = storage.sfHealth[entityUID]
		local updatedHealth = preHealth - mitigatedDamage

		if updatedHealth > 0 then
			entityBuilding.health = updatedHealth
			if updatedHealth >= entityBuilding.max_health then
				State.clearHealthTracking(entityUID)
			else
				storage.sfHealth[entityUID] = updatedHealth
			end
		else
			entityBuilding.health = 0
			State.clearHealthTracking(entityUID)
		end
	end

	function Damage.periodicEntityCheck()
		if not storage.sfHealth then
			State.initGlobalProperties()
			return
		end

		local count = 0
		local currentIndex = nextEntityIndex
		local entitiesToRemove = {}

		if currentIndex and not storage.sfHealth[currentIndex] then
			currentIndex = nil
		end

		while count < ENTITIES_PER_TICK do
			local storedHealth
			currentIndex, storedHealth = next(storage.sfHealth, currentIndex)
			if not currentIndex then
				nextEntityIndex = nil
				break
			end

			if type(storedHealth) == "number" then
				local entityData = storage.sfEntity[currentIndex]
				local entity = entityData and entityData.entity
					or (storage.sfHealthEntities and storage.sfHealthEntities[currentIndex])
				if not entity or not entity.valid then
					table.insert(entitiesToRemove, currentIndex)
				else
					local health = entity.health
					local maxHealth = entity.max_health
					if not health or not maxHealth or health >= maxHealth or health <= 0 then
						table.insert(entitiesToRemove, currentIndex)
					elseif health ~= storedHealth then
						storage.sfHealth[currentIndex] = health
					end
				end
			else
				table.insert(entitiesToRemove, currentIndex)
			end

			count = count + 1
		end

		if currentIndex then
			nextEntityIndex = currentIndex
		end

		for _, entityUID in ipairs(entitiesToRemove) do
			State.clearHealthTracking(entityUID)
		end

		Damage.cleanupDamageReports(game.tick)
	end

	function Damage.handlePlayerRepairedEntity(event)
		local entity = event.entity
		if not (entity and entity.valid and entity.unit_number and storage.sfHealth) then return end

		local uid = entity.unit_number
		if not storage.sfHealth[uid] then return end
		storage.sfHealthEntities = storage.sfHealthEntities or {}
		if not (storage.sfEntity and storage.sfEntity[uid]) then
			storage.sfHealthEntities[uid] = entity
		end

		local health = entity.health
		local maxHealth = entity.max_health
		if not health or not maxHealth or health <= 0 or health >= maxHealth then
			State.clearHealthTracking(uid)
		else
			storage.sfHealth[uid] = health
		end
	end

	function Damage.makeRemoteInterface()
		return {
			version = function()
				return 1
			end,
			get_damage_reduction_report = function(entity, tick)
				if not (entity and entity.valid) then
					return nil
				end
				if not storage.sfDamageReports then State.initGlobalProperties() end

				local report = storage.sfDamageReports[damageReportKey(entity)]
				if type(report) ~= "table" then
					return nil
				end

				local requestedTick = tick and tonumber(tick) or nil
				if requestedTick and report.tick ~= requestedTick then
					return nil
				end
				if game.tick - report.tick > DAMAGE_REPORT_TTL_TICKS then
					return nil
				end

				return copyDamageReport(report)
			end,
			list_recent_damage_reduction_reports = function()
				if not storage.sfDamageReports then State.initGlobalProperties() end
				Damage.cleanupDamageReports(game.tick, true)

				local reports = {}
				for _, report in pairs(storage.sfDamageReports) do
					reports[#reports + 1] = copyDamageReport(report)
				end
				return reports
			end
		}
	end

	return Damage
end

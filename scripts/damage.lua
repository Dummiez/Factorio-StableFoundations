return function(Shared, State, Tiles, Invulnerability, Reinforcement)
	local Damage = {}

	local DAMAGE_REPORT_TTL_TICKS = 120
	local ENTITIES_PER_TICK = Shared.SETTING.EntityRefreshCount
	local SMOKE_CLEANUP_COOLDOWN_TICKS = 60
	local MAX_SMOKE_ENTITIES = 3
	local MAX_SMOKE_RADIUS = 5
	local COVERAGE_CHECK_INTERVAL = 60

	-- nil until first resolved. A joining client starts with nil, so a damage
	-- event before its first tick resolves the same value the server holds
	-- instead of silently skipping a notification the server sends.
	local damageIndicatorAvailable = nil

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
		if damageIndicatorAvailable == nil then Damage.refreshDamageIndicatorAvailability() end
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
		if not (entityBuilding and entityBuilding.valid and finalDamage > 0) then return end
		local entityUID = entityBuilding.unit_number
		local entityData = entityUID and storage.sfEntity[entityUID]
		-- With mobile protection disabled, only tracked structures can benefit.
		-- Skip unrelated combat before exporting any prototype or position data.
		if not entityData and not (Shared.SETTING.ReinforceUnits or Shared.SETTING.ReinforcePlayers) then return end
		if not Invulnerability.canReinforceBuilding(entityBuilding) then
			-- Keep observed, unprotected damage current if eligibility later changes.
			Damage.syncEntityHealth(entityBuilding)
			return
		end

		local tileRate = nil

		if entityBuilding.prototype.is_building then
			if not entityUID then return end
			if not Tiles.isChunkReinforced(entityBuilding.surface, entityBuilding.position) then return end
			tileRate = entityData and entityData.tileRate
			if not tileRate then return end

			-- Check the complete footprint, bounded to once per second per damaged
			-- building. A fixed corner can never detect a missing interior tile.
			local lastCheck = storage.sfCoverageCheckTick[entityUID]
			if not lastCheck or game.tick - lastCheck >= COVERAGE_CHECK_INTERVAL then
				storage.sfCoverageCheckTick[entityUID] = game.tick
				local tile = Tiles.getUniformReinforcedTile(entityBuilding.surface, entityBuilding)
				if not tile then
					Reinforcement.clearBuildingReinforcement(entityBuilding.surface, entityBuilding)
					return
				end
				local liveRate = Tiles.getTileReinforcement(tile.name)
				if not Shared.sameTileReinforcement(liveRate, tileRate) then
					Reinforcement.entityStructureReinforced(
						{ surface = entityBuilding.surface, force = entityBuilding.force }, nil, entityBuilding, true
					)
					tileRate = liveRate
				elseif liveRate ~= tileRate then
					-- Saved rate tables and freshly loaded settings have different
					-- identities even when their values match. Adopt the cached table
					-- without rebuilding tooltips and bonus beacons on the first hit.
					entityData.tileRate = liveRate
				end
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

		Invulnerability.toggleInvulnerabilities(entityBuilding, false)
		if Shared.SETTING.SmokeCleanupEnabled and (damageType == "poison" or damageType == "acid") then
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

		if attackingForce == entityBuilding.force then
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
		-- Ordinary hits expose their pre-hit health, avoiding stale repair data.
		-- Overkill clamps final_health to zero, so only that case needs the last
		-- observed health (or full health if no damaged-health record exists).
		-- Bound that estimate by the raw hit: a hit with no reduction cannot revive
		-- an entity. Include additive health changes from earlier event handlers.
		local maxHealth = entityBuilding.max_health
		local preHealth = finalDamage
		if finalHealth <= 0 and mitigatedDamage < finalDamage then
			preHealth = math.min(maxHealth, finalDamage, storage.sfHealth[entityUID] or maxHealth)
		end
		local updatedHealth = math.min(maxHealth, entityBuilding.health + preHealth - mitigatedDamage)

		if updatedHealth > 0 then
			entityBuilding.health = updatedHealth
			if updatedHealth >= maxHealth then
				State.clearHealthTracking(entityUID)
			else
				storage.sfHealth[entityUID] = updatedHealth
			end
		else
			entityBuilding.health = 0
			State.clearHealthTracking(entityUID)
		end
		recordDamageReductionReport(entityBuilding, finalDamage, mitigatedDamage, damageType)
	end

	function Damage.periodicEntityCheck()
		if not storage.sfHealth then
			State.initGlobalProperties()
			return
		end

		local count = 0
		-- A local cursor resets on a joining multiplayer client, causing peers
		-- to update different saved entries. Persist it with the tracked state.
		local currentIndex = storage.sfHealthCursor
		local entitiesToRemove = {}

		if currentIndex and not storage.sfHealth[currentIndex] then
			currentIndex = nil
		end

		while count < ENTITIES_PER_TICK do
			local storedHealth
			currentIndex, storedHealth = next(storage.sfHealth, currentIndex)
			if not currentIndex then
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

		storage.sfHealthCursor = currentIndex

		for _, entityUID in ipairs(entitiesToRemove) do
			State.clearHealthTracking(entityUID)
		end

		Damage.cleanupDamageReports(game.tick)
	end

	function Damage.syncEntityHealth(entity)
		if storage.sfRemovalPrepared then return false end
		if not (entity and entity.valid and entity.unit_number and storage.sfHealth) then return false end

		local uid = entity.unit_number
		if not (storage.sfEntity[uid] or storage.sfHealthEntities[uid]) then return false end
		local health = entity.health
		local maxHealth = entity.max_health
		-- During a clamped damage event zero health is already too late to observe
		-- the pre-hit value. Do not discard the fallback in a nested remote call.
		if not health or not maxHealth or health <= 0 then return false end
		if health >= maxHealth then
			State.clearHealthTracking(uid)
			return true
		end
		storage.sfHealthEntities = storage.sfHealthEntities or {}
		if not (storage.sfEntity and storage.sfEntity[uid]) then
			storage.sfHealthEntities[uid] = entity
		end
		storage.sfHealth[uid] = health
		return true
	end

	function Damage.handlePlayerRepairedEntity(event)
		Damage.syncEntityHealth(event.entity)
	end

	function Damage.makeRemoteInterface()
		return {
			version = function()
				return 1
			end,
			sync_entity_health = Damage.syncEntityHealth,
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

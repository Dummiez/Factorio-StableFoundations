return function(Shared, State, Tiles, Invulnerability, BuildingBonus, Indicators)
	local Reinforcement = {}
	local MAX_POST_BUILD_RECHECK_AGE_TICKS = 10

	local SE_SWAP_SUFFIXES = {
		"-grounded",
		"-spaced",
		"-_-grounded",
		"-_-spaced"
	}

	-- Note: no periodic tile-coverage scan here. Tile coverage is event-driven via
	-- on_player/robot/space_platform_built_tile, on_*_mined_tile, and
	-- script_raised_set_tiles handlers. A periodic scan would call
	-- surface.count_tiles_filtered for every multi-tile reinforced entity each
	-- cycle, which becomes costly on large bases.

	local function getMatchingBuilding(entityUser, entityBuilding, tileType)
		if not entityUser or not entityBuilding or not entityBuilding.valid or not tileType then return end
		if not (Invulnerability.canReinforceBuilding(entityBuilding, true) and entityBuilding.force == entityUser.force) then return end

		local tileRate = Tiles.getTileReinforcement(tileType.name)
		if not tileRate then return end

		local uid = entityBuilding.unit_number
		local existing = storage.sfEntity[uid]
		local isNewReinforcement = not existing or (existing.tileRate ~= tileRate)

		storage.sfEntity[uid] = { entity = entityBuilding, tileRate = tileRate }
		if entityBuilding.health > 0 and entityBuilding.health ~= entityBuilding.max_health then
			storage.sfHealth[uid] = entityBuilding.health
		end
		Indicators.refreshSelectionIndicatorsForEntity(entityBuilding)

		Tiles.markChunkReinforced(entityBuilding.surface, entityBuilding.position)
		local invCaption = Invulnerability.toggleInvulnerabilities(entityBuilding, false)

		if isNewReinforcement then
			local qualityLevel = entityBuilding.quality and entityBuilding.quality.level or 0
			local displayPercent = tileRate.percent + (qualityLevel * Shared.SETTING.ReinforceQuality)
			if displayPercent > Shared.SETTING.MaxReductionPercent then
				displayPercent = Shared.SETTING.MaxReductionPercent
			end

			Indicators.showPopupText(entityUser, entityBuilding, not invCaption and
				{ "",
					entityBuilding.localised_name or { "entity-name." .. entityBuilding.name },
					" ", { "sf-mod.reinforced-with" }, " ", tileType.localised_name or { "entity-name." .. tileType.name },
					" (" .. displayPercent .. "%)" }
				or
				{ "",
					entityBuilding.localised_name or { "entity-name." .. entityBuilding.name },
					" ", { "sf-mod.reinforced" } })
		end
	end

	local function addCandidateName(names, seen, name)
		if name and not seen[name] and prototypes.entity[name] then
			names[#names + 1] = name
			seen[name] = true
		end
	end

	local function getSwapCandidateNames(baseName)
		local names, seen = {}, {}
		addCandidateName(names, seen, baseName)

		for _, suffix in ipairs(SE_SWAP_SUFFIXES) do
			addCandidateName(names, seen, baseName .. suffix)

			if string.sub(baseName, -#suffix) == suffix then
				addCandidateName(names, seen, string.sub(baseName, 1, #baseName - #suffix))
			end
		end

		return names
	end

	local function mayBeSpaceExplorationSwapCandidate(entity)
		if not script.active_mods["space-exploration"] then return false end
		if not (entity and entity.valid and entity.name and entity.unit_number) then return false end

		for _, suffix in ipairs(SE_SWAP_SUFFIXES) do
			if prototypes.entity[entity.name .. suffix]
				or string.sub(entity.name, -#suffix) == suffix then
				return true
			end
		end

		return false
	end

	local function reactivateSwappedEntity(entity)
		entity.active = true
		pcall(function()
			if entity.disabled_by_script then
				entity.disabled_by_script = false
			end
		end)
	end

	function Reinforcement.queuePostBuildRecheck(entity)
		if not mayBeSpaceExplorationSwapCandidate(entity) then return end
		if not storage.sfPostBuildRecheckQueue then State.initGlobalProperties() end

		storage.sfPostBuildRecheckQueue[#storage.sfPostBuildRecheckQueue + 1] = {
			surface_index = entity.surface.index,
			position = { x = entity.position.x, y = entity.position.y },
			force_name = entity.force.name,
			name = entity.name,
			unit_number = entity.unit_number,
			tick = game.tick
		}
	end

	function Reinforcement.processPostBuildRecheckQueue()
		local queue = storage.sfPostBuildRecheckQueue
		if not (queue and #queue > 0) then return end

		storage.sfPostBuildRecheckQueue = {}

		for _, entry in ipairs(queue) do
			local isFresh = not entry.tick or (game.tick - entry.tick) <= MAX_POST_BUILD_RECHECK_AGE_TICKS
			local surface = isFresh and game.surfaces[entry.surface_index]
			local force = isFresh and game.forces[entry.force_name]
			if surface and force then
				local names = getSwapCandidateNames(entry.name)
				local candidates = surface.find_entities_filtered {
					name = names,
					position = entry.position,
					radius = 0.5,
					force = force
				}

				local replacement
				for _, candidate in pairs(candidates) do
					if candidate.valid and candidate.unit_number then
						if candidate.unit_number ~= entry.unit_number then
							replacement = candidate
							break
						end
						replacement = replacement or candidate
					end
				end

				if replacement and replacement.valid then
					if entry.unit_number and replacement.unit_number ~= entry.unit_number then
						State.clearEntityTracking(entry.unit_number)
						local transferredBonus = BuildingBonus.transferBonusBeacon(entry.unit_number, replacement.unit_number)
						if transferredBonus then
							reactivateSwappedEntity(replacement)
						end

						Reinforcement.entityStructureReinforced(
							{ surface = surface, force = replacement.force },
							nil,
							replacement
						)
					end
				elseif entry.unit_number then
					local tracked = storage.sfEntity and storage.sfEntity[entry.unit_number]
					local trackedEntity = tracked and tracked.entity
					if tracked and not (trackedEntity and trackedEntity.valid) then
						State.clearEntityTracking(entry.unit_number)
						BuildingBonus.destroyBonusBeacon(entry.unit_number)
					end
				end
			end
		end
	end

	function Reinforcement.clearBuildingReinforcement(surface, entityBuilding)
		if not (surface and entityBuilding and entityBuilding.valid and entityBuilding.unit_number) then return end

		local pos = entityBuilding.position

		Invulnerability.toggleInvulnerabilities(entityBuilding, true)
		State.clearEntityTracking(entityBuilding.unit_number)
		BuildingBonus.applyBuildingBonus(surface, entityBuilding, nil)
		Indicators.refreshSelectionIndicatorsForEntity(entityBuilding)

		Tiles.unmarkChunkIfEmpty(surface, pos)
	end

	function Reinforcement.entityStructureReinforced(entityUser, tileList, tileType)
		if not entityUser or not entityUser.surface then return end
		local mainSurface = entityUser.surface

		if tileList == nil then
			local entityBuilding = tileType
			if not Invulnerability.canReinforceBuilding(entityBuilding, true) then return end

			local reinforcedTile = Tiles.getUniformReinforcedTile(mainSurface, entityBuilding)

			if reinforcedTile then
				getMatchingBuilding(entityUser, entityBuilding, reinforcedTile)
				BuildingBonus.applyBuildingBonus(mainSurface, entityBuilding, reinforcedTile)
			else
				Reinforcement.clearBuildingReinforcement(mainSurface, entityBuilding)
			end
			return
		end

		-- Pre-filter by force so trees, rocks, particles, and enemy structures don't enter the candidate set.
		-- For dense tile events (landfill blueprint, large stone paving), one area
		-- scan over the union bounding-box is dramatically cheaper than N per-tile
		-- scans. For sparse events (scattered tiles), the per-tile path is cheaper
		-- because the union bbox is mostly empty. Switch based on tile density.
		local userForce = entityUser.force
		local uniqueBuildings = {}

		local tileCount = #tileList
		local useUnionScan = false
		local minX, minY, maxX, maxY = 0, 0, 0, 0
		if tileCount >= 8 then
			minX, minY = math.huge, math.huge
			maxX, maxY = -math.huge, -math.huge
			for _, eventTile in ipairs(tileList) do
				local p = eventTile.position
				if p.x < minX then minX = p.x end
				if p.y < minY then minY = p.y end
				if p.x > maxX then maxX = p.x end
				if p.y > maxY then maxY = p.y end
			end
			local unionArea = (maxX - minX + 1) * (maxY - minY + 1)
			-- Use union scan when tile density >= 25% of the bbox (heuristic break-even).
			useUnionScan = (tileCount * 4) >= unionArea
		end

		if useUnionScan then
			local unionArea = { { minX, minY }, { maxX + 1, maxY + 1 } }
			local found = userForce
				and mainSurface.find_entities_filtered { area = unionArea, force = userForce }
				or mainSurface.find_entities(unionArea)
			for _, entityBuilding in pairs(found) do
				if entityBuilding.valid and entityBuilding.unit_number then
					uniqueBuildings[entityBuilding.unit_number] = entityBuilding
				end
			end
		else
			for _, eventTile in ipairs(tileList) do
				local findEntityArea = Tiles.getTileSearchArea(eventTile.position)
				local found = userForce
					and mainSurface.find_entities_filtered { area = findEntityArea, force = userForce }
					or mainSurface.find_entities(findEntityArea)
				for _, entityBuilding in pairs(found) do
					if entityBuilding.valid and entityBuilding.unit_number then
						uniqueBuildings[entityBuilding.unit_number] = entityBuilding
					end
				end
			end
		end

		for _, entityBuilding in pairs(uniqueBuildings) do
			if entityBuilding.valid and Invulnerability.canReinforceBuilding(entityBuilding, true) then
				local reinforcedTile = Tiles.getUniformReinforcedTile(mainSurface, entityBuilding)
				if reinforcedTile then
					getMatchingBuilding(entityUser, entityBuilding, reinforcedTile)
					BuildingBonus.applyBuildingBonus(mainSurface, entityBuilding, reinforcedTile)
				else
					Reinforcement.clearBuildingReinforcement(mainSurface, entityBuilding)
				end
			end
		end
	end

	function Reinforcement.entityStructureDestroyed(entityBuilding)
		if entityBuilding and entityBuilding.valid and entityBuilding.unit_number then
			State.clearEntityTracking(entityBuilding.unit_number)
			BuildingBonus.removeBuildingBonus(entityBuilding)
		end
	end

	function Reinforcement.handleScriptSetTiles(event)
		local surface = game.surfaces[event.surface_index]
		if not surface then return end
		if not (event.tiles and #event.tiles > 0) then return end

		-- Split tiles into reinforcement vs. non-reinforcement so chunk marks/unmarks
		-- can be batched. Chunks that received any reinforcement tile are skipped during
		-- unmark since we know they still have at least one.
		local reinforcementTiles, otherTiles = {}, {}
		for _, tile in ipairs(event.tiles) do
			local tileProto = surface.get_tile(tile.position).prototype
			if tileProto and Tiles.getTileReinforcement(tileProto.name) then
				reinforcementTiles[#reinforcementTiles + 1] = tile
			else
				otherTiles[#otherTiles + 1] = tile
			end
		end

		local markedChunks = {}
		for _, tile in ipairs(reinforcementTiles) do
			local chunkX = math.floor(tile.position.x / 32)
			local chunkY = math.floor(tile.position.y / 32)
			markedChunks[chunkX .. "," .. chunkY] = true
		end

		Tiles.markChunksFromTiles(surface, reinforcementTiles)
		Tiles.unmarkChunksIfEmpty(surface, otherTiles, markedChunks)

		-- Same union-bbox vs per-tile heuristic as in entityStructureReinforced.
		local uniqueBuildings = {}

		local tileCount = #event.tiles
		local useUnionScan = false
		local minX, minY, maxX, maxY = 0, 0, 0, 0
		if tileCount >= 8 then
			minX, minY = math.huge, math.huge
			maxX, maxY = -math.huge, -math.huge
			for _, tile in ipairs(event.tiles) do
				local p = tile.position
				if p.x < minX then minX = p.x end
				if p.y < minY then minY = p.y end
				if p.x > maxX then maxX = p.x end
				if p.y > maxY then maxY = p.y end
			end
			local unionArea = (maxX - minX + 1) * (maxY - minY + 1)
			useUnionScan = (tileCount * 4) >= unionArea
		end

		if useUnionScan then
			local unionArea = { { minX, minY }, { maxX + 1, maxY + 1 } }
			for _, entityBuilding in pairs(surface.find_entities(unionArea)) do
				if entityBuilding.valid and entityBuilding.unit_number then
					uniqueBuildings[entityBuilding.unit_number] = entityBuilding
				end
			end
		else
			for _, tile in ipairs(event.tiles) do
				local findArea = Tiles.getTileSearchArea(tile.position)
				for _, entityBuilding in pairs(surface.find_entities(findArea)) do
					if entityBuilding.valid and entityBuilding.unit_number then
						uniqueBuildings[entityBuilding.unit_number] = entityBuilding
					end
				end
			end
		end

		for _, entityBuilding in pairs(uniqueBuildings) do
			if entityBuilding.valid and Invulnerability.canReinforceBuilding(entityBuilding, true) then
				local user = { surface = surface, force = entityBuilding.force }
				local reinforcedTile = Tiles.getUniformReinforcedTile(surface, entityBuilding)

				if reinforcedTile then
					getMatchingBuilding(user, entityBuilding, reinforcedTile)
					BuildingBonus.applyBuildingBonus(surface, entityBuilding, reinforcedTile)
				else
					Reinforcement.clearBuildingReinforcement(surface, entityBuilding)
				end
			end
		end
	end

	return Reinforcement
end

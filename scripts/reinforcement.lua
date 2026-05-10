return function(Shared, State, Tiles, Invulnerability, BuildingBonus, Indicators)
	local Reinforcement = {}

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
		local userForce = entityUser.force
		local uniqueBuildings = {}

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

		local uniqueBuildings = {}

		for _, tile in ipairs(event.tiles) do
			local findArea = Tiles.getTileSearchArea(tile.position)
			for _, entityBuilding in pairs(surface.find_entities(findArea)) do
				if entityBuilding.valid and entityBuilding.unit_number then
					uniqueBuildings[entityBuilding.unit_number] = entityBuilding
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

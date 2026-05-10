return function(Shared, State)
	local Tiles = {}

	local tileReinforcementCache = {}
	local tilePatternMatchers = {}

	-- Lua-pattern magic chars that need escaping. `*` is NOT escaped so it can be
	-- promoted to a wildcard in the user-pattern path below.
	local LUA_MAGIC = "([%(%)%.%%%+%-%?%[%]%^%$])"

	-- Compile a user-supplied tile pattern into a matcher.
	-- - Contains `*`: glob mode. `*stone*` substring, `stone*` prefix, `*stone` suffix.
	-- - No `*`:       word-boundary mode. `stone` matches `stone-path`, `stone_brick`,
	--                 but NOT `limestone-brick` or `redstone-floor`. Boundaries apply
	--                 only on alphanumeric edges, so `wood-` still matches `wood-floor`.
	local function compileTileMatcher(rawPattern)
		if string.find(rawPattern, "*", 1, true) then
			local escaped = rawPattern:gsub(LUA_MAGIC, "%%%1")
			local converted = escaped:gsub("%*", ".*")
			local prefix = string.sub(rawPattern, 1, 1) == "*" and "" or "^"
			local suffix = string.sub(rawPattern, -1) == "*" and "" or "$"
			return prefix .. converted .. suffix
		end
		local escaped = rawPattern:gsub(LUA_MAGIC, "%%%1")
		local leftBound = string.match(string.sub(rawPattern, 1, 1), "%w") and "%f[%w]" or ""
		local rightBound = string.match(string.sub(rawPattern, -1), "%w") and "%f[%W]" or ""
		return leftBound .. escaped .. rightBound
	end

	function Tiles.resetTileReinforcementCache()
		tileReinforcementCache = {}
		tilePatternMatchers = {}

		for index, tier in ipairs(Shared.SF_NAMES) do
			for _, tileName in ipairs(tier) do
				local tileRate = Shared.SF_TILES[tileName]
				if tileRate then
					tileReinforcementCache[tileName] = tileRate
					table.insert(tilePatternMatchers, {
						rawPattern = tileName,
						pattern = compileTileMatcher(tileName),
						rate = tileRate,
						tier = index
					})
				end
			end
		end

		table.sort(tilePatternMatchers, function(a, b)
			if a.tier ~= b.tier then return a.tier < b.tier end
			return #a.rawPattern > #b.rawPattern
		end)
	end

	-- Exact tile names hit the cache first. Pattern fallback is ordered by tier and
	-- length so overlapping defaults like "refined" and "concrete" stay stable.
	function Tiles.getTileReinforcement(tileName)
		if not tileName then return nil end
		local cached = tileReinforcementCache[tileName]
		if cached ~= nil then
			return cached or nil
		end

		for _, matcher in ipairs(tilePatternMatchers) do
			if string.find(tileName, matcher.pattern) then
				tileReinforcementCache[tileName] = matcher.rate
				return matcher.rate
			end
		end

		tileReinforcementCache[tileName] = false
		return nil
	end

	-- Compute integer bounding box coords from entity, returns left, top, right, bottom, width, height
	-- Epsilon offsets strip Factorio's fractional bounding box padding (usually +/-0.4).
	function Tiles.getBoundingBox(entityBuilding)
		local box = entityBuilding.bounding_box
		local left = math.floor(box.left_top.x + 0.1)
		local top = math.floor(box.left_top.y + 0.1)
		local right = math.ceil(box.right_bottom.x - 0.1)
		local bottom = math.ceil(box.right_bottom.y - 0.1)
		return left, top, right, bottom, right - left, bottom - top
	end

	function Tiles.getTileSearchArea(position)
		return {
			{ position.x,     position.y },
			{ position.x + 1, position.y + 1 }
		}
	end

	function Tiles.isFootprintUniform(surface, entityBuilding, tileType, cheapPath)
		if not tileType then return false end

		if cheapPath then
			return Tiles.getTileReinforcement(tileType.name) ~= nil
		end

		local left, top, right, bottom, w, h = Tiles.getBoundingBox(entityBuilding)
		local expectedArea = w * h
		if expectedArea <= 0 then return false end

		local tileCount = surface.count_tiles_filtered {
			area = { { left, top }, { right, bottom } },
			name = tileType.name
		}
		return tileCount == expectedArea
	end

	function Tiles.getUniformReinforcedTile(surface, entityBuilding)
		if not (surface and entityBuilding and entityBuilding.valid) then return nil end

		local left, top, _, _, w, h = Tiles.getBoundingBox(entityBuilding)
		if w <= 0 or h <= 0 then return nil end

		if w == 1 and h == 1 then
			local centerTile = surface.get_tile({
				math.floor(entityBuilding.position.x),
				math.floor(entityBuilding.position.y)
			}).prototype
			return Tiles.getTileReinforcement(centerTile.name) and centerTile or nil
		end

		local candidateTile = surface.get_tile({ left, top }).prototype
		if not candidateTile or not Tiles.getTileReinforcement(candidateTile.name) then
			return nil
		end

		return Tiles.isFootprintUniform(surface, entityBuilding, candidateTile, false) and candidateTile or nil
	end

	local function chunkKeyFor(position)
		local chunkX = math.floor(position.x / 32)
		local chunkY = math.floor(position.y / 32)
		return chunkX, chunkY, chunkX .. "," .. chunkY
	end

	function Tiles.markChunkReinforced(surface, position)
		if not surface or not position then return end
		if not storage.reinforcedChunks then State.initGlobalProperties() end

		local _, _, chunkKey = chunkKeyFor(position)
		storage.reinforcedChunks[surface.index] = storage.reinforcedChunks[surface.index] or {}
		storage.reinforcedChunks[surface.index][chunkKey] = true
	end

	-- Batch variant: deduplicate by chunk so a 200x200 tile placement marks each chunk once.
	function Tiles.markChunksFromTiles(surface, tiles)
		if not (surface and tiles) then return end
		if not storage.reinforcedChunks then State.initGlobalProperties() end
		storage.reinforcedChunks[surface.index] = storage.reinforcedChunks[surface.index] or {}
		local surfaceChunks = storage.reinforcedChunks[surface.index]

		local seen = {}
		for _, tile in ipairs(tiles) do
			local _, _, chunkKey = chunkKeyFor(tile.position)
			if not seen[chunkKey] then
				seen[chunkKey] = true
				surfaceChunks[chunkKey] = true
			end
		end
	end

	local function chunkStillHasReinforcement(surface, chunkX, chunkY)
		local tilesInChunk = surface.find_tiles_filtered({
			area = {
				{ chunkX * 32,      chunkY * 32 },
				{ chunkX * 32 + 32, chunkY * 32 + 32 }
			}
		})
		for _, tile in pairs(tilesInChunk) do
			if Tiles.getTileReinforcement(tile.name) then
				return true
			end
		end
		return false
	end

	function Tiles.unmarkChunkIfEmpty(surface, position)
		if not surface or not position or not storage.reinforcedChunks then return end
		local surfaceChunks = storage.reinforcedChunks[surface.index]
		if not surfaceChunks then return end
		local chunkX, chunkY, chunkKey = chunkKeyFor(position)
		if not surfaceChunks[chunkKey] then return end

		if not chunkStillHasReinforcement(surface, chunkX, chunkY) then
			surfaceChunks[chunkKey] = nil
		end
	end

	-- Batch variant: collapse N mined tiles to at most one chunk-scan per affected chunk.
	function Tiles.unmarkChunksIfEmpty(surface, tiles, skipChunks)
		if not (surface and tiles and storage.reinforcedChunks) then return end
		local surfaceChunks = storage.reinforcedChunks[surface.index]
		if not surfaceChunks then return end

		local toScan = {}
		for _, tile in ipairs(tiles) do
			local chunkX, chunkY, chunkKey = chunkKeyFor(tile.position)
			if surfaceChunks[chunkKey]
				and not toScan[chunkKey]
				and not (skipChunks and skipChunks[chunkKey]) then
				toScan[chunkKey] = { x = chunkX, y = chunkY }
			end
		end

		for chunkKey, coords in pairs(toScan) do
			if not chunkStillHasReinforcement(surface, coords.x, coords.y) then
				surfaceChunks[chunkKey] = nil
			end
		end
	end

	function Tiles.isChunkReinforced(surface, position)
		if not surface or not position or not storage.reinforcedChunks then return false end
		local _, _, chunkKey = chunkKeyFor(position)
		return storage.reinforcedChunks[surface.index] and
			storage.reinforcedChunks[surface.index][chunkKey] or false
	end

	Tiles.resetTileReinforcementCache()

	return Tiles
end

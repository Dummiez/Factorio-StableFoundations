return function(Shared, Tiles, Invulnerability)
	local Indicators = {}

	local SF_TEXT_SPEED = 1.6
	local SF_TIME_TO_LIVE = 100
	local SF_TEXT_COLOR = { r = 0.9, g = 0.9, b = 0.7, a = 0.9 }

	function Indicators.clearSelectionIndicator(playerIndex)
		storage.sfSelectionIndicators = storage.sfSelectionIndicators or {}
		local indicatorId = storage.sfSelectionIndicators[playerIndex]
		local indicator = indicatorId and rendering.get_object_by_id(indicatorId)
		if indicator and indicator.valid then
			indicator.destroy()
		end
		storage.sfSelectionIndicators[playerIndex] = nil
	end

	local function getSelectedEntityTileRate(entity)
		if not (entity and entity.valid and entity.unit_number) then return nil end

		if entity.prototype.is_building then
			local entityData = storage.sfEntity and storage.sfEntity[entity.unit_number]
			return entityData and entityData.tileRate
		end

		if not Invulnerability.canReinforceBuilding(entity) then return nil end

		local tile = entity.surface.get_tile(entity.position)
		return tile and Tiles.getTileReinforcement(tile.name) or nil
	end

	local function getIndicatorReductionPercent(entity, tileRate)
		local qualityLevel = entity.quality and entity.quality.level or 0
		local reduction = tileRate.percent + (qualityLevel * Shared.SETTING.ReinforceQuality)
		local maxPercent = Shared.SETTING.MaxReductionPercent
		return reduction > maxPercent and maxPercent or reduction
	end

	function Indicators.getReinforcedTextOffset(entity)
		local _, _, _, _, _, height = Tiles.getBoundingBox(entity)
		return { 0, -math.max(0.8, (height / 2) + 0.35) }
	end

	function Indicators.getReinforcedTextPosition(entity)
		local offset = Indicators.getReinforcedTextOffset(entity)
		return {
			x = entity.position.x + offset[1],
			y = entity.position.y + offset[2]
		}
	end

	function Indicators.updateSelectionIndicator(player)
		if not (player and player.valid) then return end
		storage.sfSelectionIndicators = storage.sfSelectionIndicators or {}
		Indicators.clearSelectionIndicator(player.index)

		if not Shared.SETTING.ReinforcePopupToggle then
			return
		end
		if not (player.game_view_settings and player.game_view_settings.show_entity_info) then
			return
		end

		local entity = player.selected
		local tileRate = getSelectedEntityTileRate(entity)
		if not tileRate then
			return
		end

		local textOffset = Indicators.getReinforcedTextOffset(entity)
		local reductionPercent = getIndicatorReductionPercent(entity, tileRate)
		local indicatorText = Invulnerability.isOwnedSafeOverride(entity)
			and { "sf-mod.reinforced-indicator-safe" }
			or { "sf-mod.reinforced-indicator", Shared.SETTING.MaxReductionPercent == reductionPercent and "*".. reductionPercent or reductionPercent .. "%" }

		local indicator = rendering.draw_text {
			text = indicatorText,
			surface = entity.surface,
			target = { entity = entity, offset = textOffset },
			color = SF_TEXT_COLOR,
			scale = 1.5,
			alignment = "center",
			vertical_alignment = "middle",
			scale_with_zoom = true,
			players = { player.index },
			use_rich_text = false
		}
		storage.sfSelectionIndicators[player.index] = indicator.id
	end

	function Indicators.refreshSelectionIndicatorsForEntity(entity)
		if not (entity and entity.valid) then return end
		for _, player in pairs(game.connected_players) do
			if player.selected == entity then
				Indicators.updateSelectionIndicator(player)
			end
		end
	end

	function Indicators.refreshMovableSelectionIndicators()
		for _, player in pairs(game.connected_players) do
			local entity = player.selected
			if entity and entity.valid and entity.unit_number and not entity.prototype.is_building then
				Indicators.updateSelectionIndicator(player)
			end
		end
	end

	function Indicators.showPopupText(entityUser, entityBuilding, caption)
		if not (Shared.SETTING.ReinforcePopupToggle and entityUser.force and entityUser.force.players) then return end
		local textPosition = Indicators.getReinforcedTextPosition(entityBuilding)
		for _, player in pairs(entityUser.force.players) do
			if player and player.valid and player.character and entityBuilding.last_user and entityBuilding.surface == player.surface then
				player.create_local_flying_text {
					text = caption,
					position = textPosition,
					create_at_cursor = false,
					speed = SF_TEXT_SPEED,
					time_to_live = SF_TIME_TO_LIVE,
					color = SF_TEXT_COLOR,
				}
			end
		end
	end

	return Indicators
end

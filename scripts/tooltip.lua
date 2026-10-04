local Tooltip = {}

-- Runtime tooltip fields belong to the entity, not the mod. Saved IDs can be
-- lost on removal/reinstallation or copied with an entity, so identify our
-- fields by their names before updating or deleting anything.
function Tooltip.getFoundationFields(entity)
	local fields = {}
	if not (entity and entity.valid and entity.get_tooltip_fields) then return fields end
	for _, field in pairs(entity.get_tooltip_fields()) do
		if type(field.name) == "table" and field.name[1] == "sf-mod.foundation-label" then
			fields[#fields + 1] = field
		end
	end
	return fields
end

function Tooltip.clearFoundationFields(entity)
	local fields = Tooltip.getFoundationFields(entity)
	for _, field in ipairs(fields) do
		entity.clear_tooltip_field(field.id)
	end
	return #fields
end

function Tooltip.adoptFoundationField(entity)
	local fields = Tooltip.getFoundationFields(entity)
	local fieldId = fields[1] and fields[1].id
	for i = 2, #fields do
		entity.clear_tooltip_field(fields[i].id)
	end
	return fieldId
end

return Tooltip

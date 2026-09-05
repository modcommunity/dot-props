@tool
class_name DotPropCatalogue
extends Resource

## Every prop a server offers, and the file an operator edits.
##
## Same shape and the same reasoning as [code]DotMapCatalogue[/code]: plain JSON,
## because the person maintaining it on a community server is a person with a text
## editor; one bad entry does not condemn the file; an exact id match wins a search.

const CHANNEL := "props.catalogue"

const FORMAT_VERSION := 1

@export var props: Array[DotPropDef] = []

@export var meta: Dictionary = {}

var _by_id: Dictionary = {}


func add(prop: DotPropDef) -> DotResult:
	if prop == null:
		return DotResult.fail(DotError.CODE_INVALID, "No prop to add.")

	var valid := prop.validate()

	if not valid.ok:
		return valid

	if _by_id.size() != props.size():
		_reindex()

	if _by_id.has(prop.id):
		var existing: DotPropDef = _by_id[prop.id]
		props[props.find(existing)] = prop
		_by_id[prop.id] = prop
		return DotResult.success(prop)

	props.append(prop)
	_by_id[prop.id] = prop

	return DotResult.success(prop)


func get_prop(id: StringName) -> DotPropDef:
	if _by_id.size() != props.size():
		_reindex()

	var found: Variant = _by_id.get(id)
	return found if found is DotPropDef else null


func has(id: StringName) -> bool:
	return get_prop(id) != null


func size() -> int:
	return props.size()


func remove(id: StringName) -> bool:
	_reindex()

	if not _by_id.has(id):
		return false

	props.erase(_by_id[id])
	_by_id.erase(id)

	return true


func _reindex() -> void:
	_by_id.clear()

	for prop in props:
		_by_id[prop.id] = prop


## Every category, in alphabetical order. For a spawn menu's tabs.
func categories() -> PackedStringArray:
	var seen := {}

	for prop in props:
		if prop.enabled:
			seen[String(prop.category)] = true

	var out := PackedStringArray(seen.keys())
	out.sort()

	return out


func in_category(category: StringName) -> Array[DotPropDef]:
	var out: Array[DotPropDef] = []

	for prop in props:
		if prop.enabled and prop.category == category:
			out.append(prop)

	return out


## Props whose id or name contains [param text]. An exact id wins outright.
func search(text: String, limit: int = 30) -> Array[DotPropDef]:
	var needle := text.strip_edges().to_lower()
	var out: Array[DotPropDef] = []

	if needle == "":
		return out

	var exact := get_prop(StringName(needle))

	if exact != null:
		out.append(exact)
		return out

	for prop in props:
		if out.size() >= limit:
			break

		if (
			String(prop.id).to_lower().contains(needle)
			or prop.display_name.to_lower().contains(needle)
		):
			out.append(prop)

	return out


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}

	for prop in props:
		var valid := prop.validate()

		if not valid.ok:
			out.append("%s: %s" % [String(prop.id), valid.error.message])

		if seen.has(prop.id):
			out.append("%s appears twice" % String(prop.id))

		seen[prop.id] = true

	return out


func to_dictionary() -> Dictionary:
	var list: Array = []

	for prop in props:
		list.append(prop.to_dictionary())

	return {"format": FORMAT_VERSION, "meta": meta.duplicate(true), "props": list}


func to_json(pretty: bool = true) -> String:
	return JSON.stringify(to_dictionary(), "  " if pretty else "")


static func from_dictionary(data: Dictionary) -> DotResult:
	var format := int(data.get("format", 0))

	if format > FORMAT_VERSION:
		return DotResult.fail(
			DotError.CODE_VERSION,
			"That prop catalogue was written by a newer version of dot-props.",
			"format %d, this build reads %d" % [format, FORMAT_VERSION]
		)

	var catalogue := DotPropCatalogue.new()

	var meta_value: Variant = data.get("meta", {})
	catalogue.meta = (
		(meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	)

	var list_value: Variant = data.get("props", [])

	if not (list_value is Array):
		return DotResult.fail(DotError.CODE_PARSE, "The props key is not a list.")

	var refused := PackedStringArray()

	for entry in (list_value as Array):
		if not (entry is Dictionary):
			continue

		var prop := DotPropDef.from_dictionary(entry)
		var added := catalogue.add(prop)

		if not added.ok:
			refused.append("%s: %s" % [String(prop.id), added.error.message])

	if not refused.is_empty():
		DotLog.warn(CHANNEL, "some prop entries were dropped", {
			"count": refused.size(), "entries": ", ".join(refused)
		})

	return DotResult.success(catalogue)


static func from_json(text: String) -> DotResult:
	var parsed: Variant = JSON.parse_string(text)

	if not (parsed is Dictionary):
		return DotResult.fail(
			DotError.CODE_PARSE, "A prop catalogue must be a JSON object."
		)

	return from_dictionary(parsed)


static func load_json(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "No prop catalogue there.", path)

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return DotResult.failure(
			DotError.from_engine(FileAccess.get_open_error(), path)
		)

	var text := file.get_as_text()
	file.close()

	return from_json(text).wrap("Could not read %s." % path)


func describe() -> Dictionary:
	return {
		"props": props.size(),
		"categories": categories().size(),
	}


func _to_string() -> String:
	return "DotPropCatalogue(%d props)" % props.size()

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

## The visible followed set changed (a pack arrived, the session switched, [method refresh_content]).
## A spawn menu rebuilds on this. (Not `changed`: Resource already has one, for the editor.)
signal content_changed

var _index: DotContentIndex = null
var _kinds: PackedStringArray = PackedStringArray()

## The rows [method follow_content] added, so a refresh removes those and nothing else.
var _followed: Array[DotPropDef] = []


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


## Download every pack this catalogue's props live in.
##
## [b]Nothing used to fetch these.[/b] A DotPropDef has carried a `content_id` since it was
## written and it is serialised onto the wire, but no code anywhere asked dot-cloud for
## one — so a delivered prop was refused with "that prop's content is not loaded",
## forever, on a server that had configured it perfectly. The refusal is correct and
## that is what made it invisible: it reads as a missing pack rather than as a fetch
## that never happens.
##
## [b]At load, not on demand.[/b] A spawn request is a player's, and turning one into a
## download would let a player make this machine fetch — repeatedly, from whatever a
## manifest names — by asking for something that is not there. The catalogue is known
## before anyone connects, so this is a boot-time cost paid once. It also keeps the
## spawn path synchronous, which is what every caller of it already assumes.
##
## Non-fatal by construction: a pack that will not download leaves that prop
## unspawnable and everything else working. See [method DotContent.ensure_all] for the
## shape of the answer.
func ensure_content() -> DotResult:
	if _by_id.size() != props.size():
		_reindex()

	var ids := PackedStringArray()

	for entry in props:
		if entry != null and String(entry.content_id) != "":
			ids.append(String(entry.content_id))

	return await DotContent.ensure_all(ids)


## Follow a [DotContentIndex]: every [param kinds] entry (default [code]prop[/code]) of a mounted
## Workshop pack, in the index's current session, becomes a [DotPropDef] here, and the rows are
## rebuilt whenever a pack arrives or the session changes. This is how a subscription reaches a
## spawn menu without the menu naming a pack. Same shape as [code]DotMapCatalogue.follow_content[/code].
##
## [b]Solo only, by the index.[/b] An online session sees no solo entry, so a server that never
## followed and a client that did agree on what can be spawned. [b]Own ids win[/b]: an id this
## catalogue already holds (the game's, an operator's) is never replaced by a pack's; the pack row
## is skipped and logged at debug. Among packs the first mounted wins. A pack row is listed as
## "Name [Pack]" and carries [code]meta.pack_title[/code] and [code]meta.entry_key[/code].
## [method to_dictionary] leaves pack rows out, so saving an operator's JSON never writes a
## subscription into it. [b]An empty [param kinds] follows nothing.[/b]
##
## An entry names a [code]def[/code] (a [DotPropDef] [code].tres[/code], loaded and copied) or a
## [code]scene[/code] (the rest from [code]size[/code], [code]mass[/code], [code]cost[/code] fields
## of the entry, else defaults).
func follow_content(
	index: DotContentIndex, p_kinds: PackedStringArray = PackedStringArray(["prop"])
) -> DotPropCatalogue:
	unfollow_content()
	if index == null:
		return self
	_index = index
	_kinds = p_kinds
	index.pack_added.connect(_on_index_pack_added)
	index.session_changed.connect(_on_index_session_changed)
	refresh_content()
	return self


## Stop following and drop the pack rows. Own props stay.
func unfollow_content() -> void:
	if _index != null:
		if _index.pack_added.is_connected(_on_index_pack_added):
			_index.pack_added.disconnect(_on_index_pack_added)
		if _index.session_changed.is_connected(_on_index_session_changed):
			_index.session_changed.disconnect(_on_index_session_changed)
	_index = null
	if _drop_followed():
		content_changed.emit()


## Rebuild the pack rows from the index now. Needed after [method DotContentIndex.tag_pack],
## which changes a pack's sessions without announcing it.
func refresh_content() -> void:
	var before := _followed_keys()
	_drop_followed()
	if _index != null:
		for kind in _kinds:
			for entry in _index.entries(StringName(kind)):
				var prop := _def_from_entry(entry)
				if prop == null:
					continue
				if has(prop.id):
					DotLog.debug(CHANNEL, "a pack prop lost its id to an existing prop", {
						"id": String(prop.id), "pack": entry.content_id
					})
					continue
				if add(prop).ok:
					_followed.append(prop)
	if _followed_keys() != before:
		content_changed.emit()


func _followed_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for prop in _followed:
		out.append(str(prop.meta.get("entry_key", "")))
	return out


## Returns whether anything was dropped.
func _drop_followed() -> bool:
	var had := not _followed.is_empty()
	for prop in _followed:
		# Only a row this follower made; the game may have replaced the id since.
		if get_prop(prop.id) == prop:
			remove(prop.id)
	_followed.clear()
	return had


func _on_index_pack_added(_pack: Dictionary, _entries: Array[DotContentEntry]) -> void:
	refresh_content()


func _on_index_session_changed(_session: StringName) -> void:
	refresh_content()


func _def_from_entry(entry: DotContentEntry) -> DotPropDef:
	var prop: DotPropDef = null
	var def_path := entry.path("def")
	if def_path != "":
		var loaded: Variant = ResourceLoader.load(def_path) if ResourceLoader.exists(def_path) else null
		if loaded is DotPropDef:
			prop = (loaded as DotPropDef).duplicate(true)
	if prop == null:
		prop = DotPropDef.new()
		prop.scene_path = entry.path("scene")
		prop.mass = maxf(float(entry.raw.get("mass", prop.mass)), 0.01)
		prop.cost = maxi(int(entry.raw.get("cost", prop.cost)), 0)
		if entry.raw.has("size"):
			prop.size = clampi(int(entry.raw["size"]), 0, DotPropDef.Size.HUGE) as DotPropDef.Size
	# The entry's identity is the pack's, whatever a copied def says.
	prop.id = StringName(entry.id)
	var title := entry.pack_title if entry.pack_title != "" else entry.content_id
	var base := prop.display_name if prop.display_name != "" else entry.name
	prop.display_name = "%s [%s]" % [base, title]
	if entry.category != "":
		prop.category = StringName(entry.category)
	prop.content_id = StringName(entry.content_id)
	prop.meta = prop.meta.duplicate(true)
	prop.meta["pack_title"] = title
	prop.meta["entry_key"] = entry.key
	var valid := prop.validate()
	if not valid.ok:
		DotLog.debug(CHANNEL, "a pack prop was refused", {
			"key": entry.key, "why": valid.error.message
		})
		return null
	return prop


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
		if prop.meta.has("entry_key"):
			continue
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

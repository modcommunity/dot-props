@tool
class_name DotPropFolder
extends RefCounted

## A folder of model files becomes spawnable props, with no code and no catalogue edit.
##
## [b]The contract is a folder.[/b] A model ([code].glb[/code] or [code].gltf[/code]) that appears
## in a scanned directory is a prop. Everything else about it is optional and says so in a
## small JSON file, because the person adding a model to a community server has a file
## manager and a text editor and nothing else:
##
## [codeblock]
## props/
##   props.json            optional: credit and defaults for the whole folder, and entries
##   garden/               a subfolder is the category when nothing says otherwise
##     gnome.glb
##     gnome.json          optional sidecar for gnome.glb
##     gnome.png           optional thumbnail (or thumbs/gnome.png)
## [/codeblock]
##
## A sidecar, or an entry under [code]"props"[/code] in [code]props.json[/code] (keyed by the file's
## name without its extension), reads:
##
## [codeblock]
## { "name": "Garden gnome", "category": "garden",
##   "scale": 1.0,             // multiplier on the model's own units, or
##   "size_m": 0.6,            // the longest side in metres (instead of scale)
##   "mass": 6.0,              // kg; else the box times "density" (kg per cubic metre)
##   "shape": "convex",        // convex (default), box, sphere or cylinder
##   "cost": 1, "can_grab": true, "can_freeze": true,
##   "max_health": 0, "icon": "gnome.png",
##   "credit": { "author": "A. Modeller", "licence": "CC0", "url": "https://..." } }
## [/codeblock]
##
## [b]What is refused, and why.[/b] The scan reads only files inside the folder it was given
## (a [code]..[/code] anywhere in a path is a problem, not a model), and an id is the file's
## name reduced to lower-case letters, digits and underscores, so what a client may ask
## for is always an id the server's own catalogue holds, never a path. A model over
## [constant MAX_BYTES], or a thousand models in one folder, is a problem line and not a
## frozen server. One bad file never condemns the folder: each problem is listed and the
## rest load.
##
## [b]The result is a [DotPropDef][/b] whose [member DotPropDef.scene_path] is the game's own
## body scene (the host passes it), and whose [member DotPropDef.meta] carries [code]model[/code]
## (the file), [code]model_scale[/code], [code]shape[/code], [code]extent[/code] and [code]credit[/code]. What a
## body does with those is [DotPropModel] and the game's. dot-props does not know which
## scene a game builds bodies from.

const CHANNEL := "props.folder"

const MANIFEST := "props.json"

const MODEL_EXTENSIONS: Array[String] = ["glb", "gltf"]

## How deep a folder is searched. Three is a category, a subcategory and a pack's own folder.
const MAX_DEPTH := 3

## Largest model file taken from a loose folder, and most models taken from one folder.
const MAX_BYTES := 16 * 1024 * 1024
const MAX_MODELS := 600


## Adds every model under [param dir] to [param catalogue] as a prop built on
## [param scene_path]. Returns [code]{ "added": PackedStringArray, "problems": PackedStringArray }[/code].
##
## A folder that does not exist is not a problem (an empty [code]user://props[/code] is the
## normal case). [param options]: [code]"category"[/code] (the default one, else "props"),
## [code]"overwrite"[/code] (let a model replace a prop with the same id; off by default, so a
## dropped file cannot replace a built-in), [code]"measure"[/code] (false skips loading a model
## to measure it, for entries that carry their own extent).
static func load_into(
	catalogue: DotPropCatalogue, dir: String, scene_path: String, options: Dictionary = {}
) -> DotResult:
	var report := {"added": PackedStringArray(), "problems": PackedStringArray()}

	if catalogue == null:
		return DotResult.fail(DotError.CODE_INVALID, "No catalogue to add to.")

	if not DirAccess.dir_exists_absolute(dir):
		return DotResult.success(report)

	var manifest := _read_json(dir.path_join(MANIFEST))
	var defaults: Dictionary = manifest.get("defaults", {}) if manifest.get("defaults") is Dictionary else {}
	var credit: Dictionary = manifest.get("credit", {}) if manifest.get("credit") is Dictionary else {}
	var listed: Dictionary = manifest.get("props", {}) if manifest.get("props") is Dictionary else {}

	var entries: Array[Dictionary] = []
	var used_files: Dictionary = {}

	for stem in listed:
		var entry: Variant = listed[stem]

		if not (entry is Dictionary):
			continue

		var file := str((entry as Dictionary).get("file", ""))
		if file == "":
			file = _find_model(dir, str(stem))
		if file == "":
			report["problems"].append("%s: no model file named in props.json" % str(stem))
			continue

		used_files[file] = true
		entries.append({"stem": str(stem), "file": file, "entry": entry, "sub": file.get_base_dir()})

	for file in _list_models(dir, "", 0):
		if used_files.has(file):
			continue

		var stem := file.get_file().get_basename()
		var sidecar := _read_json(dir.path_join(file.get_basename() + ".json"))
		entries.append({"stem": stem, "file": file, "entry": sidecar, "sub": file.get_base_dir()})

	if entries.size() > MAX_MODELS:
		report["problems"].append(
			"%s: %d models, only the first %d are read" % [dir, entries.size(), MAX_MODELS]
		)
		entries.resize(MAX_MODELS)

	for item in entries:
		var made := _make_def(item, dir, scene_path, defaults, credit, catalogue, options)

		if not made.ok:
			report["problems"].append("%s: %s" % [item["stem"], made.error.message])
			continue

		var def := made.value as DotPropDef
		var added := catalogue.add(def)

		if added.ok:
			report["added"].append(String(def.id))
		else:
			report["problems"].append("%s: %s" % [item["stem"], added.error.message])

	for line in report["problems"]:
		DotLog.warn(CHANNEL, "a model was not added", {"dir": dir, "why": line})

	DotLog.info(CHANNEL, "a prop folder was read", {
		"dir": dir, "added": (report["added"] as PackedStringArray).size(),
		"problems": (report["problems"] as PackedStringArray).size(),
	})

	return DotResult.success(report)


static func _make_def(
	item: Dictionary, dir: String, scene_path: String, defaults: Dictionary,
	pack_credit: Dictionary, catalogue: DotPropCatalogue, options: Dictionary
) -> DotResult:
	var file: String = item["file"]
	var stem: String = item["stem"]
	var entry: Dictionary = (item["entry"] as Dictionary) if item["entry"] is Dictionary else {}
	var merged := defaults.duplicate(true)
	merged.merge(entry, true)

	if file.contains("..") or file.begins_with("/") or file.contains(":"):
		return DotResult.fail(DotError.CODE_INVALID, "A model path must stay inside its folder.", file)

	var path := dir.path_join(file)
	var id := StringName(sanitize_id(str(merged.get("id", stem))))

	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "That file name makes no id.", file)

	if catalogue.has(id) and not bool(options.get("overwrite", false)):
		return DotResult.fail(DotError.CODE_INVALID, "The id is taken, rename the file or give an \"id\".", String(id))

	if not (path.begins_with("res://") or path.begins_with("uid://")):
		var handle := FileAccess.open(path, FileAccess.READ)

		if handle == null:
			return DotResult.fail(DotError.CODE_IO, "The model cannot be opened.", path)

		var length := handle.get_length()
		handle.close()

		if length > MAX_BYTES:
			return DotResult.fail(
				DotError.CODE_INVALID, "The model file is over %d MB." % (MAX_BYTES / 1048576), path
			)

	var shape_name := str(merged.get("shape", "convex")).to_lower()
	if not (shape_name in ["convex", "box", "sphere", "cylinder"]):
		shape_name = "convex"

	var scale := clampf(float(merged.get("scale", 1.0)), 0.01, 100.0)
	var extent := Vector3.ZERO
	var baked: Variant = merged.get("extent", null)

	if merged.has("size_m"):
		# A side in metres is a request to measure the unscaled model and work back to a
		# scale, which a baked extent cannot answer.
		var raw := DotPropModel.measure(path, 1.0, shape_name)
		if not raw.ok:
			return raw
		var raw_extent: Vector3 = (raw.value as Dictionary)["extent"]
		var longest := maxf(raw_extent.x, maxf(raw_extent.y, raw_extent.z))
		scale = clampf(float(merged["size_m"]) / maxf(longest, 0.0001), 0.01, 100.0)

	if baked is Array and (baked as Array).size() == 3 and not merged.has("size_m"):
		extent = Vector3(float(baked[0]), float(baked[1]), float(baked[2]))
	elif bool(options.get("measure", true)):
		var measured := DotPropModel.measure(path, scale, shape_name)
		if not measured.ok:
			return measured
		extent = (measured.value as Dictionary)["extent"]
	else:
		extent = Vector3.ONE * 0.5

	if not DotPropModel.size_ok(extent):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The model would be %.2f m across; a prop is between %.2f and %.0f m." % [
				maxf(extent.x, maxf(extent.y, extent.z)), DotPropModel.MIN_SIDE, DotPropModel.MAX_SIDE
			],
			path,
		)

	var def := DotPropDef.make(id, scene_path)
	def.display_name = str(merged.get("name", humanize(stem)))
	def.category = StringName(sanitize_id(str(
		merged.get("category", item["sub"] if str(item["sub"]) != "" else options.get("category", "props"))
	)))
	def.mass = (
		maxf(float(merged["mass"]), 0.1) if merged.has("mass")
		else DotPropModel.estimate_mass(extent, float(merged.get("density", DotPropModel.DEFAULT_DENSITY)))
	)
	def.size = _size_class(extent)
	def.cost = clampi(int(merged.get("cost", _default_cost(def.size))), 1, 100)
	def.can_grab = bool(merged.get("can_grab", true))
	def.can_freeze = bool(merged.get("can_freeze", true))
	def.max_health = maxf(float(merged.get("max_health", 0.0)), 0.0)
	def.icon_path = _icon_for(dir, file, stem, str(merged.get("icon", "")))

	var credit := _credit(pack_credit, merged)
	var meta: Dictionary = {}
	if merged.get("meta") is Dictionary:
		meta = (merged["meta"] as Dictionary).duplicate(true)
	meta["model"] = path
	meta["model_scale"] = scale
	meta["shape"] = shape_name
	meta["extent"] = [extent.x, extent.y, extent.z]
	meta["folder"] = dir
	if not credit.is_empty():
		meta["credit"] = credit
	def.meta = meta

	var valid := def.validate()
	return DotResult.success(def) if valid.ok else valid


static func _credit(pack_credit: Dictionary, entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}

	for source: Variant in [pack_credit, entry.get("credit", {})]:
		if not (source is Dictionary):
			continue
		for key in ["author", "licence", "url", "source"]:
			if (source as Dictionary).has(key):
				out[key] = str((source as Dictionary)[key])

	for key in ["author", "licence", "url", "source"]:
		if entry.has(key):
			out[key] = str(entry[key])

	return out


static func _size_class(extent: Vector3) -> DotPropDef.Size:
	var longest := maxf(extent.x, maxf(extent.y, extent.z))

	if longest < 0.3:
		return DotPropDef.Size.TINY
	if longest < 0.8:
		return DotPropDef.Size.SMALL
	if longest < 2.0:
		return DotPropDef.Size.MEDIUM
	if longest < 4.0:
		return DotPropDef.Size.LARGE

	return DotPropDef.Size.HUGE


static func _default_cost(size: DotPropDef.Size) -> int:
	match size:
		DotPropDef.Size.TINY, DotPropDef.Size.SMALL:
			return 1
		DotPropDef.Size.MEDIUM:
			return 2
		DotPropDef.Size.LARGE:
			return 3
		_:
			return 4


## A thumbnail beside the model: the entry's [code]icon[/code], else [code]thumbs/<name>.png[/code] or
## [code]<name>.png[/code] next to the file. Empty when there is none, and the menu draws one.
static func _icon_for(dir: String, file: String, stem: String, named: String) -> String:
	var here := dir.path_join(file.get_base_dir())
	var candidates: Array[String] = []

	if named != "" and not named.contains(".."):
		candidates.append(dir.path_join(named))

	candidates.append(here.path_join("thumbs").path_join(stem + ".png"))
	candidates.append(here.path_join(stem + ".png"))

	for candidate in candidates:
		if ResourceLoader.exists(candidate) or FileAccess.file_exists(candidate):
			return candidate

	return ""


static func _find_model(dir: String, stem: String) -> String:
	for ext in MODEL_EXTENSIONS:
		var name := "%s.%s" % [stem, ext]
		if FileAccess.file_exists(dir.path_join(name)) or ResourceLoader.exists(dir.path_join(name)):
			return name

	return ""


## Model files under [param base], as paths relative to [param dir], sorted. An imported
## model inside an export is listed as [code]name.glb.import[/code] or [code]name.glb.remap[/code] rather
## than by its own name, so both suffixes are read as the model.
static func _list_models(dir: String, base: String, depth: int) -> PackedStringArray:
	var out := PackedStringArray()
	var here := dir.path_join(base) if base != "" else dir
	var access := DirAccess.open(here)

	if access == null:
		return out

	var seen: Dictionary = {}

	for name in access.get_files():
		var clean := name
		for suffix in [".import", ".remap"]:
			if clean.ends_with(suffix):
				clean = clean.trim_suffix(suffix)

		if clean.get_extension().to_lower() in MODEL_EXTENSIONS and not seen.has(clean):
			seen[clean] = true
			out.append(clean if base == "" else base.path_join(clean))

	if depth < MAX_DEPTH:
		for sub in access.get_directories():
			if sub.begins_with(".") or sub == "thumbs" or sub == "Textures":
				continue
			out.append_array(_list_models(dir, sub if base == "" else base.path_join(sub), depth + 1))

	out.sort()
	return out


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)

	if parsed is Dictionary:
		return parsed

	DotLog.warn(CHANNEL, "a sidecar is not a JSON object", {"path": path})
	return {}


## A file name as a prop id: lower-case letters, digits and underscores.
##
## [b]This is the whole of what a client can name.[/b] Nothing that reaches a spawn request can
## carry a slash, a dot or a scheme, so a request can only ever pick from what the server's
## own catalogue holds.
static func sanitize_id(text: String) -> String:
	var out := ""

	for i in range(text.length()):
		var c := text[i].to_lower()
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		out += c if ok else "_"

	while out.contains("__"):
		out = out.replace("__", "_")

	return out.strip_edges().trim_prefix("_").trim_suffix("_").left(48)


## "bookcaseOpen", "tool-axe", "rock_small" as "Bookcase Open", "Tool Axe", "Rock Small".
static func humanize(text: String) -> String:
	var spaced := ""

	for i in range(text.length()):
		var c := text[i]
		if i > 0 and c >= "A" and c <= "Z" and text[i - 1] >= "a" and text[i - 1] <= "z":
			spaced += " "
		spaced += " " if (c == "_" or c == "-") else c

	return spaced.strip_edges().capitalize()

class_name DotPropToySounds
extends RefCounted

## The files behind the stock toys' sound ids, as plain data a game turns into its own audio
## definitions. Kenney's CC0 impact, interface and foley sounds plus a horn made here, shipped in
## [code]toys/sounds/[/code] (credited in its CREDITS.md).
##
## [b]Data, not dot-audio definitions[/b], because this addon does not depend on dot-audio: a
## game makes one positional definition per row (path, variants, pitch range, gain), and the ids
## a [DotPropToy] emits then play. The same shape as dot-player-char's death sounds.

const BOUNCE := &"toy_bounce"
const THUMP := &"toy_thump"
const KNOCK := &"toy_knock"
const PIN := &"toy_pin"
const WOOD := &"toy_wood"
const RUBBER := &"toy_rubber"
const PUNCH := &"toy_punch"
const METAL := &"toy_metal"
const BELL := &"toy_bell"
const CLICK := &"toy_click"
const WATER := &"toy_water"
const BOING := &"toy_boing"
const HORN := &"toy_horn"


## The directory the files are in, found from this script so a pack mounted under another root
## still finds them.
static func directory() -> String:
	var here: String = (DotPropToySounds as Script).resource_path
	return here.get_base_dir().path_join("sounds")


## One row per id: `{id, path, variants, gain_db, pitch_min, pitch_max, cooldown_ms, distance}`.
## `variants` holds every file, `path` the first; `distance` is how far it carries, in metres.
static func rows() -> Array[Dictionary]:
	var dir := directory()
	var out: Array[Dictionary] = []
	for spec: Array in [
		# id, file stem, how many, gain, pitch low, pitch high, carries
		[BOUNCE, "bounce", 3, 0.0, 1.05, 1.3, 30.0],
		[THUMP, "thump", 3, -2.0, 1.0, 1.2, 30.0],
		[KNOCK, "knock", 3, 0.0, 0.8, 0.95, 35.0],
		[PIN, "pin", 3, -1.0, 1.1, 1.35, 30.0],
		[WOOD, "wood", 3, -2.0, 0.9, 1.1, 30.0],
		[RUBBER, "rubber", 3, -2.0, 0.85, 1.0, 30.0],
		[PUNCH, "punch", 3, 0.0, 0.85, 1.0, 30.0],
		[METAL, "metal", 3, -6.0, 0.9, 1.1, 30.0],
		[BELL, "bell", 2, -3.0, 0.95, 1.05, 60.0],
		[CLICK, "click", 2, 0.0, 0.95, 1.05, 15.0],
		[WATER, "water", 1, -6.0, 0.95, 1.05, 20.0],
		[BOING, "boing", 2, -4.0, 0.9, 1.1, 30.0],
		[HORN, "horn", 2, -4.0, 0.98, 1.02, 50.0],
	]:
		var variants := PackedStringArray()
		for i in range(int(spec[2])):
			variants.append(dir.path_join("%s_%d.ogg" % [spec[1], i]))
		out.append({
			"id": spec[0],
			"path": variants[0],
			"variants": variants,
			"gain_db": float(spec[3]),
			"pitch_min": float(spec[4]),
			"pitch_max": float(spec[5]),
			"distance": float(spec[6]),
			# A ball rattling in a corner is a few knocks, not a drum roll.
			"cooldown_ms": 70,
		})
	return out


## Every id, for a game listing what it must define.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in rows():
		out.append(row["id"])
	return out

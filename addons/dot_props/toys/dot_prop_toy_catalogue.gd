class_name DotPropToyCatalogue
extends RefCounted

## What a toy is: the definitions a [DotPropToyBox] builds from, by id. A map places a toy by
## naming one (`{"toy": "beach_ball", "at": [x, y, z]}`); this file says what that is.
##
## [b]Data, every field a number or a word[/b], so a game adds or retunes toys from JSON
## ([method merge]) without a script: a pack's `class_name` does not resolve, and a toy is a
## thing a mapper should be able to add. The behaviour belongs to the [member KINDS] a
## definition names, and there are few of them on purpose: a beach ball and a football are one
## kind with different numbers.
##
## Fields (every one but `kind` has a default):
## - `name`: what the use prompt calls it.
## - `kind`: one of [constant KINDS].
## - `size`: metres, `[x, y, z]` of what the kind builds (a ball's `x` is its diameter).
## - `mass` kg, `bounce` 0..1, `friction` 0..1, `damp` and `angular_damp` per second.
## - `colours`: `[[r, g, b], ...]`, what it is painted; the kind says which goes where.
## - `use`: the verb on the prompt ("Kick"), empty for a toy the use key does nothing to.
## - `kick`: the speed in m/s a use gives it (an impulse of `kick * mass`), or for a spinner
##   the rim speed.
## - `launch`: `[x, y, z]` m/s a bouncer or pad throws a person, in the toy's own frame.
## - `sound_hit`, `sound_use`: ids in [DotPropToySounds], played where it happens.
## - `on`: whether a switchable toy (lamp, fountain) starts on.

## What a toy does, by kind:
## - `ball`: a loose sphere (beach ball, football, bowling ball).
## - `pin`: a loose upright cylinder that topples (a bowling pin).
## - `barrel`: a loose upright cylinder that tips and rolls.
## - `crate`: a loose box that slides when pushed and is thrown by a blast (a game spawns them while it runs, [method DotPropToyBox.add_toy]).
## - `tyre`: a loose wheel stood on its tread; it rolls.
## - `bag`: a punching bag hung from a frame on a pin joint.
## - `swing`: a seat on a rigid pendulum hinged under a frame's bar.
## - `seesaw`: a plank hinged on a base; a person's weight tips it.
## - `spinner`: a roundabout, a disc that turns about its hub and is stood on.
## - `wobble`: a platform on a sprung pivot that tilts under whoever stands on it.
## - `bouncer`: a trampoline; landing on its bed throws a person up.
## - `pad`: a bounce pad; stepping on it throws a person forward and up.
## - `switch`: a button on a post; the use key turns its linked toys on and off.
## - `lamp`: a lamp post, lit or not; a switch or the use key turns it.
## - `fountain`: a basin whose jets run or not.
## - `horn`: a horn on a post; the use key sounds it.
## - `bell`: a bell on a frame; the use key rings it.
const KINDS: Array[StringName] = [
	&"ball", &"pin", &"barrel", &"crate", &"tyre", &"bag", &"swing", &"seesaw", &"spinner", &"wobble",
	&"bouncer", &"pad", &"switch", &"lamp", &"fountain", &"horn", &"bell",
]

## Kinds with a body that moves on its own (simulated by the server, drawn from snapshots).
const MOVING: Array[StringName] = [
	&"ball", &"pin", &"barrel", &"tyre", &"bag", &"swing", &"seesaw", &"spinner", &"wobble",
]

## Kinds nothing collides with but other toys and the world: a person walks into one and it is
## pushed ([method DotPropToy.push_from]); never a wall a body or a bot can be stuck on.
const LOOSE: Array[StringName] = [&"ball", &"pin", &"barrel", &"crate", &"tyre", &"bag", &"swing"]

## Kinds whose `on` the use key or a switch flips.
const SWITCHED: Array[StringName] = [&"switch", &"lamp", &"fountain"]

const DEFAULTS := {
	"name": "",
	"kind": "ball",
	"size": [0.5, 0.5, 0.5],
	"mass": 1.0,
	"bounce": 0.3,
	"friction": 0.6,
	"damp": 0.1,
	"angular_damp": 0.2,
	"colours": [[0.9, 0.9, 0.9]],
	"use": "",
	"kick": 0.0,
	"launch": [0.0, 0.0, 0.0],
	"sound_hit": "",
	"sound_use": "",
	"on": false,
}

## id -> normalised definition.
var defs: Dictionary = {}


## The stock set: eighteen toys, every kind at least once, tuned on a person's scale (1.8 m,
## 6 m/s, gravity 20 m/s², the family's movement).
static func stock() -> DotPropToyCatalogue:
	var c := DotPropToyCatalogue.new()
	var all := _stock_loose()
	all.merge(_stock_driven())
	all.merge(_stock_fixed())
	var _r := c.merge(all)
	return c


static func _stock_loose() -> Dictionary:
	return {
		"beach_ball": {
			"name": "beach ball", "kind": "ball", "size": [1.0, 1.0, 1.0], "mass": 0.35,
			"bounce": 0.78, "friction": 0.5, "damp": 0.25, "angular_damp": 0.4,
			"colours": [[0.93, 0.22, 0.2], [0.97, 0.96, 0.92], [0.18, 0.45, 0.88], [0.98, 0.82, 0.18], [0.97, 0.96, 0.92], [0.25, 0.7, 0.35]],
			"use": "Kick", "kick": 9.0, "sound_hit": "toy_bounce",
		},
		"football": {
			"name": "football", "kind": "ball", "size": [0.24, 0.24, 0.24], "mass": 0.43,
			"bounce": 0.62, "friction": 0.7, "damp": 0.15, "angular_damp": 0.6,
			"colours": [[0.96, 0.96, 0.94], [0.08, 0.08, 0.1]],
			"use": "Kick", "kick": 13.0, "sound_hit": "toy_thump",
		},
		"bowling_ball": {
			"name": "bowling ball", "kind": "ball", "size": [0.22, 0.22, 0.22], "mass": 6.0,
			"bounce": 0.08, "friction": 0.3, "damp": 0.05, "angular_damp": 0.1,
			"colours": [[0.3, 0.12, 0.45], [0.05, 0.05, 0.06]],
			"use": "Bowl", "kick": 7.0, "sound_hit": "toy_knock",
		},
		"bowling_pin": {
			"name": "bowling pin", "kind": "pin", "size": [0.12, 0.38, 0.12], "mass": 1.5,
			"bounce": 0.25, "friction": 0.5, "damp": 0.1, "angular_damp": 0.4,
			"colours": [[0.97, 0.96, 0.93], [0.85, 0.12, 0.12]],
			"use": "Kick", "kick": 4.0, "sound_hit": "toy_pin",
		},
		"barrel": {
			"name": "barrel", "kind": "barrel", "size": [0.6, 0.85, 0.6], "mass": 12.0,
			"bounce": 0.1, "friction": 0.7, "damp": 0.2, "angular_damp": 0.5,
			"colours": [[0.55, 0.36, 0.2], [0.25, 0.25, 0.28]],
			"use": "Push", "kick": 4.0, "sound_hit": "toy_wood",
		},
		"crate": {
			"name": "crate", "kind": "crate", "size": [0.5, 0.3, 0.4], "mass": 8.0,
			"bounce": 0.05, "friction": 0.8, "damp": 0.4, "angular_damp": 0.8,
			"colours": [[0.5, 0.4, 0.22], [0.25, 0.25, 0.28]],
			"use": "Push", "kick": 4.0, "sound_hit": "toy_wood",
		},
	}


static func _stock_driven() -> Dictionary:
	return {
		"tyre": {
			"name": "tyre", "kind": "tyre", "size": [0.8, 0.28, 0.8], "mass": 7.0,
			"bounce": 0.45, "friction": 0.9, "damp": 0.1, "angular_damp": 0.3,
			"colours": [[0.12, 0.12, 0.13], [0.6, 0.6, 0.62]],
			"use": "Roll", "kick": 6.0, "sound_hit": "toy_rubber",
		},
		"punching_bag": {
			"name": "punching bag", "kind": "bag", "size": [0.42, 1.0, 0.42], "mass": 18.0,
			"bounce": 0.1, "friction": 0.8, "damp": 0.05, "angular_damp": 0.6,
			"colours": [[0.72, 0.12, 0.12], [0.2, 0.2, 0.22]],
			"use": "Punch", "kick": 4.5, "sound_hit": "toy_punch",
		},
		"swing": {
			"name": "swing", "kind": "swing", "size": [2.0, 2.4, 0.6], "mass": 6.0,
			"bounce": 0.1, "friction": 0.6, "damp": 0.02, "angular_damp": 0.15,
			"colours": [[0.25, 0.55, 0.85], [0.9, 0.7, 0.25], [0.55, 0.45, 0.35]],
			"use": "Push", "kick": 3.5, "sound_hit": "toy_metal",
		},
		"seesaw": {
			"name": "see-saw", "kind": "seesaw", "size": [3.2, 0.55, 0.4], "mass": 25.0,
			"bounce": 0.05, "friction": 0.8, "damp": 0.05, "angular_damp": 1.0,
			"colours": [[0.95, 0.75, 0.2], [0.85, 0.3, 0.25]],
			"use": "Push", "kick": 3.0, "sound_hit": "toy_wood",
		},
		"merry_go_round": {
			"name": "roundabout", "kind": "spinner", "size": [2.8, 0.35, 2.8], "mass": 120.0,
			"bounce": 0.0, "friction": 0.9, "damp": 0.0, "angular_damp": 0.35,
			"colours": [[0.85, 0.25, 0.3], [0.95, 0.85, 0.3], [0.4, 0.42, 0.45]],
			"use": "Spin", "kick": 3.0, "sound_hit": "toy_metal",
		},
		"wobbly_platform": {
			"name": "wobbly platform", "kind": "wobble", "size": [1.6, 0.45, 1.6], "mass": 40.0,
			"bounce": 0.0, "friction": 0.9, "damp": 0.0, "angular_damp": 1.5,
			"colours": [[0.35, 0.7, 0.5], [0.4, 0.42, 0.45]],
			"sound_hit": "toy_wood",
		},
	}


static func _stock_fixed() -> Dictionary:
	return {
		"trampoline": {
			"name": "trampoline", "kind": "bouncer", "size": [2.4, 0.45, 2.4], "mass": 0.0,
			"colours": [[0.1, 0.1, 0.12], [0.2, 0.45, 0.85]],
			"launch": [0.0, 9.5, 0.0], "sound_use": "toy_boing",
		},
		"bounce_pad": {
			"name": "bounce pad", "kind": "pad", "size": [1.2, 0.12, 1.2], "mass": 0.0,
			"colours": [[0.95, 0.55, 0.15], [0.98, 0.95, 0.85]],
			"launch": [0.0, 8.5, 6.0], "sound_use": "toy_boing",
		},
		"light_switch": {
			"name": "switch", "kind": "switch", "size": [0.22, 1.05, 0.22], "mass": 0.0,
			"colours": [[0.35, 0.37, 0.4], [0.85, 0.2, 0.2], [0.25, 0.8, 0.35]],
			"use": "Press", "sound_use": "toy_click",
		},
		"lamp_post": {
			"name": "lamp", "kind": "lamp", "size": [0.3, 2.6, 0.3], "mass": 0.0,
			"colours": [[0.2, 0.22, 0.25], [1.0, 0.85, 0.55]],
			"use": "Switch", "sound_use": "toy_click", "on": true,
		},
		"fountain": {
			"name": "fountain", "kind": "fountain", "size": [1.8, 0.5, 1.8], "mass": 0.0,
			"colours": [[0.72, 0.72, 0.7], [0.35, 0.6, 0.85]],
			"use": "Turn", "sound_use": "toy_water", "on": true,
		},
		"horn": {
			"name": "horn", "kind": "horn", "size": [0.5, 1.4, 0.5], "mass": 0.0,
			"colours": [[0.35, 0.37, 0.4], [0.95, 0.75, 0.2]],
			"use": "Honk", "sound_use": "toy_horn",
		},
		"bell": {
			"name": "bell", "kind": "bell", "size": [1.2, 2.2, 0.4], "mass": 0.0,
			"colours": [[0.45, 0.32, 0.22], [0.85, 0.68, 0.25]],
			"use": "Ring", "sound_use": "toy_bell",
		},
	}


## Adds or replaces definitions from `{id: {fields}}`; a field left out of a replacement keeps
## the stock's value, so a game retunes a toy with one line. Fails on the first bad one and
## leaves the rest of the set as it was.
func merge(data: Dictionary) -> DotResult:
	var made := {}
	for raw_id: Variant in data:
		var id := StringName(str(raw_id))
		if not (data[raw_id] is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "toy '%s' is not an object" % id)
		var base: Dictionary = defs.get(id, DEFAULTS)
		var def := _normal(base, data[raw_id] as Dictionary)
		if not KINDS.has(StringName(def["kind"])):
			return DotResult.fail(DotError.CODE_INVALID, "toy '%s' has kind '%s'; the kinds are %s" % [id, def["kind"], ", ".join(KINDS)])
		def["id"] = id
		if str(def["name"]) == "":
			def["name"] = String(id).replace("_", " ")
		made[id] = def
	for id: StringName in made:
		defs[id] = made[id]
	return DotResult.success(made.size())


## [method merge] from a JSON object's text.
func merge_json(text: String) -> DotResult:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "a toy catalogue is a JSON object of {id: {fields}}")
	return merge(parsed as Dictionary)


static func _normal(base: Dictionary, given: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in DEFAULTS:
		if given.has(key):
			out[key] = given[key]
	out["kind"] = StringName(str(out["kind"]))
	out["size"] = _v3(out["size"], Vector3(0.5, 0.5, 0.5)).abs().max(Vector3.ONE * 0.02)
	out["launch"] = _v3(out["launch"], Vector3.ZERO)
	out["mass"] = maxf(float(out["mass"]), 0.0)
	out["bounce"] = clampf(float(out["bounce"]), 0.0, 1.0)
	out["friction"] = clampf(float(out["friction"]), 0.0, 1.0)
	out["damp"] = maxf(float(out["damp"]), 0.0)
	out["angular_damp"] = maxf(float(out["angular_damp"]), 0.0)
	out["kick"] = maxf(float(out["kick"]), 0.0)
	out["on"] = bool(out["on"])
	var colours: Array[Color] = []
	for raw: Variant in (out["colours"] if out["colours"] is Array else []):
		if raw is Color:
			colours.append(raw)
		elif raw is Array and (raw as Array).size() >= 3:
			colours.append(Color(float(raw[0]), float(raw[1]), float(raw[2])))
	if colours.is_empty():
		colours.append(Color(0.9, 0.9, 0.9))
	out["colours"] = colours
	out["use"] = str(out["use"])
	out["sound_hit"] = StringName(str(out["sound_hit"]))
	out["sound_use"] = StringName(str(out["sound_use"]))
	return out


static func _v3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func get_def(id: StringName) -> Dictionary:
	return defs.get(id, {})


func has(id: StringName) -> bool:
	return defs.has(id)


## Every id, sorted by its text (never by StringName, which sorts by pointer and differs between
## two processes).
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in defs:
		out.append(String(id))
	out.sort()
	return out


func size() -> int:
	return defs.size()


func describe() -> Dictionary:
	return {"toys": defs.size(), "ids": ", ".join(ids())}

class_name DotPropToyRules
extends Resource

## What a server allows of a map's toys: whether there are any, how many may be simulating at
## once, and how hard a person's walk pushes one. The `sv_toys*` cvars.
##
## [b]REPLICATED[/b] when a game binds them (the client hides the toys the server took away),
## and followed through the link like dot-player-char's ragdoll rules, duck-typed the same
## way: dot-server is not a dependency here.

const CVAR_ENABLED := "sv_toys"
const CVAR_AWAKE := "sv_toys_awake"
const CVAR_PUSH := "sv_toys_push"

## Whether a map's toys are there at all. Off, a map plays as if it had none.
@export var enabled: bool = true

## The most toys simulating at once; past it, the longest untouched are put to sleep. 0 is
## this machine's own default ([method cap]).
@export_range(0, 256, 1) var max_awake: int = 0

## How hard walking into a loose toy sends it, against the walk's own speed.
@export_range(0.0, 4.0, 0.05) var push_scale: float = 1.0


## The awake cap in force: [member max_awake], or 24 on a machine with threads and 8 on one
## without (a browser build simulates physics on its only thread, between frames it must draw).
func cap() -> int:
	if max_awake > 0:
		return max_awake
	return 24 if DotPlatform.has_threads() else 8


func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_ENABLED, "value": "1" if enabled else "0", "description": "The map's toys (balls, swings, see-saws, switches...): 1 there, 0 gone."},
		{"name": CVAR_AWAKE, "value": str(max_awake), "description": "The most toys simulating at once; 0 is the machine's default (24, or 8 without threads).", "min": 0.0, "max": 256.0},
		{"name": CVAR_PUSH, "value": str(push_scale), "description": "How hard walking into a ball or a barrel sends it, against the walk's speed.", "min": 0.0, "max": 4.0},
	]


## Registers the `sv_toys*` cvars through [param add] (a server module's `add_cvar`, or anything
## shaped `(name, default, description, flags) -> cvar`) and keeps these rules on them.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if spec.has("min") and cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Keeps these rules on a server's values as [param source] (dot-server's `DotClientLink`)
## reports them. False when it cannot (an older shell's link).
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var held := String(source.call(&"replicated_cvar", cvar_name, ""))
		if held != "":
			var _applied := set_cvar(cvar_name, held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


## Applies one cvar by name. False for another name or a value that does not parse.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	match cvar_name:
		CVAR_ENABLED:
			if not text.is_valid_int():
				return false
			enabled = text.to_int() != 0
		CVAR_AWAKE:
			if not text.is_valid_int():
				return false
			max_awake = clampi(text.to_int(), 0, 256)
		CVAR_PUSH:
			if not text.is_valid_float():
				return false
			push_scale = clampf(text.to_float(), 0.0, 4.0)
		_:
			return false
	# Resource's own `changed`, which a box listens to.
	emit_changed()
	return true


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	var _applied := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	return {"enabled": enabled, "max_awake": max_awake, "cap": cap(), "push_scale": push_scale}

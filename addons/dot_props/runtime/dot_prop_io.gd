class_name DotPropIO
extends Node

## Props wired to props: a button's output to a door's input.
##
## [b]A link table, and nothing that knows what a door is.[/b] A prop declares what it can
## say and hear in its definition's meta — `"outputs": ["pressed"]`, `"inputs": ["open",
## "close", "toggle"]` — and this keeps who is wired to whom and delivers a fired output to
## every input wired to it as [signal input_received]. What "open" does to a door, and what
## presses a button, are the game's: a door that swings and one that slides are the same
## link, and a game whose "use" key is F and one whose is E are the same table.
##
## [b]Owned by the spawner, cleared with either end.[/b] A link to a prop that has gone is a
## button that silently does nothing, so a removal takes every link touching it.
##
## [b]Server-authoritative.[/b] Links and firing happen on the authority; a client learns what
## a door did from the door, the way it learns everything else about a prop. Nothing here is
## replicated: a client that drew wires would ask [method links_from] of its own copy, which
## it does not have, and that is a game's decision to make.
##
## [codeblock]
## var io := DotPropIO.new()
## spawner.add_child(io)
## io.input_received.connect(func(target, input, value, source): ...)
## io.link(button.instance_id, &"pressed", door.instance_id, &"toggle")
## io.fire(button.instance_id, &"pressed")   # the door's handler runs
## [/codeblock]

const CHANNEL := "props.io"

## An output reached an input wired to it. [param source] may be null when the output was
## fired by something that is not a prop.
signal input_received(target: DotPropInstance, input: StringName, value: Variant, source: DotPropInstance)

## A wire was made or taken away.
signal links_changed(instance_id: int)

## Only the authority links and fires.
@export var authoritative: bool = true

## The spawner whose props these are. Unset is the parent.
@export var spawner_ref: DotNodeRef = null

## The most links one prop may have, in and out together. A cap rather than nothing,
## because every link is a delivery per firing and a prop wired to two hundred others is a
## server spending its tick on one click.
@export_range(1, 256) var max_links_per_prop: int = 16

## How deep a chain of firings may go in one call. A door whose output is wired back to the
## button that opened it fires for ever; the chain stops here and says so once.
@export_range(1, 64) var max_depth: int = 8

## Each {"from": id, "output": StringName, "to": id, "input": StringName}.
var _links: Array[Dictionary] = []

var _spawner: DotPropSpawner = null
var _depth: int = 0
var fired_count: int = 0
var refused_depth: int = 0


func _ready() -> void:
	_spawner = _resolve_spawner()
	if _spawner == null:
		DotLog.error(CHANNEL, "prop IO has no spawner; nothing can be wired")
		return
	_spawner.removed.connect(func(prop: DotPropInstance, _reason: StringName) -> void:
		var _dropped := unlink_all(prop.instance_id))


func _resolve_spawner() -> DotPropSpawner:
	if spawner_ref == null:
		return get_parent() as DotPropSpawner
	return spawner_ref.resolve_or_null(self, CHANNEL) as DotPropSpawner


# --- What a prop declares -------------------------------------------------------

## The outputs [param def] declares, from its meta's `outputs`.
static func outputs_of(def: DotPropDef) -> PackedStringArray:
	return _names(def, "outputs")


## The inputs [param def] declares, from its meta's `inputs`.
static func inputs_of(def: DotPropDef) -> PackedStringArray:
	return _names(def, "inputs")


static func _names(def: DotPropDef, key: String) -> PackedStringArray:
	var out := PackedStringArray()
	if def == null:
		return out
	var listed: Variant = def.meta.get(key, [])
	if listed is Array or listed is PackedStringArray:
		for name: Variant in listed:
			out.append(str(name))
	return out


# --- Wiring ---------------------------------------------------------------------

## Wires [param from]'s [param output] to [param to]'s [param input]. Refused when either
## prop is gone, does not declare that name, is the same prop, is already wired that way, or
## has [member max_links_per_prop] already.
func link(from: int, output: StringName, to: int, input: StringName) -> DotResult:
	if not authoritative:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the authority wires props.")
	if _spawner == null:
		return DotResult.fail(DotError.CODE_STATE, "No spawner.")
	if from == to:
		return DotResult.fail(DotError.CODE_INVALID, "A prop cannot be wired to itself.")

	var source := _spawner.get_prop(from)
	var target := _spawner.get_prop(to)

	if source == null or not source.is_alive() or target == null or not target.is_alive():
		return DotResult.fail(DotError.CODE_INVALID, "Both ends must be props that are still there.")
	if not outputs_of(source.def).has(String(output)):
		return DotResult.fail(DotError.CODE_INVALID, "%s has no output \"%s\"." % [source.def.name_or_id(), output])
	if not inputs_of(target.def).has(String(input)):
		return DotResult.fail(DotError.CODE_INVALID, "%s has no input \"%s\"." % [target.def.name_or_id(), input])
	if has_link(from, output, to, input):
		return DotResult.fail(DotError.CODE_INVALID, "Those two are already wired that way.")
	if link_count(from) >= max_links_per_prop or link_count(to) >= max_links_per_prop:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "A prop can have %d wires at most." % max_links_per_prop)

	_links.append({"from": from, "output": output, "to": to, "input": input})
	DotLog.debug(CHANNEL, "wired", {"from": from, "output": String(output), "to": to, "input": String(input)})
	links_changed.emit(from)
	links_changed.emit(to)
	return DotResult.success(_links.size())


func has_link(from: int, output: StringName, to: int, input: StringName) -> bool:
	for l in _links:
		if l["from"] == from and l["output"] == output and l["to"] == to and l["input"] == input:
			return true
	return false


## Every wire touching [param instance_id] taken away. Returns how many.
func unlink_all(instance_id: int) -> int:
	var kept: Array[Dictionary] = []
	var touched := {}
	for l in _links:
		if l["from"] == instance_id or l["to"] == instance_id:
			touched[l["from"]] = true
			touched[l["to"]] = true
		else:
			kept.append(l)
	var dropped := _links.size() - kept.size()
	_links = kept
	for id: int in touched:
		links_changed.emit(id)
	return dropped


func link_count(instance_id: int) -> int:
	var n := 0
	for l in _links:
		if l["from"] == instance_id or l["to"] == instance_id:
			n += 1
	return n


## The wires out of [param instance_id], each a copy.
func links_from(instance_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _links:
		if l["from"] == instance_id:
			out.append(l.duplicate())
	return out


func links_to(instance_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _links:
		if l["to"] == instance_id:
			out.append(l.duplicate())
	return out


# --- Firing ---------------------------------------------------------------------

## [param from] says [param output]: every input wired to it hears [param value]. Returns how
## many inputs heard it. A chain deeper than [member max_depth] stops, once, with a warning.
func fire(from: int, output: StringName, value: Variant = null) -> int:
	if not authoritative or _spawner == null:
		return 0
	if _depth >= max_depth:
		refused_depth += 1
		DotLog.warn(CHANNEL, "a chain of wired props went too deep and was stopped", {
			"from": from, "output": String(output), "depth": _depth,
		})
		return 0

	var source := _spawner.get_prop(from)
	var heard := 0
	_depth += 1
	fired_count += 1

	# A copy: a handler may wire, unwire or remove props while this walks.
	for l in _links.duplicate():
		if l["from"] != from or l["output"] != output:
			continue
		var target := _spawner.get_prop(int(l["to"]))
		if target == null or not target.is_alive():
			continue
		input_received.emit(target, l["input"], value, source)
		heard += 1

	_depth -= 1
	return heard


func describe() -> Dictionary:
	return {"links": _links.size(), "fired": fired_count, "stopped_chains": refused_depth}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["DotPropIO: %d wires, %d firings, %d chains stopped" % [_links.size(), fired_count, refused_depth]])
	for l in _links:
		lines.append("  #%d %s -> #%d %s" % [l["from"], l["output"], l["to"], l["input"]])
	return lines

class_name DotPropInstance
extends RefCounted

## One prop in the world: its definition, its node, and who put it there.
##
## [b]The owner is kept here and not on the node.[/b] Metadata on a node is invisible
## to anything that did not put it there, survives into a saved scene, and is
## unreachable once the node is freed — and the one moment ownership matters most is
## when a prop is being removed. Keeping it beside the node means
## [DotPropSpawner.removed] can say whose it was after the node has gone.

var def: DotPropDef = null

## The node in the world. May be freed; check with [method is_alive].
var node: Node3D = null

## Who spawned it.
var owner_id: StringName = &""

## Godot's instance id for [member node]. The handle everything else uses.
##
## An id rather than the node itself, because a tool holding a prop across ticks needs
## a handle that is safe to compare and safe to hold after the node is freed. A freed
## Node compared with `==` is undefined; an int is an int.
var instance_id: int = 0

## Simulated seconds when it was spawned. Never a wall clock.
var spawned_at: float = 0.0

## Whether the spawner still considers this prop to exist.
##
## [b]Separate from the node being valid, and it has to be.[/b] `queue_free()` is
## deferred, so `is_instance_valid` stays true for the rest of the frame after a prop
## is removed — and a tool that checked only the node would keep pulling on a prop an
## admin has already cleaned up, for as long as that frame lasts.
var alive: bool = true

## Whether it is frozen in place.
var frozen: bool = false

## Who is holding it with a tool, or empty.
##
## [b]One holder at a time, and this field is the whole enforcement.[/b] Two physics
## guns pulling one crate toward two players is a crate that oscillates violently
## between them and a physics step that costs ten times what it should.
var held_by: StringName = &""

## Anything the game keeps with a prop.
var meta: Dictionary = {}


func is_alive() -> bool:
	return alive and node != null and is_instance_valid(node)


func is_held() -> bool:
	return held_by != &""


func body() -> RigidBody3D:
	return node as RigidBody3D


func position() -> Vector3:
	return node.global_position if is_alive() else Vector3.ZERO


func describe() -> Dictionary:
	return {
		"prop": String(def.id) if def != null else "?",
		"owner": String(owner_id),
		"alive": is_alive(),
		"frozen": frozen,
		"held_by": String(held_by) if is_held() else "-",
	}


func _to_string() -> String:
	return "DotPropInstance(%s by %s)" % [
		String(def.id) if def != null else "?", String(owner_id)
	]

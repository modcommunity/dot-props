class_name DotPropCarry
extends Node

## Standing on a prop, and what that does to the prop. The half a crate needs to climb.
##
## [b]A character motor does not interact with a rigid body, and nothing about that
## looks broken.[/b] [DotFpsMotor] and every motor like it sweep a shape and slide
## along whatever they hit, which means a crate is exactly as solid as the floor and
## exactly as immovable: a player stands on one and it does not sink, does not tip,
## and does not carry them anywhere when a bus shoves it out from under them. Every
## number involved is correct. The crate is simply scenery that happens to be a
## [RigidBody3D], and the only way to notice is to stand on one and expect something.
##
## This is the missing half, and it is deliberately [i]outside[/i] the motor. The motor
## already publishes what is needed — [code]DotFpsState.ground_id[/code], the instance
## id of the collider underfoot — and it is documented there as a local physics handle
## that is not part of the simulation. So riding is resolved per frame on each machine
## from a handle each machine has, rather than becoming another field in a predicted
## state that a client and a server would have to agree about. Rigid-body simulation
## is not reproducible across machines, which is why [DotPropSpawner] does not predict
## props either; a predicted ride would be a correction every tick.
##
## [b]It only ever touches props.[/b] Everything here goes through the spawner, so a
## player cannot press down on the world, shove a door, or ride a vehicle by standing
## on it. A prop the spawner does not know about is not a prop.
##
## [codeblock]
## var carry := DotPropCarry.new()
## carry.spawner_ref = DotNodeRef.of_path(^"../Props")
## add_child(carry)
##
## # once per tick, per player, after the motor has run:
## var lift := carry.ride(state.ground_id, state.position, 80.0, delta)
## player.global_position += lift
## [/codeblock]

const CHANNEL := "props"

@export_group("Wiring")

## The spawner that owns the props this may touch.
@export var spawner_ref: DotNodeRef = null

@export_group("Tuning")

## Fraction of a standing player's weight that reaches the prop.
##
## [b]Not 1.0, and the reason is that a character motor is not a physics body.[/b] A
## real body resting on a crate settles into an equilibrium the solver finds; a swept
## capsule is teleported to its new position every tick and never settles, so feeding
## the full weight in makes a crate the player is standing still on accelerate away
## downward for ever. At 0.6 a crate visibly takes the weight, tips when somebody
## stands on its edge, and still holds them up.
@export_range(0.0, 2.0, 0.05) var weight_scale: float = 0.6

## Metres per second above which a carried player is not carried any further.
##
## A safety rail rather than a tuning knob. A prop caught in a solver explosion can
## report a velocity in the thousands, and a player multiplied by that leaves the map
## in one tick — which reads as the game throwing them out of the world rather than as
## one crate having a bad frame.
@export_range(0.0, 1000.0, 1.0) var max_carry_speed: float = 60.0

var _spawner: DotPropSpawner = null


func _ready() -> void:
	_spawner = _resolve_spawner()
	if _spawner == null:
		DotLog.error(CHANNEL, "prop carry has no spawner; nothing will be rideable")


func _resolve_spawner() -> DotPropSpawner:
	if spawner_ref == null:
		return get_parent() as DotPropSpawner
	return spawner_ref.resolve_or_null(self, CHANNEL) as DotPropSpawner


## The rideable prop under a player, or null when the ground is not one.
##
## [param ground_id] is [code]DotFpsState.ground_id[/code] — 0 when airborne.
func prop_under(ground_id: int) -> DotPropInstance:
	if ground_id == 0 or _spawner == null:
		return null

	var prop := _spawner.prop_for_node(instance_from_id(ground_id) as Node)
	if prop == null or not prop.is_alive() or prop.def == null:
		return null
	if not prop.def.rideable:
		return null
	return prop


## How fast the surface under a player is moving, at the point they are standing.
##
## [b]Angular velocity is included, and leaving it out is the bug that looks like
## nothing.[/b] A crate that is only sliding moves every point on it at the same
## speed, so the linear velocity alone is right — and a crate that is [i]turning[/i]
## moves the player standing on its edge a great deal faster than its centre. Take
## only the linear part and a player on a spinning crate slowly slides toward the
## middle of it, with no error anywhere and nothing to see except that they drift.
func velocity_at(ground_id: int, point: Vector3) -> Vector3:
	var prop := prop_under(ground_id)
	if prop == null:
		return Vector3.ZERO

	var body := prop.body()
	if body == null or body.freeze:
		return Vector3.ZERO

	var lever := point - body.global_position
	var velocity := body.linear_velocity + body.angular_velocity.cross(lever)

	if velocity.length() > max_carry_speed:
		return velocity.normalized() * max_carry_speed
	return velocity


## Press a standing player's weight into the prop under them.
##
## [param mass_kg] is the player's mass. Call once per tick per grounded player.
func stand(ground_id: int, point: Vector3, mass_kg: float, delta: float) -> void:
	if delta <= 0.0 or mass_kg <= 0.0:
		return

	var prop := prop_under(ground_id)
	if prop == null:
		return

	var body := prop.body()
	if body == null or body.freeze:
		return

	# At the contact point rather than centrally, which is what makes a crate tip when
	# somebody stands on its edge instead of sinking flat. `apply_impulse` takes an
	# offset from the centre of mass in global orientation.
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var impulse := Vector3.DOWN * mass_kg * gravity * weight_scale * delta
	body.apply_impulse(impulse, point - body.global_position)


## Everything a grounded player owes and is owed by the prop under them, in one call.
##
## Applies their weight and returns the displacement to add to their position this
## tick. [code]Vector3.ZERO[/code] when they are not on a prop, so a caller can add it
## unconditionally.
func ride(ground_id: int, point: Vector3, mass_kg: float, delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	stand(ground_id, point, mass_kg, delta)
	return velocity_at(ground_id, point) * delta


## Shove a prop, for a player walking into one rather than standing on one.
##
## Returns false when [param instance_id] is not a prop this may push, so a caller can
## use it as the test as well as the action.
func push(instance_id: int, at: Vector3, impulse: Vector3) -> bool:
	if _spawner == null:
		return false

	var prop := _spawner.get_prop(instance_id)
	if prop == null or not prop.is_alive() or prop.def == null or not prop.def.rideable:
		return false

	var body := prop.body()
	if body == null or body.freeze:
		return false

	body.apply_impulse(impulse, at - body.global_position)
	return true


func describe() -> Dictionary:
	return {
		"weight_scale": weight_scale,
		"max_carry_speed": "%.0f m/s" % max_carry_speed,
		"spawner": _spawner != null,
	}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("DotPropCarry: weight x%.2f, carry capped at %.0f m/s"
		% [weight_scale, max_carry_speed])
	if _spawner == null:
		lines.append("  no spawner")
	return lines


func _to_string() -> String:
	return "DotPropCarry(x%.2f)" % weight_scale

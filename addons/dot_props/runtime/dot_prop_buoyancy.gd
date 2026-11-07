class_name DotPropBuoyancy
extends RefCounted

## Buoyancy and drag on a loose rigid body in a liquid. The host passes the liquid volumes
## (`{box: AABB, material: Variant}`) and a `surface(material)` lookup returning an object with
## `density` (kg/m3) and `dampening` (drag per second), or null for none.

## The fastest a body rises through a liquid under its own buoyancy, m/s.
const RISE_SPEED := 2.0


## Volume of a box-extent prop: a sphere is pi/6 of its box, a cylinder pi/4. [param shape] is
## "box", "sphere" or "cylinder".
static func volume_of(extent: Vector3, size_scale: float, shape: String) -> float:
	var box := extent.x * extent.y * extent.z * pow(size_scale, 3.0)
	match shape:
		"sphere":
			return box * PI / 6.0
		"cylinder":
			return box * PI / 4.0
	return box


## How far [param body] is under the surface of [param liquid_box], 0 to 1, or 0 when it is outside the box.
static func submerged_fraction(at: Vector3, half_height: float, liquid_box: AABB) -> float:
	var submerged := clampf((liquid_box.end.y - (at.y - half_height)) / maxf(half_height * 2.0, 0.01), 0.0, 1.0)
	if at.x < liquid_box.position.x or at.x > liquid_box.end.x or at.z < liquid_box.position.z or at.z > liquid_box.end.z:
		return 0.0
	return submerged


## Whether [param at] is within 2 m of any liquid box: the cheap test before measuring a prop.
static func near_liquid(at: Vector3, liquids: Array) -> bool:
	for liquid: Dictionary in liquids:
		if (liquid["box"] as AABB).grow(2.0).has_point(at):
			return true
	return false


## Floats or sinks [param body] in the first liquid it is in. [param density] is the body's
## (kg/m3), [param volume] and [param half_height] its size. Returns true when a liquid acted.
static func apply(body: RigidBody3D, volume: float, half_height: float, density: float, liquids: Array, surface: Callable, step: float, gravity: float) -> bool:
	var at := body.global_position
	for liquid: Dictionary in liquids:
		var box: AABB = liquid["box"]
		if not box.grow(2.0).has_point(at):
			continue
		var s: Variant = surface.call(liquid["material"])
		if s == null:
			continue
		var submerged := submerged_fraction(at, half_height, box)
		if submerged <= 0.0:
			continue
		# Up by the liquid's weight displaced; the engine already pulls down by the body's.
		var lift: float = s.density * volume * submerged * gravity
		# A dense body is heavier than its mass says: pull the difference down too.
		var extra := maxf(density * volume - body.mass, 0.0) * gravity * submerged
		var drag := clampf(s.dampening * submerged * step, 0.0, 1.0)
		# Buoyancy is a spring stiff by liquid density over body density; critical damping settles the bob.
		var ratio := clampf(s.density / maxf(density, 1.0), 0.0, 60.0)
		var critical := 2.0 * sqrt(gravity * ratio / maxf(half_height * 2.0, 0.1))
		# Not scaled by depth: a floater rides almost out of the liquid and would bounce for ever.
		var settle := clampf(critical * step, 0.0, 1.0)
		# One impulse from the velocity read once: separate impulses let damping read it before the lift landed.
		var vy := body.linear_velocity.y
		var rise := (lift - extra) * step / maxf(body.mass, 0.001)
		var vy_after := minf(vy * (1.0 - drag) * (1.0 - settle) + rise, maxf(vy, RISE_SPEED))
		body.apply_central_impulse(Vector3.UP * (vy_after - vy) * body.mass)
		var flat := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		body.apply_central_impulse(-flat * body.mass * drag)
		body.angular_velocity *= 1.0 - drag
		return true
	return false

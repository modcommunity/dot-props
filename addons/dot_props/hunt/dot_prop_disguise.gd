class_name DotPropDisguise
extends RefCounted

## A player hiding as a prop: which one, how big it is, which way it is turned, and the
## arithmetic every hiding game has to get the same on both ends.
##
## [b]A value, not a node.[/b] The server decides what somebody is disguised as and every client
## draws it, so what a disguise is has to be something a wire can carry and a suite can build:
## an id, a size in metres and three angles. Who is wearing it, and the model that draws it, are
## the game's.
##
## [b]The hull is a capsule a motor can sweep, not the prop's box.[/b] [method hull] is half the
## NARROWER footprint for the radius and the prop's height for the height, both clamped by the
## rules. A box would be truer to the picture and wrong for the game: a player-sized motor
## sweeping a sofa-wide box cannot get through the door the sofa came in by. The hitbox is the
## other half and IS the prop's box, turned the way the prop is turned ([method hit_basis]):
## what a hunter shoots at is what they can see.
##
## [b]Both ends compute the hull from the size, never send it.[/b] A predicting client and the
## server must sweep the same capsule or every step is a correction, and a number derived from
## one replicated value cannot disagree the way two replicated values can.

## The prop's id in the game's catalogue. Empty is "not disguised": their own body.
var prop_id: StringName = &""

## The prop's size, upright, in metres: x and z across, y up.
var size: Vector3 = Vector3.ZERO

## Which way the prop faces, in degrees. Used while [member locked]; otherwise it turns with
## the player's view.
var yaw: float = 0.0

## How far it leans forward and sideways, in degrees.
var pitch: float = 0.0
var roll: float = 0.0

## Whether the prop keeps [member yaw] while the player looks about. The hiding games' "lock
## rotation": a prop that turns to face wherever its player looks is a prop that moves.
var locked: bool = false


static func of(p_prop_id: StringName, p_size: Vector3) -> DotPropDisguise:
	var d := DotPropDisguise.new()
	d.prop_id = p_prop_id
	d.size = p_size
	return d


func is_disguised() -> bool:
	return prop_id != &""


func volume() -> float:
	return absf(size.x * size.y * size.z)


## Whether [param size] is something a player may hide as, and why not.
static func may_take(p_size: Vector3, rules: DotPropDisguiseRules) -> DotResult:
	var smallest := minf(p_size.x, minf(p_size.y, p_size.z))

	if smallest <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "That has no size.")

	if smallest < rules.min_dimension:
		return DotResult.fail(DotError.CODE_INVALID,
			"That is too small to hide as (%.2f m, the least is %.2f m)." % [smallest, rules.min_dimension])

	var v := absf(p_size.x * p_size.y * p_size.z)

	if rules.max_volume > 0.0 and v > rules.max_volume:
		return DotResult.fail(DotError.CODE_INVALID,
			"That is too big to hide as (%.1f m³, the most is %.1f m³)." % [v, rules.max_volume])

	return DotResult.success(null)


## The collision capsule for [param p_size]: `Vector2(radius, height)`.
static func hull(p_size: Vector3, rules: DotPropDisguiseRules) -> Vector2:
	var radius := clampf(minf(p_size.x, p_size.z) * 0.5, rules.hull_min_radius, rules.hull_max_radius)
	var height := clampf(p_size.y, rules.hull_min_height, rules.hull_max_height)
	# A capsule cannot be shorter than it is wide; a flat prop gets a squat capsule, not an error.
	height = maxf(height, radius * 2.0)
	return Vector2(radius, height)


## How much health a prop of [param p_size] has.
static func health(p_size: Vector3, rules: DotPropDisguiseRules) -> float:
	var v := maxf(absf(p_size.x * p_size.y * p_size.z), 0.000001)
	return clampf(round(rules.health_scale * pow(v, rules.health_exponent)), rules.min_health, rules.max_health)


## The health a player has after changing from a disguise worth [param old_max] to one worth
## [param new_max], having [param current]. See [member DotPropDisguiseRules.keep_health_fraction].
static func health_after(current: float, old_max: float, new_max: float, rules: DotPropDisguiseRules) -> float:
	if not rules.keep_health_fraction or old_max <= 0.0:
		return new_max

	return clampf(ceil(new_max * clampf(current / old_max, 0.0, 1.0)), 1.0, new_max)


## Whether a prop whose nearest point is [param target] is close enough to [param eye] to copy.
static func within_reach(eye: Vector3, target: Vector3, rules: DotPropDisguiseRules) -> bool:
	return eye.distance_to(target) <= rules.reach


## The prop's turn: yaw about up, then pitch and roll about its own axes. [param view_yaw] is
## the player's own look, used while the disguise is not [member locked].
func hit_basis(view_yaw: float = 0.0) -> Basis:
	var facing := yaw if locked else view_yaw
	return Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(facing), deg_to_rad(roll)), EULER_ORDER_YXZ)


## Tilts by [param steps] of the rules' step, forward ([param forward]) or sideways, within
## the rules' limit. Returns whether anything changed.
func tilt(steps: int, forward: bool, rules: DotPropDisguiseRules) -> bool:
	var before := Vector2(pitch, roll)
	var by := rules.tilt_step * float(steps)

	if forward:
		pitch = clampf(pitch + by, -rules.max_tilt, rules.max_tilt)
	else:
		roll = clampf(roll + by, -rules.max_tilt, rules.max_tilt)

	return not before.is_equal_approx(Vector2(pitch, roll))


## Puts the prop upright again.
func straighten() -> void:
	pitch = 0.0
	roll = 0.0


## Locks the facing at [param view_yaw], or frees it.
func set_locked(on: bool, view_yaw: float) -> void:
	locked = on

	if on:
		yaw = view_yaw


## What crosses a wire: short keys, because a disguise goes to everybody on every change.
func to_wire() -> Dictionary:
	return {
		"p": String(prop_id),
		"s": [size.x, size.y, size.z],
		"y": yaw, "t": pitch, "r": roll,
		"l": locked,
	}


static func from_wire(wire: Dictionary) -> DotPropDisguise:
	var d := DotPropDisguise.new()
	d.prop_id = StringName(str(wire.get("p", "")))
	var s: Array = wire.get("s", [0, 0, 0])

	if s.size() == 3:
		d.size = Vector3(float(s[0]), float(s[1]), float(s[2]))

	d.yaw = float(wire.get("y", 0.0))
	d.pitch = float(wire.get("t", 0.0))
	d.roll = float(wire.get("r", 0.0))
	d.locked = bool(wire.get("l", false))
	return d


func duplicate_value() -> DotPropDisguise:
	return from_wire(to_wire())


func describe() -> Dictionary:
	if not is_disguised():
		return {"disguised": false}

	return {
		"prop": String(prop_id),
		"size": "%.2f x %.2f x %.2f" % [size.x, size.y, size.z],
		"turn": "%.0f / %.0f / %.0f" % [yaw, pitch, roll],
		"locked": locked,
	}

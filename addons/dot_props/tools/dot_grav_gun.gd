class_name DotGravGun
extends DotPropTool

## The gravity gun: pull a prop to you, carry it in front of you, and punt it.
##
## [b]The difference from [DotPhysGun] is what it is for, and it is not a smaller
## physics gun.[/b] A physics gun is a building tool — arbitrary distance, free
## rotation, freezing, and a deliberately soft spring so a piece can be placed
## precisely. A gravity gun is a weapon and a toy: one fixed carrying position, a
## stiff hold so the prop tracks the crosshair, and a punt that sends it away hard.
## Shipping only one of them and calling it both gives a building tool that cannot
## throw and a weapon that cannot build.
##
## Server-side, like everything that touches a prop: physics is not predicted.

## How far in front of the player a carried prop sits, in metres.
var carry_distance: float = 3.0

## How hard it is pulled to that position, per second. Stiffer than a physics gun's.
var stiffness: float = 26.0

## Fastest a carried prop may move, in m/s. The same safety cap as the physics gun's.
var max_speed: float = 80.0

## Impulse applied to a punted prop, in newton-seconds.
##
## Applied as an impulse rather than as a velocity so a heavy prop is punted less far
## than a light one — which is what makes the tool feel like it has weight, and is
## free because the solver already divides by the mass.
var punt_impulse: float = 2200.0

## How far a punt reaches when nothing is carried, in metres.
##
## Shorter than [member DotPropTool.reach], because punting something across the map
## is a griefing tool rather than a mechanic.
var punt_range: float = 14.0

## Impulse applied to a prop punted at range, as a fraction of [member punt_impulse].
var punt_at_range_scale: float = 0.6

## The prop being carried, or null.
var carried: DotPropInstance = null


## Pulls in whatever the tool is pointing at.
func pull(
	space: Variant,
	origin: Vector3,
	direction: Vector3,
	can_touch_others: bool = true
) -> DotResult:
	if carried != null:
		return DotResult.fail(DotError.CODE_STATE, "Already carrying something.")

	var prop := target(space, origin, direction)
	var allowed := may_act_on(prop, can_touch_others)

	if not allowed.ok:
		return allowed

	var body := prop.body()

	if body == null:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"That prop is not a RigidBody3D.",
			String(prop.def.id)
		)

	if prop.frozen:
		# A frozen prop is refused rather than thawed. The physics gun unfreezes what
		# it grabs because freezing is its own tool and un-freezing is the obvious
		# undo; a gravity gun that quietly unfroze somebody's build would take a
		# tower apart one piece at a time.
		return DotResult.fail(
			DotError.CODE_STATE, "That is frozen in place."
		)

	carried = prop
	prop.held_by = wielder

	return DotResult.success(prop)


## Keeps the carried prop in front of the player. Once per physics tick.
func carry(origin: Vector3, direction: Vector3, delta: float) -> void:
	if carried == null:
		return

	if not carried.is_alive():
		drop()
		return

	var body := carried.body()

	if body == null:
		drop()
		return

	var goal := origin + direction.normalized() * carry_distance
	var offset := goal - body.global_position

	body.linear_velocity = (offset * stiffness).limit_length(max_speed)

	# Damped rather than zeroed, so a carried prop keeps a little of its spin. Zeroed
	# looks like it is welded to the air; unmanaged, it whirls.
	body.angular_velocity = body.angular_velocity.lerp(
		Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0)
	)


## Punts what is carried, or what is in range if nothing is.
##
## Returns the prop that was punted, or null.
func punt(
	space: Variant,
	origin: Vector3,
	direction: Vector3,
	can_touch_others: bool = true
) -> DotPropInstance:
	var aim := direction.normalized()

	if carried != null:
		var prop := drop()

		if prop != null and prop.is_alive():
			var body := prop.body()

			if body != null:
				body.apply_central_impulse(aim * punt_impulse)

		return prop

	# Nothing carried: punt at range, less hard and less far.
	var previous_reach := reach
	reach = punt_range

	var found := target(space, origin, aim)

	reach = previous_reach

	var allowed := may_act_on(found, can_touch_others)

	if not allowed.ok:
		return null

	if found.frozen:
		return null

	var target_body := found.body()

	if target_body == null:
		return null

	target_body.apply_central_impulse(
		aim * punt_impulse * punt_at_range_scale
	)

	return found


## Puts down what is carried, keeping whatever velocity it has.
func drop() -> DotPropInstance:
	if carried == null:
		return null

	var prop := carried

	if prop.held_by == wielder:
		prop.held_by = &""

	carried = null

	return prop


func is_carrying() -> bool:
	return carried != null


func describe() -> Dictionary:
	var out := super.describe()
	out["carried"] = str(carried) if carried != null else "-"
	out["punt"] = "%.0f Ns" % punt_impulse
	return out

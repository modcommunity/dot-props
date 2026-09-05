class_name DotPhysGun
extends DotPropTool

## The physics gun: hold a prop in front of you, move it, turn it, freeze it.
##
## [b]Held by a spring, not by a transform assignment.[/b] Teleporting a rigid body to
## a target position each tick is the obvious implementation and it is what makes a
## sandbox unplayable: a body moved rather than pushed has no velocity, so it passes
## through walls, wakes nothing it touches, and hands the solver an impossible
## situation when it is finally released. Instead the gun sets a velocity toward where
## the prop should be, which is a force the solver understands — the prop pushes what
## is in the way, stops against a wall, and carries its momentum when let go.
##
## [b]Server-side, always.[/b] Props are not predicted (see [DotPropSpawner]), so the
## gun runs where the physics runs. The client sends where it is aiming and draws the
## beam to wherever the prop turns out to be, which is a frame or two behind and looks
## exactly right because the prop is [i]supposed[/i] to lag the aim.

## How hard the prop is pulled toward its target, per second.
##
## High enough to feel responsive, low enough that the prop visibly lags the aim —
## which is the whole feel of the tool. Above about 30 it snaps and stops looking like
## a physical object; below about 6 it feels like dragging something through mud.
var stiffness: float = 14.0

## How much of the prop's own velocity is kept, per second. 0 stops it dead.
##
## The damping half of the spring. Without it the prop overshoots its target and
## oscillates, which is the classic sandbox wobble.
var damping: float = 8.0

## Fastest the held prop may be moved, in m/s.
##
## [b]A hard cap, and it is a safety measure rather than a feel one.[/b] The spring's
## output is proportional to the distance to the target, so a player who aims at the
## sky and then at their feet asks for an arbitrarily large velocity — which tunnels
## the prop through the world and, at the extreme, produces a non-finite position that
## poisons the physics island it is in.
var max_speed: float = 60.0

## How fast the hold distance changes when pushed or pulled, in m/s.
var push_speed: float = 12.0

## The prop in hand, or null.
var held: DotPropInstance = null

## How far in front of the player it is being held.
var hold_distance: float = 6.0

## The prop's orientation relative to the player's view when it was grabbed.
##
## [b]Relative, so turning your view turns the prop with it[/b] — which is what makes
## a physics gun usable for building. Storing an absolute orientation means the prop
## keeps facing north while the player walks around it.
var hold_rotation: Basis = Basis.IDENTITY

## Whether the player is currently rotating the prop instead of turning their view.
var rotating: bool = false


## Grabs whatever the tool is pointing at.
func grab(
	space: Variant,
	origin: Vector3,
	direction: Vector3,
	view: Basis,
	can_touch_others: bool = true
) -> DotResult:
	if held != null:
		return DotResult.fail(DotError.CODE_STATE, "Already holding something.")

	var prop := target(space, origin, direction)
	var allowed := may_act_on(prop, can_touch_others)

	if not allowed.ok:
		return allowed

	var body := prop.body()

	if body == null:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"That prop is not a RigidBody3D, so it cannot be held.",
			String(prop.def.id)
		)

	held = prop
	prop.held_by = wielder

	# Grabbing unfreezes. A frozen prop that could be held would be dragged around
	# while still refusing to move, which is a contradiction the solver resolves by
	# doing something alarming.
	if prop.frozen:
		set_frozen(prop, false)

	hold_distance = clampf(
		origin.distance_to(body.global_position),
		_min_distance(),
		_max_distance()
	)

	# The prop's orientation in the player's frame at the moment of the grab.
	hold_rotation = view.inverse() * body.global_basis

	return DotResult.success(prop)


## Moves the held prop toward where the player is aiming. Once per physics tick.
##
## [param delta] must be the physics step, because the velocity written here is
## consumed by the solver on that step.
func hold(
	origin: Vector3,
	direction: Vector3,
	view: Basis,
	delta: float
) -> void:
	if held == null:
		return

	if not held.is_alive():
		# The prop was removed while it was in hand — an admin cleanup, an undo, a
		# player disconnecting. Letting go here rather than checking at every call
		# site is why `held` is allowed to point at something that may vanish.
		release()
		return

	var body := held.body()

	if body == null:
		release()
		return

	var goal := origin + direction.normalized() * hold_distance
	var offset := goal - body.global_position

	# The spring. Velocity toward the goal, damped by what the body is already doing,
	# so it arrives rather than oscillating around the target.
	var wanted := offset * stiffness
	var velocity := body.linear_velocity.lerp(
		wanted, clampf(damping * delta, 0.0, 1.0)
	)

	# The cap, and it is not decoration: the spring's output is proportional to the
	# distance to the goal, so a player who aims at the sky and then at their feet
	# asks for an unbounded velocity — which tunnels the prop through the world and
	# can produce a non-finite position that poisons its whole physics island.
	body.linear_velocity = velocity.limit_length(max_speed)

	# Orientation is assigned rather than sprung. A rotational spring needs an
	# inertia tensor and a stable quaternion error term to be worth anything, and a
	# held prop that fights back when turned is worse than one that simply turns.
	if not rotating:
		body.angular_velocity = Vector3.ZERO
		body.global_basis = view * hold_rotation


## Turns the held prop, in the player's own frame.
##
## For a "hold a key and move the mouse to rotate" control. Applied to the stored
## relative orientation, so it survives the player turning afterwards.
func rotate_held(yaw_degrees: float, pitch_degrees: float) -> void:
	if held == null:
		return

	hold_rotation = (
		Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		* Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees))
		* hold_rotation
	)


## Pushes the held prop further away or pulls it closer.
func push(amount: float, delta: float) -> void:
	if held == null:
		return

	hold_distance = clampf(
		hold_distance + amount * push_speed * delta,
		_min_distance(),
		_max_distance()
	)


## Lets go. Returns what was held, or null.
##
## The prop keeps whatever velocity the spring gave it, which is what makes throwing
## work and is the reason the spring exists.
func release() -> DotPropInstance:
	if held == null:
		return null

	var prop := held

	if prop.held_by == wielder:
		prop.held_by = &""

	held = null

	return prop


## Freezes the held prop where it is, and lets go.
##
## The physics gun's other half: a builder positions a piece and freezes it, and the
## next one rests on it. Without freezing, a stack of anything falls over the moment
## it is let go.
func freeze_held() -> DotResult:
	if held == null:
		return DotResult.fail(DotError.CODE_STATE, "Nothing in hand.")

	if not held.def.can_freeze:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"That cannot be frozen.",
			String(held.def.id)
		)

	# Checked here rather than in `set_frozen`, which is also the UNfreeze path and
	# a static helper an admin tool calls: a limit that refused to unfreeze, or that
	# stopped a moderator tidying up, would be a limit fighting its own operator.
	if spawner != null:
		var allowed := spawner.may_freeze(wielder)

		if not allowed.ok:
			return allowed

	var prop := held
	release()
	set_frozen(prop, true)

	return DotResult.success(prop)


## Freezes or unfreezes a prop.
##
## [b]Freezing zeroes the velocities as well as setting the mode.[/b] Godot keeps a
## frozen body's velocities and applies them the instant it is unfrozen, so a prop
## frozen while moving fast leaps away when somebody thaws it — minutes later, with
## nothing to connect the two.
static func set_frozen(prop: DotPropInstance, frozen: bool) -> void:
	if prop == null or not prop.is_alive():
		return

	var body := prop.body()

	if body == null:
		return

	if frozen:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	body.freeze = frozen
	prop.frozen = frozen


func _min_distance() -> float:
	if spawner != null and spawner.limits != null:
		return spawner.limits.hold_distance_min
	return 1.5


func _max_distance() -> float:
	if spawner != null and spawner.limits != null:
		return spawner.limits.hold_distance_max
	return 25.0


func describe() -> Dictionary:
	var out := super.describe()
	out["held"] = str(held) if held != null else "-"
	out["distance"] = "%.1f m" % hold_distance
	return out

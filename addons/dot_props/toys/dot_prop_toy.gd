class_name DotPropToy
extends "dot_prop_toy_parts.gd"

## One toy on a map, built from a [DotPropToyCatalogue] definition by a [DotPropToyBox]: its
## bodies, its joints, how it is drawn, and what a push, a use, a shot or a person standing on
## it does to it.
##
## [b]The server's physics, a client's picture.[/b] On the authoritative end the moving part is
## a real [RigidBody3D] (with its joint or its axis locks); on a client it is the same body
## frozen kinematic and posed from the replicated state ([method show_state]), so a person
## standing on a see-saw on a client stands on the plank the server tipped. Godot's rigid-body
## solver is not the same on two machines, so nothing here is predicted (dot-props'
## spawning.md).
##
## [b]A person is not a rigid body.[/b] A character motor slides along a rigid body without
## pushing it, so what a person does to a toy is said by the game every tick:
## [method push_from] (walking into it), [method stand_on] (weight on a plank), [method use]
## (the use key), [method hit] (a shot). The loose kinds are on a layer people do not collide
## with at all, so a ball rolls away from a person's shins instead of being a wall in the way.


## Builds it under this node, which is already in the tree and placed. [param p_layers] holds
## `loose_layer`, `loose_mask`, `solid_layer`, `solid_mask` (bits; the game's layout's).
func build(p_def: Dictionary, p_placement: Dictionary, p_layers: Dictionary) -> void:
	def = p_def
	placement = p_placement
	layers = p_layers
	kind = StringName(def.get("kind", &"ball"))
	_size = def.get("size", Vector3.ONE)
	on = bool(placement.get("on", def.get("on", false)))
	for raw: Variant in placement.get("links", []):
		links.append(int(raw))

	if draw:
		_visual = Node3D.new()
		_visual.name = "Look"
		add_child(_visual)

	match kind:
		&"ball": _build_ball()
		&"pin": _build_pin()
		&"barrel": _build_barrel()
		&"crate": _build_crate()
		&"tyre": _build_tyre()
		&"bag": _build_bag()
		&"swing": _build_swing()
		&"seesaw": _build_seesaw()
		&"spinner": _build_spinner()
		&"wobble": _build_wobble()
		&"bouncer": _build_bouncer()
		&"pad": _build_pad()
		&"switch": _build_switch()
		&"lamp": _build_lamp()
		&"fountain": _build_fountain()
		&"horn": _build_horn()
		&"bell": _build_bell()
	pushable = kind == &"spinner" or DotPropToyCatalogue.LOOSE.has(kind)

	if body != null:
		rest = body.global_transform
		if kind == &"tyre" and authoritative and not _driven:
			# A map hangs a stood wheel a little above its floor; dropped, it tips and rolls away.
			get_tree().physics_frame.connect(_sleep_at_start, CONNECT_ONE_SHOT)
		if not authoritative and not _driven:
			# Drawn, never simulated: posed from snapshots, still something to stand on.
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			body.freeze = true
	_show_on()


## Which of the angles this kind turns through.
func _axes() -> Vector3:
	match kind:
		&"swing": return Vector3(1, 0, 0)
		&"seesaw": return Vector3(0, 0, 1)
		&"spinner": return Vector3(0, 1, 0)
		&"bag", &"wobble": return Vector3(1, 0, 1)
	return Vector3.ZERO


func _turn() -> Basis:
	return Basis(Vector3.UP, _angle.y) * Basis(Vector3.RIGHT, _angle.x) * Basis(Vector3.BACK, _angle.z)


func _pose() -> void:
	var turn := _turn()
	body.transform = Transform3D(turn, _pivot + turn * _hang)


func _pivot_global() -> Vector3:
	return to_global(_pivot)


## A change of velocity [param dv] at [param point] (world space), turned into the spins this
## kind allows, as a point mass at that radius would take it.
func _nudge(point: Vector3, dv: Vector3) -> void:
	var r := point - _pivot_global()
	var w := r.cross(dv) / maxf(r.length_squared(), 0.04)
	_spin += (global_basis.inverse() * w) * _axes()


## The velocity of a point on the moving part, in world space.
func _point_velocity(point: Vector3) -> Vector3:
	return (global_basis * _spin).cross(point - _pivot_global())


func _physics_process(delta: float) -> void:
	if not _driven or not authoritative or body == null or delta <= 0.0:
		return
	var torque := _torque
	_torque = Vector3.ZERO
	var accel := Vector3.ZERO
	var damp := float(def.get("angular_damp", 0.2))
	match kind:
		&"swing", &"bag":
			var length := maxf(_hang.length(), 0.2)
			accel = Vector3(-gravity / length * sin(_angle.x), 0, -gravity / length * sin(_angle.z))
		&"seesaw":
			var inertia := maxf(float(def.get("mass", 1.0)) * _size.x * _size.x / 12.0, 0.1)
			accel = torque / inertia
		&"wobble":
			var inertia := maxf(float(def.get("mass", 1.0)) * (_size.x * _size.x + _size.z * _size.z) / 12.0, 0.1)
			accel = (torque - _angle * WOBBLE_SPRING) / inertia
			damp = WOBBLE_DAMP
	var resting := accel.length_squared() < 0.0001 and _spin.length_squared() < 0.0004
	if resting and kind != &"wobble" and kind != &"swing" and kind != &"bag":
		_spin = Vector3.ZERO
		return
	if resting and _angle.length_squared() < 0.00002:
		_spin = Vector3.ZERO
		return
	_spin += (accel - _spin * damp) * delta
	_spin *= _axes()
	_angle += _spin * delta
	if kind == &"swing" or kind == &"bag":
		# Not over the top: a swing that loops is a swing on a rigid bar, which this is not.
		_angle.x = clampf(_angle.x, -1.3, 1.3)
		_angle.z = clampf(_angle.z, -1.3, 1.3)
	if _limit > 0.0:
		for i in [0, 2]:
			if absf(_angle[i]) > _limit:
				_angle[i] = signf(_angle[i]) * _limit
				# An end hits the ground: most of the spin goes, a little comes back.
				_spin[i] = -_spin[i] * 0.2
	if kind == &"spinner":
		_angle.y = fposmod(_angle.y, TAU)
	_pose()


func usable() -> bool:
	return str(def.get("use", "")) != ""


## The prompt for the use key: "Kick the beach ball", "Switch off the lamp".
func prompt() -> String:
	var verb := str(def.get("use", ""))
	if verb == "":
		return ""
	var name_of := str(def.get("name", "toy"))
	if kind in [&"lamp", &"fountain"]:
		return "%s %s the %s" % [verb, "off" if on else "on", name_of]
	return "%s the %s" % [verb, name_of]


## The use key on it, by somebody at [param origin] looking along [param direction]. Server
## side. True when it did something.
func use(origin: Vector3, direction: Vector3) -> bool:
	if not authoritative or not usable():
		return false
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var speed := float(def.get("kick", 0.0))
	match kind:
		&"ball", &"pin", &"barrel", &"tyre":
			var lift := speed * 0.35 if kind == &"ball" and float(def.get("mass", 1.0)) < 3.0 else 0.0
			var at := Vector3(0, _size.y * 0.3, 0) if kind == &"pin" else Vector3.ZERO
			_wake()
			body.apply_impulse((flat * speed + Vector3(0, lift, 0)) * body.mass, at)
		&"swing", &"bag":
			var centre := body.global_position
			_nudge(centre, flat * speed)
		&"seesaw":
			# Down at the end nearer the person, as a hand on it would.
			var local_x := (body.global_transform.affine_inverse() * origin).x
			var end := body.to_global(Vector3(signf(local_x if local_x != 0.0 else 1.0) * _size.x * 0.45, 0, 0))
			_nudge(end, Vector3(0, -speed, 0))
		&"spinner":
			var from_hub := Vector3(origin.x - body.global_position.x, 0, origin.z - body.global_position.z)
			var tangent := Vector3.UP.cross(from_hub.normalized()) if from_hub.length() > 0.01 else flat
			var sense := signf(tangent.dot(flat)) if tangent.dot(flat) != 0.0 else 1.0
			_spin_by(sense * speed)
		&"switch":
			_flip_links()
		&"lamp", &"fountain":
			_set_on(not on)
		&"horn", &"bell":
			pass
		_:
			return false
	_bump_count()
	return true


## `func(index: int) -> bool`: flips the box's toy [param index] and says whether it is on now.
## The box hands every switch this.
var link_fn: Callable = Callable()


func _set_on(value: bool) -> void:
	on = value
	_show_on()


## A switch flips every toy it is linked to (a lamp lit goes out, one out comes on), and shows
## the first one's state itself: down for on. Unlinked, it just flips.
func _flip_links() -> void:
	var now := not on
	if link_fn.is_valid():
		for i in range(links.size()):
			var lit: Variant = link_fn.call(links[i])
			if i == 0 and lit is bool:
				now = lit
	_set_on(now)


## Flipped by a switch. Returns whether it is on now.
func flip() -> bool:
	on = not on
	_bump_count()
	_show_on()
	return on


func _bump_count() -> void:
	count = (count + 1) % 256


## Spins a roundabout so its rim moves at [param rim_speed] faster (or slower, negative).
func _spin_by(rim_speed: float) -> void:
	var r := _size.x * 0.5
	# Its own y and the world's are the same axis: a roundabout is never placed tilted.
	_spin.y = clampf(_spin.y + rim_speed / maxf(r, 0.1), -4.0, 4.0)


## Somebody's capsule (feet at [param feet], [param radius], [param height]) moving at
## [param velocity] this tick: a loose toy in its way is pushed ahead of it, a roundabout's rim
## is turned along. Server side. True when it pushed.
func push_from(feet: Vector3, velocity: Vector3, radius: float, height: float, scale: float = 1.0) -> bool:
	if not authoritative or body == null:
		return false
	if kind == &"spinner":
		return _push_rim(feet, velocity, radius, height)
	if not DotPropToyCatalogue.LOOSE.has(kind):
		return false
	var centre := body.global_position
	var reach := _radius + radius
	if centre.y < feet.y - _radius or centre.y > feet.y + height + _radius:
		return false
	var d := Vector3(centre.x - feet.x, 0.0, centre.z - feet.z)
	var dist := d.length()
	if dist > reach + 0.05:
		return false
	var n := d / dist if dist > 0.01 else Vector3(velocity.x, 0, velocity.z).normalized()
	if n.length_squared() < 0.5:
		return false
	var approach := Vector3(velocity.x, 0, velocity.z).dot(n)
	# Standing in it: out of the way, gently. Walking into it: ahead of the person, a little
	# faster than they walk, as a foot sends a ball.
	var want := maxf(approach * 1.3, 0.0) * scale
	if dist < reach - 0.08:
		want = maxf(want, 0.8)
	var have := (_point_velocity(centre) if _driven else body.linear_velocity).dot(n)
	if want - have < 0.05:
		return false
	if _driven:
		# A swing's seat or a hanging bag: a heavy bag gives less to a walk than a seat does.
		var give := 1.0 if kind == &"swing" else 0.5
		_nudge(centre, n * (want - have) * give)
		return true
	var lift := (want - have) * 0.3 if kind == &"ball" and float(def.get("mass", 1.0)) < 3.0 else 0.0
	# A pin or a barrel is pushed above its middle, so it tips as well as slides.
	var at := Vector3(0, _size.y * 0.25, 0) if kind == &"pin" or kind == &"barrel" else Vector3.ZERO
	_wake()
	body.apply_impulse((n * (want - have) + Vector3(0, lift, 0)) * body.mass, at)
	return true


func _push_rim(feet: Vector3, velocity: Vector3, radius: float, height: float) -> bool:
	var hub := body.global_position
	if feet.y > hub.y + 0.1 or feet.y + height < hub.y - 0.1:
		return false
	var from_hub := Vector3(feet.x - hub.x, 0, feet.z - hub.z)
	var dist := from_hub.length()
	var r := _size.x * 0.5
	if dist < 0.01 or absf(dist - r) > radius + 0.12:
		return false
	var tangent := Vector3.UP.cross(from_hub / dist)
	var along := Vector3(velocity.x, 0, velocity.z).dot(tangent)
	var rim := _spin.y * r
	if absf(along) < 0.3 or absf(along) <= absf(rim) and signf(along) == signf(rim):
		return false
	_spin_by((along - rim) * 0.25)
	return true


## Somebody of [param mass] kg standing at [param feet] this tick: their weight on a see-saw or
## a wobbly platform. Server side. True when it bore them.
func stand_on(feet: Vector3, mass: float, p_gravity: float) -> bool:
	if not authoritative or body == null or not (kind == &"seesaw" or kind == &"wobble"):
		return false
	var local := body.global_transform.affine_inverse() * feet
	var half := Vector3(_size.x * 0.5 + 0.1, 0.0, _size.z * 0.5 + 0.25)
	if absf(local.x) > half.x or absf(local.z) > half.z or local.y < -0.15 or local.y > 0.45:
		return false
	var torque := (feet - _pivot_global()).cross(Vector3(0, -mass * p_gravity, 0))
	_torque += (global_basis.inverse() * torque) * _axes()
	return true


## A shot or a blast: [param impulse] N·s along [param direction] at [param point]. Server side.
func hit(point: Vector3, direction: Vector3, impulse: float) -> bool:
	if not authoritative or impulse <= 0.0:
		return false
	# A bell is rung by a shot as by a hand: its count moves, which every client hears.
	if kind == &"bell":
		_bump_count()
		return true
	if body == null:
		return false
	if _driven:
		_nudge(point, direction.normalized() * impulse / maxf(float(def.get("mass", 1.0)), 0.1))
		return true
	_wake()
	body.apply_impulse(direction.normalized() * impulse, point - body.global_position)
	return true


## A bouncer or a pad under somebody at [param feet] moving at [param velocity]: the velocity it
## throws them at, or [code]Vector3.INF[/code] when it does not. A pure function of where the
## toy stands, so a predicting client throws its own player on the same tick the server does.
func launch_for(feet: Vector3, velocity: Vector3) -> Vector3:
	if not (kind == &"bouncer" or kind == &"pad") or velocity.y > 0.5:
		return Vector3.INF
	var local := global_transform.affine_inverse() * feet
	var launch: Vector3 = def.get("launch", Vector3.ZERO)
	if kind == &"bouncer":
		var r := _size.x * 0.5 * 0.85
		if Vector2(local.x, local.z).length() > r or absf(local.y - _size.y) > 0.15:
			return Vector3.INF
		return Vector3(velocity.x, maxf(launch.y, -velocity.y * 0.5), velocity.z)
	if absf(local.x) > _size.x * 0.5 or absf(local.z) > _size.z * 0.5 or absf(local.y - _size.y) > 0.15:
		return Vector3.INF
	return global_basis * launch + Vector3(velocity.x, 0, velocity.z) * 0.25


## Its footprint in its own frame: where a bot's walkable mesh should not go. Empty for a
## loose toy, which a person walks through and pushes. At least two metres tall, so a baker
## never takes a low one (a pad, a trampoline) for a step it can climb onto.
func footprint() -> AABB:
	var box := _footprint()
	if box.size != Vector3.ZERO:
		box.size.y = maxf(box.size.y, 2.0)
	return box


func _footprint() -> AABB:
	var s := _size
	match kind:
		&"bag": return AABB(Vector3(-1.0, 0, -0.6), Vector3(1.6, s.y + 1.6, 1.2))
		&"swing": return AABB(Vector3(-s.x * 0.5 - 0.1, 0, -1.4), Vector3(s.x + 0.2, s.y, 2.8))
		&"seesaw": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5 - 0.1), Vector3(s.x, s.y + 0.3, s.z + 0.2))
		&"spinner", &"bouncer", &"fountain": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), Vector3(s.x, s.y + 0.3, s.z))
		&"wobble", &"pad": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), Vector3(s.x, s.y + 0.1, s.z))
		&"switch", &"lamp", &"horn": return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, s.y, 0.6))
		&"bell": return AABB(Vector3(-s.x * 0.5 - 0.1, 0, -0.3), Vector3(s.x + 0.2, s.y, 0.6))
	return AABB()


# --- State --------------------------------------------------------------------------

## Puts it back where the map has it, still, asleep. Server side; a round's start.
func reset() -> void:
	on = bool(placement.get("on", def.get("on", false)))
	_show_on()
	if body == null or not authoritative:
		return
	if _driven:
		_angle = Vector3.ZERO
		_spin = Vector3.ZERO
		_torque = Vector3.ZERO
		_pose()
		return
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, rest)
	body.global_transform = rest
	body.sleeping = true


func _sleep_at_start() -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	# Jolt wakes a sleeper with nothing under it, so the wheel is lowered onto the floor first.
	var from := body.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (_radius + 0.5), body.collision_mask & ~body.collision_layer)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var spot := body.global_transform
		spot.origin.y = float((hit["position"] as Vector3).y) + _radius * 0.97
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, spot)
		body.global_transform = spot
		rest = spot
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = true


func _wake() -> void:
	if body != null and body.sleeping:
		body.sleeping = false


## Whether its moving part is simulating now. A driven kind (a swing, a see-saw) is never
## counted: it is an angle, not a body the solver carries.
func awake() -> bool:
	return body != null and not _driven and not body.freeze and not body.sleeping


## Whether a driven kind is moving.
func moving() -> bool:
	return _driven and _spin.length_squared() > 0.0004


## Where its moving part is, in world space: what a server replicates. Its own transform for a
## toy that does not move.
func state_transform() -> Transform3D:
	return body.global_transform if body != null else global_transform


## A replicated state, on a client: the moving part posed, and what is on and how often it was
## used, with the sound and the flourish when that changed.
##
## [param delta] is the time since the last state shown, for the spin a roundabout is measured
## turning at ([method surface_velocity]); left out, the wall clock's.
func show_state(position_now: Vector3, rotation_now: Quaternion, on_now: bool, count_now: int, delta: float = -1.0) -> void:
	if body != null and not authoritative:
		var turned := Basis(rotation_now.normalized())
		if _driven:
			_measure_spin(turned, delta)
		body.global_transform = Transform3D(turned, position_now)
	if on_now != on:
		on = on_now
		_show_on()
	count = count_now


## A client's own reading of how fast a driven part is turning (world space, rad/s), from the
## poses it was shown: the spin itself is the server's and is not sent, and a person carried
## round a roundabout on a client is carried at this ([method carry]).
var _shown_spin: Vector3 = Vector3.ZERO
var _shown_basis: Basis = Basis.IDENTITY
var _shown_usec: int = -1


func _measure_spin(turned: Basis, delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _shown_usec < 0:
		# The first pose: nothing to measure against yet.
		_shown_usec = now
		_shown_basis = turned
		return
	var dt := delta if delta >= 0.0 else float(now - _shown_usec) / 1000000.0
	# The same pose twice in one frame (a state, then its interpolation) measures nothing.
	if dt < 0.0005:
		return
	_shown_usec = now
	var before := _shown_basis
	_shown_basis = turned
	if dt > 0.5:
		_shown_spin = Vector3.ZERO
		return
	var change := (turned * before.inverse()).get_rotation_quaternion()
	var angle := change.get_angle()
	var w := Vector3.ZERO
	if angle > 0.00001:
		if angle > PI:
			angle -= TAU
		w = change.get_axis().normalized() * angle / dt
	# Halfway to each new reading: a frame's jitter in the interpolation is not a lurch.
	_shown_spin = _shown_spin.lerp(w, 0.5)


## How fast the moving part's surface moves at [param point] (world space): what a person
## standing on a roundabout is carried at. Zero for a toy that does not turn. On a client it is
## measured from the poses shown.
func surface_velocity(point: Vector3) -> Vector3:
	if body == null or not _driven:
		return Vector3.ZERO
	return _world_spin().cross(point - _pivot_global())


func _world_spin() -> Vector3:
	return global_basis * _spin if authoritative else _shown_spin


## Where a person standing at [param feet] on this roundabout is carried in [param delta]
## seconds, and how far round they turn: `{offset, yaw}`, or empty when it is not a roundabout
## turning under them. A rotation about the hub, not the rim's speed along a tangent, which
## would walk a rider outwards a little every tick until they fell off. Only the roundabout: a
## see-saw's or a platform's tilt is followed by the motor's own ground snap.
func carry(feet: Vector3, delta: float) -> Dictionary:
	if kind != &"spinner" or body == null or delta <= 0.0:
		return {}
	var spin := _world_spin().y
	if absf(spin) < 0.01:
		return {}
	var hub := body.global_position
	var local := feet - hub
	if Vector2(local.x, local.z).length() > _size.x * 0.5 + 0.1 or absf(local.y) > 0.3:
		return {}
	var turn := spin * delta
	var moved := local.rotated(Vector3.UP, turn)
	return {"offset": Vector3(moved.x - local.x, 0.0, moved.z - local.z), "yaw": turn}


## Every frame (or tick) on an end that draws: the knock when the moving part stops short, and
## the press when the use count moved. [param delta] is the time since the last call.
func sense(delta: float) -> void:
	if count != _heard_count:
		_heard_count = count
		var id: StringName = def.get("sound_use", &"")
		if id != &"":
			sound.emit(id, global_position + Vector3(0, _size.y * 0.6, 0), 1.0)
		_play_flourish()
	if body == null or delta <= 0.0:
		return
	_sound_wait -= delta
	var at := body.to_global(_sense_local)
	if _last_sense == Vector3.INF:
		_last_sense = at
		return
	var velocity := (at - _last_sense) / delta
	_last_sense = at
	var change := (velocity - _last_velocity).length()
	var before := _last_velocity.length()
	_last_velocity = velocity
	var id_hit: StringName = def.get("sound_hit", &"")
	if id_hit == &"" or _sound_wait > 0.0:
		return
	# A turn as sharp as a bounce, from a part that was moving: a knock. Gravity alone changes a
	# falling ball's speed by a third of a metre a tick, far under this.
	if change > 1.6 and before > 0.9:
		_sound_wait = 0.12
		sound.emit(id_hit, at, clampf(change / 8.0, 0.15, 1.0))


func _show_on() -> void:
	if _cap != null:
		_cap.material_override = _mat(2 if on else 1, 0.3)
	if _bulb != null:
		_bulb.material_override = DotPropToyLook.material(_colour(1), 0.3, 2.5 if on else 0.0)
	if _light != null:
		_light.visible = on
	if _jets != null:
		_jets.emitting = on
	if _water != null:
		_water.visible = true


func _play_flourish() -> void:
	if _flourish == null or not is_inside_tree():
		return
	var tween := create_tween()
	match kind:
		&"bouncer":
			tween.tween_property(_flourish, ^"position:y", _size.y - 0.22, 0.08)
			tween.tween_property(_flourish, ^"position:y", _size.y - 0.02, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		&"bell":
			tween.tween_property(_flourish, ^"rotation:x", 0.5, 0.15)
			tween.tween_property(_flourish, ^"rotation:x", 0.0, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_:
			var start := _flourish.scale
			tween.tween_property(_flourish, ^"scale", start * 1.15, 0.08)
			tween.tween_property(_flourish, ^"scale", start, 0.3)


func describe() -> Dictionary:
	return {
		"index": index, "id": String(def.get("id", "")), "kind": String(kind),
		"at": state_transform().origin.snapped(Vector3.ONE * 0.01), "awake": awake(),
		"on": on, "count": count,
	}

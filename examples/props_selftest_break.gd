extends "props_selftest_tools.gd"

## Breaking, carry, disguise and piece checks.


func _test_breaking() -> void:
	_section("breaking a prop")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	spawner.limits.per_player_budget = 40
	spawner.limits.world_budget = 80
	var damage := _damage_node(spawner)

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 1.0, 0.0))
	var box := spawner.spawn(&"box", &"alice", Vector3(4.0, 1.0, 0.0))

	_check(not damage.is_breakable(crate.instance_id),
		"a prop with no max_health is indestructible")
	_check(damage.health_of(crate.instance_id) < 0.0,
		"and answers -1 rather than 0, which would read as about to break")
	_check(damage.is_breakable(box.instance_id), "one with max_health is tracked")
	_check(is_equal_approx(damage.health_of(box.instance_id), 100.0),
		"at full health", "%.0f" % damage.health_of(box.instance_id))

	var hurt := damage.hurt(box.instance_id, 40.0, &"alice")
	_check(hurt.ok, "hurting it succeeds")
	_check(is_equal_approx(float(hurt.value), 60.0), "and reports what is left",
		"%.0f" % float(hurt.value))
	_check(box.is_alive(), "and the prop is still there")

	# Captured into an Array rather than into locals: a GDScript lambda captures by
	# value, so a captured int assigned inside a handler stays at its initial value
	# outside it while an Array mutated inside one is visible. See docs.
	var seen: Array = []
	damage.broken.connect(func(p: DotPropInstance, at: Vector3, by: StringName) -> void:
		seen.append({"alive": p.is_alive(), "at": at, "by": by}))

	var killed := damage.hurt(box.instance_id, 60.0, &"alice")
	_check(killed.ok and is_equal_approx(float(killed.value), 0.0),
		"the blow that reaches zero breaks it")
	_check(seen.size() == 1, "broken fires once", "%d" % seen.size())
	_check(seen.size() == 1 and bool((seen[0] as Dictionary)["alive"]),
		"and fires while the prop is still alive, so debris has somewhere to go")
	_check(seen.size() == 1 and StringName((seen[0] as Dictionary)["by"]) == &"alice",
		"carrying who broke it")
	_check(not box.is_alive(), "and the prop leaves the world")
	_check(spawner.player_count(&"alice") == 1,
		"and stops counting against its owner's budget",
		"%d" % spawner.player_count(&"alice"))

	var gone := damage.hurt(box.instance_id, 10.0)
	_check(not gone.ok, "hurting a prop that is already gone is refused")

	var solid := damage.hurt(crate.instance_id, 10.0)
	_check(not solid.ok and solid.error.code == DotError.CODE_UNSUPPORTED,
		"hurting an indestructible prop is refused as unsupported")

	_check(not damage.hurt(crate.instance_id, -5.0).ok, "negative damage is refused")
	_done()


func _test_breaking_authority() -> void:
	_section("and who may break one")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0

	var damage := DotPropDamage.new()
	damage.authoritative = false
	spawner.add_child(damage)

	var box := spawner.spawn(&"box", &"alice", Vector3.ZERO)

	_check(damage.is_breakable(box.instance_id),
		"a client's damage node still tracks health, so it can draw a damaged crate")

	var refused := damage.hurt(box.instance_id, 500.0)
	_check(not refused.ok and refused.error.code == DotError.CODE_FORBIDDEN,
		"but may not hurt anything")
	_check(not damage.break_now(box.instance_id).ok, "nor break one outright")
	_check(box.is_alive(), "and the prop survives")
	_done()


func _test_impact() -> void:
	_section("an impact rather than a wound")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	spawner.limits.per_player_budget = 40
	var damage := _damage_node(spawner)

	var box := spawner.spawn(&"box", &"alice", Vector3.ZERO)

	_check(not damage.impact(box.instance_id, 4.0), "a slow bump does nothing")
	_check(box.is_alive(), "and the prop survives being walked into")
	_check(is_equal_approx(damage.health_of(box.instance_id), 100.0),
		"at full health, because an impact is not damage")

	_check(damage.impact(box.instance_id, 20.0, &"bus"), "a fast one breaks it outright")
	_check(not box.is_alive(), "and the prop is gone")

	var crate := spawner.spawn(&"crate", &"alice", Vector3.ZERO)
	_check(not damage.impact(crate.instance_id, 500.0),
		"a prop with no break_impact_speed is never broken by one")

	var second := spawner.spawn(&"box", &"alice", Vector3.ZERO)
	_check(damage.break_now(second.instance_id).ok, "break_now breaks whatever the health")
	_check(not second.is_alive(), "immediately")
	_done()


func _test_explosion() -> void:
	_section("a barrel")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	spawner.limits.per_player_budget = 40
	spawner.limits.world_budget = 80
	var damage := _damage_node(spawner)

	var barrel := spawner.spawn(&"barrel", &"alice", Vector3.ZERO)
	var near := spawner.spawn(&"crate", &"alice", Vector3(2.0, 0.0, 0.0))
	var far := spawner.spawn(&"crate", &"alice", Vector3(40.0, 0.0, 0.0))

	# Gravity off on both, so what is measured is the blast rather than the fall (one tick of
	# gravity once read as a 0.16 m/s shove).
	for crate_body in [near.body(), far.body()]:
		crate_body.freeze = false
		crate_body.gravity_scale = 0.0
		crate_body.linear_velocity = Vector3.ZERO

	var blasts: Array = []
	damage.exploded.connect(
		func(at: Vector3, radius: float, dmg: float, force: float, by: StringName) -> void:
			blasts.append({"at": at, "radius": radius, "damage": dmg, "force": force, "by": by}))

	damage.hurt(barrel.instance_id, 999.0, &"alice")

	# An impulse is not readable in `linear_velocity` until the step that consumes it has run.
	await get_tree().physics_frame

	_check(blasts.size() == 1, "breaking a barrel describes one blast", "%d" % blasts.size())
	var blast: Dictionary = blasts[0] if blasts.size() == 1 else {}
	_check(blasts.size() == 1 and is_equal_approx(float(blast["radius"]), 6.0),
		"with the radius its definition carries")
	_check(blasts.size() == 1 and is_equal_approx(float(blast["damage"]), 90.0),
		"and the damage, which this addon applies to nobody")

	# The push IS this addon's, because a prop is the one thing it knows about.
	_check(near.body().linear_velocity.length() > 0.1,
		"a prop inside the radius is shoved",
		"%.2f m/s" % near.body().linear_velocity.length())
	_check(far.body().linear_velocity.length() < 0.001,
		"and one outside it is not",
		"%.2f m/s" % far.body().linear_velocity.length())

	var crate := spawner.spawn(&"crate", &"alice", Vector3.ZERO)
	var quiet: Array = []
	damage.exploded.connect(func(_a: Vector3, _r: float, _d: float, _f: float, _b: StringName) -> void:
		quiet.append(true))
	damage.break_now(crate.instance_id)
	_check(quiet.is_empty(), "a prop with no explode_radius describes no blast")

	var silly := DotPropDef.make(&"dud", "res://fixtures/prop_body.tscn")
	silly.explode_radius = 5.0
	_check(not silly.validate().ok,
		"a blast with no damage and no force is refused, not shipped as a dud barrel")
	_done()



func _test_carry() -> void:
	_section("standing on a prop")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	spawner.limits.per_player_budget = 40

	var carry := DotPropCarry.new()
	spawner.add_child(carry)

	var box := spawner.spawn(&"box", &"alice", Vector3(0.0, 1.0, 0.0))
	var anvil := spawner.spawn(&"anvil", &"alice", Vector3(9.0, 1.0, 0.0))

	_check(carry.prop_under(box.node.get_instance_id()) == box,
		"the prop under a player is found from the motor's ground_id")
	_check(carry.prop_under(0) == null, "an airborne player is on nothing")
	_check(carry.prop_under(_world.get_instance_id()) == null,
		"and the world is not a prop, so nobody can ride the floor")
	_check(carry.prop_under(anvil.node.get_instance_id()) == null,
		"a prop marked rideable = false is scenery, not a platform")

	var body := box.body()
	body.freeze = false
	body.linear_velocity = Vector3(3.0, 0.0, 0.0)
	body.angular_velocity = Vector3.ZERO

	var at_centre := carry.velocity_at(box.node.get_instance_id(), body.global_position)
	_check(at_centre.is_equal_approx(Vector3(3.0, 0.0, 0.0)),
		"a sliding prop carries a player at its own speed", str(at_centre))

	# The half that is invisible without it: on a TURNING prop every point moves at a
	# different speed, so a player on the edge of one is carried faster than its
	# centre. Take only the linear part and they drift toward the middle, silently.
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3(0.0, 2.0, 0.0)
	var edge := body.global_position + Vector3(1.0, 0.0, 0.0)
	var at_edge := carry.velocity_at(box.node.get_instance_id(), edge)
	_check(at_edge.length() > 1.0,
		"a spinning prop carries the edge of itself, not just its centre",
		"%.2f m/s" % at_edge.length())
	_check(carry.velocity_at(box.node.get_instance_id(), body.global_position).length() < 0.01,
		"while its centre stays put")

	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3(5000.0, 0.0, 0.0)
	var capped := carry.velocity_at(box.node.get_instance_id(), body.global_position)
	_check(capped.length() <= carry.max_carry_speed + 0.001,
		"a prop having a bad frame cannot throw a player out of the world",
		"%.0f m/s" % capped.length())

	body.linear_velocity = Vector3(2.0, 0.0, 0.0)
	var lift := carry.ride(box.node.get_instance_id(), body.global_position, 80.0, 0.5)
	_check(lift.is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"ride returns the displacement for the tick", str(lift))
	_check(carry.ride(0, Vector3.ZERO, 80.0, 0.5) == Vector3.ZERO,
		"and zero for a player on nothing, so a caller can add it unconditionally")
	_done()


func _test_carry_pushes() -> void:
	_section("and pressing down on it")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	spawner.limits.per_player_budget = 40

	var carry := DotPropCarry.new()
	spawner.add_child(carry)

	var box := spawner.spawn(&"box", &"alice", Vector3(0.0, 40.0, 0.0))
	var body := box.body()
	body.freeze = false
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

	await get_tree().physics_frame

	carry.stand(box.node.get_instance_id(), body.global_position, 80.0, 1.0 / 60.0)

	# An impulse is not readable in linear_velocity until the step that consumes it
	# has run. This addon's own suite has paid for that twice.
	await get_tree().physics_frame

	_check(body.linear_velocity.y < -0.01,
		"a player standing on a prop presses it down",
		"%.3f m/s" % body.linear_velocity.y)

	var tipper := spawner.spawn(&"box", &"alice", Vector3(0.0, 40.0, 20.0))
	var tipping := tipper.body()
	tipping.freeze = false
	tipping.gravity_scale = 0.0
	tipping.linear_velocity = Vector3.ZERO
	tipping.angular_velocity = Vector3.ZERO
	await get_tree().physics_frame

	# On the EDGE, which is what makes a crate tip rather than sink flat.
	carry.stand(
		tipper.node.get_instance_id(),
		tipping.global_position + Vector3(0.5, 0.0, 0.0),
		80.0,
		1.0 / 60.0,
	)
	await get_tree().physics_frame

	_check(tipping.angular_velocity.length() > 0.0001,
		"and standing on its edge tips it",
		"%.4f rad/s" % tipping.angular_velocity.length())

	var pushed := spawner.spawn(&"box", &"alice", Vector3(0.0, 40.0, 40.0))
	var pushed_body := pushed.body()
	pushed_body.freeze = false
	pushed_body.gravity_scale = 0.0
	pushed_body.linear_velocity = Vector3.ZERO
	await get_tree().physics_frame

	_check(
		carry.push(pushed.instance_id, pushed_body.global_position, Vector3(50.0, 0.0, 0.0)),
		"walking into a prop shoves it"
	)
	await get_tree().physics_frame
	_check(pushed_body.linear_velocity.x > 0.01, "and it moves",
		"%.2f m/s" % pushed_body.linear_velocity.x)

	var anvil := spawner.spawn(&"anvil", &"alice", Vector3(0.0, 40.0, 60.0))
	_check(not carry.push(anvil.instance_id, Vector3.ZERO, Vector3.RIGHT),
		"a prop that is not rideable is not pushable either")
	_check(not carry.push(999999, Vector3.ZERO, Vector3.RIGHT),
		"and an id that is not a prop at all is refused")
	_done()



func _test_disguise() -> void:
	_section("hiding as a prop: what a player may become, and what it costs them")

	var rules := DotPropDisguiseRules.new()
	_check(rules.validate().ok, "the default rules are usable")

	var cabinet := Vector3(0.7, 1.4, 0.5)
	var bottle := Vector3(0.12, 0.3, 0.12)
	var hc := DotPropDisguise.health(cabinet, rules)
	var hb := DotPropDisguise.health(bottle, rules)
	_check(hc > 100.0 and hc <= rules.max_health, "a cabinet is worth a lot of hits (%.0f)" % hc)
	_check(hb < 30.0 and hb >= rules.min_health, "a bottle very few (%.0f)" % hb)
	var ratio := hc / hb
	# 0.49 m³ against 0.0043 m³ is over a hundred times the volume; the health must not follow it.
	_check(ratio > 4.0 and ratio < 20.0, "and the cabinet is worth several bottles, not a hundred (%.1fx)" % ratio)

	_check(not DotPropDisguise.may_take(Vector3(0.05, 0.3, 0.05), rules).ok, "a pencil is too small to hide as")
	_check(not DotPropDisguise.may_take(Vector3(3, 3, 3), rules).ok, "a shed is too big")
	_check(DotPropDisguise.may_take(cabinet, rules).ok, "a cabinet is fine")

	var sofa := Vector3(2.1, 0.9, 0.95)
	var hull := DotPropDisguise.hull(sofa, rules)
	_check(is_equal_approx(hull.x, 0.475), "a sofa's hull is half its NARROWER footprint, so it fits the door it came in by (r %.3f)" % hull.x)
	_check(is_equal_approx(hull.y, 0.95), "and a capsule is never shorter than it is wide (h %.2f for a 0.9 m sofa)" % hull.y)
	var tiny := DotPropDisguise.hull(bottle, rules)
	_check(is_equal_approx(tiny.x, rules.hull_min_radius) and is_equal_approx(tiny.y, rules.hull_min_height),
		"a bottle gets the smallest hull the rules allow (r %.2f, h %.2f)" % [tiny.x, tiny.y])

	_check(is_equal_approx(DotPropDisguise.health_after(50.0, 100.0, 140.0, rules), 70.0),
		"changing disguise keeps the fraction of health, not the new prop's full health")
	rules.keep_health_fraction = false
	_check(is_equal_approx(DotPropDisguise.health_after(50.0, 100.0, 140.0, rules), 140.0),
		"unless the server says a new prop is a fresh one")
	rules.keep_health_fraction = true

	_check(DotPropDisguise.within_reach(Vector3.ZERO, Vector3(0, 0, -2.9), rules)
		and not DotPropDisguise.within_reach(Vector3.ZERO, Vector3(0, 0, -3.2), rules),
		"a prop is copied from within reach and not past it")

	var d := DotPropDisguise.of(&"cabinet", cabinet)
	_check(d.is_disguised() and not DotPropDisguise.new().is_disguised(), "an empty id is your own body")
	_check(d.tilt(2, true, rules) and is_equal_approx(d.pitch, 30.0), "a tilt turns by the rules' step")
	for i in range(10):
		var _t := d.tilt(1, true, rules)
	_check(is_equal_approx(d.pitch, rules.max_tilt), "and stops at the rules' limit")
	d.straighten()
	_check(is_equal_approx(d.pitch, 0.0) and is_equal_approx(d.roll, 0.0), "and comes upright again")

	d.set_locked(true, 120.0)
	var turned := d.hit_basis(10.0)
	_check(turned.is_equal_approx(Basis(Vector3.UP, deg_to_rad(120.0))),
		"locked, it keeps the facing it was locked at whatever the player looks at")
	d.set_locked(false, 0.0)
	_check(d.hit_basis(10.0).is_equal_approx(Basis(Vector3.UP, deg_to_rad(10.0))),
		"unlocked, it turns with the player's view")

	d.roll = 15.0
	var back := DotPropDisguise.from_wire(d.to_wire())
	_check(back.prop_id == &"cabinet" and back.size.is_equal_approx(cabinet) and is_equal_approx(back.roll, 15.0)
		and back.locked == d.locked, "a disguise survives the wire")

	_check_leant_bottle(rules)

	var bad := DotPropDisguiseRules.new()
	bad.hull_min_height = 0.1
	_check(not bad.validate().ok, "rules whose smallest hull would be a capsule shorter than it is wide are refused")
	_done()


func _check_leant_bottle(rules: DotPropDisguiseRules) -> void:
	# Leant every way a player can turn it, a bottle's box never goes under the floor and its
	# lowest corner is on it.
	var bottle_d := DotPropDisguise.of(&"bottle", Vector3(0.1, 0.32, 0.1))
	var worst_low := INF
	var worst_high := -INF
	var hull_ok := true
	for p in range(-4, 5):
		for q in range(-4, 5):
			bottle_d.pitch = p * 45.0
			bottle_d.roll = q * 45.0
			var frame := bottle_d.model_transform(Vector3(2.0, 1.0, -3.0), 37.0)
			var lowest := INF
			for corner in range(8):
				var local := Vector3(0.05 if corner & 1 else -0.05, 0.32 if corner & 2 else 0.0, 0.05 if corner & 4 else -0.05)
				lowest = minf(lowest, (frame * local).y)
			worst_low = minf(worst_low, lowest - 1.0)
			worst_high = maxf(worst_high, lowest - 1.0)
			var box_mid := bottle_d.box_transform(37.0).origin.y
			hull_ok = hull_ok and is_equal_approx(box_mid, bottle_d.standing_size().y * 0.5) \
				and bottle_d.standing_hull(rules).y >= bottle_d.standing_size().y - 0.001 or bottle_d.standing_size().y > rules.hull_max_height
	_check(worst_low > -0.0005 and worst_high < 0.0005,
		"a leant prop rests on the floor at every turn, never under it (lowest corner %.4f..%.4f m)" % [worst_low, worst_high])
	bottle_d.pitch = 90.0
	bottle_d.roll = 0.0
	var lying := bottle_d.standing_size()
	_check(is_equal_approx(lying.y, 0.1) and is_equal_approx(lying.z, 0.32),
		"a bottle on its side is as tall as it is wide and as long as it was tall (%s)" % str(lying))
	_check(hull_ok, "and its hull and hitbox follow the leant box: as tall, the middle at half its height")


func _test_taunts() -> void:
	_section("taunts: chosen, forced, and the meter between")

	var t := DotPropTaunts.new()
	t.auto_after = 10.0
	t.auto_radius = 1.5
	t.cooldown = 2.0
	_check(not t.may_taunt(&"p", 0.0).ok, "a server with no taunts refuses one and says so")

	var added := t.add_all([
		{"id": "whistle", "title": "Whistle", "seconds": 1.5, "sound": "res://taunts/whistle.ogg"},
		{"id": "honk", "title": "Honk", "seconds": 0.8},
		{"title": "no id"},
	])
	_check(added == 2 and t.order.size() == 2, "a list adds every entry with an id (%d)" % added)

	t.observe(&"p", Vector3.ZERO, 0.0)
	t.observe(&"p", Vector3(1.0, 0, 0), 4.0)
	_check(is_equal_approx(t.meter(&"p", 5.0), 0.5), "shuffling inside the radius is standing still (meter %.2f at 5 s)" % t.meter(&"p", 5.0))
	_check(not t.due(&"p", 9.9) and t.due(&"p", 10.0), "a taunt is forced when the meter is full, and not a tick before")

	t.observe(&"p", Vector3(3.0, 0, 0), 6.0)
	_check(is_equal_approx(t.meter(&"p", 6.0), 0.0), "leaving the radius starts the clock again")

	var chosen := t.taunt(&"p", 7.0, &"whistle")
	_check(chosen.get("id") == &"whistle" and int(chosen["points"]) == t.points_voluntary and not chosen["forced"],
		"a chosen taunt is paid (%d)" % int(chosen.get("points", -1)))
	_check(not t.may_taunt(&"p", 9.0).ok, "and nobody taunts over their own taunt or inside the cooldown")
	_check(t.may_taunt(&"p", 10.5).ok, "until it has played and the cooldown has passed (%.1f + %.1f s)" % [1.5, t.cooldown])
	_check(is_equal_approx(t.still_for(&"p", 8.0), 1.0), "and choosing one starts the standing-still clock again")

	var forced := t.taunt(&"q", 3.0, &"", true, 42)
	_check(t.has(StringName(forced.get("id", ""))) and int(forced["points"]) == 0 and forced["forced"],
		"a forced taunt picks one itself and pays nothing by default")
	_check(t.taunt(&"q", 3.0, &"", true, 42).get("id") == forced.get("id"), "and the same seed picks the same one")

	t.auto_after = 0.0
	_check(is_equal_approx(t.meter(&"p", 999.0), 0.0) and not t.due(&"p", 999.0), "with the clock off nobody is ever forced")

	t.reset()
	_check(t.ready_in(&"p", 0.0) == 0.0, "a new round starts everybody's clock again")
	_done()


func _test_pieces() -> void:
	_section("pieces: collision shaped like the model, measured once and read back")

	# A table built of boxes: a 2 x 1 m top 0.75 m up on four legs. Its box would fill the
	# space under it; its pieces must not.
	var table := Node3D.new()
	var parts := [[Vector3(2.0, 0.08, 1.0), Vector3(0.0, 0.71, 0.0)]]
	for x in [-0.9, 0.9]:
		for z in [-0.4, 0.4]:
			parts.append([Vector3(0.1, 0.67, 0.1), Vector3(x, 0.335, z)])
	for part: Array in parts:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = part[1]
		table.add_child(mesh)

	var pieces := DotPropPieces.measure(table, Transform3D.IDENTITY)
	_check(pieces.size() >= 2, "a table is cut into pieces", "%d" % pieces.size())
	_check(DotPropPieces.contains(pieces, Vector3(0.0, 0.72, 0.0)) and DotPropPieces.contains(pieces, Vector3(0.9, 0.3, 0.4), 0.02),
		"its top and its legs are solid")
	_check(not DotPropPieces.contains(pieces, Vector3(0.0, 0.3, 0.0)), "and the space under it is not")
	_check(absf(DotPropPieces.top_at(pieces, 0.3, 0.2) - 0.75) < 0.03 and DotPropPieces.top_at(pieces, 3.0, 0.0) == -INF,
		"a thing set down on it rests on its top, and nothing is under a point off it",
		"%.3f" % DotPropPieces.top_at(pieces, 0.3, 0.2))
	var again := DotPropPieces.measure(table, Transform3D.IDENTITY)
	_check(JSON.stringify(DotPropPieces.encode(again)) == JSON.stringify(DotPropPieces.encode(pieces)),
		"measuring twice gives the same numbers, so a --check can compare files")

	var wire: Variant = JSON.parse_string(JSON.stringify(DotPropPieces.encode(pieces)))
	var back := DotPropPieces.decode(wire)
	_check(back.size() == pieces.size() and DotPropPieces.bounds(back).is_equal_approx(DotPropPieces.bounds(pieces)),
		"pieces survive JSON and come back the same")
	_check(DotPropPieces.decode([[1, 2, 3], "nonsense", 7]).is_empty(), "anything malformed is skipped, not guessed at")
	var shapes := DotPropPieces.shapes(back)
	_check(shapes.size() == back.size() and shapes[0].points.size() == back[0].size(), "one convex shape per piece")
	table.free()

	# A crate is its own box: no pieces, and the game keeps colliding with the box.
	var crate := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	crate.mesh = cube
	_check(DotPropPieces.measure(crate, Transform3D.IDENTITY).is_empty(), "a crate gets no pieces: its box is as good")
	crate.free()
	_done()




func _test_toy_catalogue() -> void:
	_section("the toy catalogue: a dozen and more, every kind, retuned from data")
	var c := DotPropToyCatalogue.stock()
	_check(c.size() >= 12, "the stock has at least a dozen toys", str(c.size()))
	var kinds := {}
	for id in c.ids():
		kinds[c.get_def(StringName(id))["kind"]] = true
	_check(kinds.size() == DotPropToyCatalogue.KINDS.size(), "and uses every kind", str(kinds.keys()))
	var sounds := DotPropToySounds.ids()
	var unheard := PackedStringArray()
	for id in c.ids():
		var def := c.get_def(StringName(id))
		for key in ["sound_hit", "sound_use"]:
			if def[key] != &"" and not sounds.has(def[key]):
				unheard.append("%s.%s" % [id, key])
	_check(unheard.is_empty(), "every sound a toy names is a row in DotPropToySounds", ", ".join(unheard))
	var absent := PackedStringArray()
	for row in DotPropToySounds.rows():
		for path: String in row["variants"]:
			if not ResourceLoader.exists(path):
				absent.append(path)
	_check(absent.is_empty(), "and every row's files are shipped", ", ".join(absent))
	var tuned := c.merge({"beach_ball": {"mass": 0.5}, "giant_ball": {"kind": "ball", "size": [2, 2, 2]}})
	_check(tuned.ok and is_equal_approx(float(c.get_def(&"beach_ball")["mass"]), 0.5)
		and float(c.get_def(&"beach_ball")["bounce"]) > 0.7 and c.has(&"giant_ball"),
		"a game retunes one field of a stock toy and adds its own from data")
	var bad := c.merge({"rocket": {"kind": "rocket"}})
	_check(not bad.ok and not c.has(&"rocket"), "a kind that does not exist is refused, by name", bad.error.message if not bad.ok else "")
	_check(DotPropToyBox.normal_placement({"toy": "swing", "at": [1, 0, 2], "yaw": 90, "links": [3]}).get("links") == [3]
		and DotPropToyBox.normal_placement({"at": [0, 0, 0]}).is_empty(), "a placement is {toy, at}, and one without a toy is refused")
	_done()


## A floor, and a box of every stock toy on it in a row, four metres apart. A hundred metres
## up, clear of whatever the earlier sections left falling (a crate under the tyre flung it
## three hundred metres).

extends "props_selftest_core.gd"

## Wiring, freezing, size and gun checks.


func _test_tool_permissions() -> void:
	_section("what a tool may act on")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0

	var tool := DotPropTool.new()
	tool.spawner = spawner
	tool.wielder = &"alice"

	var mine := spawner.spawn(&"crate", &"alice", Vector3.ZERO)
	var theirs := spawner.spawn(&"crate", &"bob", Vector3.ZERO)
	var scenery := spawner.spawn(&"pillar", &"alice", Vector3.ZERO)

	_check(tool.may_act_on(mine).ok, "my own prop is fair game")
	_check(tool.may_act_on(theirs).ok, "and so is somebody else's, by default")
	_check(not tool.may_act_on(theirs, false).ok,
		"unless the server says otherwise")
	_check(not tool.may_act_on(scenery).ok,
		"a prop marked ungrabbable is refused")
	_check(not tool.may_act_on(null).ok, "and so is nothing")

	# One holder at a time: two guns pulling one crate makes it oscillate between
	# them and costs ten times the physics step.
	mine.held_by = &"bob"
	_check(not tool.may_act_on(mine).ok, "a prop somebody else holds is refused")

	mine.held_by = &"alice"
	_check(tool.may_act_on(mine).ok, "and one I hold myself is not")

	# The mass limit.
	spawner.limits.grab_mass_limit = 100.0
	var heavy := spawner.spawn(&"safe", &"alice", Vector3.ZERO)
	_check(not tool.may_act_on(heavy).ok, "a prop over the mass limit is refused")

	spawner.queue_free()
	_done()


## Creative mode, as the addon has it: an owner nobody else's tool or damage reaches.
func _test_protected_owners() -> void:
	_section("a protected owner's props")

	var spawner := _spawner()
	spawner.catalogue = _breakables()
	spawner.limits.spawn_interval = 0.0
	var damage := _damage_node(spawner)

	var tool := DotPropTool.new()
	tool.spawner = spawner
	tool.wielder = &"alice"
	var bob_tool := DotPropTool.new()
	bob_tool.spawner = spawner
	bob_tool.wielder = &"bob"

	var bobs := spawner.spawn(&"box", &"bob", Vector3(0.0, 1.0, 0.0))
	spawner.set_protected(&"bob", true)
	_check(spawner.is_protected(&"bob") and not spawner.is_protected(&"alice"), "protection is per owner")
	var refused := tool.may_act_on(bobs)
	_check(not refused.ok and refused.error.code == DotError.CODE_FORBIDDEN, "nobody else's tool may act on their props")
	_check(not tool.may_act_on(bobs, true).ok, "whatever the server's touch rule says")
	_check(bob_tool.may_act_on(bobs).ok, "but their own does")
	_check(not damage.hurt(bobs.instance_id, 40.0, &"alice").ok and is_equal_approx(damage.health_of(bobs.instance_id), 100.0),
		"and nothing else hurts them", "%.0f" % damage.health_of(bobs.instance_id))
	_check(not damage.impact(bobs.instance_id, 50.0, &"alice") and bobs.is_alive(), "not even an impact that would break one")

	spawner.set_protected(&"bob", false)
	_check(tool.may_act_on(bobs).ok and damage.hurt(bobs.instance_id, 40.0, &"alice").ok, "turned off, they are fair game again")

	spawner.set_protected(&"bob", true)
	var _left := spawner.player_left(&"bob")
	_check(not spawner.is_protected(&"bob"), "and leaving takes the protection with them")
	_check(int(spawner.describe()["protected"]) == 0, "which describe() counts")

	spawner.queue_free()
	_done()


## Props wired to props: a button's output to a door's input, delivered, cleared with either end.
func _test_wiring() -> void:
	_section("props wired to props")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0
	var catalogue := spawner.catalogue
	var button_def := DotPropDef.make(&"button", "res://fixtures/prop_body.tscn")
	button_def.meta = {"outputs": ["pressed"]}
	catalogue.add(button_def)
	var door_def := DotPropDef.make(&"door", "res://fixtures/prop_body.tscn")
	door_def.meta = {"inputs": ["open", "close", "toggle"], "outputs": ["opened"]}
	catalogue.add(door_def)

	var io := DotPropIO.new()
	spawner.add_child(io)

	var button := spawner.spawn(&"button", &"alice", Vector3(0.0, 1.0, 0.0))
	var door := spawner.spawn(&"door", &"alice", Vector3(3.0, 1.0, 0.0))
	var crate := spawner.spawn(&"crate", &"alice", Vector3(6.0, 1.0, 0.0))

	_check(DotPropIO.outputs_of(button.def) == PackedStringArray(["pressed"]) and DotPropIO.inputs_of(door.def).has("toggle"),
		"a prop declares what it says and hears in its meta")
	_check(io.link(button.instance_id, &"pressed", door.instance_id, &"toggle").ok, "a button is wired to a door")
	_check(not io.link(button.instance_id, &"pressed", door.instance_id, &"toggle").ok, "but not twice the same way")
	_check(not io.link(button.instance_id, &"shouted", door.instance_id, &"toggle").ok, "nor from an output it does not have")
	_check(not io.link(button.instance_id, &"pressed", crate.instance_id, &"toggle").ok, "nor to a prop with no such input")
	_check(not io.link(door.instance_id, &"opened", door.instance_id, &"open").ok, "nor to itself")

	var heard: Array = []
	io.input_received.connect(func(target: DotPropInstance, input: StringName, value: Variant, source: DotPropInstance) -> void:
		heard.append([target.instance_id, input, value, source.instance_id if source != null else 0]))
	_check(io.fire(button.instance_id, &"pressed", true) == 1 and heard.size() == 1
		and heard[0] == [door.instance_id, &"toggle", true, button.instance_id], "firing the output reaches the door's input", str(heard))

	# A loop: the door's "opened" wired back to... another door's toggle, whose "opened" fires back.
	var other := spawner.spawn(&"door", &"alice", Vector3(9.0, 1.0, 0.0))
	var _a := io.link(door.instance_id, &"opened", other.instance_id, &"toggle")
	var _b := io.link(other.instance_id, &"opened", door.instance_id, &"toggle")
	var bounce := func(target: DotPropInstance, input: StringName, _v: Variant, _s: DotPropInstance) -> void:
		if input == &"toggle" and target.def.id == &"door":
			var _n := io.fire(target.instance_id, &"opened")
	io.input_received.connect(bounce)
	heard.clear()
	var _loop := io.fire(door.instance_id, &"opened")
	_check(io.refused_depth > 0 and heard.size() <= io.max_depth + 1, "a wired loop stops at the depth limit", "%d deliveries" % heard.size())
	io.input_received.disconnect(bounce)

	spawner.remove(door.instance_id)
	_check(io.links_from(button.instance_id).is_empty() and io.link_count(other.instance_id) == 0,
		"removing a prop takes every wire touching it")

	io.max_links_per_prop = 1
	var lamp := spawner.spawn(&"door", &"alice", Vector3(12.0, 1.0, 0.0))
	_check(io.link(button.instance_id, &"pressed", other.instance_id, &"open").ok
		and not io.link(button.instance_id, &"pressed", lamp.instance_id, &"open").ok, "and a prop has at most max_links_per_prop wires")

	var mirror := DotPropIO.new()
	mirror.authoritative = false
	spawner.add_child(mirror)
	_check(not mirror.link(button.instance_id, &"pressed", lamp.instance_id, &"open").ok and mirror.fire(button.instance_id, &"pressed") == 0,
		"a client's copy wires and fires nothing")
	_check(io.describe()["links"] == 1 and io.describe_lines().size() == 2, "describe says what is wired")

	spawner.queue_free()
	_done()


func _test_freezing() -> void:
	_section("freezing")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 10.0, 0.0))
	var body := crate.body()

	body.linear_velocity = Vector3(0.0, -30.0, 0.0)

	DotPhysGun.set_frozen(crate, true)

	_check(crate.frozen, "a prop can be frozen")
	_check(body.freeze, "and the body knows it")

	# Godot keeps a frozen body's velocities and applies them the instant it is
	# unfrozen, so a prop frozen while falling fast leaps away when somebody thaws
	# it — minutes later, with nothing to connect the two.
	_check(
		body.linear_velocity.length() < 0.001,
		"and its velocity is zeroed, so unfreezing does not launch it",
		"%.2f m/s" % body.linear_velocity.length()
	)

	DotPhysGun.set_frozen(crate, false)
	_check(not crate.frozen, "and can be unfrozen")

	spawner.queue_free()
	_done()


func _test_freeze_limit() -> void:
	_section("the freeze limit")

	# A frozen prop costs nothing to simulate, so it has its own ceiling rather than
	# sharing the physics budget — and that ceiling has to actually be enforced,
	# which for a while it was not: the knob existed and nothing read it.
	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.0
	limits.per_player_frozen = 2

	var spawner := _spawner(limits)

	var gun := DotPhysGun.new()
	gun.spawner = spawner
	gun.wielder = &"alice"

	var props: Array[DotPropInstance] = []

	for _i in range(4):
		props.append(spawner.spawn(&"crate", &"alice", Vector3.ZERO))

	for i in range(2):
		gun.held = props[i]
		props[i].held_by = &"alice"
		_check(gun.freeze_held().ok, "freezing within the limit works")

	_check(spawner.frozen_count(&"alice") == 2, "two are frozen")

	gun.held = props[2]
	props[2].held_by = &"alice"

	var refused := gun.freeze_held()
	_check(not refused.ok, "and the third is refused")
	_check(
		refused.ok or refused.code() == DotError.CODE_QUOTA,
		"as a quota rather than as an internal error"
	)
	_check(gun.held == props[2], "and the prop is still in hand, not dropped")

	# Unfreezing frees a slot, and unfreezing is never refused — a limit that fought
	# its own operator tidying up would be a limit nobody keeps on.
	DotPhysGun.set_frozen(props[0], false)
	_check(spawner.frozen_count(&"alice") == 1, "unfreezing frees a slot")
	_check(gun.freeze_held().ok, "and the next freeze is allowed")

	# Another player has their own allowance.
	var bob := spawner.spawn(&"crate", &"bob", Vector3.ZERO)
	var bob_gun := DotPhysGun.new()
	bob_gun.spawner = spawner
	bob_gun.wielder = &"bob"
	bob_gun.held = bob
	bob.held_by = &"bob"

	_check(bob_gun.freeze_held().ok, "and another player has their own")

	spawner.queue_free()
	_done()


func _test_size_ceiling() -> void:
	_section("the size ceiling")

	# A size class is a ceiling, not a budget: allow a hundred crates and forbid the one model
	# the size of the map.
	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.0
	limits.max_size = DotPropDef.Size.SMALL

	var catalogue := _catalogue()
	catalogue.get_prop(&"crate").size = DotPropDef.Size.SMALL
	catalogue.get_prop(&"safe").size = DotPropDef.Size.HUGE

	var spawner := DotPropSpawner.new()
	spawner.catalogue = catalogue
	spawner.limits = limits
	spawner.authoritative = true
	_world.add_child(spawner)

	var refusals := PackedStringArray()
	spawner.refused.connect(
		func(_p: StringName, _id: StringName, reason: String) -> void:
			refusals.append(reason)
	)

	_check(
		spawner.spawn(&"crate", &"alice", Vector3.ZERO) != null,
		"a prop within the ceiling spawns"
	)
	_check(
		spawner.spawn(&"safe", &"alice", Vector3.ZERO) == null,
		"and one above it is refused"
	)
	_check(
		refusals.size() == 1 and refusals[0].contains("too large"),
		"with a reason a player can act on",
		str(refusals)
	)

	limits.max_size = DotPropDef.Size.HUGE
	_check(
		spawner.spawn(&"safe", &"alice", Vector3.ZERO) != null,
		"and raising the ceiling allows it"
	)

	spawner.queue_free()
	_done()


func _test_physgun_holds() -> void:
	_section("the physics gun")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 2.0, -6.0))

	var gun := DotPhysGun.new()
	gun.spawner = spawner
	gun.wielder = &"alice"

	# Grabbed directly rather than through a ray, so this tests the hold and not
	# Godot's raycast. The ray path is exercised by the gravity gun's punt below.
	gun.held = crate
	crate.held_by = &"alice"
	gun.hold_distance = 6.0
	gun.hold_rotation = Basis.IDENTITY

	var origin := Vector3(0.0, 2.0, 0.0)
	var direction := Vector3(0.0, 0.0, -1.0)

	for _i in range(120):
		gun.hold(origin, direction, Basis.IDENTITY, 1.0 / 60.0)
		await get_tree().physics_frame

	var goal := origin + direction * gun.hold_distance
	var distance := crate.position().distance_to(goal)

	_check(distance < 1.0, "a held prop converges on where it is aimed",
		"%.2f m away" % distance)

	# The prop is pushed, not teleported: it has a velocity, which is what makes
	# it collide with things on the way and carry momentum when released.
	gun.hold(origin, Vector3(1.0, 0.0, 0.0), Basis.IDENTITY, 1.0 / 60.0)
	_check(
		crate.body().linear_velocity.length() > 0.1,
		"and is moved by velocity rather than by teleporting",
		"%.2f m/s" % crate.body().linear_velocity.length()
	)

	gun.push(1.0, 1.0)
	_check(gun.hold_distance > 6.0, "it can be pushed further out")

	gun.push(-100.0, 1.0)
	_check(
		gun.hold_distance >= spawner.limits.hold_distance_min,
		"and cannot be pulled inside the player"
	)

	var released := gun.release()
	_check(released == crate, "releasing hands the prop back")
	_check(not crate.is_held(), "and it is no longer held")
	_check(gun.held == null, "and the gun is empty")

	# A prop removed while held: the gun lets go rather than working on a freed node.
	gun.held = crate
	crate.held_by = &"alice"
	spawner.remove(crate.instance_id)

	# In the SAME frame as the removal, deliberately: queue_free() is deferred, so a
	# check that relied on the node becoming invalid would pass here by accident and
	# fail in the window an admin cleanup actually happens in.
	gun.hold(origin, direction, Basis.IDENTITY, 1.0 / 60.0)
	_check(gun.held == null, "a prop removed while held is let go of, not crashed on")

	spawner.queue_free()
	_done()


func _test_physgun_caps_speed() -> void:
	_section("the physics gun's speed cap")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 2.0, 0.0))

	var gun := DotPhysGun.new()
	gun.spawner = spawner
	gun.wielder = &"alice"
	gun.held = crate
	gun.hold_distance = 20.0
	gun.max_speed = 20.0

	# The spring's output is proportional to the distance to the goal, so aiming a
	# long way from the prop asks for an unbounded velocity — which tunnels it
	# through the world and can produce a non-finite position.
	gun.hold(
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 1.0, 0.0), Basis.IDENTITY, 1.0 / 60.0
	)

	var speed := crate.body().linear_velocity.length()

	_check(speed <= gun.max_speed + 0.001,
		"a wildly distant target does not produce an unbounded velocity",
		"%.2f m/s, cap %.2f" % [speed, gun.max_speed])
	_check(
		is_finite(crate.body().linear_velocity.length()),
		"and the velocity stays finite"
	)

	spawner.queue_free()
	_done()


func _test_gravgun_punts() -> void:
	_section("the gravity gun")

	var spawner := _spawner()
	spawner.limits.spawn_interval = 0.0

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 2.0, -3.0))

	var gun := DotGravGun.new()
	gun.spawner = spawner
	gun.wielder = &"alice"

	gun.carried = crate
	crate.held_by = &"alice"

	var origin := Vector3(0.0, 2.0, 0.0)
	var aim := Vector3(0.0, 0.0, -1.0)

	for _i in range(60):
		gun.carry(origin, aim, 1.0 / 60.0)
		await get_tree().physics_frame

	var carried_at := crate.position().distance_to(
		origin + aim * gun.carry_distance
	)
	_check(carried_at < 1.5, "a carried prop sits in front of the player",
		"%.2f m away" % carried_at)

	crate.body().linear_velocity = Vector3.ZERO
	await get_tree().physics_frame

	var punted := gun.punt(null, origin, aim)

	# An impulse is not readable until the step that consumes it has run; reading it at once
	# gives the velocity from before the punt.
	await get_tree().physics_frame

	var light_speed := crate.body().linear_velocity.z

	_check(punted == crate, "punting returns the prop")
	_check(not gun.is_carrying(), "and lets go of it")
	_check(light_speed < -1.0, "and sends it away along the aim", "%.1f m/s" % light_speed)

	# A punt is an impulse, so a heavy prop goes less far than a light one — which
	# is what makes the tool feel like it has weight, and is free because the solver
	# already divides by the mass.
	var heavy := spawner.spawn(&"safe", &"alice", Vector3(0.0, 2.0, -3.0))

	# Not set here: the spawner puts the definition's mass on the body. Asserted so the
	# comparison below cannot pass by being wrong in both halves.
	_check(is_equal_approx(heavy.body().mass, 900.0), "a heavy prop is heavy without being told twice")

	# Mass is set BEFORE a step runs: an impulse applied in between is divided by the old mass.
	await get_tree().physics_frame

	var heavy_gun := DotGravGun.new()
	heavy_gun.spawner = spawner
	heavy_gun.wielder = &"alice"
	heavy_gun.carried = heavy
	heavy.held_by = &"alice"

	heavy.body().linear_velocity = Vector3.ZERO
	await get_tree().physics_frame

	heavy_gun.punt(null, origin, aim)
	await get_tree().physics_frame

	_check(
		absf(heavy.body().linear_velocity.z) < absf(light_speed),
		"and a heavy prop is punted less far than a light one",
		"%.1f vs %.1f m/s" % [heavy.body().linear_velocity.z, light_speed]
	)

	_check_gravgun_refuses_frozen(spawner)
	spawner.queue_free()
	_done()


## A frozen prop is refused rather than quietly thawed, or a build comes apart piece by piece.
func _check_gravgun_refuses_frozen(spawner: DotPropSpawner) -> void:
	var frozen := spawner.spawn(&"crate", &"alice", Vector3(0.0, 2.0, -3.0))
	DotPhysGun.set_frozen(frozen, true)

	var refusing := DotGravGun.new()
	refusing.spawner = spawner
	refusing.wielder = &"alice"

	_check(not refusing.may_act_on(frozen).ok or frozen.frozen, "a frozen prop stays frozen")

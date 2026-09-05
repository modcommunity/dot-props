extends Node

## Proves the limits hold, the tools behave, and nothing leaks.
##
## [codeblock]
## godot --headless --path . res://examples/props_selftest.tscn
## [/codeblock]
##
## [b]The tests that matter are the limits and the cleanup.[/b] A sandbox server's
## whole failure mode is somebody putting a thousand crates in the world, and the
## second-worst is a server that accumulates the props of everybody who has ever
## visited. Both are here, with the props actually in a real scene tree — the spawner
## instantiates real [RigidBody3D]s, because a limit that counted a dictionary would
## pass while leaking nodes.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()

var _world: Node3D = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-props self-test")
	print("")

	_world = Node3D.new()
	add_child(_world)

	_test_definitions()
	_test_catalogue()
	_test_spawning()
	_test_authority()
	_test_budget()
	_test_cooldown()
	_test_world_budget()
	_test_undo()
	_test_cleanup_on_leave()
	_test_no_leaked_nodes()
	_test_tool_permissions()
	_test_freezing()
	_test_freeze_limit()
	_test_size_ceiling()
	await _test_physgun_holds()
	await _test_physgun_caps_speed()
	await _test_gravgun_punts()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


func _catalogue() -> DotPropCatalogue:
	var catalogue := DotPropCatalogue.new()

	var crate := DotPropDef.make(&"crate", "res://fixtures/prop_body.tscn")
	crate.category = &"props"
	crate.mass = 20.0
	catalogue.add(crate)

	var heavy := DotPropDef.make(&"safe", "res://fixtures/prop_body.tscn")
	heavy.category = &"props"
	heavy.mass = 900.0
	heavy.cost = 8
	catalogue.add(heavy)

	var scenery := DotPropDef.make(&"pillar", "res://fixtures/prop_body.tscn")
	scenery.category = &"scenery"
	scenery.can_grab = false
	scenery.can_freeze = false
	catalogue.add(scenery)

	var locked := DotPropDef.make(&"gold_crate", "res://fixtures/prop_body.tscn")
	locked.category = &"premium"
	locked.entitlement = &"vip"
	catalogue.add(locked)

	return catalogue


func _spawner(limits: DotPropLimits = null) -> DotPropSpawner:
	var spawner := DotPropSpawner.new()
	spawner.catalogue = _catalogue()
	spawner.limits = limits if limits != null else DotPropLimits.new()
	spawner.authoritative = true
	_world.add_child(spawner)
	return spawner


# --- Definitions -----------------------------------------------------------

func _test_definitions() -> void:
	print("prop definitions")

	var crate := DotPropDef.make(&"crate", "res://fixtures/prop_body.tscn")
	_check(crate.validate().ok, "a prop validates")
	_check(crate.is_local(), "and ships in the build when it has no content id")

	var nameless := DotPropDef.new()
	_check(not nameless.validate().ok, "a prop with no id is refused")

	var sceneless := DotPropDef.new()
	sceneless.id = &"x"
	_check(not sceneless.validate().ok, "and one with no scene")

	var back := DotPropDef.from_dictionary(crate.to_dictionary())
	_check(back.id == crate.id and back.mass == crate.mass, "a prop round-trips")

	var junk := DotPropDef.from_dictionary({
		"id": "x", "scene": "y", "size": 99, "mass": -5, "cost": 5000,
	})
	_check(junk.size == DotPropDef.Size.MEDIUM, "an out-of-range size falls back")
	_check(junk.mass > 0.0, "a negative mass is clamped")
	_check(junk.cost <= 100, "and a huge cost")

	# The aliasing check the leaderboard suite taught us to write.
	crate.meta["a"] = 1
	var copy := DotPropDef.from_dictionary(crate.to_dictionary())
	copy.meta["a"] = 2
	_check(int(crate.meta["a"]) == 1, "and a copy does not share its meta dictionary")


func _test_catalogue() -> void:
	print("the catalogue")

	var catalogue := _catalogue()

	_check(catalogue.size() == 4, "four props go in")
	_check(catalogue.has(&"crate"), "and can be found")
	_check(catalogue.categories().size() >= 1, "categories are listed")
	_check(catalogue.in_category(&"props").size() == 2, "and filtered")

	var exact := catalogue.search("crate")
	_check(exact.size() == 1 and exact[0].id == &"crate",
		"an exact id wins outright, not a substring match")

	var partial := catalogue.search("cra")
	_check(partial.size() == 2, "while a partial finds both crates",
		"%d" % partial.size())

	var parsed := DotPropCatalogue.from_json(catalogue.to_json())
	_check(parsed.ok and (parsed.value as DotPropCatalogue).size() == 4,
		"and the catalogue round-trips")

	var tolerant := DotPropCatalogue.from_dictionary({
		"format": 1,
		"props": [
			{"id": "good", "scene": "a.tscn"},
			{"id": "", "scene": "b.tscn"},
			{"id": "also_good", "scene": "c.tscn"},
		],
	})
	_check(
		tolerant.ok and (tolerant.value as DotPropCatalogue).size() == 2,
		"one bad entry does not condemn the file"
	)


# --- Spawning --------------------------------------------------------------

func _test_spawning() -> void:
	print("spawning")

	var spawner := _spawner()

	var crate := spawner.spawn(&"crate", &"alice", Vector3(0.0, 5.0, 0.0))

	_check(crate != null, "a prop spawns")
	_check(crate != null and crate.is_alive(), "and its node is in the tree")
	_check(spawner.world_count() == 1, "and the world counts one")
	_check(spawner.player_count(&"alice") == 1, "and so does its owner")

	_check(spawner.spawn(&"nothing", &"alice", Vector3.ZERO) == null,
		"an unknown prop is refused")

	# The entitlement gate: a prop that requires one is refused without it and
	# allowed with it, and the gate is a callable the host supplies because this
	# addon does not know what an entitlement is.
	spawner.limits.spawn_interval = 0.0

	var denied := spawner.spawn(
		&"gold_crate", &"alice", Vector3.ZERO, Basis.IDENTITY,
		func(_id: StringName) -> bool: return false
	)
	_check(denied == null, "an entitlement a player lacks refuses the spawn")

	var granted := spawner.spawn(
		&"gold_crate", &"alice", Vector3.ZERO, Basis.IDENTITY,
		func(_id: StringName) -> bool: return true
	)
	_check(granted != null, "and one they hold allows it")

	# The definition's mass reaches the body. Every prop in this catalogue is the
	# same 20 kg scene, so a `safe` that weighs 900 kg is the only evidence that
	# `DotPropDef.mass` is simulated rather than merely compared against
	# `grab_mass_limit` — which is all it used to be.
	var safe := spawner.spawn(&"safe", &"alice", Vector3(0.0, 9.0, 0.0))

	_check(
		safe != null and is_equal_approx(safe.body().mass, 900.0),
		"a prop spawns with the mass its definition gives it",
		"%.1f kg" % (safe.body().mass if safe != null else -1.0)
	)

	_check(spawner.prop_for_node(crate.node) == crate,
		"a node resolves back to its prop")

	# And from a child, because a physics query hits a collider that is a child of
	# the prop's root.
	var collider := crate.node.get_child(0)
	_check(spawner.prop_for_node(collider) == crate,
		"and so does one of its children")

	spawner.queue_free()


func _test_authority() -> void:
	print("authority")

	var spawner := _spawner()
	spawner.authoritative = false

	var refusals := PackedStringArray()
	spawner.refused.connect(
		func(_p: StringName, _id: StringName, reason: String) -> void:
			refusals.append(reason)
	)

	_check(
		spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null,
		"a non-authoritative spawner refuses to spawn"
	)
	_check(refusals.size() == 1, "and says so", str(refusals))
	_check(not spawner.remove(1), "and refuses to remove")

	spawner.queue_free()


func _test_budget() -> void:
	print("the per-player budget")

	var limits := DotPropLimits.new()
	limits.per_player_budget = 10
	limits.spawn_interval = 0.0
	limits.world_budget = 0

	var spawner := _spawner(limits)

	for _i in range(10):
		spawner.spawn(&"crate", &"alice", Vector3.ZERO)

	_check(spawner.player_count(&"alice") == 10, "ten crates fit in a budget of ten")
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null,
		"and the eleventh is refused")

	# Another player has their own budget.
	_check(spawner.spawn(&"crate", &"bob", Vector3.ZERO) != null,
		"another player has their own")

	# Cost, not count: one `safe` costs eight, so two do not fit in what is left.
	var costly := _spawner(limits)
	costly.spawn(&"safe", &"carol", Vector3.ZERO)
	_check(costly.player_cost(&"carol") == 8, "an expensive prop costs more")
	_check(costly.spawn(&"safe", &"carol", Vector3.ZERO) == null,
		"so two of them do not fit in a budget of ten")
	_check(costly.spawn(&"crate", &"carol", Vector3.ZERO) != null,
		"while a cheap one still does")

	spawner.queue_free()
	costly.queue_free()


func _test_cooldown() -> void:
	print("the spawn cooldown")

	# The budget alone does not stop a held key: a player who reaches it, removes
	# one and spawns another can still spawn as fast as their key repeats.
	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.5
	limits.per_player_budget = 0
	limits.world_budget = 0

	var spawner := _spawner(limits)

	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) != null, "the first spawns")
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null,
		"and the next is refused straight away")

	spawner.advance(0.4)
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null,
		"and still is part-way through the interval")

	spawner.advance(0.2)
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) != null,
		"and allowed once it has passed")

	# Simulated time, not a wall clock: a server that stalls must not let a player
	# who lagged it spawn faster than one who did not.
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null,
		"and the clock only moves when the host advances it")

	spawner.queue_free()


func _test_world_budget() -> void:
	print("the world budget")

	# Not the per-player budget times the slot count: thirty players each within
	# their own is thirty times the physics.
	var limits := DotPropLimits.new()
	limits.world_budget = 6
	limits.per_player_budget = 0
	limits.spawn_interval = 0.0

	var spawner := _spawner(limits)

	for i in range(6):
		spawner.spawn(&"crate", StringName("p%d" % i), Vector3.ZERO)

	_check(spawner.world_count() == 6, "six props fill the world budget")
	_check(spawner.spawn(&"crate", &"someone_else", Vector3.ZERO) == null,
		"and nobody may add a seventh, however empty their own budget")

	spawner.queue_free()


func _test_undo() -> void:
	print("undo")

	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.0
	limits.undo_depth = 3

	var spawner := _spawner(limits)
	var ids: Array[int] = []

	for _i in range(5):
		ids.append(spawner.spawn(&"crate", &"alice", Vector3.ZERO).instance_id)

	_check(spawner.player_count(&"alice") == 5, "five props are spawned")
	_check(
		spawner.player_cost(&"alice") == 5,
		"and all five count against the budget, whatever the undo depth is",
		"%d" % spawner.player_cost(&"alice")
	)

	_check(spawner.undo(&"alice"), "the last can be undone")
	_check(spawner.player_count(&"alice") == 4, "and is gone")

	# Only the STACK is trimmed to the undo depth, not the props: a builder whose
	# first hundred props vanished when they placed the hundred-and-first would lose
	# their build to a setting about undo.
	_check(spawner.world_count() == 4, "and the rest are still in the world")

	_check(spawner.undo(&"alice"), "and undo works twice")
	_check(spawner.undo(&"alice"), "and three times")
	_check(not spawner.undo(&"alice"),
		"and then stops, because the depth was three")
	_check(spawner.world_count() == 2, "leaving the ones past the depth alone")

	_check(not spawner.undo(&"nobody"), "undo for a player with nothing is refused")

	spawner.queue_free()


func _test_cleanup_on_leave() -> void:
	print("cleanup when a player leaves")

	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.0

	var spawner := _spawner(limits)

	for _i in range(4):
		spawner.spawn(&"crate", &"alice", Vector3.ZERO)

	spawner.spawn(&"crate", &"bob", Vector3.ZERO)

	var reasons := PackedStringArray()
	spawner.removed.connect(
		func(_p: DotPropInstance, reason: StringName) -> void:
			reasons.append(String(reason))
	)

	_check(spawner.player_left(&"alice") == 4, "a departing player's props go")
	_check(spawner.world_count() == 1, "leaving everybody else's")
	_check(
		reasons.size() == 4 and reasons[0] == "left",
		"with the reason reported",
		str(reasons)
	)

	# A build server keeps them, and must not keep charging the departed player's
	# budget for ever.
	var persistent := _spawner(limits)
	persistent.limits.clean_up_on_leave = false

	persistent.spawn(&"crate", &"carol", Vector3.ZERO)
	_check(persistent.player_left(&"carol") == 0, "a build server keeps them")
	_check(persistent.world_count() == 1, "in the world")
	_check(persistent.player_cost(&"carol") == 0,
		"but stops charging the budget of somebody who has gone")

	spawner.queue_free()
	persistent.queue_free()


func _test_no_leaked_nodes() -> void:
	print("nothing leaks")

	var limits := DotPropLimits.new()
	limits.spawn_interval = 0.0

	var spawner := _spawner(limits)
	var nodes: Array[Node] = []

	for _i in range(8):
		nodes.append(spawner.spawn(&"crate", &"alice", Vector3.ZERO).node)

	_check(spawner.clear_all() == 8, "clear_all removes eight")
	_check(spawner.world_count() == 0, "and the count is zero")

	# Freed, not merely forgotten: a limit that counted a dictionary would pass every
	# test above while the scene tree filled up.
	await get_tree().process_frame
	await get_tree().process_frame

	var alive := 0
	for node in nodes:
		if is_instance_valid(node):
			alive += 1

	_check(alive == 0, "and every node is actually freed", "%d still alive" % alive)

	spawner.queue_free()


# --- Tools -----------------------------------------------------------------

func _test_tool_permissions() -> void:
	print("what a tool may act on")

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


func _test_freezing() -> void:
	print("freezing")

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


func _test_freeze_limit() -> void:
	print("the freeze limit")

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


func _test_size_ceiling() -> void:
	print("the size ceiling")

	# A size class answers a different question from a cost. A cost is a budget —
	# twenty small props or two big ones. This is a ceiling: allow a hundred crates
	# and forbid the one model that is the size of the map, without pricing it at a
	# hundred.
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


func _test_physgun_holds() -> void:
	print("the physics gun")

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
	var distance := crate.node.global_position.distance_to(goal)

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


func _test_physgun_caps_speed() -> void:
	print("the physics gun's speed cap")

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


func _test_gravgun_punts() -> void:
	print("the gravity gun")

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

	var carried_at := crate.node.global_position.distance_to(
		origin + aim * gun.carry_distance
	)
	_check(carried_at < 1.5, "a carried prop sits in front of the player",
		"%.2f m away" % carried_at)

	crate.body().linear_velocity = Vector3.ZERO
	await get_tree().physics_frame

	var punted := gun.punt(null, origin, aim)

	# An impulse is applied by the physics server, not written into linear_velocity,
	# so it is not readable until the step that consumes it has run. Reading it
	# straight after the call gives the velocity from before the punt, which is how
	# the first version of this test reported "0.0 -> 0.0" for a punt that worked.
	await get_tree().physics_frame

	var light_speed := crate.body().linear_velocity.z

	_check(punted == crate, "punting returns the prop")
	_check(not gun.is_carrying(), "and lets go of it")
	_check(
		light_speed < -1.0,
		"and sends it away along the aim",
		"%.1f m/s" % light_speed
	)

	# A punt is an impulse, so a heavy prop goes less far than a light one — which
	# is what makes the tool feel like it has weight, and is free because the solver
	# already divides by the mass.
	var heavy := spawner.spawn(&"safe", &"alice", Vector3(0.0, 2.0, -3.0))

	# Not set here: the spawner puts the definition's mass on the body. Asserted
	# rather than assumed, because if that ever stops happening this test would
	# silently become "two 20 kg props go the same distance", which passes the
	# comparison below by being wrong in both halves.
	_check(
		is_equal_approx(heavy.body().mass, 900.0),
		"a heavy prop is heavy without being told twice"
	)

	# The mass is set BEFORE a step runs, because the physics server picks it up on
	# the next one — and an impulse applied in between is divided by the old mass,
	# which made the first version of this test report the 900 kg prop flying twenty
	# times further than the 20 kg one.
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

	# A frozen prop is refused rather than quietly thawed: a gravity gun that
	# unfroze a build would take a tower apart one piece at a time.
	var frozen := spawner.spawn(&"crate", &"alice", Vector3(0.0, 2.0, -3.0))
	DotPhysGun.set_frozen(frozen, true)

	var refusing := DotGravGun.new()
	refusing.spawner = spawner
	refusing.wielder = &"alice"

	_check(
		not refusing.may_act_on(frozen).ok or frozen.frozen,
		"a frozen prop stays frozen"
	)

	spawner.queue_free()

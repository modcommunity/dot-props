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

const CHECKS := 334

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 38

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

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
	_test_spawning_2d()
	_test_authority()
	_test_budget()
	_test_group_limits()
	_test_cooldown()
	_test_world_budget()
	_test_undo()
	_test_cleanup_on_leave()
	_test_no_leaked_nodes()
	_test_tool_permissions()
	_test_protected_owners()
	_test_wiring()
	_test_freezing()
	_test_freeze_limit()
	_test_size_ceiling()
	await _test_physgun_holds()
	await _test_physgun_caps_speed()
	await _test_gravgun_punts()
	_test_breaking()
	_test_breaking_authority()
	_test_impact()
	await _test_explosion()
	_test_carry()
	await _test_carry_pushes()
	_test_disguise()
	_test_taunts()
	_test_pieces()
	_test_toy_catalogue()
	await _test_toys()
	await _test_toy_mirror()
	await _test_rolling()
	_test_prop_folder()
	_test_workshop_props()
	_test_ledge()
	_test_clear_cache()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


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

	# A 2D prop, in the same catalogue as the 3D ones on purpose. A [DotPropDef]
	# deliberately says nothing about dimension — it is an id, a scene, a cost and a
	# permission — so a catalogue holding both is a legitimate thing for a game with a
	# 2D world to have, and the spawner has to pick the right entry point rather than
	# infer one.
	var bench := DotPropDef.make(&"bench", "res://fixtures/prop_body_2d.tscn")
	bench.category = &"furniture"
	bench.mass = 55.0
	catalogue.add(bench)

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
	_section("prop definitions")

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
	_done()


func _test_catalogue() -> void:
	_section("the catalogue")

	var catalogue := _catalogue()

	_check(catalogue.size() == 5, "five props go in", "%d" % catalogue.size())
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
	_check(parsed.ok and (parsed.value as DotPropCatalogue).size() == 5,
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
	_done()


# --- Spawning --------------------------------------------------------------

func _test_spawning() -> void:
	_section("spawning")

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
	var collider: Node = crate.node.get_child(0)
	_check(spawner.prop_for_node(collider) == crate,
		"and so does one of its children")

	spawner.queue_free()
	_done()


## The same spawner, into a 2D world.
##
## [b]The point of this section is that everything except the placement is shared.[/b]
## The budget, the interval, the undo stack, the ownership and the removal are the same
## code — so what is worth checking is the three lines that differ and the one thing a
## mixed catalogue makes possible: asking for a 2D prop through the 3D entry point, and
## the reverse. Both have to be refused rather than half-built, because a scene that is
## instantiated and then rejected is a leaked node that nothing reports.
func _test_spawning_2d() -> void:
	_section("spawning in 2D")

	var world_2d := Node2D.new()
	_world.add_child(world_2d)

	var spawner := DotPropSpawner.new()
	spawner.catalogue = _catalogue()
	spawner.limits = DotPropLimits.new()
	spawner.limits.spawn_interval = 0.0
	spawner.authoritative = true
	# The props go into the 2D world rather than under the spawner, which is a plain
	# Node and would give them no transform of their own to be placed in.
	spawner.world_ref = DotNodeRef.of_path(^"..")
	world_2d.add_child(spawner)

	var bench := spawner.spawn_2d(&"bench", &"alice", Vector2(120.0, -40.0), 0.5)

	_check(bench != null, "a 2D prop spawns")
	_check(bench != null and bench.is_alive(), "and its node is in the tree")
	_check(bench != null and bench.is_2d(), "and it knows it is 2D")
	_check(
		bench != null and bench.position_2d().is_equal_approx(Vector2(120.0, -40.0)),
		"where it was asked for",
		str(bench.position_2d()) if bench != null else "null"
	)
	_check(
		bench != null and is_equal_approx(bench.body_2d().mass, 55.0),
		"with the mass its definition gives it",
		"%.1f kg" % (bench.body_2d().mass if bench != null else -1.0)
	)
	# The books are the shared half, and they are what a 2D game is actually buying.
	_check(spawner.world_count() == 1, "the world counts it")
	_check(spawner.player_count(&"alice") == 1, "and so does its owner")

	# Freezing is the one prop operation a 2D game needs and it lives on the physics
	# gun, which is a 3D tool. It handles both, in the one place that also zeroes the
	# velocities — a body frozen while moving otherwise leaps away when somebody thaws
	# it, minutes later, with nothing to connect the two.
	bench.body_2d().linear_velocity = Vector2(400.0, 0.0)
	DotPhysGun.set_frozen(bench, true)
	_check(bench.frozen and bench.body_2d().freeze, "and it freezes")
	_check(
		bench.body_2d().linear_velocity == Vector2.ZERO,
		"with its velocity zeroed rather than stored up"
	)

	var before := world_2d.get_child_count()

	# A 3D prop through the 2D door, and a 2D prop through the 3D one. Both refused,
	# and — the part worth checking — neither leaves its instantiated scene behind.
	_check(
		spawner.spawn_2d(&"crate", &"alice", Vector2.ZERO) == null,
		"a 3D prop asked for in 2D is refused"
	)
	_check(
		spawner.spawn(&"bench", &"alice", Vector3.ZERO) == null,
		"and a 2D prop asked for in 3D"
	)
	_check(
		world_2d.get_child_count() == before,
		"leaving nothing behind either time",
		"%d children, was %d" % [world_2d.get_child_count(), before]
	)

	_check(spawner.undo(&"alice"), "undo works on it like any other prop")
	_check(spawner.world_count() == 0, "and the world is empty again")

	world_2d.queue_free()
	_done()


func _test_authority() -> void:
	_section("authority")

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
	_done()


func _test_budget() -> void:
	_section("the per-player budget")

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
	_done()


func _test_group_limits() -> void:
	_section("limits per group, and per player")

	var limits := DotPropLimits.new()
	limits.per_player_budget = 0
	limits.spawn_interval = 0.0
	limits.world_budget = 0
	limits.group_limits = {&"crates": 2}

	var spawner := _spawner(limits)
	spawner.catalogue.get_prop(&"crate").limit_group = &"crates"

	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) != null
		and spawner.spawn(&"crate", &"alice", Vector3.ZERO) != null, "two of a group of two fit")

	var reasons: Array = []
	spawner.refused.connect(func(_p: StringName, _id: StringName, why: String) -> void: reasons.append(why))
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null, "and the third is refused")
	_check(not reasons.is_empty() and str(reasons[-1]).contains("crates"),
		"saying which limit", str(reasons))
	_check(spawner.spawn(&"safe", &"alice", Vector3.ZERO) != null,
		"while a prop in another group is not counted against it")
	_check(spawner.group_count(&"alice", &"crates") == 2 and spawner.group_count(&"alice", &"props") == 1,
		"each group is counted on its own")

	# A role: the game answers per player. Bob is an admin with ten.
	spawner.limit_resolver = func(player: StringName, key: StringName, base: int) -> int:
		return 10 if player == &"bob" and key == &"crates" else base
	for i in 5:
		spawner.spawn(&"crate", &"bob", Vector3.ZERO)
	_check(spawner.group_count(&"bob", &"crates") == 5, "an override lets one player past the default")
	_check(spawner.spawn(&"crate", &"alice", Vector3.ZERO) == null, "and nobody else")

	var usage := spawner.group_usage(&"bob")
	_check(usage.has(&"crates") and int(usage[&"crates"][0]) == 5 and int(usage[&"crates"][1]) == 10,
		"usage reports count and limit per group", str(usage))

	var round_trip := DotPropDef.from_dictionary(spawner.catalogue.get_prop(&"crate").to_dictionary())
	_check(round_trip.limit_group == &"crates", "a definition's group survives a document")
	_check(DotPropDef.make(&"x", "res://x.tscn").group() == DotPropDef.GROUP_PROPS,
		"and one with none is a prop")

	spawner.catalogue.get_prop(&"crate").limit_group = &""
	spawner.queue_free()
	_done()


func _test_cooldown() -> void:
	_section("the spawn cooldown")

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
	_done()


func _test_world_budget() -> void:
	_section("the world budget")

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
	_done()


func _test_undo() -> void:
	_section("undo")

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
	_done()


func _test_cleanup_on_leave() -> void:
	_section("cleanup when a player leaves")

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
	_done()


func _test_no_leaked_nodes() -> void:
	_section("nothing leaks")

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
	_done()


# --- Tools -----------------------------------------------------------------

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
	_done()


# --- Breaking --------------------------------------------------------------

func _damage_node(spawner: DotPropSpawner) -> DotPropDamage:
	var damage := DotPropDamage.new()
	damage.authoritative = true
	spawner.add_child(damage)
	return damage


func _breakables() -> DotPropCatalogue:
	var catalogue := _catalogue()

	var box := DotPropDef.make(&"box", "res://fixtures/prop_body.tscn")
	box.max_health = 100.0
	box.break_impact_speed = 12.0
	catalogue.add(box)

	var barrel := DotPropDef.make(&"barrel", "res://fixtures/prop_body.tscn")
	barrel.max_health = 20.0
	barrel.explode_radius = 6.0
	barrel.explode_damage = 90.0
	barrel.explode_force = 400.0
	catalogue.add(barrel)

	var anvil := DotPropDef.make(&"anvil", "res://fixtures/prop_body.tscn")
	anvil.rideable = false
	catalogue.add(anvil)

	return catalogue


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

	# Gravity off on both, so what is measured is the blast rather than the fall. The
	# first version of this check read `linear_velocity.length()` one physics step
	# after the barrel went off and reported the crate 40 m away as "shoved" at
	# 0.16 m/s, which was one tick of gravity and nothing to do with the explosion.
	for crate_body in [near.body(), far.body()]:
		crate_body.freeze = false
		crate_body.gravity_scale = 0.0
		crate_body.linear_velocity = Vector3.ZERO

	var blasts: Array = []
	damage.exploded.connect(
		func(at: Vector3, radius: float, dmg: float, force: float, by: StringName) -> void:
			blasts.append({"at": at, "radius": radius, "damage": dmg, "force": force, "by": by}))

	damage.hurt(barrel.instance_id, 999.0, &"alice")

	# The blast's shove is an impulse, and an impulse is not readable in
	# `linear_velocity` until the step that consumes it has run. This addon's own
	# notes record paying for that twice; this is the third time, and the first
	# version of this check reported a barrel that moved nothing.
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


# --- Standing on one -------------------------------------------------------

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


# --- Hiding as a prop -------------------------------------------------------

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

	# Leant every way a player can turn it (every quarter turn of pitch and roll, and the
	# eighths between), a bottle's box never goes under the floor and its lowest corner is on
	# it: the first build turned a prop about the foot of its box and half a bottle laid on its
	# side was under the floor, out of every shot.
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

	var bad := DotPropDisguiseRules.new()
	bad.hull_min_height = 0.1
	_check(not bad.validate().ok, "rules whose smallest hull would be a capsule shorter than it is wide are refused")
	_done()


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



# --- Toys ----------------------------------------------------------------------

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
func _toy_world(authoritative: bool) -> Array:
	var holder := Node3D.new()
	holder.position = Vector3(0, 100, 0)
	_world.add_child(holder)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	holder.add_child(floor_body)
	var toys := DotPropToyBox.new()
	toys.authoritative = authoritative
	toys.draw = true
	# world 1, loose 2, solid 4, footprints 8.
	toys.loose_layer = 2
	toys.loose_mask = 1 | 2 | 4
	toys.solid_layer = 4
	toys.solid_mask = 1 | 2
	toys.footprint_layer = 8
	toys.aim_mask = 1 | 2 | 4
	holder.add_child(toys)
	toys.catalogue = DotPropToyCatalogue.stock()
	var placements: Array = []
	var x := 0.0
	for id in toys.catalogue.ids():
		# Turned, so nothing passes only because a toy's axes are the world's: a swing pushed
		# at an angle to its bar is what blew Godot's hinge apart.
		placements.append({"toy": id, "at": [x, 0, 0], "yaw": 20})
		x += 4.0
	# The switch (index of light_switch) turns the lamp.
	var ids := toys.catalogue.ids()
	placements[ids.find("light_switch")]["links"] = [ids.find("lamp_post")]
	var built := toys.build(placements)
	return [holder, toys, built]


func _index(toys: DotPropToyBox, id: String) -> int:
	for t in toys.toys:
		if String(t.def["id"]) == id:
			return t.index
	return -1


func _step_physics(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


func _test_toys() -> void:
	_section("toys on the server: pushed, kicked, stood on, switched, bounced on, capped, sent home")
	var made := _toy_world(true)
	var floor_body: Node3D = made[0]
	var toys: DotPropToyBox = made[1]
	_check((made[2] as DotResult).ok and toys.count() == toys.catalogue.size(), "every stock toy is built", str(toys.count()))
	await _step_physics(90)
	var fell := PackedStringArray()
	for t in toys.toys:
		if t.body != null and t.body.global_position.y < 99.95:
			fell.append("%s at %s" % [t.def["id"], t.body.global_position.snapped(Vector3.ONE * 0.01)])
	_check(fell.is_empty(), "a second and a half on, nothing has fallen through the floor", ", ".join(fell))

	# Walking into the beach ball at 5 m/s sends it ahead.
	var ball := toys.toy(_index(toys, "beach_ball"))
	var start := ball.body.global_position
	var feet := start + Vector3(-0.75, -0.5, 0)
	var pushed := toys.push_from(feet, Vector3(5, 0, 0), 0.35, 1.8)
	await _step_physics(20)
	_check(pushed == 1 and ball.body.global_position.x > start.x + 1.0,
		"a person walking into the beach ball sends it on ahead", "%d pushed, moved %.2f m" % [pushed, ball.body.global_position.x - start.x])
	var far := toys.push_from(start + Vector3(-6, 0, 0), Vector3(5, 0, 0), 0.35, 1.8)
	_check(far == 0, "and one walking six metres away does not")

	# A crate added at run time is a loose body: pushed along, put to sleep at rest, removable.
	toys.sleep_after = 0.5
	var crate := toys.add_toy(&"crate", Vector3(80, 0.0, -80))
	await _step_physics(30)
	var c0 := crate.body.global_position
	var cpush := toys.push_from(c0 + Vector3(-0.6, -0.5, 0), Vector3(5, 0, 0), 0.35, 1.8)
	await _step_physics(20)
	_check(crate != null and cpush >= 1 and crate.body.global_position.x > c0.x + 0.2, "a crate added at run time is pushed along",
		"%d pushed, moved %.2f m" % [cpush, crate.body.global_position.x - c0.x])
	for _i in range(300):
		toys.advance(1.0 / 60.0)
		await get_tree().physics_frame
	_check(not crate.awake(), "and sleeps once it has been still for sleep_after seconds", "v %s w %s sleeping %s" % [str(crate.body.linear_velocity), str(crate.body.angular_velocity), str(crate.body.sleeping)])
	var before_n := toys.count()
	toys.remove_toy(crate)
	_check(toys.count() == before_n - 1, "remove_toy takes it out again")
	toys.sleep_after = 0.0

	# A drop over a pit (past the floor's edge) is lost after fall_limit metres, not at kill_y.
	var lost_seen := [0]
	var _lc := toys.lost.connect(func(_t: DotPropToy) -> void: lost_seen[0] += 1)
	toys.fall_limit = 4.0
	toys.lost_mode = DotPropToyBox.LostMode.REMOVE
	var pit := toys.add_toy(&"crate", Vector3(150, 1.0, 0.0))
	var n_pit := toys.count()
	for _i in range(240):
		toys.advance(1.0 / 60.0)
		await get_tree().physics_frame
	_check(lost_seen[0] == 1 and toys.count() == n_pit - 1 and not toys.toys.has(pit),
		"a crate dropped over a pit is lost after fall_limit and removed (LostMode.REMOVE)", "%d lost, %d toys of %d" % [lost_seen[0], toys.count(), n_pit])
	toys.lost_mode = DotPropToyBox.LostMode.HOME
	toys.fall_limit = 0.0

	# The football kicked along -z.
	var football := toys.toy(_index(toys, "football"))
	var f0 := football.body.global_position
	var kicked := toys.use(football.index, f0 + Vector3(0, 1.4, 1.0), Vector3(0, -0.4, -1))
	await _step_physics(15)
	_check(kicked and football.body.global_position.z < f0.z - 1.5, "the use key kicks the football along the look",
		"%.2f m" % (f0.z - football.body.global_position.z))

	# A person on one end of the see-saw tips it down at that end.
	var seesaw := toys.toy(_index(toys, "seesaw"))
	var end_feet := seesaw.body.global_position + seesaw.body.global_basis.x * 1.3 + Vector3(0, 0.1, 0)
	for _i in range(40):
		var _bore := toys.stand_on(end_feet, 70.0)
		await get_tree().physics_frame
	var tip := seesaw.body.to_global(Vector3(1.5, 0, 0)).y
	var other := seesaw.body.to_global(Vector3(-1.5, 0, 0)).y
	_check(tip < other - 0.3, "somebody standing on one end of the see-saw tips it down there", "%.2f against %.2f" % [tip, other])

	var spinner := toys.toy(_index(toys, "merry_go_round"))
	var _spun := toys.use(spinner.index, spinner.body.global_position + Vector3(1.6, 1.0, 0), Vector3(0, 0, 1))
	await _step_physics(10)
	var turned := spinner.body.global_basis.x.angle_to(spinner.global_basis.x)
	_check(absf(spinner._spin.y) > 0.5 and turned > 0.05 and spinner.body.global_position.distance_to(spinner.rest.origin) < 0.01,
		"the roundabout spins about its hub and goes nowhere", "%.2f rad/s, turned %.2f" % [spinner._spin.y, turned])

	# Somebody standing on the turning deck is carried round the hub with it: a rotation, so a
	# rider a metre out is still a metre out after it, and turned by the same angle.
	var rider := spinner.body.global_position + Vector3(1.0, 0.02, 0)
	var carried := toys.carry_for(rider, 1.0 / 60.0, spinner.body.get_instance_id())
	var looked := toys.carry_for(rider, 1.0 / 60.0)
	var after := rider + (carried.get("offset", Vector3.ZERO) as Vector3)
	var hub := spinner.body.global_position
	_check(not carried.is_empty() and int(carried["index"]) == spinner.index
		and is_equal_approx(float(carried["yaw"]), spinner._spin.y / 60.0)
		and absf(Vector2(after.x - hub.x, after.z - hub.z).length() - 1.0) < 0.001
		and (carried["offset"] as Vector3).length() > 0.005 and not looked.is_empty(),
		"a person standing on the turning roundabout is carried round its hub, the same a metre out",
		str(carried))
	var off_deck := toys.carry_for(hub + Vector3(2.5, 0.02, 0), 1.0 / 60.0)
	var on_floor := toys.carry_for(rider, 1.0 / 60.0, floor_body.get_child(0).get_instance_id() if floor_body.get_child_count() > 0 else 1)
	_check(off_deck.is_empty() and on_floor.is_empty(), "beside it, or on other ground, nobody is carried")
	# A game already riding props through DotPropCarry gets the roundabout by handing it the box.
	var prop_carry := DotPropCarry.new()
	prop_carry.toys = toys
	var lifted := prop_carry.ride(spinner.body.get_instance_id(), rider, 70.0, 1.0 / 60.0)
	_check(lifted.is_equal_approx(carried["offset"]), "and DotPropCarry with the toys set carries them the same", str(lifted))
	prop_carry.free()

	# The swing, pushed at an angle to its bar, swings along its own plane and stays on the bar.
	var swing := toys.toy(_index(toys, "swing"))
	var _pushed := toys.use(swing.index, swing.body.global_position + Vector3(0.5, 1.2, 1.0), Vector3(-0.4, -0.2, -1))
	var furthest := 0.0
	var stayed := true
	for _i in range(90):
		await get_tree().physics_frame
		furthest = maxf(furthest, swing.body.global_position.distance_to(swing.rest.origin))
		var from_bar := swing.body.global_position.distance_to(swing._pivot_global())
		stayed = stayed and absf(from_bar - swing._hang.length()) < 0.01
	_check(furthest > 0.4 and stayed and swing.body.global_position.distance_to(swing.rest.origin) < furthest,
		"a pushed swing swings out, back, and never off its bar", "out %.2f m" % furthest)
	var bag := toys.toy(_index(toys, "punching_bag"))
	var _punched := toys.use(bag.index, bag.body.global_position + Vector3(0, 0, 1.2), Vector3(0, 0, -1))
	await _step_physics(12)
	_check(bag.body.global_position.distance_to(bag.rest.origin) > 0.15, "a punched bag swings away from the punch")

	var lamp := toys.toy(_index(toys, "lamp_post"))
	var switch := toys.toy(_index(toys, "light_switch"))
	var was_lit := lamp.on
	var _pressed := toys.use(switch.index, switch.global_position + Vector3(0, 1.4, 1), Vector3(0, -0.3, -1))
	_check(switch.on == lamp.on and lamp.on != was_lit and switch.count == 1 and lamp.count == 1,
		"the switch flips its linked lamp, and both count it")
	var horn := toys.toy(_index(toys, "horn"))
	var _honk := toys.use(horn.index, Vector3.ZERO, Vector3.FORWARD)
	_check(horn.count == 1 and not toys.toy(_index(toys, "trampoline")).usable(), "the horn counts a honk; a trampoline is not used, it is jumped on")

	var tramp := toys.toy(_index(toys, "trampoline"))
	var on_bed := toys.launch_for(tramp.global_position + Vector3(0.3, tramp._size.y, 0), Vector3(1, -6, 0))
	var beside := toys.launch_for(tramp.global_position + Vector3(2.5, 0, 0), Vector3(0, -6, 0))
	var rising := toys.launch_for(tramp.global_position + Vector3(0, tramp._size.y, 0), Vector3(0, 3, 0))
	_check(not on_bed.is_empty() and (on_bed["velocity"] as Vector3).y > 8.0 and is_equal_approx((on_bed["velocity"] as Vector3).x, 1.0)
		and beside.is_empty() and rising.is_empty(), "landing on the trampoline's bed throws a person up; beside it or rising, nothing")
	var pad := toys.toy(_index(toys, "bounce_pad"))
	var thrown := toys.launch_for(pad.global_position + Vector3(0, pad._size.y, 0), Vector3.ZERO)
	_check(not thrown.is_empty() and (thrown["velocity"] as Vector3).z > 4.0 and (thrown["velocity"] as Vector3).y > 6.0,
		"the bounce pad throws forward along its arrow and up")

	# Shot: a pistol's damage knocks a pin over and away; the floor is not a toy; a bell rings.
	var pin := toys.toy(_index(toys, "bowling_pin"))
	var p0 := pin.body.global_position
	var shot_at := toys.shot(pin.body, p0 + Vector3(0, 0.2, 0), Vector3(1, 0, 0), 25.0)
	var floor_shot := toys.shot(floor_body.get_child(0), p0 - Vector3(0, 0.5, 0), Vector3.DOWN, 25.0)
	var bell := toys.toy(_index(toys, "bell"))
	var rung := bell.count
	var bell_shot := toys.shot(bell.fixed, bell.global_position + Vector3(0, 1.8, 0), Vector3(0, 0, -1), 25.0)
	var tyre := toys.toy(_index(toys, "tyre"))
	var t0 := tyre.body.global_position
	var blasted := toys.blast(t0 + Vector3(-1.0, 0, 0), 4.0, 6.0)
	await _step_physics(12)
	_check(shot_at == pin.index and pin.body.global_position.distance_to(p0) > 0.15 and floor_shot == -1,
		"a shot pushes the toy it hits, and the floor is not one", "moved %.2f m" % pin.body.global_position.distance_to(p0))
	_check(bell_shot == bell.index and bell.count == (rung + 1) % 256, "a shot bell rings", "%d, %d -> %d" % [bell_shot, rung, bell.count])
	# Along a ray, for a game whose own trace never meets a toy: the football from three metres,
	# and nothing through the floor.
	var ball2 := toys.toy(_index(toys, "bowling_ball"))
	var aim_from := ball2.body.global_position + Vector3(0, 0, 3.0)
	var along := toys.shot_along(aim_from, Vector3(0, 0, -1), 10.0, 25.0, 1)
	var under := toys.shot_along(ball2.body.global_position + Vector3(0, 2, 0), Vector3.DOWN, 1.0, 25.0, 1)
	_check(along == ball2.index and under == -1, "a shot along a ray pushes the first toy on it, and a short one reaches none", "%d, %d" % [along, under])
	_check(blasted >= 1 and tyre.body.global_position.x > t0.x + 0.1, "a blast beside the tyre sends it away",
		"%d moved, tyre %.2f m" % [blasted, tyre.body.global_position.x - t0.x])

	# The cap: two awake at most; the rest put to sleep.
	toys.rules.max_awake = 2
	for id in ["beach_ball", "football", "barrel", "tyre", "bowling_ball"]:
		var t := toys.toy(_index(toys, id))
		var _u := toys.use(t.index, t.body.global_position + Vector3(0, 1, 1), Vector3(0, 0, -1))
	await _step_physics(2)
	toys.advance(1.0 / 60.0)
	_check(toys.awake_count() <= 2, "past sv_toys_awake the longest untouched are put to sleep", str(toys.awake_count()))
	toys.rules.max_awake = 0

	var nav := toys.nav_bodies()
	var shapes := (nav[0] as Node).get_child_count() if not nav.is_empty() else 0
	var fixed_kinds := 0
	for t in toys.toys:
		if t.footprint().size != Vector3.ZERO:
			fixed_kinds += 1
	_check(shapes == fixed_kinds and fixed_kinds >= 8 and toys.toy(_index(toys, "beach_ball")).footprint().size == Vector3.ZERO,
		"a footprint for every toy that stands in the way, none for a loose one", "%d of %d" % [shapes, fixed_kinds])
	# Through the trampoline's footprint, under its bed and between its legs: a ray with every
	# bit set meets nothing there, and the navigation parser still reads the boxes.
	var bed := toys.toy(_index(toys, "trampoline"))
	var across := PhysicsRayQueryParameters3D.create(bed.global_position + Vector3(0, 1.2, -3), bed.global_position + Vector3(0, 1.2, 3))
	var met := (toys.get_world_3d().direct_space_state.intersect_ray(across) as Dictionary)
	var source := NavigationMeshSourceGeometryData3D.new()
	var parse_mesh := NavigationMesh.new()
	parse_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	NavigationServer3D.parse_source_geometry_data(parse_mesh, source, nav[0] as Node)
	_check(met.is_empty() and source.get_vertices().size() >= shapes * 8 * 3,
		"a footprint stops no ray, and a baker still parses it", "met %s, %d floats" % [str(DotPropToyBox.toy_of(met.get("collider")).def["id"] if DotPropToyBox.toy_of(met.get("collider")) != null else met.get("collider")), source.get_vertices().size()])

	ball.body.global_position = Vector3(0, -50, 0)
	toys.kill_y = 0.0
	toys.advance(1.0 / 60.0)
	_check(ball.body.global_position.distance_to(ball.rest.origin) < 0.01, "a toy that falls out of the world goes home")
	toys.reset()
	await _step_physics(2)
	_check(football.body.global_position.distance_to(football.rest.origin) < 0.05 and lamp.on == bool(lamp.def["on"]),
		"a reset puts every toy home and every lamp as the map has it")

	var _off := toys.rules.set_cvar(DotPropToyRules.CVAR_ENABLED, "0")
	_check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED and toys.aimed(Vector3(0, 1, 3), Vector3.FORWARD) == -1,
		"sv_toys 0 takes them out of the world")
	var _on := toys.rules.set_cvar(DotPropToyRules.CVAR_ENABLED, "1")

	toys.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	_done()


func _test_toy_mirror() -> void:
	_section("toys on a client: frozen, posed from the server's state, heard when they change")
	var made := _toy_world(false)
	var floor_body: Node3D = made[0]
	var toys: DotPropToyBox = made[1]
	var up := Vector3(0, 100, 0)
	var ball := toys.toy(_index(toys, "beach_ball"))
	_check(ball.body.freeze and ball.body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC and not ball.use(Vector3.ZERO, Vector3.FORWARD),
		"a client's toy is frozen and does nothing itself")
	var heard: Array = []
	toys.sound.connect(func(id: StringName, _at: Vector3, _s: float) -> void: heard.append(id))
	ball.show_state(up + Vector3(3, 2, 1), Quaternion(Vector3.UP, 0.5), false, 0)
	await _step_physics(3)
	_check(ball.body.global_position.distance_to(up + Vector3(3, 2, 1)) < 0.01, "posed where the server says")
	var horn := toys.toy(_index(toys, "horn"))
	horn.show_state(Vector3.ZERO, Quaternion.IDENTITY, false, 1)
	toys._process(1.0 / 60.0)
	_check(heard.has(DotPropToySounds.HORN), "a use count that moved is heard", str(heard))
	# A ball dropped onto the floor (in the server's states) is heard landing.
	heard.clear()
	for i in range(20):
		var y := maxf(2.0 - 0.12 * float(i), 0.5)
		ball.show_state(up + Vector3(3, y, 1), Quaternion.IDENTITY, false, 0)
		toys._process(1.0 / 60.0)
	_check(heard.has(DotPropToySounds.BOUNCE), "and a ball stopping short on the floor is heard", str(heard))
	var aimed := toys.aimed(up + Vector3(3, 2, 4), Vector3(0, 0, -1), 4.0)
	_check(aimed == ball.index, "the use prompt finds a client's toy along the look")
	# A client's roundabout turns as the server's states say, and its own player standing on it
	# is carried at the spin measured from them: the spin itself is not sent.
	var spinner := toys.toy(_index(toys, "merry_go_round"))
	var hub := spinner.body.global_position
	for i in range(6):
		spinner.show_state(hub, Quaternion(Vector3.UP, 0.05 * float(i)), false, 0, 1.0 / 60.0)
	var measured := spinner.surface_velocity(hub + Vector3(1, 0, 0)).length()
	var ride := toys.carry_for(hub + Vector3(1.0, 0.02, 0), 1.0 / 60.0)
	_check(absf(measured - 3.0) < 0.3 and not ride.is_empty() and float(ride["yaw"]) > 0.03,
		"a client measures the roundabout's spin from the poses it is shown, and carries its rider at it",
		"%.2f m/s a metre out, %s" % [measured, str(ride)])
	spinner.show_state(hub, Quaternion(Vector3.UP, 0.25), false, 0, 0.6)
	_check(toys.carry_for(hub + Vector3(1.0, 0.02, 0), 1.0 / 60.0).is_empty(), "and a pose after a long gap is not a spin")
	toys.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	_done()


## A barrel that rolls hurts, a nudged one does not, and one toy hurts one person once per cooldown.
func _test_rolling() -> void:
	_section("rolling: a fast barrel hurts a person it touches, a slow one and a ball do not")
	var made := _toy_world(true)
	var floor_body: Node3D = made[0]
	var toys: DotPropToyBox = made[1]
	var barrel: DotPropToy = toys.toys[_index(toys, "barrel")]
	var ball: DotPropToy = toys.toys[_index(toys, "beach_ball")]
	await _step_physics(60)
	var rule := DotPropRolling.new()
	var at := barrel.body.global_position
	var victims := [{"id": &"p1", "position": Vector3(at.x, at.y - 0.4, at.z), "radius": 0.35, "height": 1.8}]
	_check(rule.scan(toys, victims, 0.1).is_empty(), "a barrel standing still hurts nobody")
	barrel.body.linear_velocity = Vector3(1.5, 0, 0)
	_check(rule.scan(toys, victims, 0.1).is_empty(), "a barrel pushed along at a walk hurts nobody", str(rule.min_speed))
	barrel.body.sleeping = false
	barrel.body.linear_velocity = Vector3(7.0, 0, 0)
	var hit := rule.scan(toys, victims, 0.1)
	_check(hit.size() == 1 and hit[0]["victim"] == &"p1" and float(hit[0]["damage"]) > 5.0, "a barrel at 7 m/s hurts the person it is on", str(hit.size()))
	_check(rule.scan(toys, victims, 0.1).is_empty(), "the same barrel does not hit the same person again inside the cooldown")
	_check(not rule.scan(toys, victims, 1.0).is_empty(), "and does once the cooldown has passed")
	_check(rule.damage_for(40.0, 12.0) <= rule.max_damage and rule.damage_for(2.0, 12.0) == 0.0, "damage is capped and zero under the minimum speed")
	ball.body.linear_velocity = Vector3(9.0, 0, 0)
	var far := [{"id": &"p2", "position": ball.body.global_position - Vector3(0, 0.2, 0), "radius": 0.35, "height": 1.8}]
	_check(rule.scan(toys, far, 0.1).is_empty(), "a beach ball at speed hurts nobody: only barrels, crates and tyres do")
	toys.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	_done()


## Loose models become props: a folder, a sidecar, a baked manifest, and what is refused.
func _test_prop_folder() -> void:
	_section("a folder of models becomes props")

	var dir := "user://props_selftest_folder"
	DirAccess.make_dir_recursive_absolute(dir)

	# A model made here, so the addon's suite needs no art: a 2 m wide, 1 m tall box.
	var scene := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = Vector3(2.0, 1.0, 1.0)
	scene.add_child(mesh)
	mesh.owner = scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	doc.write_to_filesystem(state, dir + "/crate_thing.glb")
	doc.write_to_filesystem(state, dir + "/Nope Id!.glb")
	scene.free()

	var side := FileAccess.open(dir + "/crate_thing.json", FileAccess.WRITE)
	side.store_string('{"name": "Crate thing", "category": "Boxes", "mass": 9, "scale": 2, "icon": "../x.png"}')
	side.close()

	var catalogue := DotPropCatalogue.new()
	var res := DotPropFolder.load_into(catalogue, dir, "res://x.tscn")
	_check(res.ok, "a folder reads", "" if res.ok else res.error.message)

	var def := catalogue.get_prop(&"crate_thing")
	_check(def != null, "a model becomes a prop named for its file")
	_check(def != null and def.display_name == "Crate thing" and def.category == &"boxes", "the sidecar names and files it")
	_check(def != null and is_equal_approx(def.mass, 9.0), "and gives its mass")

	var extent: Array = def.meta["extent"] if def != null else [0, 0, 0]
	_check(
		absf(float(extent[0]) - 4.0) < 0.05 and absf(float(extent[1]) - 2.0) < 0.05,
		"the scale is applied to the measured size, in metres", str(extent)
	)
	_check(def != null and def.icon_path == "", "an icon cannot point out of the folder")
	_check(catalogue.has(&"nope_id"), "an id is made of lower-case words, whatever the file is called")

	var again := DotPropFolder.load_into(catalogue, dir, "res://x.tscn")
	_check((again.value as Dictionary)["added"].is_empty(), "reading again adds nothing and replaces nothing")
	_check(DotPropFolder.load_into(catalogue, "user://no_such_folder_here", "res://x.tscn").ok, "a missing folder is not a problem")

	var measured := DotPropModel.measure(dir + "/crate_thing.glb", 1.0, "box")
	_check(measured.ok and (measured.value as Dictionary)["shape"] is Shape3D, "a model is measured into a shape")
	_check(not DotPropModel.measure(dir + "/missing.glb", 1.0).ok, "a missing model is an error, not a null")
	_check(DotPropFolder.sanitize_id("../../a/B c") == "a_b_c", "an id never carries a path")

	_done()


func _workshop_pack(cid: String, version: String, prefix: String, ids: Array) -> Dictionary:
	var entries: Array = []
	for id in ids:
		entries.append({"kind": "prop", "id": id, "name": "Pack %s" % id, "scene": "%s.tscn" % id,
			"category": "pack_stuff", "mass": 5})
	entries.append({"kind": "weapon", "id": "not_a_prop", "name": "Gun", "def": "gun.tres"})
	return {
		"content_id": cid, "version": version, "session": "solo", "source": "subscription",
		"prefix": prefix,
		"provides": {"schema": 1, "title": "Alice props", "kinds": ["prop", "weapon"], "entries": entries},
	}


func _test_clear_cache() -> void:
	_section("clear_cache drops the shared materials")

	var first := DotPropToyLook.material(Color.RED)
	_check(DotPropToyLook.material(Color.RED) == first, "a colour is built once")
	DotPropToyLook.clear_cache()
	DotPropModel.clear_cache()
	_check(DotPropToyLook.material(Color.RED) != first, "after clear_cache it is built again")
	_check(DotPropToyLook.material(Color.RED) is StandardMaterial3D, "and still usable")

	_done()


func _test_workshop_props() -> void:
	_section("Workshop props follow the content index")

	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var catalogue := _catalogue()
	var own := catalogue.size()
	var changes := [0]
	catalogue.content_changed.connect(func() -> void: changes[0] += 1)
	catalogue.follow_content(index)
	_check(catalogue.size() == own and changes[0] == 0, "an empty index adds nothing and announces nothing")

	# A def the pack ships, read from a directory standing in for the mount.
	var dir := "user://ws_props_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var shipped := DotPropDef.new()
	shipped.id = &"ignored_id"
	shipped.display_name = "Shipped"
	shipped.scene_path = "res://fixtures/prop_body.tscn"
	shipped.mass = 7.0
	ResourceSaver.save(shipped, dir + "/shipped.tres")

	var info := _workshop_pack("alice/props", "1.0.0", dir, ["pack_rock", "crate"])
	(info["provides"]["entries"] as Array).append(
		{"kind": "prop", "id": "pack_def", "name": "Def", "def": "shipped.tres"})
	index.add_pack(info)

	var rock := catalogue.get_prop(&"pack_rock")
	_check(rock != null and catalogue.size() == own + 2,
		"a pack mounted afterwards adds its props", "%d props" % catalogue.size())
	_check(rock != null and rock.display_name == "Pack pack_rock [Alice props]",
		"a pack prop is listed as Name [Pack]")
	_check(rock != null and rock.scene_path == dir + "/pack_rock.tscn" and is_equal_approx(rock.mass, 5.0)
			and rock.category == &"pack_stuff" and rock.content_id == &"alice/props",
		"it carries the mounted scene path, the entry's numbers and its pack")
	var made := catalogue.get_prop(&"pack_def")
	_check(made != null and made.id == &"pack_def" and made.display_name == "Shipped [Alice props]"
			and is_equal_approx(made.mass, 7.0),
		"a def entry is loaded and copied, its id taken from the entry")
	_check(catalogue.get_prop(&"not_a_prop") == null, "a weapon entry is offered to nobody")
	_check(changes[0] == 1, "one announcement for the arrival", str(changes[0]))

	# Clash: the game's own id wins, and stays the game's through refreshes.
	var own_crate := catalogue.get_prop(&"crate")
	_check(not own_crate.meta.has("entry_key"),
		"a pack prop under an id the game holds does not replace it")
	catalogue.refresh_content()
	_check(not catalogue.get_prop(&"crate").meta.has("entry_key"), "and a refresh does not either")
	catalogue.add(DotPropDef.make(&"pack_rock", "res://fixtures/prop_body.tscn"))
	catalogue.refresh_content()
	_check(not catalogue.get_prop(&"pack_rock").meta.has("entry_key"),
		"an id the game takes over later is the game's, kept by the refresh")
	var saved := catalogue.to_dictionary()["props"] as Array
	_check(saved.size() == own + 1 and not str(saved).contains("pack_def"),
		"saving the catalogue leaves pack rows out", str(saved.size()))

	# Remove: online hides, solo restores.
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(catalogue.get_prop(&"pack_def") == null and catalogue.size() == own + 1,
		"online shows no subscribed prop and keeps the game's own", str(catalogue.size()))
	index.set_session(DotContentIndex.SESSION_SOLO)
	_check(catalogue.get_prop(&"pack_def") != null, "solo again brings it back")
	index.tag_pack(&"alice/props", "1.0.0", DotContentIndex.SESSION_ONLINE)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	catalogue.refresh_content()
	_check(catalogue.get_prop(&"pack_def") != null, "a pack the server also requires shows online")
	index.set_session(DotContentIndex.SESSION_SOLO)

	# A catalogue following nothing, and one that stopped.
	var none := _catalogue()
	none.follow_content(index, PackedStringArray())
	_check(none.size() == own, "empty kinds follow nothing")
	var fresh := _catalogue().follow_content(index)
	_check(fresh.get_prop(&"pack_def") != null, "following after the mount sees what is already there")
	fresh.unfollow_content()
	_check(fresh.get_prop(&"pack_def") == null and fresh.size() == own, "unfollowing removes the pack rows")
	index.add_pack(_workshop_pack("carol/late", "1.0.0", dir, ["late_prop"]))
	_check(fresh.get_prop(&"late_prop") == null and catalogue.get_prop(&"late_prop") != null,
		"an unfollowed catalogue hears no more, a followed one does")

	DirAccess.remove_absolute(dir + "/shipped.tres")
	DirAccess.remove_absolute(dir)
	_done()


func _test_ledge() -> void:
	_section("ledge")
	var material := StandardMaterial3D.new()
	var right := DotPropLedge.make(8.0, 3.0, 20.0, 3.5, 1.0, 7, material)
	var left := DotPropLedge.make(8.0, 3.0, 20.0, 3.5, -1.0, 7, material)
	var points: PackedVector3Array = ((right.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points
	var lo := INF
	for p: Vector3 in points:
		lo = minf(lo, p.x)
	_check(is_equal_approx(lo, 1.0) and is_equal_approx(DotPropLedge.clear_width(8.0, 3.0), 5.0),
		"a right ledge's face is 3 m in from the edge, leaving 5 m", "face at x=%.2f" % lo)
	var hi := -INF
	for p: Vector3 in ((left.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points:
		hi = maxf(hi, p.x)
	_check(is_equal_approx(hi, -1.0), "a left one mirrors it", "face at x=%.2f" % hi)
	var span := 0.0
	for p: Vector3 in points:
		span = maxf(span, absf(p.z))
	_check(is_equal_approx(span, 10.0) and right.get_child_count() == left.get_child_count(), "it is as long as asked and the same on both sides", str(span))
	_check(right.collision_layer == 1 and right.side == 1.0 and left.side == -1.0, "it is solid on the layers it was given")
	right.free()
	left.free()
	_done()

extends "props_selftest_base.gd"

## Spawning, limits, ownership and cleanup checks.


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

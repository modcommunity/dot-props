extends "props_selftest_break.gd"

## The toy box checks.


func _test_toys_prefilter() -> void:
	_section("toy box push_from: the prefilter gives the unfiltered result, and is faster")
	var made_a := _scatter_box(300)
	var made_b := _scatter_box(300)
	# Far apart, or the two boxes' toys collide with each other.
	(made_b[0] as Node3D).position.x = 1000.0
	var a: DotPropToyBox = made_a[1]
	var b: DotPropToyBox = made_b[1]
	await _step_physics(30)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var movers: Array[DotPropToy] = []
	for t in a.toys:
		if t.pushable and t.body != null:
			movers.append(t)
	var feet: Array[Vector3] = []
	var vel: Array[Vector3] = []
	for i in range(100):
		var at := movers[rng.randi() % movers.size()].body.global_position if i % 2 == 0 else Vector3(rng.randf_range(-95, 95), 100, rng.randf_range(-95, 95))
		feet.append(Vector3(at.x + rng.randf_range(-0.5, 0.5), 100.0, at.z + rng.randf_range(-0.5, 0.5)))
		vel.append(Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
	var same := true
	var why := ""
	var pushed := 0
	for i in range(100):
		var na := a.push_from(feet[i], vel[i], 0.35, 1.8)
		var nb := b.push_from_unfiltered(feet[i] + Vector3(1000, 0, 0), vel[i], 0.35, 1.8)
		pushed += na
		if na != nb:
			why += "count %d: %d vs %d; " % [i, na, nb]
		same = same and na == nb
	for i in range(a.count()):
		var ta := a.toys[i]
		var tb := b.toys[i]
		if ta.body == null:
			continue
		# Which toys were pushed, not their velocities: two physics worlds settle a hair apart.
		if ta.touched_at != tb.touched_at:
			why += "toy %d %s; " % [i, ta.kind]
		same = same and ta.touched_at == tb.touched_at
	_check(same and pushed > 0, "100 players over 300 toys: the same count and the same toys moved as the unfiltered path", "%d pushes %s" % [pushed, why.left(300)])
	for _i in range(120):
		a.advance(1.0 / 60.0)
		await get_tree().physics_frame
	var asleep := 0
	for t in a.toys:
		if t.body != null and t.body.sleeping:
			asleep += 1
	_check(a.count() == 300 and asleep > 0, "advance over settled sleepers keeps every toy and sleeps some", "%d asleep of %d" % [asleep, a.count()])
	var t0 := Time.get_ticks_usec()
	for i in range(100):
		var _n := a.push_from(feet[i], vel[i], 0.35, 1.8)
	var filtered := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in range(100):
		var _n := a.push_from_unfiltered(feet[i], vel[i], 0.35, 1.8)
	var plain := Time.get_ticks_usec() - t0
	print("BENCH push_from 100 players x 300 toys: filtered %.2f ms, unfiltered %.2f ms (%.2fx)" % [filtered / 1000.0, plain / 1000.0, plain / maxf(filtered, 1.0)])
	_check(filtered <= plain * 1.25, "the prefiltered push_from is not slower than the unfiltered one (timing noise allowed)", "%d us vs %d us" % [filtered, plain])
	made_a[0].queue_free()
	made_b[0].queue_free()
	_done()


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
	var pit_id := pit.get_instance_id()
	var n_pit := toys.count()
	for _i in range(240):
		toys.advance(1.0 / 60.0)
		await get_tree().physics_frame
	_check(lost_seen[0] == 1 and toys.count() == n_pit - 1 and not toys.toys.any(func(t: DotPropToy) -> bool: return t.get_instance_id() == pit_id),
		"a crate dropped over a pit is lost after fall_limit and removed (LostMode.REMOVE)", "%d lost, %d toys of %d" % [lost_seen[0], toys.count(), n_pit])
	toys.lost_mode = DotPropToyBox.LostMode.HOME
	toys.fall_limit = 0.0
	await _toys_ride(toys, floor_body)
	await _toys_play(toys)
	await _toys_shot(toys, floor_body)
	await _toys_reset(toys, floor_body)


func _toys_ride(toys: DotPropToyBox, floor_body: Node3D) -> void:
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


func _toys_play(toys: DotPropToyBox) -> void:
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


func _toys_shot(toys: DotPropToyBox, floor_body: Node3D) -> void:
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


func _toys_reset(toys: DotPropToyBox, floor_body: Node3D) -> void:
	var ball := toys.toy(_index(toys, "beach_ball"))
	var football := toys.toy(_index(toys, "football"))
	var lamp := toys.toy(_index(toys, "lamp_post"))
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


## A toy freed outside the box (its holder freed, a game's cleanup) leaves a dead entry in `toys`.
func _test_toys_freed() -> void:
	_section("a toy freed behind the box's back does not break the box")
	var made := _toy_world(true)
	var toys: DotPropToyBox = made[1]
	var total := toys.count()
	var live_index := 2
	for i in [0, 1, total - 1]:
		toys.toy(i).free()
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var feet := Vector3(0, 100, 0)
	var _a := toys.awake_count()
	toys.advance(0.1)
	var _b := toys.push_from(feet, Vector3.FORWARD, 0.4, 1.8)
	var _c := toys.push_from_unfiltered(feet, Vector3.FORWARD, 0.4, 1.8)
	var _d := toys.stand_on(feet, 80.0)
	var _e := toys.launch_for(feet, Vector3.DOWN)
	var _f := toys.carry_for(feet, 0.1)
	var _g := toys.blast(feet, 50.0, 5.0)
	var _h := toys.toy(0)
	var _i := toys.describe()
	var _j := toys.describe_lines()
	toys.launched(0)
	var _k := toys.use(0, feet, Vector3.FORWARD)
	toys._on_rules_changed()
	toys.reset()
	await _step_physics(2)
	OS.remove_logger(catcher)
	_check(catcher.errors.is_empty(), "every public method skips the freed toys without an engine error", "; ".join(catcher.errors.slice(0, 2)))
	_check(toys.toy(0) == null and toys.toy(live_index) != null, "toy(i) hands back null for a freed one and the toy for a live one")
	_check(toys.describe_lines().size() == total - 3, "the listing leaves the freed toys out", str(toys.describe_lines().size()))
	_check(toys.count() == total, "the live toys keep their indexes", str(toys.count()))
	made[0].free()
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


## A tyre a map hangs a hand above its floor is lowered onto it and then stays still until touched.
func _test_tyre_rest() -> void:
	_section("a placed tyre on flat ground stays put until touched")
	var holder := Node3D.new()
	holder.position = Vector3(0, 100, 0)
	_world.add_child(holder)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	holder.add_child(floor_body)
	var toys := DotPropToyBox.new()
	toys.authoritative = true
	toys.loose_layer = 2
	toys.loose_mask = 1 | 2 | 4
	toys.solid_layer = 4
	toys.solid_mask = 1 | 2
	toys.footprint_layer = 8
	holder.add_child(toys)
	toys.catalogue = DotPropToyCatalogue.stock()
	var built := toys.build([{"toy": "tyre", "at": [3.0, 0.275, 2.0]}, {"toy": "tyre", "at": [6.0, 0.0, 2.0], "yaw": 30}])
	_check(built.ok and toys.count() == 2, "two tyres built", str(built.ok))
	await _step_physics(2)
	var starts: Array[Vector3] = []
	for t in toys.toys:
		starts.append(t.body.global_position)
	await _step_physics(180)
	for i in toys.toys.size():
		var moved: float = toys.toys[i].body.global_position.distance_to(starts[i])
		_check(moved < 0.05, "tyre %d moves %.3f m in three seconds (limit 0.05)" % [i, moved])
	toys.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	_done()


## Loose models become props: a folder, a sidecar, a baked manifest, and what is refused.


## An unguarded call on a freed node can still return a plausible value, so only the error shows it.
class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, _file: String, _line: int, code: String,
			rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtraces: Array) -> void:
		errors.append("%s %s %s" % [code, rationale, function])

extends "props_selftest_toys.gd"

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

const CHECKS := 344

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 41


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
	await _test_toys_prefilter()
	await _test_toy_mirror()
	await _test_toys_freed()
	await _test_rolling()
	await _test_tyre_rest()
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

extends Node

## Shared state and helpers of the props self-test; the tests are in the files that extend this one.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

var _world: Node3D = null


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

	# A 2D prop in the same catalogue on purpose: a DotPropDef says nothing about dimension,
	# so the spawner must pick the right entry point rather than infer one.
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


# Definitions


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


func _scatter_box(count: int) -> Array:
	var made := _toy_world(true)
	var toys: DotPropToyBox = made[1]
	toys.clear()
	var ids := toys.catalogue.ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(count):
		var _t := toys.add_toy(StringName(ids[i % ids.size()]), Vector3(rng.randf_range(-90, 90), 0.5, rng.randf_range(-90, 90)))
	return made

extends Node3D

## Every stock toy on a lawn, rendered: the look no assertion reaches.
##
## [codeblock]
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://examples/toy_gallery.tscn -- --out=res://screenshots/toys.png
## [/codeblock]
##
## `--kick` kicks every usable toy a second before the frame, so the picture shows them moving
## (the beach ball in the air, the swing out, the roundabout turning, the lamp switched).

var _out := "res://screenshots/toys.png"
var _kick := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--kick":
			_kick = true
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	var lawn := MeshInstance3D.new()
	lawn.mesh = DotPropToyLook.box(Vector3(80, 1, 80))
	lawn.material_override = DotPropToyLook.material(Color(0.45, 0.7, 0.4), 0.95)
	lawn.position = Vector3(0, -0.5, 0)
	ground.add_child(lawn)
	add_child(ground)

	var toys := DotPropToyBox.new()
	toys.loose_layer = 2
	toys.loose_mask = 1 | 2 | 4
	toys.solid_layer = 4
	toys.solid_mask = 1 | 2
	add_child(toys)
	toys.catalogue = DotPropToyCatalogue.stock()
	var ids := toys.catalogue.ids()
	var placements: Array = []
	var columns := 6
	for i in ids.size():
		var col := i % columns
		var row := i / columns
		placements.append({"toy": ids[i], "at": [(col - (columns - 1) * 0.5) * 4.2, 0, -row * 5.0], "yaw": 20})
	placements[ids.find("light_switch")]["links"] = [ids.find("lamp_post")]
	var _built := toys.build(placements)

	var camera := Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 9, 13), Vector3(0, 0.6, -5))
	camera.current = true

	for _i in 30:
		await get_tree().physics_frame
	if _kick:
		for t in toys.toys:
			if t.usable():
				var _u := toys.use(t.index, t.global_position + Vector3(0, 1.4, 1.2), Vector3(0.2, -0.2, -1))
		for _i in 40:
			await get_tree().physics_frame
	for _i in 4:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved %s: %s" % [_out, error_string(image.save_png(path))])
	for line in toys.describe_lines():
		print(line)
	get_tree().quit()

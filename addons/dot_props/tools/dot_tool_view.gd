class_name DotToolView
extends Node3D

## The first-person model of a held tool or toy (physics gun, launcher, remover), drawn under the camera.
## It joins `dot_view_model`, so dot-menu's applier hands it `viewmodel_fov` like any other held model.

const CHANNEL := "props.toolview"
## The lens and depth the model is authored at; the same numbers a held weapon model uses.
const REFERENCE_FOV := 90.0
const REFERENCE_DEPTH := 0.55
const MAX_PULL_IN := 0.1

## The camera this draws under, resolved against this node. Left empty it is the parent.
@export var camera_ref: DotNodeRef = null

## Vertical field of view the model is drawn at; 0 draws it under the camera's own lens.
@export var hands_fov: float = 0.0

## A dome on a short body (a launcher) rather than a long barrel.
@export var domed: bool = false

var _kick: float = 0.0
var _camera: Camera3D = null


## Builds a model tinted [param colour] and puts it under [param camera] when one is given.
static func make(colour: Color, is_domed: bool = false, camera: Node = null) -> DotToolView:
	var view := DotToolView.new()
	view.name = "ToolViewModel"
	view.domed = is_domed
	view._build(colour)
	if camera != null:
		camera.add_child(view)
	DotLog.debug(CHANNEL, "built", {"domed": is_domed, "colour": colour.to_html(false)})
	return view


## The vertical field of view that is [param horizontal] degrees across a 4:3 frame.
static func vertical_from_horizontal_4_3(horizontal: float) -> float:
	var half := deg_to_rad(clampf(horizontal, 20.0, 170.0) * 0.5)
	return rad_to_deg(2.0 * atan(tan(half) * 3.0 / 4.0))


## How much X and Y are scaled to draw at [param hands] degrees under a [param camera]-degree lens.
static func lens_scale(camera: float, hands: float) -> float:
	if hands <= 1.0 or hands >= 179.0 or camera <= 1.0 or camera >= 179.0:
		return 1.0
	return tan(deg_to_rad(camera) * 0.5) / tan(deg_to_rad(hands) * 0.5)


## The same horizontal-at-4:3 convention as a held weapon model, so the two agree.
func set_hands_fov_at_4_3(horizontal: float) -> void:
	hands_fov = vertical_from_horizontal_4_3(horizontal)


## A short recoil, for a tool that was just used.
func kick() -> void:
	_kick = 1.0


func describe() -> Dictionary:
	return {"hands_fov": hands_fov, "domed": domed, "kick": _kick, "camera": _camera != null}


func _init() -> void:
	add_to_group(&"dot_view_model")


func _process(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 6.0)
	var camera := _find_camera()
	var k := lens_scale(camera.fov, hands_fov) if camera != null else 1.0
	scale = Vector3(k, k, 1.0)
	var size := lens_scale(REFERENCE_FOV, hands_fov) if camera != null else 1.0
	position = Vector3(0.0, 0.0, -maxf((size - 1.0) * REFERENCE_DEPTH, -MAX_PULL_IN) + _kick * 0.05)


func _find_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	_camera = camera_ref.resolve_or_null(self, CHANNEL) as Camera3D if camera_ref != null else get_parent() as Camera3D
	return _camera


func _build(colour: Color) -> void:
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.position = Vector3(0.2, -0.22, -0.5)
	grip.rotation_degrees = Vector3(0.0, 6.0, 0.0)
	add_child(grip)
	var body := _box(Vector3(0.07, 0.08, 0.26), colour)
	grip.add_child(body)
	if not domed:
		var barrel := _box(Vector3(0.05, 0.05, 0.22), colour.darkened(0.35))
		barrel.position = Vector3(0.0, 0.01, -0.24)
		grip.add_child(barrel)
	else:
		var dome := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		dome.mesh = sphere
		dome.material_override = _material(colour.lightened(0.2))
		dome.position = Vector3(0.0, 0.0, -0.17)
		grip.add_child(dome)
	var handle := _box(Vector3(0.045, 0.1, 0.05), colour.darkened(0.5))
	handle.position = Vector3(0.0, -0.08, 0.08)
	grip.add_child(handle)


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour)
	return mesh


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	return m

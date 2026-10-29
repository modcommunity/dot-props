extends Node3D

## The half of [DotPropToy] that builds it: the state it keeps and the bodies, joints and looks each
## kind is made of. No class_name, so [DotPropToy] reaches it by relative path.

## A sound to play at a point: a bounce, a knock, a press. [param strength] is 0..1.
signal sound(id: StringName, at: Vector3, strength: float)

## The definition this was built from ([method DotPropToyCatalogue.get_def]).
var def: Dictionary = {}
var kind: StringName = &""

## Where it is in its box, and what its placement said.
var index: int = -1
var placement: Dictionary = {}

## Whether this end simulates it (a server, an offline game) or draws a replicated state.
var authoritative: bool = true

## Whether to build meshes, lights and particles. False on a dedicated server.
var draw: bool = true

## The toys a switch turns on and off with itself, by index in the box.
var links: PackedInt32Array = PackedInt32Array()

## A switchable toy's state: a lamp lit, a fountain running, a switch down.
var on: bool = false

## Uses so far, wrapping at 256: a press, a honk, a bounce. What a client hears change.
var count: int = 0

## The moving part, or null for a toy that does not move (a pad, a lamp).
var body: RigidBody3D = null

## The parts that never move (a frame, a base, a basin), or null.
var fixed: StaticBody3D = null

## The moving part's transform at rest, in world space: where a reset puts it.
var rest: Transform3D = Transform3D.IDENTITY

## The box's clock when somebody last pushed, used or hit it: the sleep cap puts the longest
## untouched to sleep first.
var touched_at: float = -INF

## Seconds the moving part has been at rest while awake, for [member DotPropToyBox.sleep_after].
var still_for: float = 0.0

## Collision: loose kinds go on `loose`, everything else (and every fixed part) on `solid`.
var layers: Dictionary = {}

## Whether a person can push this kind at all (a loose kind or a roundabout); the box skips the rest.
var pushable: bool = false

var _size: Vector3 = Vector3.ONE
var _radius: float = 0.25
## Where on the moving part a knock is heard from (a see-saw's end, not its pivot).
var _sense_local: Vector3 = Vector3.ZERO
var _last_sense: Vector3 = Vector3.INF
var _last_velocity: Vector3 = Vector3.ZERO
var _sound_wait: float = 0.0
var _heard_count: int = 0

var _visual: Node3D = null
var _cap: MeshInstance3D = null
var _bulb: MeshInstance3D = null
var _light: OmniLight3D = null
var _jets: CPUParticles3D = null
var _water: MeshInstance3D = null
var _flourish: Node3D = null

func _colour(i: int) -> Color:
	var list: Array = def.get("colours", [])
	return list[i % list.size()] if not list.is_empty() else Color.WHITE


func _mat(i: int, rough: float = 0.75) -> StandardMaterial3D:
	return DotPropToyLook.material(_colour(i), rough)


## The moving part: a rigid body at [param at] (this toy's frame), on the loose or the solid
## layer, its mass and material from the definition before it enters the tree.
## Half the toy's width: how far from its middle it can touch.
func radius() -> float:
	return _radius


func _make_body(at: Transform3D, loose: bool) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "Body"
	b.mass = maxf(float(def.get("mass", 1.0)), 0.05)
	b.linear_damp = float(def.get("damp", 0.1))
	b.angular_damp = float(def.get("angular_damp", 0.2))
	var surface := PhysicsMaterial.new()
	surface.bounce = float(def.get("bounce", 0.3))
	surface.friction = float(def.get("friction", 0.6))
	b.physics_material_override = surface
	b.can_sleep = true
	b.collision_layer = int(layers.get("loose_layer" if loose else "solid_layer", 1))
	b.collision_mask = int(layers.get("loose_mask" if loose else "solid_mask", 1))
	b.transform = at
	b.set_meta(&"dot_prop_toy", self)
	add_child(b)
	body = b
	return b


func _make_fixed() -> StaticBody3D:
	if fixed == null:
		fixed = StaticBody3D.new()
		fixed.name = "Fixed"
		fixed.collision_layer = int(layers.get("solid_layer", 1))
		fixed.collision_mask = 0
		fixed.set_meta(&"dot_prop_toy", self)
		add_child(fixed)
	return fixed


static func _shape(owner_body: CollisionObject3D, shape: Shape3D, at: Transform3D = Transform3D.IDENTITY) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = at
	owner_body.add_child(node)
	return node


static func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


## A loose cylinder (a pin, a barrel, a tyre) collides as a twelve-sided hull: Godot's own
## cylinder shape let a tyre stood at an angle sink through a floor in its first second.
static func _hull_cylinder(radius: float, height: float) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		for y: float in [-height * 0.5, height * 0.5]:
			points.append(Vector3(cos(a) * radius, y, sin(a) * radius))
	var s := ConvexPolygonShape3D.new()
	s.points = points
	return s


static func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


## Meshes for a part: under the body when it moves (so they move with it), else the look.
func _look_on(part: Node3D) -> Node3D:
	if not draw:
		return null
	var holder := Node3D.new()
	holder.name = "Look"
	part.add_child(holder)
	return holder


func _build_ball() -> void:
	var r := _size.x * 0.5
	_radius = r
	var b := _make_body(Transform3D(Basis.IDENTITY, Vector3(0, r, 0)), true)
	var shape := SphereShape3D.new()
	shape.radius = r
	var _s := _shape(b, shape)
	# A small fast ball would pass through a thin wall between two ticks.
	b.continuous_cd = r < 0.2
	var look := _look_on(b)
	if look == null:
		return
	var colours: Array = def.get("colours", [])
	if colours.size() >= 3:
		var _m := DotPropToyLook.add(look, DotPropToyLook.painted_sphere(r, colours), DotPropToyLook.painted())
	elif float(def.get("mass", 1.0)) > 3.0:
		# Heavy and polished, with its three holes.
		var _m := DotPropToyLook.add(look, DotPropToyLook.sphere(r, 20), _mat(0, 0.2))
		for i in 3:
			var at := Vector3(0.22 * (i - 1) * r, 0.55 * r, 0.8 * r + (0.05 * r if i == 1 else 0.0))
			var _h := DotPropToyLook.add(look, DotPropToyLook.sphere(r * 0.13, 8), _mat(1), Transform3D(Basis.IDENTITY, at))
	else:
		var _m := DotPropToyLook.add(look, DotPropToyLook.painted_sphere(r, colours if colours.size() >= 2 else [_colour(0), _colour(0)], true), DotPropToyLook.painted())


func _build_pin() -> void:
	var r := _size.x * 0.5
	var h := _size.y
	_radius = r
	var b := _make_body(Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), true)
	var _s := _shape(b, _hull_cylinder(r, h))
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0, -h * 0.15, 0)
	var look := _look_on(b)
	if look == null:
		return
	var _belly := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 0.6, h * 0.55, r), _mat(0, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, -h * 0.22, 0)))
	var _neck := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 0.45, h * 0.3, r * 0.95), _mat(0, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.18, 0)))
	var _band := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 0.5, h * 0.06), _mat(1, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.14, 0)))
	var _head := DotPropToyLook.add(look, DotPropToyLook.sphere(r * 0.6, 12), _mat(0, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.38, 0)))


func _build_barrel() -> void:
	var r := _size.x * 0.5
	var h := _size.y
	_radius = r
	var b := _make_body(Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), true)
	var _s := _shape(b, _hull_cylinder(r, h))
	var look := _look_on(b)
	if look == null:
		return
	var _staves := DotPropToyLook.add(look, DotPropToyLook.cylinder(r, h, -1.0, 14), _mat(0))
	for y: float in [-0.32, 0.32]:
		var _hoop := DotPropToyLook.add(look, DotPropToyLook.torus(r * 0.97, r * 1.04), _mat(1, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, h * y, 0)))
	var _lid := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 0.92, 0.01), DotPropToyLook.material(_colour(0).darkened(0.25)), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)))


func _build_crate() -> void:
	_radius = maxf(_size.x, _size.z) * 0.5
	var b := _make_body(Transform3D(Basis.IDENTITY, Vector3(0, _size.y * 0.5, 0)), true)
	var _s := _shape(b, _box_shape(_size))
	var look := _look_on(b)
	if look == null:
		return
	var _planks := DotPropToyLook.add(look, DotPropToyLook.box(_size), _mat(0))
	var _band := DotPropToyLook.add(look, DotPropToyLook.box(Vector3(_size.x + 0.01, _size.y * 0.18, _size.z + 0.01)), _mat(1, 0.9))


func _build_tyre() -> void:
	var r := _size.x * 0.5
	var w := _size.y
	_radius = r
	var b := _make_body(Transform3D(Basis.IDENTITY, Vector3(0, r, 0)), true)
	# The axle along the toy's x: stood on its tread, it rolls along z.
	var axle := Basis(Vector3.BACK, PI * 0.5)
	var _s := _shape(b, _hull_cylinder(r, w), Transform3D(axle, Vector3.ZERO))
	var look := _look_on(b)
	if look == null:
		return
	var _rubber := DotPropToyLook.add(look, DotPropToyLook.torus(r * 0.5, r), _mat(0, 0.9), Transform3D(axle.scaled(Vector3(1.0, w / (r * 0.5), 1.0)), Vector3.ZERO))
	var _hub := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 0.5, w * 0.5), _mat(1, 0.4), Transform3D(axle, Vector3.ZERO))


func _build_bag() -> void:
	var r := _size.x * 0.5
	var h := _size.y
	_radius = r
	var top := h + 1.55
	var f := _make_fixed()
	var post_at := Vector3(-0.85, 0, 0)
	var _post := _shape(f, _box_shape(Vector3(0.14, top + 0.1, 0.14)), Transform3D(Basis.IDENTITY, post_at + Vector3(0, (top + 0.1) * 0.5, 0)))
	var _foot := _shape(f, _box_shape(Vector3(0.7, 0.08, 0.7)), Transform3D(Basis.IDENTITY, post_at + Vector3(0, 0.04, 0)))
	var chain := 0.35
	var hang := chain + h * 0.5
	var b := _make_driven(Vector3(0, top, 0), Vector3(0, -hang, 0), true)
	var capsule := CapsuleShape3D.new()
	capsule.radius = r
	capsule.height = h
	var _s := _shape(b, capsule)
	if draw:
		var steel := _mat(1, 0.4)
		var _p := DotPropToyLook.rod(_visual, post_at, post_at + Vector3(0, top + 0.1, 0), 0.07, steel)
		var _a := DotPropToyLook.rod(_visual, post_at + Vector3(0, top + 0.05, 0), Vector3(0.05, top + 0.05, 0), 0.05, steel)
		var _ft := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(0.7, 0.08, 0.7)), steel, Transform3D(Basis.IDENTITY, post_at + Vector3(0, 0.04, 0)))
		var look := _look_on(b)
		var _c := DotPropToyLook.rod(look, Vector3(0, h * 0.5, 0), Vector3(0, hang, 0), 0.015, steel)
		var _bag := DotPropToyLook.add(look, DotPropToyLook.cylinder(r, h, -1.0, 14), _mat(0, 0.6))
		var _cap := DotPropToyLook.add(look, DotPropToyLook.cylinder(r * 1.02, 0.12), steel, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5 - 0.06, 0)))


func _build_swing() -> void:
	var w := _size.x
	var top := _size.y
	var seat := Vector3(0.6, 0.06, _size.z * 0.5)
	var rope := top - 0.5
	var f := _make_fixed()
	for side: float in [-1.0, 1.0]:
		for leg: float in [-1.0, 1.0]:
			var foot := Vector3(side * w * 0.5, 0, leg * 0.75)
			var head := Vector3(side * w * 0.5, top, 0)
			var mid := (foot + head) * 0.5
			var _leg := _shape(f, _box_shape(Vector3(0.1, foot.distance_to(head), 0.1)),
				Transform3D(Basis(Vector3.RIGHT, -leg * atan2(0.75, top)), mid))
	var _bar := _shape(f, _box_shape(Vector3(w + 0.1, 0.1, 0.1)), Transform3D(Basis.IDENTITY, Vector3(0, top, 0)))
	var b := _make_driven(Vector3(0, top, 0), Vector3(0, -rope, 0), true)
	_radius = 0.32
	var _s := _shape(b, _box_shape(seat))
	if draw:
		var frame := _mat(0, 0.5)
		for side: float in [-1.0, 1.0]:
			for leg: float in [-1.0, 1.0]:
				var _l := DotPropToyLook.rod(_visual, Vector3(side * w * 0.5, 0, leg * 0.75), Vector3(side * w * 0.5, top, 0), 0.05, frame)
		var _b := DotPropToyLook.rod(_visual, Vector3(-w * 0.5 - 0.05, top, 0), Vector3(w * 0.5 + 0.05, top, 0), 0.06, frame)
		var look := _look_on(b)
		var _seat := DotPropToyLook.add(look, DotPropToyLook.box(seat), _mat(1, 0.6))
		for side: float in [-1.0, 1.0]:
			var _r := DotPropToyLook.rod(look, Vector3(side * seat.x * 0.45, 0, 0), Vector3(side * seat.x * 0.45, rope, 0), 0.012, _mat(2))


func _build_seesaw() -> void:
	var length := _size.x
	var pivot := _size.y
	var width := _size.z
	var f := _make_fixed()
	var _base := _shape(f, _box_shape(Vector3(0.3, pivot - 0.05, width * 0.6)), Transform3D(Basis.IDENTITY, Vector3(0, (pivot - 0.05) * 0.5, 0)))
	var b := _make_driven(Vector3(0, pivot, 0), Vector3.ZERO, false)
	var _s := _shape(b, _box_shape(Vector3(length, 0.1, width)), Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)))
	_radius = length * 0.5
	_sense_local = Vector3(length * 0.5, 0, 0)
	# An end on the ground: the plank's half-length over the pivot's height, less the plank.
	_limit = asin(clampf((pivot - 0.02) / (length * 0.5), 0.0, 1.0))
	if draw:
		var _pv := DotPropToyLook.add(_visual, _prism(Vector3(0.6, pivot, width * 0.7)), _mat(1), Transform3D(Basis.IDENTITY, Vector3(0, pivot * 0.5, 0)))
		var look := _look_on(b)
		var _p := DotPropToyLook.add(look, DotPropToyLook.box(Vector3(length, 0.1, width)), _mat(0, 0.6), Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)))
		for side: float in [-1.0, 1.0]:
			var x := side * (length * 0.5 - 0.45)
			var _h := DotPropToyLook.rod(look, Vector3(x, 0.1, -width * 0.35), Vector3(x, 0.45, -width * 0.35), 0.025, _mat(1, 0.4))
			var _h2 := DotPropToyLook.rod(look, Vector3(x, 0.1, width * 0.35), Vector3(x, 0.45, width * 0.35), 0.025, _mat(1, 0.4))
			var _t := DotPropToyLook.rod(look, Vector3(x, 0.45, -width * 0.35), Vector3(x, 0.45, width * 0.35), 0.025, _mat(1, 0.4))


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


func _build_spinner() -> void:
	var r := _size.x * 0.5
	var deck := _size.y
	var f := _make_fixed()
	var _hub := _shape(f, _cyl_shape(0.15, deck - 0.06), Transform3D(Basis.IDENTITY, Vector3(0, (deck - 0.06) * 0.5, 0)))
	var b := _make_driven(Vector3(0, deck, 0), Vector3.ZERO, false)
	var _s := _shape(b, _cyl_shape(r, 0.1), Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0)))
	_radius = r
	_sense_local = Vector3(r, 0, 0)
	if draw:
		var look := _look_on(b)
		# Eight sectors in the first two colours, painted on one disc.
		var _deck := DotPropToyLook.add(look, DotPropToyLook.painted_disc(r, 0.1, [_colour(0), _colour(1)], 8), DotPropToyLook.painted(), Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0)))
		var rail := _mat(2, 0.4)
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI * 0.25
			var foot := Vector3(cos(a), 0, sin(a)) * r * 0.8
			var _u := DotPropToyLook.rod(look, foot, foot + Vector3(0, 0.75, 0), 0.03, rail)
			var _i := DotPropToyLook.rod(look, foot + Vector3(0, 0.75, 0), Vector3(0, 0.95, 0), 0.025, rail)
		var _top := DotPropToyLook.add(look, DotPropToyLook.sphere(0.08, 8), rail, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)))
		var _h := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(0.15, deck - 0.06), rail, Transform3D(Basis.IDENTITY, Vector3(0, (deck - 0.06) * 0.5, 0)))


func _build_wobble() -> void:
	var height := _size.y
	var f := _make_fixed()
	var _post := _shape(f, _cyl_shape(0.12, height - 0.12), Transform3D(Basis.IDENTITY, Vector3(0, (height - 0.12) * 0.5, 0)))
	var b := _make_driven(Vector3(0, height, 0), Vector3.ZERO, false)
	var _s := _shape(b, _box_shape(Vector3(_size.x, 0.15, _size.z)))
	_radius = maxf(_size.x, _size.z) * 0.5
	_sense_local = Vector3(_size.x * 0.5, 0, 0)
	_limit = WOBBLE_MOST
	if draw:
		var _p := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(0.12, height - 0.12), _mat(1, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, (height - 0.12) * 0.5, 0)))
		var look := _look_on(b)
		var _top := DotPropToyLook.add(look, DotPropToyLook.box(Vector3(_size.x, 0.15, _size.z)), _mat(0, 0.6))
		var _edge := DotPropToyLook.add(look, DotPropToyLook.box(Vector3(_size.x * 1.02, 0.05, _size.z * 1.02)), _mat(1, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, -0.07, 0)))


# Driven kinds are an angle or two integrated here and a kinematic body posed from them, not
# joints: a hinge between a static frame and a body flung a swing away, and costs the server a
# solver iteration per tick.

## How hard the sprung pivot rights a wobbly platform, per radian, and how much it damps
## (per second, of its spin); the most it tilts.
const WOBBLE_SPRING := 4500.0
const WOBBLE_DAMP := 9.0
const WOBBLE_MOST := 0.3

## The pivot in this toy's frame, and the body's origin from it at rest.
var _pivot: Vector3 = Vector3.ZERO
var _hang: Vector3 = Vector3.ZERO
## Angles about this toy's own x, y and z (radians), and how fast each turns.
var _angle: Vector3 = Vector3.ZERO
var _spin: Vector3 = Vector3.ZERO
## Torque from people's weight this tick, in this toy's frame; used and cleared each tick.
var _torque: Vector3 = Vector3.ZERO
## The most an angle goes (a see-saw's end on the ground, a platform's tilt). 0 is none.
var _limit: float = 0.0
var _driven: bool = false

## Gravity a pendulum swings under, m/s²; the box sets it.
var gravity: float = 20.0


func _make_driven(pivot: Vector3, hang: Vector3, loose: bool) -> RigidBody3D:
	_pivot = pivot
	_hang = hang
	_driven = true
	var b := _make_body(Transform3D(Basis.IDENTITY, pivot + hang), loose)
	# Moved by this script on every end, never by the solver.
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	return b


func _build_bouncer() -> void:
	var r := _size.x * 0.5
	var top := _size.y
	var f := _make_fixed()
	var _bed := _shape(f, _cyl_shape(r, 0.08), Transform3D(Basis.IDENTITY, Vector3(0, top - 0.04, 0)))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var _leg := _shape(f, _box_shape(Vector3(0.08, top, 0.08)), Transform3D(Basis.IDENTITY, Vector3(cos(a) * r * 0.9, top * 0.5, sin(a) * r * 0.9)))
	if draw:
		var _legs := Node3D.new()
		_visual.add_child(_legs)
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI * 0.25
			var _l := DotPropToyLook.rod(_visual, Vector3(cos(a) * r * 0.9, 0, sin(a) * r * 0.9), Vector3(cos(a) * r * 0.9, top, sin(a) * r * 0.9), 0.04, _mat(0, 0.4))
		var _rim := DotPropToyLook.add(_visual, DotPropToyLook.torus(r * 0.86, r), _mat(1, 0.6), Transform3D(Basis.IDENTITY, Vector3(0, top, 0)))
		_flourish = DotPropToyLook.add(_visual, DotPropToyLook.cylinder(r * 0.87, 0.03, -1.0, 24), _mat(0, 0.9), Transform3D(Basis.IDENTITY, Vector3(0, top - 0.02, 0)))


func _build_pad() -> void:
	var f := _make_fixed()
	var _slab := _shape(f, _box_shape(_size), Transform3D(Basis.IDENTITY, Vector3(0, _size.y * 0.5, 0)))
	if draw:
		var _base := DotPropToyLook.add(_visual, DotPropToyLook.box(_size), _mat(0, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, _size.y * 0.5, 0)))
		# An arrow along the way it throws (+z), lying on the top.
		var arrow := DotPropToyLook.material(_colour(1), 0.5, 0.6)
		var _shaft := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(_size.x * 0.18, 0.02, _size.z * 0.45)), arrow, Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.01, -_size.z * 0.12)))
		_flourish = DotPropToyLook.add(_visual, _prism(Vector3(_size.x * 0.55, _size.z * 0.3, 0.02)), arrow,
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, _size.y + 0.01, _size.z * 0.22)))


func _build_post(height: float, width: float) -> void:
	var f := _make_fixed()
	var _post := _shape(f, _box_shape(Vector3(width, height, width)), Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)))
	if draw:
		var _p := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(width, height, width)), _mat(0, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)))


func _build_switch() -> void:
	_build_post(_size.y, _size.x)
	# The button is what a person aims the use key at: solid, over the post's top.
	var _button := _shape(fixed, _box_shape(Vector3(_size.x * 1.3, 0.16, _size.z * 1.3)), Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.08, 0)))
	if draw:
		var _plate := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(_size.x * 1.3, 0.04, _size.z * 1.3)), _mat(0, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.02, 0)))
		_cap = DotPropToyLook.add(_visual, DotPropToyLook.cylinder(_size.x * 0.4, 0.08), _mat(1, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.08, 0)))


func _build_lamp() -> void:
	var f := _make_fixed()
	var _post := _shape(f, _box_shape(Vector3(0.14, _size.y, 0.14)), Transform3D(Basis.IDENTITY, Vector3(0, _size.y * 0.5, 0)))
	if draw:
		var _p := DotPropToyLook.rod(_visual, Vector3.ZERO, Vector3(0, _size.y, 0), 0.06, _mat(0, 0.4))
		var _foot := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(0.16, 0.12), _mat(0, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)))
		var _hood := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(0.08, 0.16, 0.24), _mat(0, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.1, 0)))
		_bulb = DotPropToyLook.add(_visual, DotPropToyLook.sphere(0.13, 12), _mat(1), Transform3D(Basis.IDENTITY, Vector3(0, _size.y - 0.04, 0)))
		_light = OmniLight3D.new()
		_light.light_color = _colour(1)
		_light.omni_range = 7.0
		_light.light_energy = 1.4
		_light.shadow_enabled = false
		_light.position = Vector3(0, _size.y - 0.15, 0)
		_visual.add_child(_light)


func _build_fountain() -> void:
	var r := _size.x * 0.5
	var h := _size.y
	var f := _make_fixed()
	var _basin := _shape(f, _cyl_shape(r, h), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)))
	var _spout := _shape(f, _cyl_shape(0.1, 0.6), Transform3D(Basis.IDENTITY, Vector3(0, h + 0.3, 0)))
	if draw:
		var stone := _mat(0, 0.9)
		var _wall := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(r, h, -1.0, 24), stone, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)))
		_water = DotPropToyLook.add(_visual, DotPropToyLook.cylinder(r * 0.88, 0.02, -1.0, 24), DotPropToyLook.material(_colour(1), 0.1), Transform3D(Basis.IDENTITY, Vector3(0, h + 0.005, 0)))
		var _col := DotPropToyLook.add(_visual, DotPropToyLook.cylinder(0.1, 0.6, 0.07), stone, Transform3D(Basis.IDENTITY, Vector3(0, h + 0.3, 0)))
		_jets = CPUParticles3D.new()
		_jets.amount = 90
		_jets.lifetime = 1.0
		_jets.position = Vector3(0, h + 0.62, 0)
		_jets.direction = Vector3.UP
		_jets.spread = 14.0
		_jets.initial_velocity_min = 3.2
		_jets.initial_velocity_max = 3.8
		_jets.gravity = Vector3(0, -9.8, 0)
		_jets.scale_amount_min = 0.6
		_jets.scale_amount_max = 1.0
		var drop := DotPropToyLook.sphere(0.035, 6)
		drop.material = DotPropToyLook.material(_colour(1).lightened(0.35), 0.1, 0.4)
		_jets.mesh = drop
		_visual.add_child(_jets)


func _build_horn() -> void:
	_build_post(_size.y, 0.14)
	if draw:
		var brass := _mat(1, 0.3)
		_flourish = DotPropToyLook.add(_visual, DotPropToyLook.cylinder(_size.x * 0.45, _size.z * 1.1, 0.05, 16), brass,
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, _size.y + 0.05, _size.z * 0.4)))
		var _bulb_ := DotPropToyLook.add(_visual, DotPropToyLook.sphere(0.12, 10), DotPropToyLook.material(Color(0.12, 0.12, 0.12)), Transform3D(Basis.IDENTITY, Vector3(0, _size.y + 0.05, -0.18)))


func _build_bell() -> void:
	var w := _size.x
	var top := _size.y
	var f := _make_fixed()
	for side: float in [-1.0, 1.0]:
		var _p := _shape(f, _box_shape(Vector3(0.14, top, 0.14)), Transform3D(Basis.IDENTITY, Vector3(side * w * 0.5, top * 0.5, 0)))
	var _bar := _shape(f, _box_shape(Vector3(w + 0.14, 0.14, 0.14)), Transform3D(Basis.IDENTITY, Vector3(0, top, 0)))
	if draw:
		var wood := _mat(0, 0.8)
		for side: float in [-1.0, 1.0]:
			var _p := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(0.14, top, 0.14)), wood, Transform3D(Basis.IDENTITY, Vector3(side * w * 0.5, top * 0.5, 0)))
		var _b := DotPropToyLook.add(_visual, DotPropToyLook.box(Vector3(w + 0.14, 0.14, 0.14)), wood, Transform3D(Basis.IDENTITY, Vector3(0, top, 0)))
		_flourish = Node3D.new()
		_flourish.position = Vector3(0, top - 0.07, 0)
		_visual.add_child(_flourish)
		var _bell := DotPropToyLook.add(_flourish, DotPropToyLook.cylinder(0.3, 0.42, 0.13, 16), _mat(1, 0.25), Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)))
		var _rope := DotPropToyLook.rod(_flourish, Vector3(0, -0.5, 0), Vector3(0, -1.2, 0), 0.015, DotPropToyLook.material(Color(0.8, 0.75, 0.6)))


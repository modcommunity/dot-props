class_name DotPropToy
extends Node3D

## One toy on a map, built from a [DotPropToyCatalogue] definition by a [DotPropToyBox]: its
## bodies, its joints, how it is drawn, and what a push, a use, a shot or a person standing on
## it does to it.
##
## [b]The server's physics, a client's picture.[/b] On the authoritative end the moving part is
## a real [RigidBody3D] (with its joint or its axis locks); on a client it is the same body
## frozen kinematic and posed from the replicated state ([method show_state]), so a person
## standing on a see-saw on a client stands on the plank the server tipped. Godot's rigid-body
## solver is not the same on two machines, so nothing here is predicted (dot-props'
## spawning.md).
##
## [b]A person is not a rigid body.[/b] A character motor slides along a rigid body without
## pushing it, so what a person does to a toy is said by the game every tick:
## [method push_from] (walking into it), [method stand_on] (weight on a plank), [method use]
## (the use key), [method hit] (a shot). The loose kinds are on a layer people do not collide
## with at all, so a ball rolls away from a person's shins instead of being a wall in the way.

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

## Collision: loose kinds go on `loose`, everything else (and every fixed part) on `solid`.
var layers: Dictionary = {}

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


## Builds it under this node, which is already in the tree and placed. [param p_layers] holds
## `loose_layer`, `loose_mask`, `solid_layer`, `solid_mask` (bits; the game's layout's).
func build(p_def: Dictionary, p_placement: Dictionary, p_layers: Dictionary) -> void:
	def = p_def
	placement = p_placement
	layers = p_layers
	kind = StringName(def.get("kind", &"ball"))
	_size = def.get("size", Vector3.ONE)
	on = bool(placement.get("on", def.get("on", false)))
	for raw: Variant in placement.get("links", []):
		links.append(int(raw))

	if draw:
		_visual = Node3D.new()
		_visual.name = "Look"
		add_child(_visual)

	match kind:
		&"ball": _build_ball()
		&"pin": _build_pin()
		&"barrel": _build_barrel()
		&"tyre": _build_tyre()
		&"bag": _build_bag()
		&"swing": _build_swing()
		&"seesaw": _build_seesaw()
		&"spinner": _build_spinner()
		&"wobble": _build_wobble()
		&"bouncer": _build_bouncer()
		&"pad": _build_pad()
		&"switch": _build_switch()
		&"lamp": _build_lamp()
		&"fountain": _build_fountain()
		&"horn": _build_horn()
		&"bell": _build_bell()

	if body != null:
		rest = body.global_transform
		if not authoritative and not _driven:
			# Drawn, never simulated: posed from snapshots, still something to stand on.
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			body.freeze = true
	_show_on()


# --- What the kinds build ---------------------------------------------------------

func _colour(i: int) -> Color:
	var list: Array = def.get("colours", [])
	return list[i % list.size()] if not list.is_empty() else Color.WHITE


func _mat(i: int, rough: float = 0.75) -> StandardMaterial3D:
	return DotPropToyLook.material(_colour(i), rough)


## The moving part: a rigid body at [param at] (this toy's frame), on the loose or the solid
## layer, its mass and material from the definition before it enters the tree.
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


# --- The driven kinds ---------------------------------------------------------------
#
# A swing, a punching bag, a see-saw, a wobbly platform and a roundabout each move about one
# fixed point, so each is an angle or two and a spin, integrated here, and a kinematic body
# posed from them. Not joints: Godot's own hinge and pin joints blew a swing pushed at an angle
# to its bar off to a thousand kilometres within half a second (2026-10-12), and a joint
# between a static frame and a body is a solver iteration a server pays for every tick. An
# angle is cheap, cannot drift off its pivot, and is the same on every machine that runs it.

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


## Which of the angles this kind turns through.
func _axes() -> Vector3:
	match kind:
		&"swing": return Vector3(1, 0, 0)
		&"seesaw": return Vector3(0, 0, 1)
		&"spinner": return Vector3(0, 1, 0)
		&"bag", &"wobble": return Vector3(1, 0, 1)
	return Vector3.ZERO


func _turn() -> Basis:
	return Basis(Vector3.UP, _angle.y) * Basis(Vector3.RIGHT, _angle.x) * Basis(Vector3.BACK, _angle.z)


func _pose() -> void:
	var turn := _turn()
	body.transform = Transform3D(turn, _pivot + turn * _hang)


func _pivot_global() -> Vector3:
	return to_global(_pivot)


## A change of velocity [param dv] at [param point] (world space), turned into the spins this
## kind allows, as a point mass at that radius would take it.
func _nudge(point: Vector3, dv: Vector3) -> void:
	var r := point - _pivot_global()
	var w := r.cross(dv) / maxf(r.length_squared(), 0.04)
	_spin += (global_basis.inverse() * w) * _axes()


## The velocity of a point on the moving part, in world space.
func _point_velocity(point: Vector3) -> Vector3:
	return (global_basis * _spin).cross(point - _pivot_global())


func _physics_process(delta: float) -> void:
	if not _driven or not authoritative or body == null or delta <= 0.0:
		return
	var torque := _torque
	_torque = Vector3.ZERO
	var accel := Vector3.ZERO
	var damp := float(def.get("angular_damp", 0.2))
	match kind:
		&"swing", &"bag":
			var length := maxf(_hang.length(), 0.2)
			accel = Vector3(-gravity / length * sin(_angle.x), 0, -gravity / length * sin(_angle.z))
		&"seesaw":
			var inertia := maxf(float(def.get("mass", 1.0)) * _size.x * _size.x / 12.0, 0.1)
			accel = torque / inertia
		&"wobble":
			var inertia := maxf(float(def.get("mass", 1.0)) * (_size.x * _size.x + _size.z * _size.z) / 12.0, 0.1)
			accel = (torque - _angle * WOBBLE_SPRING) / inertia
			damp = WOBBLE_DAMP
	var resting := accel.length_squared() < 0.0001 and _spin.length_squared() < 0.0004
	if resting and kind != &"wobble" and kind != &"swing" and kind != &"bag":
		_spin = Vector3.ZERO
		return
	if resting and _angle.length_squared() < 0.00002:
		_spin = Vector3.ZERO
		return
	_spin += (accel - _spin * damp) * delta
	_spin *= _axes()
	_angle += _spin * delta
	if kind == &"swing" or kind == &"bag":
		# Not over the top: a swing that loops is a swing on a rigid bar, which this is not.
		_angle.x = clampf(_angle.x, -1.3, 1.3)
		_angle.z = clampf(_angle.z, -1.3, 1.3)
	if _limit > 0.0:
		for i in [0, 2]:
			if absf(_angle[i]) > _limit:
				_angle[i] = signf(_angle[i]) * _limit
				# An end hits the ground: most of the spin goes, a little comes back.
				_spin[i] = -_spin[i] * 0.2
	if kind == &"spinner":
		_angle.y = fposmod(_angle.y, TAU)
	_pose()


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


# --- What people do to it ---------------------------------------------------------

## Whether the use key does anything to it.
func usable() -> bool:
	return str(def.get("use", "")) != ""


## The prompt for the use key: "Kick the beach ball", "Switch off the lamp".
func prompt() -> String:
	var verb := str(def.get("use", ""))
	if verb == "":
		return ""
	var name_of := str(def.get("name", "toy"))
	if kind in [&"lamp", &"fountain"]:
		return "%s %s the %s" % [verb, "off" if on else "on", name_of]
	return "%s the %s" % [verb, name_of]


## The use key on it, by somebody at [param origin] looking along [param direction]. Server
## side. True when it did something.
func use(origin: Vector3, direction: Vector3) -> bool:
	if not authoritative or not usable():
		return false
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var speed := float(def.get("kick", 0.0))
	match kind:
		&"ball", &"pin", &"barrel", &"tyre":
			var lift := speed * 0.35 if kind == &"ball" and float(def.get("mass", 1.0)) < 3.0 else 0.0
			var at := Vector3(0, _size.y * 0.3, 0) if kind == &"pin" else Vector3.ZERO
			_wake()
			body.apply_impulse((flat * speed + Vector3(0, lift, 0)) * body.mass, at)
		&"swing", &"bag":
			var centre := body.global_position
			_nudge(centre, flat * speed)
		&"seesaw":
			# Down at the end nearer the person, as a hand on it would.
			var local_x := (body.global_transform.affine_inverse() * origin).x
			var end := body.to_global(Vector3(signf(local_x if local_x != 0.0 else 1.0) * _size.x * 0.45, 0, 0))
			_nudge(end, Vector3(0, -speed, 0))
		&"spinner":
			var from_hub := Vector3(origin.x - body.global_position.x, 0, origin.z - body.global_position.z)
			var tangent := Vector3.UP.cross(from_hub.normalized()) if from_hub.length() > 0.01 else flat
			var sense := signf(tangent.dot(flat)) if tangent.dot(flat) != 0.0 else 1.0
			_spin_by(sense * speed)
		&"switch":
			_flip_links()
		&"lamp", &"fountain":
			_set_on(not on)
		&"horn", &"bell":
			pass
		_:
			return false
	_bump_count()
	return true


## `func(index: int) -> bool`: flips the box's toy [param index] and says whether it is on now.
## The box hands every switch this.
var link_fn: Callable = Callable()


func _set_on(value: bool) -> void:
	on = value
	_show_on()


## A switch flips every toy it is linked to (a lamp lit goes out, one out comes on), and shows
## the first one's state itself: down for on. Unlinked, it just flips.
func _flip_links() -> void:
	var now := not on
	if link_fn.is_valid():
		for i in range(links.size()):
			var lit: Variant = link_fn.call(links[i])
			if i == 0 and lit is bool:
				now = lit
	_set_on(now)


## Flipped by a switch. Returns whether it is on now.
func flip() -> bool:
	on = not on
	_bump_count()
	_show_on()
	return on


func _bump_count() -> void:
	count = (count + 1) % 256


## Spins a roundabout so its rim moves at [param rim_speed] faster (or slower, negative).
func _spin_by(rim_speed: float) -> void:
	var r := _size.x * 0.5
	# Its own y and the world's are the same axis: a roundabout is never placed tilted.
	_spin.y = clampf(_spin.y + rim_speed / maxf(r, 0.1), -4.0, 4.0)


## Somebody's capsule (feet at [param feet], [param radius], [param height]) moving at
## [param velocity] this tick: a loose toy in its way is pushed ahead of it, a roundabout's rim
## is turned along. Server side. True when it pushed.
func push_from(feet: Vector3, velocity: Vector3, radius: float, height: float, scale: float = 1.0) -> bool:
	if not authoritative or body == null:
		return false
	if kind == &"spinner":
		return _push_rim(feet, velocity, radius, height)
	if not DotPropToyCatalogue.LOOSE.has(kind):
		return false
	var centre := body.global_position
	var reach := _radius + radius
	if centre.y < feet.y - _radius or centre.y > feet.y + height + _radius:
		return false
	var d := Vector3(centre.x - feet.x, 0.0, centre.z - feet.z)
	var dist := d.length()
	if dist > reach + 0.05:
		return false
	var n := d / dist if dist > 0.01 else Vector3(velocity.x, 0, velocity.z).normalized()
	if n.length_squared() < 0.5:
		return false
	var approach := Vector3(velocity.x, 0, velocity.z).dot(n)
	# Standing in it: out of the way, gently. Walking into it: ahead of the person, a little
	# faster than they walk, as a foot sends a ball.
	var want := maxf(approach * 1.3, 0.0) * scale
	if dist < reach - 0.08:
		want = maxf(want, 0.8)
	var have := (_point_velocity(centre) if _driven else body.linear_velocity).dot(n)
	if want - have < 0.05:
		return false
	if _driven:
		# A swing's seat or a hanging bag: a heavy bag gives less to a walk than a seat does.
		var give := 1.0 if kind == &"swing" else 0.5
		_nudge(centre, n * (want - have) * give)
		return true
	var lift := (want - have) * 0.3 if kind == &"ball" and float(def.get("mass", 1.0)) < 3.0 else 0.0
	# A pin or a barrel is pushed above its middle, so it tips as well as slides.
	var at := Vector3(0, _size.y * 0.25, 0) if kind == &"pin" or kind == &"barrel" else Vector3.ZERO
	_wake()
	body.apply_impulse((n * (want - have) + Vector3(0, lift, 0)) * body.mass, at)
	return true


func _push_rim(feet: Vector3, velocity: Vector3, radius: float, height: float) -> bool:
	var hub := body.global_position
	if feet.y > hub.y + 0.1 or feet.y + height < hub.y - 0.1:
		return false
	var from_hub := Vector3(feet.x - hub.x, 0, feet.z - hub.z)
	var dist := from_hub.length()
	var r := _size.x * 0.5
	if dist < 0.01 or absf(dist - r) > radius + 0.12:
		return false
	var tangent := Vector3.UP.cross(from_hub / dist)
	var along := Vector3(velocity.x, 0, velocity.z).dot(tangent)
	var rim := _spin.y * r
	if absf(along) < 0.3 or absf(along) <= absf(rim) and signf(along) == signf(rim):
		return false
	_spin_by((along - rim) * 0.25)
	return true


## Somebody of [param mass] kg standing at [param feet] this tick: their weight on a see-saw or
## a wobbly platform. Server side. True when it bore them.
func stand_on(feet: Vector3, mass: float, p_gravity: float) -> bool:
	if not authoritative or body == null or not (kind == &"seesaw" or kind == &"wobble"):
		return false
	var local := body.global_transform.affine_inverse() * feet
	var half := Vector3(_size.x * 0.5 + 0.1, 0.0, _size.z * 0.5 + 0.25)
	if absf(local.x) > half.x or absf(local.z) > half.z or local.y < -0.15 or local.y > 0.45:
		return false
	var torque := (feet - _pivot_global()).cross(Vector3(0, -mass * p_gravity, 0))
	_torque += (global_basis.inverse() * torque) * _axes()
	return true


## A shot or a blast: [param impulse] N·s along [param direction] at [param point]. Server side.
func hit(point: Vector3, direction: Vector3, impulse: float) -> bool:
	if not authoritative or body == null or impulse <= 0.0:
		return false
	if _driven:
		_nudge(point, direction.normalized() * impulse / maxf(float(def.get("mass", 1.0)), 0.1))
		return true
	_wake()
	body.apply_impulse(direction.normalized() * impulse, point - body.global_position)
	return true


## A bouncer or a pad under somebody at [param feet] moving at [param velocity]: the velocity it
## throws them at, or [code]Vector3.INF[/code] when it does not. A pure function of where the
## toy stands, so a predicting client throws its own player on the same tick the server does.
func launch_for(feet: Vector3, velocity: Vector3) -> Vector3:
	if not (kind == &"bouncer" or kind == &"pad") or velocity.y > 0.5:
		return Vector3.INF
	var local := global_transform.affine_inverse() * feet
	var launch: Vector3 = def.get("launch", Vector3.ZERO)
	if kind == &"bouncer":
		var r := _size.x * 0.5 * 0.85
		if Vector2(local.x, local.z).length() > r or absf(local.y - _size.y) > 0.15:
			return Vector3.INF
		return Vector3(velocity.x, maxf(launch.y, -velocity.y * 0.5), velocity.z)
	if absf(local.x) > _size.x * 0.5 or absf(local.z) > _size.z * 0.5 or absf(local.y - _size.y) > 0.15:
		return Vector3.INF
	return global_basis * launch + Vector3(velocity.x, 0, velocity.z) * 0.25


## Its footprint in its own frame: where a bot's walkable mesh should not go. Empty for a
## loose toy, which a person walks through and pushes. At least two metres tall, so a baker
## never takes a low one (a pad, a trampoline) for a step it can climb onto.
func footprint() -> AABB:
	var box := _footprint()
	if box.size != Vector3.ZERO:
		box.size.y = maxf(box.size.y, 2.0)
	return box


func _footprint() -> AABB:
	var s := _size
	match kind:
		&"bag": return AABB(Vector3(-1.0, 0, -0.6), Vector3(1.6, s.y + 1.6, 1.2))
		&"swing": return AABB(Vector3(-s.x * 0.5 - 0.1, 0, -1.4), Vector3(s.x + 0.2, s.y, 2.8))
		&"seesaw": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5 - 0.1), Vector3(s.x, s.y + 0.3, s.z + 0.2))
		&"spinner", &"bouncer", &"fountain": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), Vector3(s.x, s.y + 0.3, s.z))
		&"wobble", &"pad": return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), Vector3(s.x, s.y + 0.1, s.z))
		&"switch", &"lamp", &"horn": return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, s.y, 0.6))
		&"bell": return AABB(Vector3(-s.x * 0.5 - 0.1, 0, -0.3), Vector3(s.x + 0.2, s.y, 0.6))
	return AABB()


# --- State --------------------------------------------------------------------------

## Puts it back where the map has it, still, asleep. Server side; a round's start.
func reset() -> void:
	on = bool(placement.get("on", def.get("on", false)))
	_show_on()
	if body == null or not authoritative:
		return
	if _driven:
		_angle = Vector3.ZERO
		_spin = Vector3.ZERO
		_torque = Vector3.ZERO
		_pose()
		return
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, rest)
	body.global_transform = rest
	body.sleeping = true


func _wake() -> void:
	if body != null and body.sleeping:
		body.sleeping = false


## Whether its moving part is simulating now. A driven kind (a swing, a see-saw) is never
## counted: it is an angle, not a body the solver carries.
func awake() -> bool:
	return body != null and not _driven and not body.freeze and not body.sleeping


## Whether a driven kind is moving.
func moving() -> bool:
	return _driven and _spin.length_squared() > 0.0004


## Where its moving part is, in world space: what a server replicates. Its own transform for a
## toy that does not move.
func state_transform() -> Transform3D:
	return body.global_transform if body != null else global_transform


## A replicated state, on a client: the moving part posed, and what is on and how often it was
## used, with the sound and the flourish when that changed.
func show_state(position_now: Vector3, rotation_now: Quaternion, on_now: bool, count_now: int) -> void:
	if body != null and not authoritative:
		body.global_transform = Transform3D(Basis(rotation_now.normalized()), position_now)
	if on_now != on:
		on = on_now
		_show_on()
	count = count_now


## Every frame (or tick) on an end that draws: the knock when the moving part stops short, and
## the press when the use count moved. [param delta] is the time since the last call.
func sense(delta: float) -> void:
	if count != _heard_count:
		_heard_count = count
		var id: StringName = def.get("sound_use", &"")
		if id != &"":
			sound.emit(id, global_position + Vector3(0, _size.y * 0.6, 0), 1.0)
		_play_flourish()
	if body == null or delta <= 0.0:
		return
	_sound_wait -= delta
	var at := body.to_global(_sense_local)
	if _last_sense == Vector3.INF:
		_last_sense = at
		return
	var velocity := (at - _last_sense) / delta
	_last_sense = at
	var change := (velocity - _last_velocity).length()
	var before := _last_velocity.length()
	_last_velocity = velocity
	var id_hit: StringName = def.get("sound_hit", &"")
	if id_hit == &"" or _sound_wait > 0.0:
		return
	# A turn as sharp as a bounce, from a part that was moving: a knock. Gravity alone changes a
	# falling ball's speed by a third of a metre a tick, far under this.
	if change > 1.6 and before > 0.9:
		_sound_wait = 0.12
		sound.emit(id_hit, at, clampf(change / 8.0, 0.15, 1.0))


func _show_on() -> void:
	if _cap != null:
		_cap.material_override = _mat(2 if on else 1, 0.3)
	if _bulb != null:
		_bulb.material_override = DotPropToyLook.material(_colour(1), 0.3, 2.5 if on else 0.0)
	if _light != null:
		_light.visible = on
	if _jets != null:
		_jets.emitting = on
	if _water != null:
		_water.visible = true


func _play_flourish() -> void:
	if _flourish == null or not is_inside_tree():
		return
	var tween := create_tween()
	match kind:
		&"bouncer":
			tween.tween_property(_flourish, ^"position:y", _size.y - 0.22, 0.08)
			tween.tween_property(_flourish, ^"position:y", _size.y - 0.02, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		&"bell":
			tween.tween_property(_flourish, ^"rotation:x", 0.5, 0.15)
			tween.tween_property(_flourish, ^"rotation:x", 0.0, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_:
			var start := _flourish.scale
			tween.tween_property(_flourish, ^"scale", start * 1.15, 0.08)
			tween.tween_property(_flourish, ^"scale", start, 0.3)


func describe() -> Dictionary:
	return {
		"index": index, "id": String(def.get("id", "")), "kind": String(kind),
		"at": state_transform().origin.snapped(Vector3.ONE * 0.01), "awake": awake(),
		"on": on, "count": count,
	}

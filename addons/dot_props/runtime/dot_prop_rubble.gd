class_name DotPropRubble
extends StaticBody3D

## A heap of fallen rock across part of a road: a bump, never a wall. Build it with
## [method make]. The collider is one wedge so a wheel climbs it instead of striking a box face.

## Peak height of the heap in metres. A truck's wheels clear 0.5 at a walk and are thrown at speed.
var height: float = 0.5


## A heap [param width] across and [param length] along, seeded so every machine builds the
## same one. [param material] is the rock look; [param layers] the collision layer bits.
static func make(width: float, length: float, height_m: float, seed_value: int, material: Material, layers: int = 1) -> DotPropRubble:
	var heap := DotPropRubble.new()
	heap.name = "Rubble"
	heap.height = height_m
	heap.collision_layer = layers
	var hw := width * 0.5
	var hl := length * 0.5
	var points := PackedVector3Array([
		Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(-hw, 0, hl), Vector3(hw, 0, hl),
		Vector3(-hw * 0.7, height_m, -hl * 0.1), Vector3(hw * 0.7, height_m, -hl * 0.1),
		Vector3(-hw * 0.7, height_m, hl * 0.2), Vector3(hw * 0.7, height_m, hl * 0.2),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	heap.add_child(collider)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rocks := clampi(int(width * length * 1.6), 5, 18)
	for i in rocks:
		var size := Vector3(rng.randf_range(0.5, 1.2), rng.randf_range(0.3, 0.7), rng.randf_range(0.5, 1.2))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		var x := rng.randf_range(-hw * 0.85, hw * 0.85)
		var z := rng.randf_range(-hl * 0.85, hl * 0.85)
		# On the wedge's surface at (x, z): high in the middle, down to nothing at the edges.
		var up := height_m * clampf(1.0 - maxf(absf(x) / hw, absf(z) / hl) * 0.8, 0.0, 1.0)
		mesh.position = Vector3(x, maxf(up - size.y * 0.3, size.y * 0.25), z)
		mesh.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		heap.add_child(mesh)
	return heap

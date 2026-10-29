class_name DotPropLedge
extends StaticBody3D

## A rock outcrop pinching a road to a narrow ledge, tapered so a wheel is guided in rather
## than struck. Build it with [method make], origin on the road's centreline. It only takes
## width; [method clear_width] says what is left, so a game can refuse a ledge no truck fits.

## Metres of road the outcrop takes, measured from the edge it grows out of.
var intrusion: float = 2.0
## Metres along the road it holds that full intrusion between its tapers.
var length: float = 20.0
## Which edge it grows from: -1 the left, +1 the right.
var side: float = 1.0


## What is left of a road [param road_width] across once [param intrusion_m] is taken.
static func clear_width(road_width: float, intrusion_m: float) -> float:
	return road_width - intrusion_m


## An outcrop taking [param intrusion_m] off the [param side] edge of a road [param road_width]
## across, [param length_m] long, [param height_m] high. Seeded so every machine builds the same one.
static func make(road_width: float, intrusion_m: float, length_m: float, height_m: float, side_sign: float, seed_value: int, material: Material, layers: int = 1) -> DotPropLedge:
	var ledge := DotPropLedge.new()
	ledge.name = "Ledge"
	ledge.intrusion = intrusion_m
	ledge.length = length_m
	ledge.side = signf(side_sign)
	ledge.collision_layer = layers
	var edge := ledge.side * road_width * 0.5
	var face := edge - ledge.side * intrusion_m
	var hl := length_m * 0.5
	# Footprint: the road-facing face is full intrusion between the tapers, which run out to the
	# road's edge at both ends. The rock goes 2 m past the edge so it is never seen to float.
	var outer := edge + ledge.side * 2.0
	var ring := [
		Vector2(outer, -hl), Vector2(outer, hl), Vector2(edge, hl), Vector2(face, hl * 0.62),
		Vector2(face, -hl * 0.62), Vector2(edge, -hl),
	]
	var low := -1.5
	var points := PackedVector3Array()
	for p: Vector2 in ring:
		points.append(Vector3(p.x, low, p.y))
		points.append(Vector3(p.x, height_m, p.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ledge.add_child(collider)
	ledge.add_child(_hull_mesh(ring, low, height_m, material))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in clampi(int(length_m * 0.5), 6, 24):
		var size := Vector3(rng.randf_range(0.8, 1.8), rng.randf_range(0.8, 2.0), rng.randf_range(0.8, 1.8))
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		rock.mesh = box
		rock.material_override = material
		var z := rng.randf_range(-hl * 0.55, hl * 0.55)
		# Along the face, a little proud of it, from the foot to the top.
		rock.position = Vector3(face + ledge.side * rng.randf_range(-0.1, 0.3), rng.randf_range(0.2, height_m - 0.3), z)
		rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		ledge.add_child(rock)
	return ledge


## The footprint [param ring] extruded between [param low] and [param top], with a flat lid.
static func _hull_mesh(ring: Array, low: float, top: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		var quad := [Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(quad[k])
	for i in range(1, n - 1):
		for k in [0, i, i + 1]:
			var p: Vector2 = ring[k]
			st.add_vertex(Vector3(p.x, top, p.y))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material
	return mesh

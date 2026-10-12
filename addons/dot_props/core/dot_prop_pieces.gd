class_name DotPropPieces
extends RefCounted

## Collision shaped like the model: a prop as a few convex pieces instead of one box.
##
## [b]Why not one box.[/b] A tree's box is its canopy's width all the way to the ground, so nobody
## can stand by its trunk, walk under its leaves or jump onto a low branch, and a bot pressed
## against the box looks like it hangs in the air beside the tree. A table's box fills the space
## under it, which in a hiding game is the best spot in the room.
##
## [b]Why not the mesh itself.[/b] A concave (trimesh) shape of a few hundred triangles catches a
## character on every seam and costs far more per contact than a handful of convex hulls, and a
## server holds thousands of props.
##
## [b]Measured once, offline, read by everybody.[/b] [method measure] cuts a model up with the
## engine's own convex decomposition (V-HACD, [method MeshInstance3D.create_multiple_convex_collisions]),
## which a headless server neither has the meshes for nor should spend seconds on, and which an
## export template may not be built with. So a game's measuring tool writes the pieces into its
## catalogue ([method encode]) and the server and every client build the same shapes from those
## numbers ([method decode], [method shapes]). Two ends building collision from two measurements
## would be a predicting client walking round a branch the server has somewhere else.
##
## A piece is the points of one convex hull, in the prop's own frame: the frame a catalogue
## places a model in (scaled, its footprint centred on the origin, its base on the floor).

## A model smaller than this in every direction stays one box: there is nothing to stand on or
## crawl under that its box takes away.
const MIN_SIZE := 0.6

## The most pieces a prop is cut into: about three per metre of its largest side, between
## these. A tree takes up to ten, a chair two or three.
const MIN_PIECES := 2
const MAX_PIECES := 10
const PIECES_PER_METRE := 3.0

## Pieces that fill this share of the prop's box are no better than the box, and cost more.
const BOX_FILL := 0.8

## V-HACD's voxel budget. Higher finds thinner branches and costs seconds per model.
const RESOLUTION := 200000

## V-HACD's tolerance: how far (as a share of the model's size) a piece may be from convex
## before it is cut again. Lower finds a branch under a leaf clump, and costs pieces.
const CONCAVITY := 0.01

## Millimetres, so a re-measure writes the same bytes and a `--check` can compare files.
const ROUND := 0.001


## Cuts [param model] (a scene whose [MeshInstance3D]s are the prop) into convex pieces in the
## prop's frame, [param frame] being where the catalogue puts the model in it (its scale and
## offset). Returns an empty array when one box is as good: a small model, or one the
## decomposition finds convex anyway. Tool time only; see the class notes.
static func measure(model: Node, frame: Transform3D, max_pieces: int = -1, concavity: float = CONCAVITY) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []

	# One mesh per material: a model says which part is which by its materials (a tree's
	# leaves and its bark), and a decomposition of the whole merges a leaf clump with the trunk
	# beside it into one hull, filling the space above a branch where a person would stand.
	var groups: Dictionary = {}
	_append(model, frame, groups)

	if groups.is_empty():
		return out

	var meshes: Array[Mesh] = []
	var box := AABB()

	for key: String in _sorted_keys(groups):
		var mesh: Mesh = (groups[key] as SurfaceTool).commit()
		box = mesh.get_aabb() if meshes.is_empty() else box.merge(mesh.get_aabb())
		meshes.append(mesh)

	var longest := box.size[box.size.max_axis_index()]

	if longest < MIN_SIZE:
		return out

	if max_pieces < 0:
		max_pieces = clampi(roundi(longest * PIECES_PER_METRE), MIN_PIECES, MAX_PIECES)

	for mesh in meshes:
		var size := mesh.get_aabb().size
		# Each material's share of the pieces follows its share of the model's size.
		var share := clampi(roundi(max_pieces * size[size.max_axis_index()] / longest), 1, max_pieces)
		out.append_array(_decompose(mesh, share, concavity))

	# One convex piece, or pieces that fill the box anyway, are no better than the box round
	# them and cost more.
	if out.size() < 2 or fill(out, box) >= BOX_FILL:
		out.clear()

	out.sort_custom(func(a: PackedVector3Array, b: PackedVector3Array) -> bool: return _key(a) < _key(b))
	return out


static func _decompose(mesh: Mesh, max_pieces: int, concavity: float) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var holder := MeshInstance3D.new()
	holder.mesh = mesh
	var settings := MeshConvexDecompositionSettings.new()
	settings.max_convex_hulls = max_pieces
	settings.resolution = RESOLUTION
	settings.max_concavity = concavity
	settings.mode = MeshConvexDecompositionSettings.CONVEX_DECOMPOSITION_MODE_VOXEL
	settings.project_hull_vertices = true
	holder.create_multiple_convex_collisions(settings)

	for body in holder.get_children():
		for child in body.get_children():
			var hull := (child as CollisionShape3D).shape as ConvexPolygonShape3D if child is CollisionShape3D else null
			if hull == null or hull.points.size() < 4:
				continue
			var placed := (child as CollisionShape3D).transform
			var points := PackedVector3Array()
			for p in hull.points:
				points.append(_rounded(placed * p))
			out.append(points)

	holder.free()
	return out


static func _sorted_keys(groups: Dictionary) -> Array:
	var keys := groups.keys()
	keys.sort()
	return keys


## The share of [param box] the pieces cover, sampled on a grid of [param steps] a side.
static func fill(pieces: Array, box: AABB, steps: int = 14) -> float:
	var hulls: Array = []
	for piece: PackedVector3Array in pieces:
		hulls.append([bounds([piece]), planes(piece)])
	var inside := 0
	for i in range(steps):
		for j in range(steps):
			for k in range(steps):
				var p := box.position + box.size * Vector3((i + 0.5) / steps, (j + 0.5) / steps, (k + 0.5) / steps)
				for hull: Array in hulls:
					if not (hull[0] as AABB).has_point(p):
						continue
					var all_in := true
					for plane: Plane in hull[1]:
						if plane.distance_to(p) > 0.0:
							all_in = false
							break
					if all_in:
						inside += 1
						break
	return float(inside) / float(steps * steps * steps)


## Pieces as JSON: one flat array of numbers per hull.
static func encode(pieces: Array) -> Array:
	var out: Array = []
	for piece: PackedVector3Array in pieces:
		var flat: Array = []
		for p in piece:
			flat.append_array([snappedf(p.x, ROUND), snappedf(p.y, ROUND), snappedf(p.z, ROUND)])
		out.append(flat)
	return out


## Pieces from JSON ([method encode]'s form). Anything malformed is skipped, never guessed at.
static func decode(raw: Variant) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	if not (raw is Array):
		return out
	for flat: Variant in raw:
		if not (flat is Array) or (flat as Array).size() < 12 or (flat as Array).size() % 3 != 0:
			continue
		var points := PackedVector3Array()
		var numbers := flat as Array
		for i in range(0, numbers.size(), 3):
			points.append(Vector3(float(numbers[i]), float(numbers[i + 1]), float(numbers[i + 2])))
		out.append(points)
	return out


## One shape per piece, to share between every copy of the prop in a map: a shape resource is
## data, and three hundred trees can hold the same five.
static func shapes(pieces: Array) -> Array[ConvexPolygonShape3D]:
	var out: Array[ConvexPolygonShape3D] = []
	for piece: PackedVector3Array in pieces:
		var shape := ConvexPolygonShape3D.new()
		shape.points = piece
		out.append(shape)
	return out


## The box round every piece, in the prop's frame.
static func bounds(pieces: Array) -> AABB:
	var box := AABB()
	var any := false
	for piece: PackedVector3Array in pieces:
		for p in piece:
			if not any:
				box = AABB(p, Vector3.ZERO)
				any = true
			else:
				box = box.expand(p)
	return box


## Whether [param point] (prop frame) is inside any piece, or within [param margin] of one.
## Each hull's planes are built from its points, so this needs no physics space.
static func contains(pieces: Array, point: Vector3, margin: float = 0.0) -> bool:
	for piece: PackedVector3Array in pieces:
		if _inside_hull(piece, point, margin):
			return true
	return false


## Every plane of the hull of [param points], outward. Brute force over point triples, which is
## fine for the thirty-odd points a piece has and is only asked when something is hit.
static func planes(points: PackedVector3Array) -> Array[Plane]:
	var out: Array[Plane] = []
	var n := points.size()
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var plane := Plane(points[i], points[j], points[k])
				if plane.normal == Vector3.ZERO or not plane.normal.is_finite():
					continue
				var above := 0
				var below := 0
				for p in points:
					var d := plane.distance_to(p)
					if d > 0.0005:
						above += 1
					elif d < -0.0005:
						below += 1
				if above > 0 and below > 0:
					continue
				if above > 0:
					plane = -plane
				var seen := false
				for q in out:
					if q.normal.dot(plane.normal) > 0.9999 and absf(q.d - plane.d) < 0.001:
						seen = true
						break
				if not seen:
					out.append(plane)
	return out


static func _inside_hull(points: PackedVector3Array, point: Vector3, margin: float) -> bool:
	var box := bounds([points]).grow(margin)
	if not box.has_point(point):
		return false
	for plane in planes(points):
		if plane.distance_to(point) > margin:
			return false
	return true


static func _append(node: Node, parent: Transform3D, groups: Dictionary) -> void:
	var here := parent

	if node is Node3D:
		here = parent * (node as Node3D).transform

	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			# Only an ArrayMesh says; a PrimitiveMesh (a BoxMesh stand-in) is always triangles.
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material := mesh.surface_get_material(surface)
			var key := material.resource_name if material != null and material.resource_name != "" else "surface"
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = tool
			(groups[key] as SurfaceTool).append_from(mesh, surface, here)

	for child in node.get_children():
		_append(child, here, groups)


static func _rounded(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, ROUND), snappedf(p.y, ROUND), snappedf(p.z, ROUND))


static func _key(points: PackedVector3Array) -> String:
	var box := bounds([points])
	return "%09.3f|%09.3f|%09.3f|%d" % [box.position.y + 1000.0, box.position.x + 1000.0, box.position.z + 1000.0, points.size()]

@tool
class_name DotPropModel
extends RefCounted

## A model file (.glb or .gltf) turned into something a rigid body can wear: the picture, a
## collision shape, and the numbers a catalogue needs (size, mass).
##
## [b]Why this is here and not in a game.[/b] Every game that wants real props does the same
## four things: load a model whether it is an imported resource or a loose file somebody
## dropped in a folder, measure it, build collision that is not the mesh, and give it a mass.
## Doing it twice is two sets of rules about what "a convex shape" means.
##
## [b]Collision is one convex hull, never the triangles.[/b] A concave (trimesh) shape is for
## static scenery: on a dynamic body it is refused by the engines this family runs on, and
## on a static one it catches a sliding character on every seam. A hull is solid where a
## chair is not, which is the price, and what [DotPropPieces] exists to spend for the few
## props where it matters (it needs a measuring pass; this does not). [code]box[/code],
## [code]sphere[/code] and [code]cylinder[/code] are fitted to the model's box instead, for a
## sidecar that knows better.
##
## [b]Loose files are read with [GLTFDocument].[/b] That works without the editor ever having
## imported them, which is the only way a model dropped on a running server can appear, and
## it resolves a model's external textures beside the file. A [code]res://[/code] model goes
## through the resource loader instead, because inside an export only the imported copy
## exists.

const CHANNEL := "props.model"

## The most vertices kept for one hull. A model with more is thinned: the engines build the
## hull from these every spawn, and a thousand points are no more convex than a hundred.
const MAX_HULL_POINTS := 160

## Points closer than this (metres) are one point.
const WELD := 0.01

## A model thinner than this on any side gets a collision at least this thick, or the body
## is a plane the solver lets everything through.
const MIN_THICKNESS := 0.04

## The sides of a model a catalogue accepts, in metres after scaling. A dropped-in file that
## is a kilometre across is somebody's whole level, and one a millimetre across is a typo.
const MIN_SIDE := 0.02
const MAX_SIDE := 40.0

## Kilograms per cubic metre of the model's box, by default: a prop is hollow and thin-walled
## far more often than solid, so a quarter of a wooden block's weight is nearer the truth
## for furniture than the whole of it.
const DEFAULT_DENSITY := 120.0

static var _cache: Dictionary = {}


## Loads the model at [param path] as a fresh [Node3D] the caller owns. Fails on a file that
## is missing, unreadable, or not a model.
static func load_scene(path: String) -> DotResult:
	var root: Node = null

	if path.begins_with("res://") or path.begins_with("uid://"):
		if not ResourceLoader.exists(path):
			return DotResult.fail(DotError.CODE_IO, "No model there.", path)

		var res: Resource = load(path)

		if res is PackedScene:
			root = (res as PackedScene).instantiate()
	elif FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(path, state, 0, path.get_base_dir())

		if err != OK:
			return DotResult.fail(
				DotError.CODE_PARSE, "That model could not be read.", "%s (%s)" % [path, error_string(err)]
			)

		root = doc.generate_scene(state)
	else:
		return DotResult.fail(DotError.CODE_IO, "No model there.", path)

	if not (root is Node3D):
		if root != null:
			root.free()
		return DotResult.fail(DotError.CODE_PARSE, "That file is not a 3D model.", path)

	repair_textures(root, path)

	return DotResult.success(root)


## Gives a material that lost its texture the one beside the model.
##
## [b]The sixth form of the family's delivery bug.[/b] An imported model records its texture as
## a UID plus the path it had when imported, and inside a mounted pack neither exists, so the
## mesh loads white. A Kenney kit keeps its atlas at [code]Textures/colormap.png[/code]
## beside the models; this sets that on a material that has no texture, and does nothing
## for one that has (which is every one in a build).
static func repair_textures(root: Node, model_path: String) -> int:
	var atlas_path := "%s/Textures/colormap.png" % model_path.get_base_dir()
	var atlas: Texture2D = null
	var repaired := 0

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D

		if mi.mesh == null:
			continue

		for surface in range(mi.mesh.get_surface_count()):
			var material := mi.get_active_material(surface) as BaseMaterial3D

			if material == null or material.albedo_texture != null:
				continue

			if atlas == null:
				if not (ResourceLoader.exists(atlas_path) or FileAccess.file_exists(atlas_path)):
					return repaired

				atlas = _texture(atlas_path)

				if atlas == null:
					return repaired

			var copy := material.duplicate() as BaseMaterial3D
			copy.albedo_texture = atlas
			mi.set_surface_override_material(surface, copy)
			repaired += 1

	return repaired


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D

	var image := Image.load_from_file(path)

	return ImageTexture.create_from_image(image) if image != null else null


## The model's box in its own frame, every mesh's transform down to [param root] included.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D

		if mi.mesh == null or not mi.visible:
			continue

		var local := _relative(mi, root) * mi.get_aabb()
		box = local if first else box.merge(local)
		first = false

	return box


static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node

	while at != null and at != root:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()

	return xf


## The model's vertices in the body's frame (scaled, then moved by [param offset]), welded.
static func points(root: Node3D, scale: float, offset: Vector3) -> PackedVector3Array:
	var seen: Dictionary = {}

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D

		if mi.mesh == null or not mi.visible:
			continue

		var xf := _relative(mi, root)

		for surface in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]

			if not (verts is PackedVector3Array):
				continue

			for v in (verts as PackedVector3Array):
				var p := (xf * v) * scale + offset
				seen[Vector3i((p / WELD).round())] = p

	var out := PackedVector3Array(seen.values())

	if out.size() > MAX_HULL_POINTS:
		out = _thin(out)

	return out


## Keeps the points that stick out furthest in a fixed spread of directions, which is what a
## hull is made of; dropping every Nth point instead can drop a corner and shrink the shape.
static func _thin(all: PackedVector3Array) -> PackedVector3Array:
	var keep: Dictionary = {}
	var directions := 80

	for i in range(directions):
		# A Fibonacci sphere: even directions without a lookup table.
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(directions)
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var phi := float(i) * 2.399963
		var dir := Vector3(cos(phi) * r, y, sin(phi) * r)
		var best := -1
		var best_dot := -INF

		for j in range(all.size()):
			var d := all[j].dot(dir)
			if d > best_dot:
				best_dot = d
				best = j

		keep[best] = true

	var out := PackedVector3Array()

	for index in keep:
		out.append(all[index])

	return out


## Everything a body needs from one model at one scale, built once and shared.
##
## [code]{ "extent": Vector3 (the scaled box), "offset": Vector3 (what to add to the model so
## its box is centred on the body), "shape": Shape3D, "scale": float }[/code], or a failure.
## Cached by path, scale and shape: forty crates are one measurement, one shape. The scene
## itself is not cached, because a node can have one parent.
static func measure(path: String, scale: float, shape_name: String = "convex") -> DotResult:
	var key := "%s|%.4f|%s" % [path, scale, shape_name]

	if _cache.has(key):
		return DotResult.success(_cache[key])

	var loaded := load_scene(path)

	if not loaded.ok:
		return loaded

	var root := loaded.value as Node3D
	var box := bounds(root)

	if box.size.length() <= 0.0:
		root.free()
		return DotResult.fail(DotError.CODE_INVALID, "That model has no mesh.", path)

	var extent := box.size * scale
	var offset := -(box.position + box.size * 0.5) * scale
	var shape := _make_shape(root, scale, offset, extent, shape_name)
	root.free()

	var info := {"extent": extent, "offset": offset, "shape": shape, "scale": scale}
	_cache[key] = info

	return DotResult.success(info)


## A fresh copy of the model, scaled and centred as [method measure] says, ready to be a
## child of the body. Scaled on a plain node above the meshes: the body itself must never
## be scaled (see game-playground's notes on resizing).
static func visual(path: String, scale: float, offset: Vector3) -> Node3D:
	var loaded := load_scene(path)

	if not loaded.ok:
		return null

	var model := loaded.value as Node3D
	var holder := Node3D.new()
	holder.name = "Model"
	holder.position = offset
	holder.scale = Vector3.ONE * scale
	holder.add_child(model)

	return holder


static func _make_shape(
	root: Node3D, scale: float, offset: Vector3, extent: Vector3, shape_name: String
) -> Shape3D:
	var thick := Vector3(
		maxf(extent.x, MIN_THICKNESS), maxf(extent.y, MIN_THICKNESS), maxf(extent.z, MIN_THICKNESS)
	)

	match shape_name:
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = maxf(thick.x, maxf(thick.y, thick.z)) * 0.5
			return sphere
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = maxf(thick.x, thick.z) * 0.5
			cylinder.height = thick.y
			return cylinder
		"box":
			var box := BoxShape3D.new()
			box.size = thick
			return box
		_:
			pass

	var pts := points(root, scale, offset)

	# A flat model (a rug, a plate) has a hull the solver reads as a plane. A box of the
	# minimum thickness is the honest shape for it.
	if pts.size() < 4 or minf(extent.x, minf(extent.y, extent.z)) < MIN_THICKNESS:
		var flat := BoxShape3D.new()
		flat.size = thick
		return flat

	var hull := ConvexPolygonShape3D.new()
	hull.points = pts

	return hull


## A mass for a model the author did not weigh: its box, by [constant DEFAULT_DENSITY] or
## [param density], clamped to what a physics gun can sensibly be asked to lift.
static func estimate_mass(extent: Vector3, density: float = DEFAULT_DENSITY) -> float:
	return clampf(extent.x * extent.y * extent.z * density, 0.2, 2000.0)


## Whether [param extent] is a size a catalogue accepts. See [constant MIN_SIDE].
static func size_ok(extent: Vector3) -> bool:
	return (
		maxf(extent.x, maxf(extent.y, extent.z)) <= MAX_SIDE
		and maxf(extent.x, maxf(extent.y, extent.z)) >= MIN_SIDE
	)


static func clear_cache() -> void:
	_cache.clear()

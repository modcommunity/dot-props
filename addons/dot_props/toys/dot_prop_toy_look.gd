class_name DotPropToyLook
extends RefCounted

## How a toy is drawn: meshes made in code from the definition's size and colours.
##
## [b]Made, not modelled[/b], because a toy is a ball, a plank or a post, every one of them a
## primitive, and a model would be a file every consumer's pack has to carry and import. A
## mesh made here is the same in every game, costs nothing to deliver, and changes with the
## definition's numbers. Matte, unshaded nowhere, and without textures: what the browser's
## Compatibility renderer draws cheapest.

## A plain matte material. Cached per colour, so eighteen toys of six colours make six.
static var _materials: Dictionary = {}


## Drops the shared materials so a headless run exits with none alive; they are rebuilt on use.
static func clear_cache() -> void:
	_materials.clear()


static func material(colour: Color, rough: float = 0.75, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [colour.to_html(), rough, emit]
	var made: StandardMaterial3D = _materials.get(key)
	if made != null:
		return made
	made = StandardMaterial3D.new()
	made.albedo_color = colour
	made.roughness = rough
	if emit > 0.0:
		made.emission_enabled = true
		made.emission = colour
		made.emission_energy_multiplier = emit
	_materials[key] = made
	return made


## A material that takes its colour from the mesh's vertices: the beach ball's segments.
static func painted() -> StandardMaterial3D:
	var made: StandardMaterial3D = _materials.get("vertex")
	if made == null:
		made = StandardMaterial3D.new()
		made.vertex_color_use_as_albedo = true
		made.roughness = 0.55
		_materials["vertex"] = made
	return made


static func add(parent: Node3D, mesh: Mesh, mat: Material, at: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.transform = at
	parent.add_child(node)
	return node


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(radius: float, height: float, top: float = -1.0, segments: int = 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, segments: int = 16) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 4)
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 10
	return m


## A sphere painted in [param colours] by longitude, one segment each in turn: a beach ball.
## [param patches] instead paints the second colour round twelve evenly spread points and the
## first everywhere else: a football's patches. Vertex colours, one material.
static func painted_sphere(radius: float, colours: Array, patches: bool = false) -> ArrayMesh:
	var base := sphere(radius, 24)
	var arrays := base.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tint := PackedColorArray()
	tint.resize(vertices.size())
	var points: Array[Vector3] = []
	if patches:
		points = _icosahedron()
	for i in vertices.size():
		var v := vertices[i]
		var c: Color = colours[0]
		if patches:
			var near := false
			for p: Vector3 in points:
				if v.normalized().dot(p) > 0.94:
					near = true
					break
			c = colours[1 % colours.size()] if near else colours[0]
		else:
			var angle := fposmod(atan2(v.z, v.x), TAU)
			var segment := int(angle / TAU * float(colours.size())) % colours.size()
			c = colours[segment]
			# The caps: white, as a beach ball's are.
			if absf(v.y) > radius * 0.93:
				c = Color(0.97, 0.96, 0.92)
		tint[i] = c
	arrays[Mesh.ARRAY_COLOR] = tint
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A disc (a short cylinder) painted in [param sectors] wedges, [param colours] in turn.
static func painted_disc(radius: float, height: float, colours: Array, sectors: int) -> ArrayMesh:
	var base := cylinder(radius, height, -1.0, sectors * 4)
	var arrays := base.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tint := PackedColorArray()
	# Coloured per triangle by its middle, so a wedge's edge is a line and not a blend.
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var flat_vertices := PackedVector3Array()
	var flat_normals := PackedVector3Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for t in range(0, indices.size(), 3):
		var mid := (vertices[indices[t]] + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
		var angle := fposmod(atan2(mid.z, mid.x), TAU)
		var c: Color = colours[int(angle / TAU * float(sectors)) % colours.size()]
		for k in 3:
			flat_vertices.append(vertices[indices[t + k]])
			flat_normals.append(normals[indices[t + k]])
			tint.append(c)
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = flat_vertices
	out_arrays[Mesh.ARRAY_NORMAL] = flat_normals
	out_arrays[Mesh.ARRAY_COLOR] = tint
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return out


static func _icosahedron() -> Array[Vector3]:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var out: Array[Vector3] = []
	for v: Vector3 in [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]:
		out.append(v.normalized())
	return out


## A thin rod from [param a] to [param b] in [param parent]'s space: a leg, a rope, a rail.
static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var up := (b - a).normalized() if length > 0.0001 else Vector3.UP
	var basis := Basis.IDENTITY
	if absf(up.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(up).normalized()
		basis = Basis(axis, Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	return add(parent, cylinder(radius, length, -1.0, 8), mat, Transform3D(basis, mid))

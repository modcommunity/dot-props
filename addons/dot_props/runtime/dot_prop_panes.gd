class_name DotPropPanes
extends RefCounted

## Breakable map boxes (glass, thin ice): indexing, damage, blast and impact arithmetic, and the
## shard plan. A pane is `{node: Node3D, health: float, material: StringName}` in a Dictionary
## keyed by the box's index; the host owns that dictionary, its signals and its shard spawning.

## Speed into a pane above which a body or walker breaks it, m/s.
const IMPACT_SPEED := 6.0
const SHARDS_PER_M2 := 0.6
const SHARDS_MAX := 10


## Panes under [param map]: every StaticBody3D with `pg_box`-style [param index_meta] whose
## [param health_of] (material -> health, via the host's surface lookup) is above 0.
## [param material_of] takes the node and returns its material id.
static func index_map(map: Node, index_meta: StringName, material_of: Callable, health_of: Callable) -> Dictionary:
	var out := {}
	if map == null:
		return out
	var stack: Array[Node] = [map]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is StaticBody3D) or not n.has_meta(index_meta):
			continue
		var material: StringName = material_of.call(n)
		var health := float(health_of.call(material)) if material != &"" else 0.0
		if health > 0.0:
			out[int(n.get_meta(index_meta))] = {"node": n, "health": health, "material": material}
	return out


## Takes [param amount] off pane [param index]. Returns `{before, broke}`, or empty when there is no such pane.
static func damage(panes: Dictionary, index: int, amount: float) -> Dictionary:
	if not panes.has(index):
		return {}
	var pane: Dictionary = panes[index]
	var before := float(pane["health"])
	pane["health"] = before - amount
	return {"before": before, "broke": float(pane["health"]) <= 0.0}


## Panes a blast at [param at] reaches, as `[node, damage]`, less with distance.
static func blast_hits(panes: Dictionary, at: Vector3, radius: float, amount: float) -> Array:
	var out := []
	if radius <= 0.0:
		return out
	for index: int in panes.keys():
		var node := (panes[index] as Dictionary)["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var bounds := bounds_of(node)
		var distance := maxf(0.0, bounds.get_center().distance_to(at) - bounds.size.length() * 0.5)
		if distance < radius:
			out.append([node, amount * clampf(1.0 - distance / radius, 0.0, 1.0)])
	return out


## Panes struck at speed. [param bodies] are `[id, RigidBody3D]`, [param walkers] `[id, feet position]`;
## [param last_speed] maps id to the velocity at the end of the last tick (the contact has already
## stopped them now). Only the part along the pane's normal counts. Returns `[node, damage]`: a body
## does mass * speed / 2, a walker the pane's whole health.
static func impact_hits(panes: Dictionary, bodies: Array, walkers: Array, last_speed: Dictionary) -> Array:
	var hits := []
	for index: int in panes.keys():
		var node := (panes[index] as Dictionary)["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var bounds := bounds_of(node)
		var normal := normal_of(node)
		for each: Array in bodies:
			var body := each[1] as RigidBody3D
			if body == null or not body.is_inside_tree():
				continue
			var was: Vector3 = last_speed.get(each[0], Vector3.ZERO)
			var into := absf(was.dot(normal))
			if into > IMPACT_SPEED and bounds.grow(0.5 + reach_of(body)).has_point(body.global_position):
				hits.append([node, body.mass * into * 0.5])
		for each: Array in walkers:
			var was: Vector3 = last_speed.get(each[0], Vector3.ZERO)
			var feet: Vector3 = (each[1] as Vector3) + Vector3.UP * 0.1
			var near := bounds.grow(0.7)
			# Chest for a wall, feet for a floor: a player landing on thin ice has the chest a metre above it.
			if absf(was.dot(normal)) > IMPACT_SPEED and (near.has_point(feet + Vector3.UP * 0.8) or near.has_point(feet)):
				hits.append([node, (panes[index] as Dictionary)["health"]])
	return hits


## Where shards start and how fast they fly, as `[{at, velocity}]`; seeded by the pane so every
## machine agrees.
static func shard_plan(bounds: AABB) -> Array:
	var largest := maxf(bounds.size.x * bounds.size.y, maxf(bounds.size.x * bounds.size.z, bounds.size.y * bounds.size.z))
	var count := clampi(int(ceil(largest * SHARDS_PER_M2)), 3, SHARDS_MAX)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bounds.get_center())
	var out := []
	for i in count:
		var at := bounds.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * bounds.size
		var out_dir := at - bounds.get_center()
		out_dir.y = absf(out_dir.y)
		out.append({"at": at, "velocity": out_dir.normalized() * rng.randf_range(2.0, 5.0) + Vector3.UP * 1.5})
	return out


## The world AABB of a map box, from its own collision shape.
static func bounds_of(node: Node3D) -> AABB:
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size := ((child as CollisionShape3D).shape as BoxShape3D).size
			return node.global_transform * AABB(-size * 0.5, size)
	return AABB(node.global_position, Vector3.ZERO)


## A pane's normal: its box's thinnest axis, in the world.
static func normal_of(node: Node3D) -> Vector3:
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size := ((child as CollisionShape3D).shape as BoxShape3D).size
			var axis := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
			return node.global_basis[axis].normalized()
	return Vector3.UP


## Half the diagonal of a body's first collision shape.
static func reach_of(body: Node3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			return (child as CollisionShape3D).shape.get_debug_mesh().get_aabb().size.length() * 0.5
	return 0.5

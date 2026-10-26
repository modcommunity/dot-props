class_name DotPropToyBox
extends Node3D

## A map's toys: built from its placements, simulated on the server under a cap on how many are
## awake, pushed, stood on, used and shot through calls the game makes, and drawn on a client
## from replicated states.
##
## [b]Placed by data[/b]: a map lists `{"toy": "<catalogue id>", "at": [x, y, z], "yaw": deg}`
## (plus `links` for a switch and `on` for a lamp or a fountain), and both ends build the same
## toys in the same order from it, so a toy's index is the same on every machine and is all a
## game needs to pair a replicated entity with it ([method normal_placement] is the format).
##
## [b]What the game wires[/b], because this addon depends on dot-core alone:
## - the collision bits ([member loose_layer] and the rest), from its own layout;
## - every tick on the server: [method advance], [method push_from] and [method stand_on] for
##   each person, [method use] when the use key goes down on one ([method aimed] finds it);
## - in its movement code on every end: [method launch_for], for the bouncers and pads, and
##   [method carry_for] after the move, for a roundabout's riders (or [DotPropCarry] with
##   [member DotPropCarry.toys] set, which does it for a game already riding props);
## - on a client: [member authoritative] false, and [method DotPropToy.show_state] from its own
##   replicated entity per toy (the state is [method DotPropToy.state_transform], `on`, `count`);
## - [signal sound] into its audio, with [DotPropToySounds]' rows in its catalogue.

## A toy made a sound: play [param id] at [param at], [param strength] 0..1.
signal sound(id: StringName, at: Vector3, strength: float)

## A toy was used. Server side.
signal used(index: int)

var catalogue: DotPropToyCatalogue = null
var rules: DotPropToyRules = DotPropToyRules.new()

## Whether this end simulates the toys (a server, an offline game) or draws replicated states.
var authoritative: bool = true

## Whether to build meshes, lights and particles, and to listen for knocks. False on a server.
var draw: bool = true

## Collision bits. Loose toys are on [member loose_layer], which people should not collide
## with; the rest on [member solid_layer], which they should (to stand on a see-saw).
var loose_layer: int = 1
var loose_mask: int = 1
var solid_layer: int = 1
var solid_mask: int = 1

## A layer nothing collides with, for the footprints a bot's walkable mesh is baked round
## ([method nav_bodies]). 0 builds none.
var footprint_layer: int = 0

## What the use key's ray stops at: the toys' layers and whatever walls should block a reach.
var aim_mask: int = 0xFFFFFFFF

## Gravity a person's weight is under, m/s².
var gravity: float = 20.0

## Below this a toy is lost and [member lost_mode] applies.
var kill_y: float = -30.0

## What becomes of a lost toy: home (where the map placed it), the last spot it rested at (home
## when it never rested, as with a toy dropped over a pit), or gone.
enum LostMode { HOME, LAST_REST, REMOVE }
var lost_mode: LostMode = LostMode.HOME

## A toy this far below where it last rested is lost too, so a drop over a pit is noticed in a
## second, not at `kill_y` (0: only `kill_y` counts).
var fall_limit: float = 0.0

## A toy was lost, before [member lost_mode] is applied; a removal frees it after the handlers.
signal lost(toy: DotPropToy)

## Further than this from home, a toy goes home at the next round (and at once when it is
## asleep there, so a ball kicked into a corner of the map stays put for the round).
var lost_distance: float = 80.0

var toys: Array[DotPropToy] = []

## Seconds at rest after which an awake loose toy is put to sleep (0: the engine's own timer).
var sleep_after: float = 0.0

## Placements naming toys this catalogue does not have: left out, listed once.
var missing: PackedStringArray = PackedStringArray()

var _now: float = 0.0
var _rested: Dictionary = {}
var _calm: Dictionary = {}
var _footprints: StaticBody3D = null
var _rules_connected: bool = false


## The placement format, normalised: `{toy, at, yaw, links, on?}`, or empty when it is not one.
static func normal_placement(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var p := raw as Dictionary
	if not p.has("toy") or not p.has("at"):
		return {}
	var at: Variant = p["at"]
	if not (at is Array) or (at as Array).size() < 3:
		return {}
	var out := {
		"toy": str(p["toy"]),
		"at": [snappedf(float(at[0]), 0.001), snappedf(float(at[1]), 0.001), snappedf(float(at[2]), 0.001)],
		"yaw": snappedf(float(p.get("yaw", 0.0)), 0.01),
	}
	var links: Array = []
	for raw_link: Variant in p.get("links", []):
		links.append(int(raw_link))
	if not links.is_empty():
		out["links"] = links
	if p.has("on"):
		out["on"] = bool(p["on"])
	return out


## Builds every toy in [param placements] (normalised or not). Clears what was there.
func build(placements: Array) -> DotResult:
	clear()
	if catalogue == null:
		catalogue = DotPropToyCatalogue.stock()
	if not _rules_connected and rules != null:
		var _c := rules.changed.connect(_on_rules_changed)
		_rules_connected = true
	if not is_inside_tree():
		return DotResult.fail(DotError.CODE_STATE, "a toy box builds in the tree")

	for raw: Variant in placements:
		var placement := normal_placement(raw)
		if placement.is_empty():
			continue
		var def := catalogue.get_def(StringName(placement["toy"]))
		if def.is_empty():
			if not missing.has(placement["toy"]):
				missing.append(placement["toy"])
			continue
		var toy := DotPropToy.new()
		toy.name = "Toy%d" % toys.size()
		toy.index = toys.size()
		toy.authoritative = authoritative
		toy.draw = draw
		toy.gravity = gravity
		var at: Array = placement["at"]
		toy.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(placement["yaw"]))), Vector3(float(at[0]), float(at[1]), float(at[2])))
		add_child(toy)
		toy.build(def, placement, {
			"loose_layer": loose_layer, "loose_mask": loose_mask,
			"solid_layer": solid_layer, "solid_mask": solid_mask,
		})
		toy.link_fn = _flip
		var _s := toy.sound.connect(_on_toy_sound)
		toys.append(toy)

	_build_footprints()
	_on_rules_changed()
	if not missing.is_empty():
		DotLog.warn(CHANNEL, "a map names toys this catalogue does not have; they are left out", {"missing": ", ".join(missing)})
	return DotResult.success(toys.size())


const CHANNEL := "dot_props.toys"


## Adds one toy of catalogue [param id] at [param at] while the map runs (a loot crate dropped
## by a zombie). Its index is past the built ones, so a game that pairs toys by index with a
## client keeps such toys in a box of their own. Null when the id is unknown or the box is not
## in the tree.
func add_toy(id: StringName, at: Vector3, yaw: float = 0.0, p_def: Dictionary = {}) -> DotPropToy:
	if catalogue == null:
		catalogue = DotPropToyCatalogue.stock()
	var def := p_def if not p_def.is_empty() else catalogue.get_def(id)
	if def.is_empty() or not is_inside_tree():
		return null
	var placement := {"toy": str(id), "at": [at.x, at.y, at.z], "yaw": yaw}
	var toy := DotPropToy.new()
	toy.name = "Toy%d" % toys.size()
	toy.index = toys.size()
	toy.authoritative = authoritative
	toy.draw = draw
	toy.gravity = gravity
	toy.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	add_child(toy)
	toy.build(def, placement, {
		"loose_layer": loose_layer, "loose_mask": loose_mask,
		"solid_layer": solid_layer, "solid_mask": solid_mask,
	})
	var _s := toy.sound.connect(_on_toy_sound)
	toys.append(toy)
	return toy


## Takes [param toy] out of the box and frees it. The indexes of the toys after it move down.
func remove_toy(toy: DotPropToy) -> void:
	var at := toys.find(toy)
	if at < 0:
		return
	toys.remove_at(at)
	_rested.erase(toy)
	_calm.erase(toy)
	for i in range(at, toys.size()):
		toys[i].index = i
	if is_instance_valid(toy):
		remove_child(toy)
		toy.queue_free()


func clear() -> void:
	for toy in toys:
		if is_instance_valid(toy):
			remove_child(toy)
			toy.queue_free()
	toys.clear()
	_rested.clear()
	_calm.clear()
	missing.clear()
	if _footprints != null:
		remove_child(_footprints)
		_footprints.queue_free()
		_footprints = null


func count() -> int:
	return toys.size()


func toy(index: int) -> DotPropToy:
	return toys[index] if index >= 0 and index < toys.size() else null


func _build_footprints() -> void:
	if footprint_layer == 0:
		return
	_footprints = StaticBody3D.new()
	_footprints.name = "Footprints"
	_footprints.collision_layer = footprint_layer
	_footprints.collision_mask = 0
	# Never in the physics space: a baker parses the shapes off the nodes, and a game's shot
	# with every bit in its mask would otherwise stop on a two-metre box nobody can see.
	_footprints.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	_footprints.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_footprints)
	for t in toys:
		var box := t.footprint()
		if box.size == Vector3.ZERO:
			continue
		var shape := BoxShape3D.new()
		shape.size = box.size
		var node := CollisionShape3D.new()
		node.shape = shape
		node.transform = t.transform * Transform3D(Basis.IDENTITY, box.get_center())
		_footprints.add_child(node)


## The bodies a bot's walkable mesh should be baked round: one static body of boxes, one per
## toy that stands in the way (a swing's sweep, a see-saw, a roundabout, a trampoline). Never
## the loose toys, which a person walks through and pushes. Out of the physics space, so no
## ray or body ever meets them; none while `sv_toys` is 0.
func nav_bodies() -> Array:
	return [_footprints] if _footprints != null and (rules == null or rules.enabled) else []


# --- The server's tick ------------------------------------------------------------

## Whether [param t] is lost this tick, and the lost mode applied to it if so. A toy that has
## been nearly still for 0.3 s counts as resting where it is.
func _lost(t: DotPropToy, delta: float) -> bool:
	var at := t.body.global_position
	var slow := t.body.linear_velocity.length_squared() < 0.04
	var calm: float = (float(_calm.get(t, 0.0)) + delta) if slow else 0.0
	_calm[t] = calm
	if calm >= 0.3:
		_rested[t] = at
	var rested: Variant = _rested.get(t)
	var below := at.y < kill_y or not at.is_finite()
	if fall_limit > 0.0 and rested is Vector3:
		below = below or at.y < (rested as Vector3).y - fall_limit
	elif fall_limit > 0.0:
		below = below or at.y < t.rest.origin.y - fall_limit
	if not below:
		return false
	lost.emit(t)
	if not is_instance_valid(t) or toys.find(t) < 0:
		return true
	if lost_mode == LostMode.REMOVE:
		remove_toy(t)
		return true
	_calm.erase(t)
	if lost_mode == LostMode.LAST_REST and rested is Vector3:
		var spot := Transform3D(t.rest.basis, rested as Vector3)
		t.body.linear_velocity = Vector3.ZERO
		t.body.angular_velocity = Vector3.ZERO
		PhysicsServer3D.body_set_state(t.body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, spot)
		t.body.global_transform = spot
		t.body.sleeping = true
	else:
		t.reset()
		_rested.erase(t)
	return true

## One tick on the server: the clock, the lost toys sent home, and the awake cap.
func advance(delta: float) -> void:
	_now += delta
	if not authoritative or not rules.enabled:
		return
	var awake: Array[DotPropToy] = []
	for t: DotPropToy in toys.duplicate():
		if not is_instance_valid(t) or t.body == null:
			continue
		if _lost(t, delta):
			continue
		if t.awake():
			if sleep_after > 0.0:
				var slow := t.body.linear_velocity.length_squared() < 0.0025 and t.body.angular_velocity.length_squared() < 0.01
				t.still_for = t.still_for + delta if slow else 0.0
				if t.still_for >= sleep_after:
					t.still_for = 0.0
					t.body.linear_velocity = Vector3.ZERO
					t.body.angular_velocity = Vector3.ZERO
					t.body.sleeping = true
					continue
			awake.append(t)
	var cap := rules.cap()
	if awake.size() <= cap:
		return
	# The longest untouched sleep first, and among those the slowest, so a ball in flight is
	# the last to be stopped.
	awake.sort_custom(func(a: DotPropToy, b: DotPropToy) -> bool:
		if a.touched_at != b.touched_at:
			return a.touched_at < b.touched_at
		return a.body.linear_velocity.length_squared() < b.body.linear_velocity.length_squared())
	for i in range(awake.size() - cap):
		var t := awake[i]
		t.body.linear_velocity = Vector3.ZERO
		t.body.angular_velocity = Vector3.ZERO
		t.body.sleeping = true


## Toys simulating now.
func awake_count() -> int:
	var n := 0
	for t in toys:
		if t.awake():
			n += 1
	return n


## A person's capsule this tick: whatever loose toy it walks into is pushed, a roundabout's rim
## turned. Server side. Returns how many it moved.
func push_from(feet: Vector3, velocity: Vector3, radius: float, height: float) -> int:
	if not authoritative or not rules.enabled:
		return 0
	var n := 0
	for t in toys:
		if t.body != null and _near(t, feet, 4.0) and t.push_from(feet, velocity, radius, height, rules.push_scale):
			t.touched_at = _now
			n += 1
	return n


## A person of [param mass] kg standing at [param feet] this tick. Server side.
func stand_on(feet: Vector3, mass: float) -> int:
	if not authoritative or not rules.enabled:
		return 0
	var n := 0
	for t in toys:
		if t.body != null and _near(t, feet, 3.0) and t.stand_on(feet, mass, gravity):
			t.touched_at = _now
			n += 1
	return n


static func _near(t: DotPropToy, at: Vector3, reach: float) -> bool:
	return t.global_position.distance_squared_to(at) < (reach + t._radius) * (reach + t._radius) \
		or t.body.global_position.distance_squared_to(at) < (reach + t._radius) * (reach + t._radius)


## The velocity a bouncer or pad under [param feet] throws a person at, and which toy:
## `{velocity, index}`, or empty. A pure function of the placements, for both ends' movement.
func launch_for(feet: Vector3, velocity: Vector3) -> Dictionary:
	if not rules.enabled:
		return {}
	for t in toys:
		if t.kind != &"bouncer" and t.kind != &"pad":
			continue
		if t.global_position.distance_squared_to(feet) > 9.0:
			continue
		var out := t.launch_for(feet, velocity)
		if out != Vector3.INF:
			return {"velocity": out, "index": t.index}
	return {}


## A person standing at [param feet] on a turning roundabout this tick: how far it carries them
## and turns them, `{offset, yaw, index}`, or empty. [param ground_id] is the motor's collider
## underfoot (`DotFpsState.ground_id`); 0 looks for a roundabout under the feet instead. Both
## ends, in the movement after the move, like [method launch_for]: a client carries its own
## player at the spin it measured from the server's poses.
func carry_for(feet: Vector3, delta: float, ground_id: int = 0) -> Dictionary:
	if not rules.enabled or toys.is_empty():
		return {}
	if ground_id != 0:
		var t := toy_of(instance_from_id(ground_id))
		if t == null or t.kind != &"spinner":
			return {}
		return _carried(t, feet, delta)
	for t in toys:
		if t.kind == &"spinner" and t.global_position.distance_squared_to(feet) < 9.0:
			var out := _carried(t, feet, delta)
			if not out.is_empty():
				return out
	return {}


static func _carried(t: DotPropToy, feet: Vector3, delta: float) -> Dictionary:
	var out := t.carry(feet, delta)
	if not out.is_empty():
		out["index"] = t.index
	return out


## A person was thrown by toy [param index]: its count goes up, which is what every client hears.
## Server side.
func launched(index: int) -> void:
	var t := toy(index)
	if t != null and authoritative:
		t._bump_count()
		t.touched_at = _now


## The usable toy along a ray from [param origin], within [param reach], nothing solid between;
## -1 for none. Works on a client too (the frozen bodies are still there), for the prompt.
func aimed(origin: Vector3, direction: Vector3, reach: float = 2.2) -> int:
	if not rules.enabled or toys.is_empty() or not is_inside_tree():
		return -1
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * reach, aim_mask)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var t := toy_of(hit.get("collider"))
	return t.index if t != null and t.usable() else -1


## The toy a collider belongs to, or null.
static func toy_of(collider: Variant) -> DotPropToy:
	if collider is Object and is_instance_valid(collider) and (collider as Object).has_meta(&"dot_prop_toy"):
		var t: Variant = (collider as Object).get_meta(&"dot_prop_toy")
		return t as DotPropToy if t is DotPropToy else null
	return null


## Toy [param index] used by somebody at [param origin] looking along [param direction].
## Server side. True when it did something.
func use(index: int, origin: Vector3, direction: Vector3) -> bool:
	var t := toy(index)
	if t == null or not authoritative or not rules.enabled:
		return false
	if not t.use(origin, direction):
		return false
	t.touched_at = _now
	used.emit(index)
	return true


## A shot or a blast at [param point] hitting [param collider]: the toy it belongs to is pushed.
## Server side. The toy's index, or -1.
func hit(collider: Object, point: Vector3, direction: Vector3, impulse: float) -> int:
	var t := toy_of(collider)
	if t == null or not authoritative or not rules.enabled or not t.hit(point, direction, impulse):
		return -1
	t.touched_at = _now
	return t.index


## How hard a shot pushes a toy, from its damage: the speed it would give a toy of up to
## [constant SHOT_MASS_CAP] kg. A pistol's 25 sends a beach ball off at 5 m/s, a heavy rifle's
## 60 at the 9 m/s cap; a barrel, at the mass cap, takes a quarter of that. A bullet's real
## momentum would barely move a ball, and a damage-sized impulse sent one off at 40 m/s.
const SHOT_SPEED_PER_DAMAGE := 0.2
const SHOT_SPEED_MIN := 1.5
const SHOT_SPEED_MAX := 9.0
const SHOT_MASS_CAP := 3.0


## A shot that did [param damage] hitting [param collider] at [param point] along
## [param direction]: [method hit] with the push its damage is worth. Server side. The toy's
## index, or -1 when the collider is not a toy's (so a game's hit scan calls it first and falls
## through to its own damage). A shot bell rings.
func shot(collider: Object, point: Vector3, direction: Vector3, damage: float) -> int:
	var t := toy_of(collider)
	if t == null or damage <= 0.0:
		return -1
	var speed := clampf(damage * SHOT_SPEED_PER_DAMAGE, SHOT_SPEED_MIN, SHOT_SPEED_MAX)
	return hit(collider, point, direction, speed * _shot_mass(t))


## A shot from [param origin] along [param direction], [param reach] metres: the first toy on it
## is pushed as [method shot] pushes, unless something on [param wall_mask] (the level) stops
## the ray first. For a game whose own hit scan never meets a toy (an analytic trace, or a mask
## without the toys' layers) and which lets the shot go on to whoever is behind the ball, so a
## toy is never cover. Server side. The toy's index, or -1.
func shot_along(origin: Vector3, direction: Vector3, reach: float, damage: float, wall_mask: int = 0) -> int:
	if not authoritative or not rules.enabled or toys.is_empty() or not is_inside_tree() or reach <= 0.0:
		return -1
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * reach, wall_mask | loose_layer | solid_layer)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	return shot(hit.get("collider"), hit.get("position"), direction, damage)


## The mass a push is reckoned for: the toy's, up to the cap, and something for a fixed toy
## (a bell weighs nothing in the catalogue, and a push of nothing is refused).
static func _shot_mass(t: DotPropToy) -> float:
	return clampf(float(t.def.get("mass", 1.0)), 0.25, SHOT_MASS_CAP)


## A blast at [param at]: every moving toy within [param radius] is pushed away from it, at up to
## [param speed] m/s at the centre and nothing at the edge, whatever it weighs. Server side. How
## many it moved.
func blast(at: Vector3, radius: float, speed: float) -> int:
	if not authoritative or not rules.enabled or radius <= 0.0:
		return 0
	var n := 0
	for t in toys:
		if t.body == null:
			continue
		var from := t.body.global_position - at
		var dist := from.length()
		if dist > radius:
			continue
		var away := (from / dist) if dist > 0.01 else Vector3.UP
		# Up a little as well, or a blast on the ground slides a ball along it.
		away = (away + Vector3(0, 0.35, 0)).normalized()
		# The whole speed whatever the toy weighs: a blast throws a barrel as it throws a ball,
		# where a bullet (the mass cap in [method shot]) barely moves one.
		var push := speed * (1.0 - dist / radius) * maxf(float(t.def.get("mass", 1.0)), 0.25)
		if push > 0.0 and t.hit(t.body.global_position, away, push):
			t.touched_at = _now
			n += 1
	return n


func _flip(index: int) -> Variant:
	var t := toy(index)
	return t.flip() if t != null else null


## Every toy home, still and asleep: a round's start. Server side.
func reset() -> void:
	for t in toys:
		t.reset()


# --- Drawing ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if draw and authoritative and rules.enabled:
		for t in toys:
			t.sense(delta)


func _process(delta: float) -> void:
	if draw and not authoritative and rules.enabled:
		for t in toys:
			t.sense(delta)


func _on_toy_sound(id: StringName, at: Vector3, strength: float) -> void:
	sound.emit(id, at, strength)


## `sv_toys 0` takes every toy out of the world (no body, nothing drawn) on every end that
## follows the rules, and 1 puts them back where they were.
func _on_rules_changed() -> void:
	var on := rules == null or rules.enabled
	for t in toys:
		t.visible = on
		t.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func describe() -> Dictionary:
	return {
		"toys": toys.size(), "awake": awake_count(), "cap": rules.cap() if rules != null else 0,
		"enabled": rules.enabled if rules != null else true, "authoritative": authoritative,
		"missing": ", ".join(missing),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for t in toys:
		var d := t.describe()
		out.append("%d %s %s%s%s" % [t.index, d["id"], d["at"], " awake" if d["awake"] else "", " on" if d["on"] else ""])
	return out

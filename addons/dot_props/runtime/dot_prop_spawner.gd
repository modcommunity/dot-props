@tool
class_name DotPropSpawner
extends Node

## Spawns, tracks, limits and removes props. The node a sandbox game adds.
##
## [b]Server-authoritative, and props are not predicted.[/b] Everything else in this
## family is built so a client can predict it — movement, weapons, the timer — and
## props deliberately are not. Rigid-body simulation is not reproducible across
## machines: the solver's iteration order, the order bodies enter an island, and the
## last bits of every float differ between a server and a client, and two runs of the
## same stack of crates diverge in a second or two. A predicted prop is therefore a
## prop that is corrected constantly, which looks far worse than one that is simply
## interpolated a few tens of milliseconds behind.
##
## So: the server owns every prop, the client draws what it is told, and the tools
## ([DotPhysGun], [DotGravGun]) send [i]intent[/i] and receive results. That is the
## same division [DotFpsCommand] makes, minus the prediction.
##
## [codeblock]
## var spawner := DotPropSpawner.new()
## spawner.catalogue = catalogue
## spawner.limits = DotPropLimits.new()
## spawner.world_ref = DotNodeRef.of_path(^"../World")
## add_child(spawner)
##
## var spawned := spawner.spawn(&"crate", player_id, at, basis)
## [/codeblock]

const CHANNEL := "props"

## A prop entered the world.
signal spawned(prop: DotPropInstance)

## A prop left it. [param reason] is one of the REASON_* constants.
signal removed(prop: DotPropInstance, reason: StringName)

## A spawn was refused, and why. For telling the player.
##
## [b]Emitted rather than swallowed.[/b] "I pressed spawn and nothing happened" is the
## commonest complaint on a sandbox server and the reason is almost always one the
## player could have been told: their budget, the cooldown, the world cap.
signal refused(player_id: StringName, prop_id: StringName, reason: String)

const REASON_PLAYER := &"player"
const REASON_UNDO := &"undo"
const REASON_LEFT := &"left"
const REASON_CLEANUP := &"cleanup"
const REASON_ADMIN := &"admin"

@export_group("Content")

@export var catalogue: DotPropCatalogue = null

@export var limits: DotPropLimits = null

@export_group("Wiring")

## Where spawned props are added. Defaults to this node.
@export var world_ref: DotNodeRef = null

@export_group("Role")

## Whether this spawner may actually create props.
##
## [b]False on a client.[/b] A client holds a spawner so it can render and account for
## what the server tells it about; if it could spawn, a modified client would fill the
## world. Every mutating method refuses on a non-authoritative spawner before it
## checks anything else.
@export var authoritative: bool = false

## Instance id -> DotPropInstance.
var _props: Dictionary = {}

## Player id -> Array[int] of every instance id they own, newest last.
##
## [b]Not the undo stack, and keeping them apart is the fix for a real bug.[/b] The
## first version used one list for both, and trimming it to the undo depth therefore
## removed props from their owner's ACCOUNT as well as from their history: a player
## whose undo depth was 64 could hold 64 props against their budget and any number
## beyond it for free, and `clear_player` left everything past the depth in the world
## for ever. The self-test caught it as a count of three where five had been spawned.
var _by_player: Dictionary = {}

## Player id -> Array[int], newest last, bounded by [member DotPropLimits.undo_depth].
##
## History, not ownership. Passing the depth means the oldest can no longer be undone,
## not that it stops being yours.
var _undo: Dictionary = {}

## Player id -> seconds of simulated time when they last spawned.
var _last_spawn: Dictionary = {}

## Simulated seconds, advanced by the host. See [method advance].
##
## [b]Not a wall clock.[/b] The cooldown has to be the same on a server that stalls
## for a second as on one that does not, and a wall clock lets a player who lags the
## server spawn faster than one who does not.
var _now: float = 0.0

var _world: Node = null

var spawn_count: int = 0
var refusal_count: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if limits == null:
		limits = DotPropLimits.new()

	var valid := limits.validate()

	if not valid.ok:
		DotLog.warn(CHANNEL, "prop limits are not usable", {
			"why": valid.error.message
		})


## Advances the spawner's clock. Call once per simulated tick with the tick duration.
func advance(delta: float) -> void:
	_now += delta


# --- Spawning --------------------------------------------------------------

## Spawns a prop for a player. Null on refusal, with [signal refused] emitted.
##
## [param entitlements] is whatever the host uses to answer "may this player have
## this" — a [Callable] taking the entitlement id, or an empty one for no check. This
## addon does not know what an entitlement is; it knows a prop can require one.
func spawn(
	prop_id: StringName,
	player_id: StringName,
	at: Vector3,
	orientation: Basis = Basis.IDENTITY,
	entitlements: Callable = Callable()
) -> DotPropInstance:
	if not authoritative:
		_refuse(player_id, prop_id, "This client may not spawn props.")
		return null

	if catalogue == null:
		_refuse(player_id, prop_id, "This server has no prop catalogue.")
		return null

	var def := catalogue.get_prop(prop_id)

	if def == null or not def.enabled:
		_refuse(player_id, prop_id, "No such prop.")
		return null

	if def.entitlement != &"" and entitlements.is_valid():
		if not bool(entitlements.call(def.entitlement)):
			_refuse(player_id, prop_id, "You do not have that prop.")
			return null

	var allowed := may_spawn(def, player_id)

	if not allowed.ok:
		_refuse(player_id, prop_id, allowed.error.message)
		return null

	if not ResourceLoader.exists(def.scene_path):
		# A prop in the catalogue whose content is not mounted. Distinguished from
		# "no such prop" because the two need different fixes: this one is a missing
		# pack, and telling the player "no such prop" sends them to the wrong place.
		_refuse(
			player_id, prop_id,
			"That prop's content is not loaded on this server."
		)
		return null

	var scene: Resource = load(def.scene_path)

	if not (scene is PackedScene):
		_refuse(player_id, prop_id, "That prop's scene is not a PackedScene.")
		return null

	var resolved := _resolve_world()

	if not resolved.ok:
		_refuse(player_id, prop_id, resolved.error.message)
		return null

	var node := (scene as PackedScene).instantiate()

	if not (node is Node3D):
		node.queue_free()
		_refuse(player_id, prop_id, "That prop's scene is not a Node3D.")
		return null

	var body := node as Node3D
	body.global_transform = Transform3D(orientation, at)

	# The definition's mass is put ON the body, rather than left to whatever the
	# scene was saved with.
	#
	# [b]Otherwise `mass` is a number nothing simulates.[/b] It is read in exactly
	# one place — `DotPropTool.may_act_on`, against `grab_mass_limit` — so a
	# catalogue that says 900 kg and a scene saved at 20 kg gives a prop that is
	# refused by a physics gun for being too heavy and then thrown like a beach ball
	# by a gravity gun. Nothing errors either way, and the two numbers are only ever
	# compared by a player wondering why. A game that ships one scene for a dozen
	# props — which is the cheap way to do it, and what game-playground does — has
	# every one of them at the same mass without this line.
	#
	# Assigned before the body is in the tree, so the first physics step already sees
	# it: dot-props' own suite found that a mass set after an impulse divides that
	# impulse by the OLD mass, and a prop spawned into a stack is pushed on its first
	# step.
	if body is RigidBody3D:
		(body as RigidBody3D).mass = def.mass

	(resolved.value as Node).add_child(body)

	var instance := DotPropInstance.new()
	instance.def = def
	instance.node = body
	instance.owner_id = player_id
	instance.instance_id = body.get_instance_id()
	instance.spawned_at = _now

	_props[instance.instance_id] = instance

	if not _by_player.has(player_id):
		_by_player[player_id] = []

	if not _undo.has(player_id):
		_undo[player_id] = []

	(_by_player[player_id] as Array).append(instance.instance_id)
	(_undo[player_id] as Array).append(instance.instance_id)

	_trim_undo(player_id)

	_last_spawn[player_id] = _now
	spawn_count += 1

	spawned.emit(instance)

	return instance


## Whether a player may spawn one of these right now.
func may_spawn(def: DotPropDef, player_id: StringName) -> DotResult:
	if limits == null:
		return DotResult.success(null)

	if def.size > limits.max_size:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"That prop is too large for this server.",
			"%s, ceiling %s" % [
				DotPropDef.Size.keys()[def.size],
				DotPropDef.Size.keys()[limits.max_size],
			]
		)

	if limits.spawn_interval > 0.0 and _last_spawn.has(player_id):
		var elapsed := _now - float(_last_spawn[player_id])

		if elapsed < limits.spawn_interval:
			return DotResult.fail(
				DotError.CODE_RATE_LIMITED,
				"Slow down.",
				"%.2f s of %.2f s" % [elapsed, limits.spawn_interval]
			)

	if limits.world_budget > 0 and world_cost() + def.cost > limits.world_budget:
		return DotResult.fail(
			DotError.CODE_QUOTA,
			"The server is at its prop limit.",
			"%d of %d" % [world_cost(), limits.world_budget]
		)

	if limits.per_player_budget > 0:
		var mine := player_cost(player_id)

		if mine + def.cost > limits.per_player_budget:
			return DotResult.fail(
				DotError.CODE_QUOTA,
				"You are at your prop limit.",
				"%d of %d" % [mine, limits.per_player_budget]
			)

	return DotResult.success(null)


## Whether a player may freeze another prop.
##
## Separate from the spawn budget because a frozen prop costs nothing to simulate —
## a builder should be allowed more of them than a physics budget would give. Counted
## over what they actually own, not tracked as a running total, because a running
## total drifts the moment a prop is removed by anything that did not decrement it.
func may_freeze(player_id: StringName) -> DotResult:
	if limits == null or limits.per_player_frozen <= 0:
		return DotResult.success(null)

	var frozen := frozen_count(player_id)

	if frozen >= limits.per_player_frozen:
		return DotResult.fail(
			DotError.CODE_QUOTA,
			"You have frozen as many props as this server allows.",
			"%d of %d" % [frozen, limits.per_player_frozen]
		)

	return DotResult.success(null)


## How many of a player's props are frozen.
func frozen_count(player_id: StringName) -> int:
	var total := 0

	for prop in props_of(player_id):
		if prop.frozen:
			total += 1

	return total


func _refuse(player_id: StringName, prop_id: StringName, reason: String) -> void:
	refusal_count += 1
	refused.emit(player_id, prop_id, reason)


# --- Removing --------------------------------------------------------------

func remove(instance_id: int, reason: StringName = REASON_PLAYER) -> bool:
	if not authoritative:
		return false

	var found: Variant = _props.get(instance_id)

	if not (found is DotPropInstance):
		return false

	var instance: DotPropInstance = found

	_props.erase(instance_id)

	if _by_player.has(instance.owner_id):
		(_by_player[instance.owner_id] as Array).erase(instance_id)

	if _undo.has(instance.owner_id):
		(_undo[instance.owner_id] as Array).erase(instance_id)

	# Announced BEFORE the node is freed, so a listener holding a reference — a
	# physics gun with this prop in its hand, a netcode replicating it — can let go
	# while it still exists. Freeing first leaves every one of them with a freed
	# object and a null check they did not know they needed.
	removed.emit(instance, reason)

	# Marked dead immediately, and this is not the same as freeing the node.
	# queue_free() is DEFERRED — is_instance_valid stays true for the rest of the
	# frame — so a tool that checked only the node would keep working on a prop that
	# has already been removed, for as long as the frame lasts. That is exactly the
	# window in which an admin cleanup happens under somebody's physics gun.
	instance.alive = false

	if instance.node != null and is_instance_valid(instance.node):
		instance.node.queue_free()

	return true


## Undoes a player's most recent spawn. False when they have nothing to undo.
func undo(player_id: StringName) -> bool:
	var stack_value: Variant = _undo.get(player_id)

	if not (stack_value is Array) or (stack_value as Array).is_empty():
		return false

	var stack: Array = stack_value

	return remove(int(stack[stack.size() - 1]), REASON_UNDO)


## Removes everything a player spawned. Returns how many went.
func clear_player(
	player_id: StringName, reason: StringName = REASON_CLEANUP
) -> int:
	var stack_value: Variant = _by_player.get(player_id)

	if not (stack_value is Array):
		return 0

	# Copied before iterating: remove() mutates this array, and iterating a list
	# while removing from it skips every other entry — which leaves half a player's
	# props behind and is invisible until somebody counts.
	var ids: Array = (stack_value as Array).duplicate()
	var count := 0

	for id in ids:
		if remove(int(id), reason):
			count += 1

	_by_player.erase(player_id)
	_undo.erase(player_id)
	_last_spawn.erase(player_id)

	return count


## Removes every prop in the world.
func clear_all(reason: StringName = REASON_ADMIN) -> int:
	var ids: Array = _props.keys()
	var count := 0

	for id in ids:
		if remove(int(id), reason):
			count += 1

	return count


## Called by the host when a player disconnects.
func player_left(player_id: StringName) -> int:
	if limits != null and not limits.clean_up_on_leave:
		# Kept, but disowned: the props stay and stop counting against a budget
		# nobody is using. A persistent build server wants exactly this, and without
		# the disown the budget of a departed player is held for ever.
		_by_player.erase(player_id)
		_undo.erase(player_id)
		_last_spawn.erase(player_id)
		return 0

	return clear_player(player_id, REASON_LEFT)


func _trim_undo(player_id: StringName) -> void:
	if limits == null or limits.undo_depth <= 0:
		return

	var stack: Array = _undo[player_id]

	# Only the HISTORY is trimmed, never the ownership list. Passing the undo depth
	# means the oldest can no longer be undone — not that it disappears, and not that
	# it stops counting against the budget. Doing this to the ownership list, which
	# is what the first version did, let a player spawn past their undo depth for
	# free and left everything past it in the world when they disconnected.
	while stack.size() > limits.undo_depth:
		stack.pop_front()


# --- Queries ---------------------------------------------------------------

func get_prop(instance_id: int) -> DotPropInstance:
	var found: Variant = _props.get(instance_id)
	return found if found is DotPropInstance else null


## The prop a node belongs to, or null. For a tool that has hit something.
func prop_for_node(node: Node) -> DotPropInstance:
	if node == null:
		return null

	# Walks up, because a physics query hits a collider that may be a child of the
	# prop's own root — which is what a prop with several shapes looks like.
	var walk := node

	while walk != null:
		var found: Variant = _props.get(walk.get_instance_id())

		if found is DotPropInstance:
			return found

		walk = walk.get_parent()

	return null


func world_count() -> int:
	return _props.size()


func world_cost() -> int:
	var total := 0

	for id in _props:
		total += (_props[id] as DotPropInstance).def.cost

	return total


func player_count(player_id: StringName) -> int:
	var stack_value: Variant = _by_player.get(player_id, [])
	return (stack_value as Array).size() if stack_value is Array else 0


func player_cost(player_id: StringName) -> int:
	var stack_value: Variant = _by_player.get(player_id)

	if not (stack_value is Array):
		return 0

	var total := 0

	for id in (stack_value as Array):
		var found: Variant = _props.get(int(id))

		if found is DotPropInstance:
			total += (found as DotPropInstance).def.cost

	return total


## Every live prop in the world, whoever owns it.
##
## [b]A copy, and that is not a nicety.[/b] Callers walk this to decide what to
## remove, freeze or shove, and removing a prop mutates the list it came from — so
## handing out the internal one turns "clear everything in a radius" into a loop that
## skips every second prop. `clear_all` makes the same copy for the same reason.
func all_props() -> Array[DotPropInstance]:
	var out: Array[DotPropInstance] = []

	for id in _props:
		var prop: DotPropInstance = _props[id]

		if prop.is_alive():
			out.append(prop)

	return out


func props_of(player_id: StringName) -> Array[DotPropInstance]:
	var out: Array[DotPropInstance] = []
	var stack_value: Variant = _by_player.get(player_id, [])

	if not (stack_value is Array):
		return out

	for id in (stack_value as Array):
		var found: Variant = _props.get(int(id))

		if found is DotPropInstance:
			out.append(found)

	return out


func _resolve_world() -> DotResult:
	if world_ref == null:
		return DotResult.success(self)

	if _world != null and is_instance_valid(_world):
		return DotResult.success(_world)

	var resolved := world_ref.resolve(self)

	if not resolved.ok:
		return resolved.wrap("Could not find where to put spawned props.")

	_world = resolved.value

	return DotResult.success(_world)


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"props": _props.size(),
		"cost": world_cost(),
		"players": _by_player.size(),
		"spawned": spawn_count,
		"refused": refusal_count,
		"limits": limits.describe_summary() if limits != null else "none",
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("props        %d (%d cost)" % [_props.size(), world_cost()])
	out.append("limits       %s" % (
		limits.describe_summary() if limits != null else "none"
	))

	for player_id in _by_player:
		out.append("  %-16s %d props, %d cost" % [
			String(player_id), player_count(player_id), player_cost(player_id)
		])

	return out

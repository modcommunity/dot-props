class_name DotPropDamage
extends Node

## Health for props, and the blast one leaves behind. The half a crate needs to break.
##
## [b]Health lives here and not on the prop's scene.[/b] A prop in this addon is a
## plain scene with a [RigidBody3D] at its root — that is what makes one droppable,
## what lets a dot-cloud pack ship one, and what
## [method DotPropSpawner.spawn] assumes. Putting hit points on the node would mean
## every breakable prop needs a script, every such script needs to resolve
## [code]class_name[/code] at load, and a delivered pack cannot do that: this family
## measured that a script in a mounted pack cannot resolve its own base class. So the
## numbers are on [DotPropDef], which is a document, and the state is here, keyed by
## the instance id the spawner already hands out.
##
## [b]It deals no damage to anybody.[/b] dot-combat owns the damage model — hit groups,
## armour, team scales, falloff — and a second one inside a prop addon would be a
## second set of rules about who a blast hurts. When a barrel goes off this emits
## [signal exploded] describing the blast and stops; the game hands that to
## [code]DotCombatManager.explode[/code]. The prop knows it is a barrel. Only the game
## knows what a barrel does to a person.
##
## [codeblock]
## var damage := DotPropDamage.new()
## damage.spawner_ref = DotNodeRef.of_path(^"../Props")
## add_child(damage)
## damage.exploded.connect(_on_prop_exploded)
## damage.hurt(crate_id, 40.0, &"u7")
## [/codeblock]

const CHANNEL := "props"

## Why a prop was removed when this broke it. Extends [DotPropSpawner]'s REASON_*.
const REASON_BROKEN := &"broken"

## A prop took damage and survived it.
signal damaged(prop: DotPropInstance, amount: float, remaining: float, by: StringName)

## A prop's health reached zero, or an impact broke it outright.
##
## Fired [i]before[/i] the prop is removed, so a handler can still read its node,
## its transform and its velocity — which is what spawning debris where it stood
## needs. The prop is gone by the time this returns.
signal broken(prop: DotPropInstance, at: Vector3, by: StringName)

## A broken prop described a blast. Hand it to a damage model; nothing here will.
signal exploded(at: Vector3, radius: float, damage: float, force: float, by: StringName)

@export_group("Wiring")

## The spawner whose props this tracks.
@export var spawner_ref: DotNodeRef = null

@export_group("Role")

## Whether this may actually break anything.
##
## False on a client, for [DotPropSpawner.authoritative]'s reason: a prop's existence
## is the server's to decide, and a client that could break one would disagree with
## the server about what is in the world.
@export var authoritative: bool = false

## Instance id -> remaining health.
var _health: Dictionary = {}

var _spawner: DotPropSpawner = null


func _ready() -> void:
	_spawner = _resolve_spawner()
	if _spawner == null:
		DotLog.error(CHANNEL, "prop damage has no spawner; nothing will be breakable")
		return

	_spawner.spawned.connect(_on_spawned)
	_spawner.removed.connect(_on_removed)

	# Props that already exist. A damage node added after a spawner has been running
	# would otherwise treat every prop already in the world as indestructible, which
	# is a map whose crates break only if you reload it.
	for prop in _spawner.all_props():
		_on_spawned(prop)


func _resolve_spawner() -> DotPropSpawner:
	if spawner_ref == null:
		return get_parent() as DotPropSpawner
	return spawner_ref.resolve_or_null(self, CHANNEL) as DotPropSpawner


func _on_spawned(prop: DotPropInstance) -> void:
	if prop == null or prop.def == null:
		return
	if prop.def.max_health > 0.0:
		_health[prop.instance_id] = prop.def.max_health


func _on_removed(prop: DotPropInstance, _reason: StringName) -> void:
	if prop != null:
		_health.erase(prop.instance_id)


## Remaining health, or 0.0 for a prop with none and -1.0 for one that is indestructible.
##
## The three answers are distinct on purpose: "about to break", "already gone" and
## "cannot be broken" are different things to a caller deciding whether to bother
## swinging at it.
func health_of(instance_id: int) -> float:
	if not _health.has(instance_id):
		return -1.0
	return float(_health[instance_id])


func is_breakable(instance_id: int) -> bool:
	return _health.has(instance_id)


## Take [param amount] off a prop, breaking it if that reaches zero.
##
## Returns the remaining health, 0.0 if this broke it, or a failure when the prop is
## not one this can hurt. Never null, per the family's rule about fallible calls.
func hurt(instance_id: int, amount: float, by: StringName = &"") -> DotResult:
	if not authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Only an authoritative prop-damage node may hurt a prop."
		)

	if amount <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "Damage must be positive.")

	if _spawner == null:
		return DotResult.fail(DotError.CODE_STATE, "No spawner.")

	var prop := _spawner.get_prop(instance_id)
	if prop == null or not prop.is_alive():
		return DotResult.fail(DotError.CODE_INVALID, "No such prop.", str(instance_id))

	if not _health.has(instance_id):
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "That prop cannot be broken.", prop.def.name_or_id()
		)

	var remaining: float = maxf(float(_health[instance_id]) - amount, 0.0)
	_health[instance_id] = remaining

	if remaining > 0.0:
		damaged.emit(prop, amount, remaining, by)
		return DotResult.success(remaining)

	_break(prop, by)
	return DotResult.success(0.0)


## Break a prop outright, whatever its health. What a fast impact does.
func break_now(instance_id: int, by: StringName = &"") -> DotResult:
	if not authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Only an authoritative prop-damage node may break a prop."
		)

	if _spawner == null:
		return DotResult.fail(DotError.CODE_STATE, "No spawner.")

	var prop := _spawner.get_prop(instance_id)
	if prop == null or not prop.is_alive():
		return DotResult.fail(DotError.CODE_INVALID, "No such prop.", str(instance_id))

	if not _health.has(instance_id):
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "That prop cannot be broken.", prop.def.name_or_id()
		)

	_break(prop, by)
	return DotResult.success(0.0)


## Report a collision against a prop at [param speed] m/s, breaking it if that is enough.
##
## [b]Closing speed, not damage, and that is the whole point of the field.[/b] A crate
## has to survive being walked into and must not survive a bus, and what separates
## those two is how fast the thing arrived rather than how many times it has been hit.
## Returns true when the impact broke it.
func impact(instance_id: int, speed: float, by: StringName = &"") -> bool:
	if not authoritative or _spawner == null:
		return false

	var prop := _spawner.get_prop(instance_id)
	if prop == null or not prop.is_alive() or prop.def == null:
		return false

	var threshold := prop.def.break_impact_speed
	if threshold <= 0.0 or speed < threshold:
		return false

	_break(prop, by)
	return true


func _break(prop: DotPropInstance, by: StringName) -> void:
	var at := prop.position()

	# Said before the prop is removed, because where it stood and how fast it was
	# going is the whole of what debris and an explosion need, and `queue_free` has
	# already been called by the time a `removed` handler runs.
	broken.emit(prop, at, by)

	var def := prop.def
	if def != null and def.explode_radius > 0.0:
		exploded.emit(at, def.explode_radius, def.explode_damage, def.explode_force, by)
		_shove_nearby(prop, at, def.explode_radius, def.explode_force)

	_health.erase(prop.instance_id)
	_spawner.remove(prop.instance_id, REASON_BROKEN)

	DotLog.debug(
		CHANNEL,
		"prop broken",
		{"prop": def.name_or_id() if def != null else "?", "by": String(by)},
	)


## Push every other prop in the blast away from it.
##
## [b]Props only, and that is not a shortcut.[/b] This addon knows what a prop is and
## nothing else: a player, an NPC and a vehicle are all somebody else's, and pushing
## one would need their id space, their authority rules and their prediction. The
## game gets the blast on [signal exploded] and pushes whatever else it owns.
func _shove_nearby(source: DotPropInstance, at: Vector3, radius: float, force: float) -> void:
	if force <= 0.0:
		return

	for other in _spawner.all_props():
		if other.instance_id == source.instance_id or not other.is_alive():
			continue

		var body := other.body()
		if body == null or body.freeze:
			continue

		var offset := body.global_position - at
		var distance := offset.length()
		if distance > radius:
			continue

		# A body whose centre is exactly on the blast has no direction to go, and
		# normalising a zero vector is a zero vector rather than an error — so it
		# would silently take no impulse at all, which is the one case a barrel is
		# most obviously supposed to move something.
		var direction := offset / distance if distance > 0.001 else Vector3.UP
		var falloff := 1.0 - (distance / radius)
		body.apply_central_impulse(direction * force * falloff)


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"tracked": _health.size(),
		"spawner": _spawner != null,
	}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("DotPropDamage: %d breakable prop(s)" % _health.size())
	if _spawner == null:
		lines.append("  no spawner")
		return lines
	for instance_id: int in _health:
		var prop := _spawner.get_prop(instance_id)
		var name_of := prop.def.name_or_id() if prop != null and prop.def != null else "?"
		lines.append("  %-16s %.0f hp" % [name_of, float(_health[instance_id])])
	return lines


func _to_string() -> String:
	return "DotPropDamage(%d)" % _health.size()

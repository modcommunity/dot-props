class_name DotPropTool
extends RefCounted

## What a tool that acts on props has in common: a reach, a target, and a holder.
##
## [b]A tool is not a node and does not own a camera.[/b] It is given an origin and a
## direction each tick and asked what it would hit — so the same physics gun works
## for a player with a first-person camera, for a bot, for a replay being played back,
## and for a headless test, none of which have a viewport.
##
## Subclasses: [DotPhysGun], [DotGravGun].

const CHANNEL := "props.tool"

## The spawner that owns the props this tool acts on.
var spawner: DotPropSpawner = null

## Who is holding the tool. Used for permission and for the one-holder rule.
var wielder: StringName = &""

## How far it reaches, in metres. Falls back to the spawner's limits.
var reach: float = 0.0


func effective_reach() -> float:
	if reach > 0.0:
		return reach

	if spawner != null and spawner.limits != null:
		return spawner.limits.grab_range

	return 40.0


## What the tool would act on, looking along [param direction] from [param origin].
##
## [param space] is a [PhysicsDirectSpaceState3D]. Typed [Variant] so this file does
## not depend on being in a 3D scene to compile — a headless test drives the tools
## with a stub, which is how they are tested at all.
func target(
	space: Variant,
	origin: Vector3,
	direction: Vector3,
	mask: int = 0xFFFFFFFF
) -> DotPropInstance:
	if space == null or spawner == null:
		return null

	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * effective_reach()
	)
	query.collision_mask = mask
	query.collide_with_areas = false

	var hit: Dictionary = space.intersect_ray(query)

	if hit.is_empty():
		return null

	return spawner.prop_for_node(hit.get("collider") as Node)


## Whether this tool may act on [param prop].
##
## [b]Ownership is deliberately not checked here.[/b] Whether a player may move
## somebody else's crate is a server policy — a build server says no, a sandbox says
## yes, a competitive one says only for admins — and hard-coding either answer means
## the other needs a fork. The host passes [param can_touch_others].
func may_act_on(prop: DotPropInstance, can_touch_others: bool = true) -> DotResult:
	if prop == null or not prop.is_alive():
		return DotResult.fail(DotError.CODE_STATE, "Nothing there.")

	if prop.def == null or not prop.def.can_grab:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "That cannot be picked up."
		)

	if prop.is_held() and prop.held_by != wielder:
		# One holder at a time. Two guns pulling one crate toward two players makes
		# it oscillate violently between them and costs ten times the physics step.
		return DotResult.fail(
			DotError.CODE_STATE, "Somebody else is holding that."
		)

	if not can_touch_others and prop.owner_id != wielder:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "That is not yours."
		)

	if spawner != null and spawner.limits != null:
		var cap := spawner.limits.grab_mass_limit

		if cap > 0.0 and prop.def.mass > cap:
			return DotResult.fail(
				DotError.CODE_FORBIDDEN,
				"That is too heavy.",
				"%.0f kg, limit %.0f kg" % [prop.def.mass, cap]
			)

	return DotResult.success(prop)


func describe() -> Dictionary:
	return {
		"tool": get_script().get_global_name() if get_script() != null else "?",
		"wielder": String(wielder),
		"reach": "%.1f m" % effective_reach(),
	}

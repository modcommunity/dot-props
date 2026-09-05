@tool
class_name DotPropDef
extends Resource

## One thing a player can spawn.
##
## [b]A definition, not a scene.[/b] The scene path is one field of it, because
## everything else about a prop — what it costs against a player's budget, which
## category it appears under, whether they are entitled to it, how heavy it is when a
## physics gun picks it up — is decided by the server and has to be answerable
## [i]without loading the scene[/i]. A server validating a spawn request against
## thirty players' budgets cannot load thirty scenes to do it, and a client showing a
## spawn menu of four hundred props must not load four hundred.
##
## The same reasoning as [code]DotItem[/code] in dot-loadout and
## [code]DotAvatarSchema[/code] in dot-user-avatar: the document is checkable on its
## own, and the content is fetched only when something is actually created.

## Rough size, which is what a spawn budget is really about.
##
## Not a mass and not a bounding box: a server limiting what a player may spawn cares
## about how much simulation and how much screen a prop costs, and neither of those
## tracks mass. A concrete slab and a beach ball of the same size cost the same to
## simulate.
enum Size {
	TINY,
	SMALL,
	MEDIUM,
	LARGE,
	HUGE,
}

@export_group("Identity")

## Stable id. What a spawn request names and what an entitlement is keyed on.
@export var id: StringName = &""

@export var display_name: String = ""

## Menu grouping: [code]"props/furniture"[/code], [code]"vehicles"[/code].
@export var category: StringName = &"props"

## An icon path for a spawn menu. Not loaded by anything here.
@export var icon_path: String = ""

@export_group("Content")

## The scene instantiated on spawn.
##
## May live inside a dot-cloud pack, in which case the pack must be mounted first —
## which is the game's business, not this addon's. See [DotPropSpawner].
@export var scene_path: String = ""

## The dot-cloud content id this prop lives in, or empty when it ships in the build.
@export var content_id: StringName = &""

@export_group("Simulation")

@export var size: Size = Size.MEDIUM

## Mass in kilograms, for a physics gun that pulls harder on a heavy thing.
##
## Advisory. The authority is whatever the scene's own [RigidBody3D] says; this is
## here so a menu can show it and a limit can budget against it without loading the
## scene.
@export_range(0.1, 100000.0, 0.1) var mass: float = 20.0

## Whether a physics gun may pick this up at all.
##
## Off for scenery a mapper placed, for a door, for anything whose position is part of
## the level. A sandbox without this is a sandbox where somebody takes the floor away.
@export var can_grab: bool = true

## Whether the prop may be frozen in place.
@export var can_freeze: bool = true

## What one of these costs against a player's budget. See [DotPropLimits].
##
## Separate from [member size] so a server can make one specific prop expensive
## without reclassifying it — which is what actually happens when one model turns out
## to be the one everybody spams.
@export_range(1, 100, 1) var cost: int = 1

@export_group("Permission")

## An entitlement id the player must hold, or empty for anybody.
##
## Checked by the host against whatever it uses for entitlements — dot-platform's
## source, a group on the site, an admin flag. This addon does not know what an
## entitlement is; it knows that a prop can require one.
@export var entitlement: StringName = &""

## An admin permission required instead. Empty for anybody.
@export var permission: String = ""

## Whether the prop can be spawned at all right now.
@export var enabled: bool = true

@export var meta: Dictionary = {}


static func make(p_id: StringName, p_scene: String) -> DotPropDef:
	var prop := DotPropDef.new()
	prop.id = p_id
	prop.scene_path = p_scene
	prop.display_name = String(p_id).capitalize()
	return prop


func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


func is_local() -> bool:
	return content_id == &""


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A prop needs an id.")

	if scene_path == "":
		return DotResult.fail(
			DotError.CODE_INVALID, "A prop needs a scene path.", String(id)
		)

	return DotResult.success(null)


func to_dictionary() -> Dictionary:
	var out := {
		"id": String(id),
		"scene": scene_path,
		"category": String(category),
		"size": size,
		"mass": mass,
		"cost": cost,
	}

	if display_name != "":
		out["name"] = display_name
	if icon_path != "":
		out["icon"] = icon_path
	if content_id != &"":
		out["content"] = String(content_id)
	if not can_grab:
		out["can_grab"] = false
	if not can_freeze:
		out["can_freeze"] = false
	if entitlement != &"":
		out["entitlement"] = String(entitlement)
	if permission != "":
		out["permission"] = permission
	if not enabled:
		out["enabled"] = false
	if not meta.is_empty():
		# Duplicated: a Dictionary is a reference in GDScript, so handing this one
		# out lets whoever serialises a prop edit the shared definition.
		out["meta"] = meta.duplicate(true)

	return out


static func from_dictionary(data: Dictionary) -> DotPropDef:
	var prop := DotPropDef.new()

	prop.id = StringName(str(data.get("id", "")))
	prop.scene_path = str(data.get("scene", ""))
	prop.display_name = str(data.get("name", ""))
	prop.category = StringName(str(data.get("category", "props")))
	prop.icon_path = str(data.get("icon", ""))
	prop.content_id = StringName(str(data.get("content", "")))
	prop.size = _to_size(data.get("size", Size.MEDIUM))
	prop.mass = maxf(float(data.get("mass", 20.0)), 0.1)
	prop.cost = clampi(int(data.get("cost", 1)), 1, 100)
	prop.can_grab = bool(data.get("can_grab", true))
	prop.can_freeze = bool(data.get("can_freeze", true))
	prop.entitlement = StringName(str(data.get("entitlement", "")))
	prop.permission = str(data.get("permission", ""))
	prop.enabled = bool(data.get("enabled", true))

	var meta_value: Variant = data.get("meta", {})
	prop.meta = (
		(meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	)

	return prop


static func _to_size(value: Variant) -> Size:
	var raw := int(value)
	return raw as Size if raw >= 0 and raw < Size.size() else Size.MEDIUM


func describe() -> Dictionary:
	return {
		"id": String(id),
		"category": String(category),
		"size": Size.keys()[size],
		"mass": "%.1f kg" % mass,
		"cost": cost,
		"grabbable": can_grab,
	}


func _to_string() -> String:
	return "DotPropDef(%s)" % String(id)

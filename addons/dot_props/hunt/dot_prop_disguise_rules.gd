class_name DotPropDisguiseRules
extends Resource

## What a server allows a player hiding as a prop: how big a thing they may become, how much it
## takes to kill them as it, how close they must be to copy it, and what showing themselves
## costs. Read by [DotPropDisguise]; a game fills it from its own configuration.
##
## [b]Health follows size, but not in proportion to volume.[/b] A filing cabinet is a hundred
## and fifty times a bottle's volume, and a cabinet that took a hundred and fifty times as many
## hits would be the only prop anybody picked. The hiding games settled on a curve that rises
## much more slowly — a cabinet about nine times a bottle — which is [member health_exponent]:
## health = [member health_scale] × volume ^ exponent, clamped. 0.45 and 190 put a 0.5 m³
## cabinet at about 140 and a three-litre bottle at about 14.

@export_group("Health")

## Health at one cubic metre.
@export_range(1.0, 10000.0, 1.0) var health_scale: float = 190.0

## How fast health rises with volume. 1 is in proportion; 0 is the same for everything.
@export_range(0.0, 1.0, 0.01) var health_exponent: float = 0.45

@export_range(1.0, 10000.0, 1.0) var min_health: float = 10.0
@export_range(1.0, 10000.0, 1.0) var max_health: float = 200.0

## Whether a player who changes disguise keeps the FRACTION of health they had. Off, a hurt
## player who finds a bigger prop is healed by it, which turns every chase into a dash for the
## nearest sofa.
@export var keep_health_fraction: bool = true

@export_group("Size")

## The smallest dimension a player may hide as, in metres. Under it a prop is too small to find,
## and a round against somebody who is a pencil is not a round.
@export_range(0.0, 2.0, 0.01) var min_dimension: float = 0.1

## The largest volume, in cubic metres. 0 is no limit.
@export_range(0.0, 100.0, 0.1) var max_volume: float = 8.0

## The collision hull a disguise gets, as a capsule: its radius is half the prop's NARROWER
## footprint, clamped here. Narrower rather than wider, so a sofa can still be walked through a
## door it visibly overhangs; a hull the full width of a wardrobe is a player who cannot leave
## the room they hid in.
@export_range(0.05, 2.0, 0.01) var hull_min_radius: float = 0.14
@export_range(0.05, 2.0, 0.01) var hull_max_radius: float = 0.55

## The hull's height is the prop's own, clamped here.
@export_range(0.1, 5.0, 0.01) var hull_min_height: float = 0.3
@export_range(0.1, 5.0, 0.01) var hull_max_height: float = 2.2

@export_group("Reach")

## How far from the eye a prop may be copied, in metres.
@export_range(0.5, 20.0, 0.1) var reach: float = 3.0

@export_group("Turning")

## Degrees one press of a tilt key turns the prop, and the most it may lean.
@export_range(1.0, 90.0, 1.0) var tilt_step: float = 15.0
@export_range(0.0, 180.0, 1.0) var max_tilt: float = 90.0

@export_group("Showing yourself")

## Seconds before a player who put their disguise back on may take it off again. 0 for none.
@export_range(0.0, 600.0, 0.5) var reveal_cooldown: float = 10.0

## Points a second while a player shows their own face, the risk they are paid for.
@export_range(0.0, 100.0, 0.1) var reveal_points_per_second: float = 1.0

## The most seconds of showing themselves that pay, per reveal. 0 for no limit.
@export_range(0.0, 600.0, 1.0) var reveal_paid_seconds: float = 20.0


func validate() -> DotResult:
	if min_health > max_health:
		return DotResult.fail(DotError.CODE_INVALID, "min_health is over max_health")

	if hull_min_radius > hull_max_radius or hull_min_height > hull_max_height:
		return DotResult.fail(DotError.CODE_INVALID, "a hull minimum is over its maximum")

	if hull_min_height < hull_min_radius * 2.0:
		return DotResult.fail(DotError.CODE_INVALID,
			"hull_min_height must be at least twice hull_min_radius: a capsule cannot be shorter than it is wide")

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"health": "%d..%d (%.0f x v^%.2f)" % [min_health, max_health, health_scale, health_exponent],
		"hull": "r %.2f..%.2f, h %.2f..%.2f" % [hull_min_radius, hull_max_radius, hull_min_height, hull_max_height],
		"reach": reach,
		"reveal": "cooldown %.0f s, %.1f pts/s" % [reveal_cooldown, reveal_points_per_second],
	}

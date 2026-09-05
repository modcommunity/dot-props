@tool
class_name DotPropLimits
extends DotConfig

## What a player may spawn, and how much of it.
##
## [b]A sandbox without limits lasts about four minutes.[/b] The failure is not
## malice, mostly — somebody holds the spawn key, or spawns a hundred crates to build
## something, and the server's physics step goes from two milliseconds to two hundred.
## Every limit here exists because a sandbox server without it has the same afternoon.
##
## A [DotConfig], so an operator changes it in a file or on the command line without a
## rebuild — which is what actually happens the evening a server falls over.

@export_group("Per player")

## Most props one player may have in the world at once. 0 = unlimited.
##
## Counted in [member DotPropDef.cost] rather than in props, so a server can make one
## expensive model count for ten without reclassifying it.
@export_range(0, 1000, 1) var per_player_budget: int = 64

## Seconds between spawns for one player. 0 = no wait.
##
## [b]The one that stops a held key.[/b] A budget alone does not: a player who reaches
## it, removes one and spawns another can still spawn as fast as their key repeats,
## which is a spawn and a free per frame and is worse for the server than the props
## are.
@export_range(0.0, 10.0, 0.01) var spawn_interval: float = 0.15

## Props one player may freeze. 0 = unlimited.
##
## Separate from the budget because a frozen prop costs nothing to simulate, so a
## builder should be allowed more of them than a physics budget would give — and
## because "how much may I build" and "how much may I have moving" are two questions
## a server operator wants to answer differently.
##
## Enforced by [method DotPhysGun.freeze_held]; a game freezing props by some other
## route checks it with [method DotPropSpawner.may_freeze].
@export_range(0, 1000, 1) var per_player_frozen: int = 128

## The largest prop that may be spawned. See [enum DotPropDef.Size].
##
## [b]A size class rather than a cost, because they answer different questions.[/b]
## `cost` is a budget — twenty small props or two big ones. This is a ceiling: a
## server can allow a hundred crates and forbid the one model that is the size of the
## map, without having to price it at a hundred.
@export var max_size: DotPropDef.Size = DotPropDef.Size.HUGE

@export_group("Server")

## Most props in the world at once, from everybody. 0 = unlimited.
##
## [b]Not the per-player budget times the slot count.[/b] Thirty players each within
## their own budget is thirty times the physics, and the server falls over while every
## one of them is behaving.
@export_range(0, 10000, 1) var world_budget: int = 1024

## Whether a player's props are removed when they leave.
##
## On, because the alternative is a server that accumulates the props of everybody who
## has ever visited. Off for a persistent build server, which is a real thing people
## run — and which then needs its own cleanup.
@export var clean_up_on_leave: bool = true

## How many spawns one player may undo.
@export_range(0, 500, 1) var undo_depth: int = 64

@export_group("Physics")

## How far a physics gun can reach, in metres.
@export_range(0.5, 200.0, 0.5) var grab_range: float = 40.0

## Heaviest prop a physics gun may hold, in kilograms. 0 = any.
@export_range(0.0, 100000.0, 1.0) var grab_mass_limit: float = 0.0

## How far a held prop may be pushed out from the player, in metres.
@export_range(0.5, 100.0, 0.5) var hold_distance_max: float = 25.0

@export_range(0.1, 20.0, 0.1) var hold_distance_min: float = 1.5


func env_prefix() -> String:
	return "DOT_PROPS_"


func cli_prefix() -> String:
	return "--props-"


func validate() -> DotResult:
	if hold_distance_min > hold_distance_max:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"hold_distance_min must not exceed hold_distance_max.",
			"%.1f .. %.1f" % [hold_distance_min, hold_distance_max]
		)

	if grab_range < hold_distance_max:
		# Not fatal, but it makes the maximum hold distance unreachable, which reads
		# as the push control being broken rather than as two numbers disagreeing.
		return DotResult.fail(
			DotError.CODE_INVALID,
			"grab_range must be at least hold_distance_max, or a held prop cannot be pushed to its limit.",
			"%.1f vs %.1f" % [grab_range, hold_distance_max]
		)

	return DotResult.success(null)


func describe_summary() -> String:
	return "budget %d/player %d/world, %.2fs apart, reach %.0fm" % [
		per_player_budget, world_budget, spawn_interval, grab_range
	]

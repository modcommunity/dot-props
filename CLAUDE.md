# dot-props

A sandbox layer: spawnable props, the limits that keep a server alive, the tools that move them (a physics gun and a gravity gun), props that break and props a player can ride, props wired to props, and the arithmetic of a player hiding as a prop.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to props. The reasoning is in [docs/](docs/README.md).

**Only dot-core is a dependency.** Combat, netcode, the controller and collision layouts are reached through signals, callables and ids the host wires.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/spawning.md](docs/spawning.md) | the spawner, definitions, limits, groups, ownership, protection, `DotPropIO`, what is deliberately not here |
| [docs/tools.md](docs/tools.md) | `DotPropTool`, `DotPhysGun`, `DotGravGun` |
| [docs/damage-and-carry.md](docs/damage-and-carry.md) | `DotPropDamage`, `DotPropCarry`, any physics assertion |
| [docs/hunt.md](docs/hunt.md) | `DotPropDisguise`, `DotPropTaunts` |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_props/core/` | `DotPropDef` (scene, size, mass, cost, entitlement, damage numbers), `DotPropInstance`, `DotPropCatalogue` (the JSON an operator edits), `DotPropLimits` (a layered `DotConfig`) |
| `addons/dot_props/runtime/` | `DotPropSpawner` (the node a game adds), `DotPropDamage`, `DotPropCarry`, `DotPropIO` |
| `addons/dot_props/hunt/` | `DotPropDisguiseRules`, `DotPropDisguise`, `DotPropTaunts` |
| `addons/dot_props/tools/` | `DotPropTool` (reach, targeting, `may_act_on`), `DotPhysGun`, `DotGravGun` |
| `fixtures/` | 3D and 2D prop bodies for the suite |
| `examples/props_selftest.tscn` | the suite; spawns real `RigidBody3D`s into a real tree and checks every node is freed |

## Running and testing

- The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/props_selftest.tscn`.
- A limit must be tested against real bodies in a real tree: one that counted a dictionary would pass while the scene filled up.
- A physics assertion reads after the step that consumed the impulse, and says what it excludes, or it is measuring gravity. [damage-and-carry](docs/damage-and-carry.md#testing-physics)
- game-playground (spawning, tools, IO), mg-buses-from-hell (damage, carry), mg-prop-hunt and game-hide-n-seek (`hunt/`) are the consumers; the mass bug was found from a game.

## Rules that bite

- Props are server-authoritative and never predicted. Every mutating method checks `authoritative` first. [spawning](docs/spawning.md#props-are-server-authoritative-and-are-not-predicted)
- A definition is checkable without its scene; numbers go on `DotPropDef`, never in a script on the prop (a pack's `class_name` does not resolve). [spawning](docs/spawning.md#a-definition-is-checkable-without-loading-the-scene)
- `DotPropDef.mass` is assigned before the body enters the tree. [spawning](docs/spawning.md#a-definition-is-checkable-without-loading-the-scene)
- `spawn` (3D) and `spawn_2d` stay separate; the wrong dimension is refused and freed. Write `instance.position()`, never `instance.node.global_position`. [spawning](docs/spawning.md#a-prop-is-not-always-a-3d-one)
- Every limit has a reason; cooldowns run on simulated seconds advanced by the host, never a wall clock. [spawning](docs/spawning.md#the-limits-and-why-each-one-exists)
- A refusal names the limit it hit; who gets more is `limit_resolver`, never this addon. [spawning](docs/spawning.md#counts-per-kind-and-a-players-own-limits)
- Ownership and undo are two lists; passing the undo depth never disowns. Departed players' props are disowned even when kept. [spawning](docs/spawning.md#ownership-and-undo-are-two-different-lists)
- Protection is the spawner's (`set_protected`), asked by every tool and every damage path. [spawning](docs/spawning.md#protected-owners)
- `is_alive()`, never `is_instance_valid`; `removed` fires before the free. [spawning](docs/spawning.md#is_alive-is-not-the-node-is-valid)
- `DotPropIO` knows nothing about doors; a removal drops every wire; depth stops at `max_depth`. [spawning](docs/spawning.md#props-wired-to-props)
- Tools take an origin and a direction, never a camera; ownership is the host's `can_touch_others`; one holder at a time. [tools](docs/tools.md#what-every-tool-shares)
- The physics gun pushes with a velocity, never teleports; `max_speed` is a safety cap; `hold_rotation` is view-relative; freezing zeroes velocities. [tools](docs/tools.md#the-physics-gun-holds-with-a-spring)
- The static `set_frozen` emits no signal. [tools](docs/tools.md#its-signals)
- The gravity gun punts with an impulse and refuses a frozen prop. [tools](docs/tools.md#the-gravity-gun-is-not-a-smaller-physics-gun)
- `DotPropDamage` describes a blast (`exploded`) and shoves only props; dot-combat hurts people. `max_health = 0` is indestructible. [damage-and-carry](docs/damage-and-carry.md#dotpropdamage-holds-the-health-and-applies-none-of-it)
- Carry uses the angular velocity too, and `weight_scale` below 1. [damage-and-carry](docs/damage-and-carry.md#a-character-motor-does-not-touch-a-rigid-body)
- A disguise's hull is computed on both ends from the replicated size, never sent. [hunt](docs/hunt.md#dotpropdisguise)

## Where a game plugs in

| To change | Where |
| --- | --- |
| What can be spawned | `DotPropCatalogue`, from JSON |
| What a prop costs against a budget | `DotPropDef.cost` |
| How many of a kind a player may have | `DotPropDef.limit_group`, `DotPropLimits.group_limits` |
| Who gets bigger limits | `DotPropSpawner.limit_resolver` |
| Who may spawn what | `DotPropDef.entitlement` / `permission`, plus the `entitlements` callable |
| How much anybody may spawn | `DotPropLimits`, layered like any `DotConfig` |
| Where props go in the tree | `DotPropSpawner.world_ref` |
| Whether players may move each other's props | `can_touch_others` on every tool call; `set_protected` for one owner |
| How a physics gun feels | `stiffness`, `damping`, `push_speed` on `DotPhysGun` |
| A held or frozen prop's collision layer | `DotPhysGun.grabbed` / `released` / `freeze_changed` |
| A new tool | `DotPropTool` subclass |
| Telling the player why a spawn failed | `DotPropSpawner.refused` |
| Doing something to everything in the world | `DotPropSpawner.all_props`, which hands out a copy |
| A prop that has code behind it | `DotPropDef.meta`, read on `spawned`. See game-playground's entities |
| Buttons, levers, doors | `DotPropIO`, with `outputs` / `inputs` in the definition's meta |
| What breaks, and what a blast does | `DotPropDef` damage fields; `DotPropDamage.exploded` connected to dot-combat |
| Riding a prop | `DotPropCarry`, fed the motor's `ground_id` |
| A player disguised as a prop | `DotPropDisguiseRules`, `DotPropDisguise`, `DotPropTaunts` |
| A prop in a 2D world | `DotPropSpawner.spawn_2d`. See game-hungario |

Deliberately not here: replication, a spawn menu, constraints (welding, ropes, thrusters, wheels), saving a build, a damage model for people, content delivery. [spawning](docs/spawning.md#deliberately-not-here)

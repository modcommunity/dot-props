# dot-props

A sandbox layer: spawnable props, the limits that keep a server alive, the tools that move them (a physics gun and a gravity gun), props that break and props a player can ride, props wired to props, the arithmetic of a player hiding as a prop, and a catalogue of toys a map places (balls, swings, see-saws, trampolines, switches).

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
| [docs/pieces.md](docs/pieces.md) | `DotPropPieces`, a map prop's collision, a game's measuring tool |
| [docs/toys.md](docs/toys.md) | anything in `toys/`, or a game placing or replicating toys |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_props/core/` | `DotPropDef` (scene, size, mass, cost, entitlement, damage numbers), `DotPropInstance`, `DotPropCatalogue` (the JSON an operator edits), `DotPropLimits` (a layered `DotConfig`), `DotPropPieces` (collision shaped like the model) |
| `addons/dot_props/runtime/` | `DotPropSpawner` (the node a game adds), `DotPropDamage`, `DotPropCarry`, `DotPropIO` |
| `addons/dot_props/hunt/` | `DotPropDisguiseRules`, `DotPropDisguise`, `DotPropTaunts` |
| `addons/dot_props/tools/` | `DotPropTool` (reach, targeting, `may_act_on`), `DotPhysGun`, `DotGravGun` |
| `addons/dot_props/toys/` | `DotPropToyCatalogue` (18 stock toys over 16 kinds, retuned from JSON), `DotPropToyBox` (a map's toys, the awake cap, push/stand/use/hit/launch), `DotPropToy` (one, its bodies and look), `DotPropToyRules` (`sv_toys*`), `DotPropToySounds` (+ `sounds/`, CC0), `DotPropToyLook` (meshes made in code) |
| `fixtures/` | 3D and 2D prop bodies for the suite |
| `examples/props_selftest.tscn` | the suite; spawns real `RigidBody3D`s into a real tree and checks every node is freed |
| `examples/toy_gallery.tscn` | every stock toy rendered on a lawn (xvfb; `--kick` shows them moving) |

## Running and testing

- The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/props_selftest.tscn`.
- A limit must be tested against real bodies in a real tree: one that counted a dictionary would pass while the scene filled up.
- A physics assertion reads after the step that consumed the impulse, and says what it excludes, or it is measuring gravity. [damage-and-carry](docs/damage-and-carry.md#testing-physics)
- game-playground (spawning, tools, IO), mg-buses-from-hell (damage, carry), mg-prop-hunt and game-hide-n-seek (`hunt/`), game-hide-n-seek (`toys/`) are the consumers; the mass bug was found from a game.
- After touching a toy's look, `xvfb-run -a godot --path . res://examples/toy_gallery.tscn -- --kick` and look at `screenshots/toys.png`.

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
- A leant disguise turns about its box's middle and rests on the floor: draw with `model_transform`, hit with `box_transform`, sweep `standing_hull`. [hunt](docs/hunt.md#dotpropdisguise)
- **Toys are placed by data and paired by index**: both ends build the same toys in the same order from the map, so a game replicates each by index (its state is `state_transform()`, `on`, `count`) and never sends what a toy is. [toys](docs/toys.md#placed-by-data-paired-by-index)
- A loose toy is on a layer people do not collide with and is pushed by the game's `push_from`; a person standing on a see-saw is `stand_on`. A character motor never moves a rigid body. [toys](docs/toys.md#three-kinds-of-motion)
- A swing, a bag, a see-saw, a platform and a roundabout are driven angles posing a kinematic body, never Godot joints (a hinge pushed off its axis blew a seat a thousand kilometres away). [toys](docs/toys.md#three-kinds-of-motion)
- `count` is a use counter, not an event: a client plays the sound when it moves. Knocks are heard from motion (`sense`), which works on a frozen copy. [toys](docs/toys.md#replication-the-servers-physics-a-clients-picture)
- A trampoline or pad is `launch_for`, a pure function the game calls in its movement on every end; only the server counts the bounce. [toys](docs/toys.md#the-launchers-are-movement-not-physics)
- A hit scan asks `shot` first (a toy's index or -1); the push is a speed from the damage given to a toy of up to 3 kg, never the damage as an impulse (a ball flew at 40 m/s). [toys](docs/toys.md#shots-and-blasts)
- A roundabout carries its riders by `carry_for` after the move on every end (a rotation about the hub, never the rim speed along a tangent); a client measures the spin from the poses, as it is not sent. [toys](docs/toys.md#a-roundabout-carries-its-riders)
- The selftest's toys are turned 20 degrees and a hundred metres up: aligned axes hid the hinge bug, and a crate left falling by an earlier section flung a tyre 300 m. [toys](docs/toys.md#testing)
- `DotPropPieces.measure` is tool time only (V-HACD, seconds per model, maybe absent from an export template); the game ships `encode`d pieces and both ends build from them. One decomposition per material, or a leaf clump and the trunk become one hull. [pieces](docs/pieces.md)

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
| A map prop's collision shaped like its model | `DotPropPieces.measure` in the game's measuring tool, `decode` + `shapes` at run time. See game-hide-n-seek |
| Toys on a map | `DotPropToyBox` with the game's collision bits, `build(placements)`; per tick `push_from`/`stand_on`/`advance`, the use key's `aimed` + `use`, shots' `hit`, `launch_for` in movement; replicate `state_transform`/`on`/`count`. See game-hide-n-seek |
| A new toy, or a stock one retuned | `DotPropToyCatalogue.merge` / `merge_json` |
| How many toys simulate, whether there are any | `DotPropToyRules` (`sv_toys`, `sv_toys_awake`, `sv_toys_push`), `bind_cvars` on the server, `follow_cvars` on a client |

Deliberately not here: replication (a toy's state is three fields a game's own behaviour sends), a spawn menu, constraints (welding, ropes, thrusters, wheels), saving a build, a damage model for people, content delivery. [spawning](docs/spawning.md#deliberately-not-here)

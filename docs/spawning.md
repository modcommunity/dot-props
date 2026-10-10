# Spawning, limits and ownership

## Props are server-authoritative and are not predicted

Everything else in this family is built so a client can predict it (movement, weapons, the timer), and props deliberately are not. Rigid-body simulation is not reproducible across machines: the solver's iteration order, the order bodies enter an island and the last bits of every float all differ between a server and a client, and two runs of the same stack of crates diverge within a second or two.

A predicted prop is therefore a prop that is corrected constantly, which looks far worse than one that is simply interpolated a few tens of milliseconds behind. So the server owns every prop, the client draws what it is told, and the tools send *intent* and receive results: the same division `DotFpsCommand` makes, minus the prediction.

This is also why `authoritative` is checked before anything else in every mutating method: a client holds a spawner so it can render and account for what the server tells it about, and if that copy could spawn, a modified client would fill the world.

## A definition is checkable without loading the scene

The same reasoning as `DotItem` in dot-loadout and `DotAvatarSchema` in dot-user-avatar: a server validating a spawn against thirty players' budgets cannot load thirty scenes to do it, and a client showing a menu of four hundred props must not load four hundred. So the cost, the category, the entitlement, the mass and the damage numbers are fields, and the scene is fetched only when something is actually created.

`cost` is separate from `size` so a server can make one specific prop expensive without reclassifying it, which is what actually happens when one model turns out to be the one everybody spams.

**`DotPropDef.mass` is put on the spawned body, before it enters the tree.** A catalogue's mass over a scene saved with another one otherwise gives a prop the physics gun refuses as too heavy and the gravity gun throws like a beach ball. It must be set before the first physics step: a `mass` assignment is not picked up until the next step, so an impulse in between is divided by the old mass.

## A prop is not always a 3D one

`DotPropSpawner.spawn` places a `Node3D` and `spawn_2d` places a `Node2D`, and everything either side of that placement is the same code: the catalogue, the entitlement check, the budget, the interval, the undo stack, the ownership and the removal. None of those is about dimension (they are about **who put what in the world and what it cost**), and a 2D game that had to re-implement them would be re-implementing the whole addon to avoid one `Vector3`.

**Two entry points rather than one widened signature.** Many repositories call `spawn(id, player, Vector3)`, and changing it is a breaking change across all of them. A `Vector2` and a rotation in radians is also what a 2D caller actually holds, and handing it a `Basis` to be thrown away becomes "why does this crate have a pitch".

`DotPropInstance.node` is therefore typed **`Node`**, not `Node3D`. `body()` / `position()` answer for a 3D prop, `body_2d()` / `position_2d()` are their counterparts, and `is_2d()` is the question, asked rather than inferred, because a `DotPropDef` deliberately says nothing about dimension and a catalogue holding both is legitimate. **Write `instance.position()`, never `instance.node.global_position`**: `node` is the handle, not the transform.

**Asking for the wrong dimension is refused without leaking.** A 3D prop through `spawn_2d` and a 2D one through `spawn` both return null, and the instantiated scene is freed. The suite checks the child count either side of both refusals.

## The limits, and why each one exists

A sandbox without limits lasts about four minutes, and the failure is mostly not malice: somebody holds the spawn key, or spawns a hundred crates to build something, and the physics step goes from two milliseconds to two hundred.

| Limit | The failure without it |
| --- | --- |
| `per_player_budget` | One player fills the world |
| `spawn_interval` | A **held key**. A budget alone does not stop it: reach the cap, remove one, spawn another, which is a spawn and a free per frame |
| `world_budget` | Thirty players each **within** their own budget is thirty times the physics, and the server falls over while everybody is behaving |
| `clean_up_on_leave` | The server accumulates the props of everybody who has ever visited |
| `grab_mass_limit` | A physics gun that can lift the map |
| `per_player_frozen` | A builder who freezes a thousand pieces. Separate from the physics budget because a frozen prop costs nothing to simulate, so they should be allowed more. Checked by `DotPhysGun.freeze_held`; unfreezing is never refused, because a limit that stopped a moderator tidying up would fight its own operator |
| `max_size` | The one model that is the size of the map. A **ceiling**, where `cost` is a budget. Checked by `DotPropSpawner.may_spawn` |

The clock the cooldown runs on is **simulated seconds, advanced by the host**, never a wall clock. A wall clock lets a player who lags the server spawn faster than one who does not.

`clean_up_on_leave = false` (a persistent build server) still **disowns** the departed player's props. Without that, the budget of somebody who left is held against them for ever.

## Counts per kind, and a player's own limits

Beside the cost budget, every definition has a `limit_group` (empty is `props`) and `DotPropLimits.group_limits` caps how many of each group one player may have: a count, not a cost, because "how much of the simulation is yours" and "how many NPCs do you have" are different questions. A refusal names the group ("You have reached your npcs limit (10)."), because "you are at your limit" with a budget left over reads as the server being wrong.

`DotPropSpawner.limit_resolver` is `func(player_id, key, base) -> int`, asked for `budget`, `frozen` and every group: the game decides who gets more. Who a player is (an admin, a supporter, somebody in a site group) is not this addon's business. `limit_for`, `group_count` and `group_usage` are what a HUD or a `limits` command reads. game-playground is the consumer (`pg_max_<group>` and per-role overrides).

## Ownership and undo are two different lists

They were one list in the first version. Trimming it to `undo_depth` removed props from their owner's **account** as well as from their history, so a player could hold `undo_depth` props against their budget and any number beyond it for free, and `clear_player` left everything past the depth in the world for ever.

Passing the undo depth means the oldest can no longer be undone. It does not mean the prop disappears, and it does not mean it stops being yours.

## Protected owners

`DotPropSpawner.set_protected(player_id, on)` makes an owner's props untouchable by anybody else: `DotPropTool.may_act_on` refuses every other wielder (before, and regardless of, the server's touch-others rule), and `DotPropDamage.hurt`, `break_now` and `impact` refuse any `by` that is not the owner, including none. It is a building server's creative mode, and it lives here rather than in a game because every tool and every source of harm already asks the spawner: a game keeping its own set would have to remember it at every call, and the first one it forgot would be the way round it. `player_left` drops the protection.

## `is_alive()` is not "the node is valid"

`queue_free()` is deferred, so `is_instance_valid` stays true for the rest of the frame after a prop is removed, and a tool that checked only the node would keep pulling on a prop an admin has already cleaned up. That is exactly the window in which a cleanup happens under somebody's physics gun. So `DotPropSpawner.remove` marks the instance dead immediately, and `is_alive()` checks both.

`removed` is emitted **before** the node is freed, so a listener holding a reference (a gun with the prop in hand, a netcode replicating it) can let go while it still exists.

## Props wired to props

`DotPropIO` is a link table beside the spawner. A prop declares what it says and hears in its definition's meta (`"outputs": ["pressed"]`, `"inputs": ["open", "close", "toggle"]`), `link(from, output, to, input)` wires one to the other, and `fire(from, output, value)` delivers to every wired input as `input_received`.

**It knows nothing about doors.** What "toggle" does to a door and what presses a button are the game's, so a swinging door and a sliding one are the same link and a game's "use" key is its own.

- Wires are refused to a prop that does not declare the name, to itself, twice the same way, and past `max_links_per_prop` (16).
- A removal takes every wire touching the prop: a link to something gone is a button that silently does nothing.
- A chain deeper than `max_depth` (8), such as a door wired back to whatever opened it, stops once, with a warning.
- Server-authoritative and not replicated: a client learns what a door did from the door.

game-playground's buttons, levers and doors are the first user.

## Deliberately not here

- **Replication.** The wire is dot-net's. What a game replicates about a prop (transform only, or transform plus velocity for extrapolation) depends on how many it has and how fast they move.
- **A spawn menu.** dot-ui has the screen stack; a menu of four hundred props with icons and a search box is a game's own design.
- **Duplicating or saving a build.** A save format has to survive the catalogue changing under it, which is a versioning problem rather than a physics one.
- **Content delivery.** `DotPropDef.content_id` says which pack a prop lives in; mounting it is dot-cloud's and the host's, exactly as `DotMapDef` does it.
- Welding, ropes and the like: see [tools.md](tools.md#deliberately-not-here). A damage model for people: see [damage-and-carry.md](damage-and-carry.md).

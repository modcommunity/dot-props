# dot-props

A sandbox layer: spawnable props, the limits that keep a server alive, and the tools
that move them.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first. This
file is only what is specific to props.

**Only dot-core is a dependency.**

## The one idea

**Props are server-authoritative and are not predicted.**

Everything else in this family is built so a client can predict it — movement,
weapons, the timer — and props deliberately are not. Rigid-body simulation is not
reproducible across machines: the solver's iteration order, the order bodies enter an
island and the last bits of every float all differ between a server and a client, and
two runs of the same stack of crates diverge within a second or two.

A predicted prop is therefore a prop that is corrected constantly, which looks far
worse than one that is simply interpolated a few tens of milliseconds behind. So the
server owns every prop, the client draws what it is told, and the tools send *intent*
and receive results — the same division `DotFpsCommand` makes, minus the prediction.

This is also why `authoritative` is checked before anything else in every mutating
method: a client holds a spawner so it can render and account for what the server
tells it about, and if that copy could spawn, a modified client would fill the world.

## Layout

```
addons/dot_props/
  core/
    dot_prop_def.gd       one spawnable: scene, size, mass, cost, entitlement
    dot_prop_instance.gd  one prop in the world: node, owner, frozen, held-by
    dot_prop_catalogue.gd every prop a server offers. The JSON an operator edits
    dot_prop_limits.gd    what a player may spawn, as a layered DotConfig
  runtime/
    dot_prop_spawner.gd   spawns, tracks, limits, removes. The node a game adds
  tools/
    dot_prop_tool.gd      reach, targeting, and what a tool may act on
    dot_phys_gun.gd       hold, move, rotate, freeze. A building tool
    dot_grav_gun.gd       pull, carry, punt. A weapon and a toy
```

## A definition is checkable without loading the scene

The same reasoning as `DotItem` in dot-loadout and `DotAvatarSchema` in
dot-user-avatar: a server validating a spawn against thirty players' budgets cannot
load thirty scenes to do it, and a client showing a menu of four hundred props must
not load four hundred. So the cost, the category, the entitlement and the mass are
fields, and the scene is fetched only when something is actually created.

`cost` is separate from `size` so a server can make one specific prop expensive
without reclassifying it — which is what actually happens when one model turns out to
be the one everybody spams.

## The limits, and why each one exists

A sandbox without limits lasts about four minutes, and the failure is mostly not
malice: somebody holds the spawn key, or spawns a hundred crates to build something,
and the physics step goes from two milliseconds to two hundred.

| Limit | The failure without it |
| --- | --- |
| `per_player_budget` | One player fills the world |
| `spawn_interval` | A **held key**. A budget alone does not stop it: reach the cap, remove one, spawn another — that is a spawn and a free per frame, which is worse for the server than the props are |
| `world_budget` | Thirty players each **within** their own budget is thirty times the physics, and the server falls over while everybody is behaving |
| `clean_up_on_leave` | The server accumulates the props of everybody who has ever visited |
| `grab_mass_limit` | A physics gun that can lift the map |
| `per_player_frozen` | A builder who freezes a thousand pieces. Separate from the physics budget because a frozen prop costs nothing to simulate, so they should be allowed more of them |
| `max_size` | The one model that is the size of the map. A **ceiling**, where `cost` is a budget — allow a hundred crates and forbid that one without pricing it at a hundred |

The clock the cooldown runs on is **simulated seconds, advanced by the host**, never a
wall clock. A wall clock lets a player who lags the server spawn faster than one who
does not.

`clean_up_on_leave = false` — a persistent build server, which is a real thing people
run — still **disowns** the departed player's props. Without that, the budget of
somebody who left is held against them for ever.

## Ownership and undo are two different lists

They were one list in the first version, and the self-test caught what that costs.
Trimming the list to `undo_depth` removed props from their owner's **account** as well
as from their history, so:

- a player could hold `undo_depth` props against their budget and **any number beyond
  it for free**;
- `clear_player` left everything past the depth in the world for ever.

Passing the undo depth means the oldest can no longer be undone. It does not mean the
prop disappears, and it does not mean it stops being yours.

## `is_alive()` is not "the node is valid"

`queue_free()` is deferred, so `is_instance_valid` stays true for the rest of the
frame after a prop is removed — and a tool that checked only the node would keep
pulling on a prop an admin has already cleaned up, for as long as that frame lasts.
That is exactly the window in which a cleanup happens under somebody's physics gun.
So `DotPropSpawner.remove` marks the instance dead immediately, and `is_alive()`
checks both.

`removed` is emitted **before** the node is freed, so a listener holding a
reference — a gun with the prop in hand, a netcode replicating it — can let go while
it still exists.

## The tools

**A tool is not a node and does not own a camera.** It is given an origin and a
direction each tick, so the same physics gun works for a player with a first-person
camera, a bot, a replay being played back, and a headless test — none of which have a
viewport.

**Ownership is deliberately not checked inside the tool.** Whether a player may move
somebody else's crate is a server policy — a build server says no, a sandbox says yes,
a competitive one says only for admins — and hard-coding either answer means the other
needs a fork. The host passes `can_touch_others`.

**One holder at a time**, enforced by `DotPropInstance.held_by`. Two guns pulling one
crate toward two players makes it oscillate violently between them and costs ten times
the physics step.

### The physics gun holds with a spring

Teleporting a rigid body to a target transform each tick is the obvious implementation
and it is what makes a sandbox unplayable: a body *moved* rather than *pushed* has no
velocity, so it passes through walls, wakes nothing it touches, and hands the solver
an impossible situation when it is finally released. Setting a velocity toward where
the prop should be is a force the solver understands — the prop pushes what is in the
way, stops against a wall, and carries its momentum when let go, which is what makes
throwing work at all.

`max_speed` is a **safety cap, not a feel dial**. The spring's output is proportional
to the distance to the goal, so a player who aims at the sky and then at their feet
asks for an arbitrarily large velocity — which tunnels the prop through the world and,
at the extreme, produces a non-finite position that poisons its whole physics island.

`hold_rotation` is stored **relative to the view**, so turning your view turns the prop
with it. An absolute orientation means the prop keeps facing north while the player
walks around it, and building is impossible.

`set_frozen` **zeroes the velocities as well as setting the mode**. Godot keeps a
frozen body's velocities and applies them the instant it is unfrozen, so a prop frozen
while falling fast leaps away when somebody thaws it — minutes later, with nothing to
connect the two.

### The gravity gun is not a smaller physics gun

A physics gun is a building tool: arbitrary distance, free rotation, freezing, and a
deliberately soft spring so a piece can be placed precisely. A gravity gun is a weapon
and a toy: one fixed carrying position, a stiff hold so the prop tracks the crosshair,
and a punt. Shipping one and calling it both gives a building tool that cannot throw
and a weapon that cannot build.

A punt is an **impulse**, not a velocity, so a heavy prop goes less far than a light
one — which is what makes the tool feel like it has weight, and is free because the
solver already divides by the mass.

A frozen prop is **refused** by the gravity gun rather than thawed. The physics gun
unfreezes what it grabs, because freezing is its own tool and unfreezing is the
obvious undo; a gravity gun that quietly unfroze somebody's build would take a tower
apart one piece at a time.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/props_selftest.tscn   # 104 checks
```

The suite spawns **real** `RigidBody3D`s into a real tree, because a limit that
counted a dictionary would pass every test while the scene tree filled up — there is a
check that every node is actually freed for exactly that reason.

Three bugs it found, none of which errored — and a fourth found by game-playground:

- **`DotPropDef.mass` was not put on the spawned body.** It was read in exactly one
  place — `DotPropTool.may_act_on`, against `grab_mass_limit` — and the body kept
  whatever mass its scene was saved with. So a catalogue saying 900 kg over a scene
  saved at 20 kg gave a prop a physics gun refuses for being too heavy and a gravity
  gun throws like a beach ball, with nothing erroring and the two numbers only ever
  compared by a player wondering why. Invisible in this addon's own suite, where every
  fixture is the same scene *and* the check is the limit rather than the physics; it
  showed the moment a game shipped one scene for a dozen props, which is the cheap way
  to do it and what game-playground does. `spawn` now assigns it before the body enters
  the tree — earlier than the first physics step, for the reason two entries below.

- **Ownership and undo shared one list** (above), which was a budget bypass.
- **A prop removed while held was not let go of** until the deferred free landed.
- **`per_player_frozen` and `size` were declared and read by nothing** — the family's
  own "a value computed and never read" pattern, in the shape where the value is a
  documented limit that does not limit anything. Both are now enforced:
  `DotPhysGun.freeze_held` checks the first, `DotPropSpawner.may_spawn` the second.
  Unfreezing is deliberately never refused, because a limit that stopped a moderator
  tidying up would be a limit fighting its own operator.
- Two in the test itself, both about physics timing and both worth remembering:
  `apply_central_impulse` is not readable in `linear_velocity` until the step that
  consumes it has run, and a `mass` assignment is not picked up by the server until
  the next step — so an impulse applied in between is divided by the **old** mass.
  The test reported a 900 kg prop flying twenty times further than a 20 kg one.

## Where a game plugs in

| To change | Where |
| --- | --- |
| What can be spawned | `DotPropCatalogue`, from JSON |
| What a prop costs against a budget | `DotPropDef.cost` |
| Who may spawn what | `DotPropDef.entitlement` / `permission`, plus the `entitlements` callable |
| How much anybody may spawn | `DotPropLimits`, layered like any `DotConfig` |
| Where props go in the tree | `DotPropSpawner.world_ref` |
| Whether players may move each other's props | `can_touch_others` on every tool call |
| How a physics gun feels | `stiffness`, `damping`, `push_speed` on `DotPhysGun` |
| A new tool | `DotPropTool` subclass |
| Telling the player why a spawn failed | `DotPropSpawner.refused` |
| Doing something to everything in the world | `DotPropSpawner.all_props`, which hands out a copy |
| A prop that has code behind it | `DotPropDef.meta`, read on `spawned`. See game-playground's entities |

## Things deliberately not here

- **Replication.** Props are server-authoritative and the wire is dot-net's. What a
  game replicates about a prop — transform only, or transform plus velocity for
  extrapolation — depends on how many it has and how fast they move.
- **A spawn menu.** dot-ui has the screen stack; a menu of four hundred props with
  icons and a search box is a game's own design.
- **Welding, ropes, thrusters, wheels.** Constraints are a much larger surface than
  spawning, they interact with each other, and a half-built constraint system is worse
  than none. `DotPropTool` is the hook.
- **Duplicating or saving a build.** A save format has to survive the catalogue
  changing under it, which is a versioning problem rather than a physics one.
- **Prop damage or health.** dot-combat has damage; whether a crate breaks is a game's
  decision.
- **Content delivery.** `DotPropDef.content_id` says which pack a prop lives in;
  mounting it is dot-cloud's and the host's, exactly as `DotMapDef` does it.

This is the **sandbox** asset for TMC's **Dot** collection. It is what you add when you want players to build things rather than only shoot at them.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## A Sandbox Layer
**A sandbox layer for Godot 4** — spawnable props, the limits that keep a server
alive, and the tools that move them.

A physics gun that holds, rotates and freezes; a gravity gun that pulls, carries and
punts; a catalogue an operator edits as JSON; per-player budgets, a spawn cooldown, an
undo stack, and cleanup when somebody leaves.

## Server-authoritative, and not predicted

Rigid-body physics is not reproducible across machines — the solver's iteration order
and the last bits of every float differ — so a predicted prop is a prop that is
corrected constantly. The server owns every prop; the client draws what it is told;
the tools send intent.

## Installing

Copy `addons/dot_props/` and [`dot-core`](../dot-core)'s `addons/dot_core/` into your
project, and enable dot-props in *Project → Project Settings → Plugins*.

## Five minutes

```gdscript
var spawner := DotPropSpawner.new()
spawner.authoritative = true                  # on the server only
spawner.catalogue = DotPropCatalogue.load_json("res://props.json").value
spawner.limits = DotPropLimits.new()
spawner.world_ref = DotNodeRef.of_path(^"../World")
add_child(spawner)

spawner.refused.connect(func(player, prop, reason): tell(player, reason))

# once per simulated tick
spawner.advance(delta)

# when a player spawns something
spawner.spawn(&"crate", player_id, aim_point, Basis.IDENTITY)
```

`props.json`:

```json
{
  "format": 1,
  "props": [
    {"id": "crate", "name": "Crate", "category": "props", "scene": "res://props/crate.tscn", "mass": 20},
    {"id": "safe", "name": "Safe", "category": "props", "scene": "res://props/safe.tscn", "mass": 900, "cost": 8},
    {"id": "pillar", "category": "scenery", "scene": "res://props/pillar.tscn", "can_grab": false}
  ]
}
```

## The tools

```gdscript
var gun := DotPhysGun.new()
gun.spawner = spawner
gun.wielder = player_id

# on the grab button
gun.grab(space_state, eye_position, aim_direction, view_basis)

# every physics tick while held
gun.hold(eye_position, aim_direction, view_basis, delta)
gun.push(scroll_amount, delta)

# on release, or to freeze it where it is
gun.release()
gun.freeze_held()
```

```gdscript
var grav := DotGravGun.new()
grav.spawner = spawner
grav.wielder = player_id

grav.pull(space_state, eye_position, aim_direction)
grav.carry(eye_position, aim_direction, delta)     # every physics tick
grav.punt(space_state, eye_position, aim_direction)
```

## Documentation

[`CLAUDE.md`](CLAUDE.md) has the design reasoning: why props are not predicted, why a
physics gun holds with a spring rather than a transform, what each limit is defending
against, and the budget bypass the self-test found.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/props_selftest.tscn   # 102 checks
```

## Licence

MIT. See [LICENSE](LICENSE).

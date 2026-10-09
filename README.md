This is the **sandbox** asset for TMC's **Dot** collection. It is what you add when you want players to build things rather than only shoot at them.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
It lets players spawn props (crates, furniture, anything with a physics body) and move them around with tools: a **physics gun** that holds, rotates and freezes a prop, and a **gravity gun** that pulls, carries and punts one. The props come from a catalogue an operator can edit as JSON.

Most of the work is in the limits, because a sandbox server without them falls over quickly. Each player has a budget, a short wait between spawns, a limit on frozen props and an undo list, the whole server has a cap, and a player's props are removed when they leave.

It can also make props breakable (with health, and an optional explosion), let players stand on props and be carried by them, and wire props together, such as a button that opens a door.

The server owns every prop, and clients only draw what it sends. Physics simulation does not come out exactly the same on two machines, so a prop predicted on the client would be corrected all the time.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_props/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it and enable dot-props in **Project → Project Settings → Plugins**. dot-core is the only dependency.

## Using it

```gdscript
var spawner := DotPropSpawner.new()
spawner.authoritative = true                  # on the server only. Otherwise every spawn is refused
spawner.catalogue = DotPropCatalogue.load_json("res://props.json").value
spawner.limits = DotPropLimits.new()
spawner.world_ref = DotNodeRef.of_path(^"../World")   # where props are added, relative to the spawner
add_child(spawner)

spawner.refused.connect(func(player, prop, reason): tell(player, reason))

spawner.advance(delta)                                 # every tick, in seconds
spawner.spawn(&"crate", player_id, aim_point, Basis.IDENTITY)
spawner.undo(player_id)
spawner.player_left(player_id)                         # removes their props
```

`props.json`:

```json
{
  "format": 1,
  "props": [
    {"id": "crate", "name": "Crate", "category": "props", "scene": "res://props/crate.tscn", "mass": 20, "max_health": 50},
    {"id": "safe", "name": "Safe", "category": "props", "scene": "res://props/safe.tscn", "mass": 900, "cost": 8},
    {"id": "pillar", "category": "scenery", "scene": "res://props/pillar.tscn", "can_grab": false}
  ]
}
```

A prop's scene is a `RigidBody3D` with no script. Other fields: `size` (a prop larger than the server's `max_size` is refused), `limit_group` (counted against `group_limits`), `can_freeze`, `rideable`, `break_impact_speed`, `explode_radius` / `explode_damage` / `explode_force`, `entitlement` and `permission` (who may spawn it), and `meta` for your own data.

### The tools

```gdscript
var gun := DotPhysGun.new()
gun.spawner = spawner
gun.wielder = player_id

gun.grab(space_state, eye_position, aim_direction, view_basis)   # on the grab button
gun.hold(eye_position, aim_direction, view_basis, delta)         # every tick while held
gun.push(scroll_amount, delta)                                   # nearer or further
gun.rotate_held(yaw_degrees, pitch_degrees)
gun.release()
gun.freeze_held()                                                # leave it frozen in place
```

```gdscript
var grav := DotGravGun.new()
grav.spawner = spawner
grav.wielder = player_id

grav.pull(space_state, eye_position, aim_direction)
grav.carry(eye_position, aim_direction, delta)                   # every tick while carrying
grav.punt(space_state, eye_position, aim_direction)
grav.drop()
```

Anybody can move anybody's props by default. `set_protected(player_id, true)` stops other players touching that player's props, and nobody can grab a prop somebody else is already holding.

### Breakable props

```gdscript
var damage := DotPropDamage.new()
damage.spawner_ref = DotNodeRef.of_path(^"../Props")
damage.authoritative = true                   # on the server. Otherwise hurt() refuses
add_child(damage)

damage.hurt(prop.instance_id, 25.0, attacker_id)
damage.impact(prop.instance_id, closing_speed, driver_id)   # from a collision
damage.broken.connect(func(prop, at, by): play_break_effect(at))
```

A prop with `max_health` 0 (the default) cannot be broken. When a prop with an explosion breaks, the addon pushes the other props nearby and fires `exploded` with the radius, damage and force. Hurting players and pushing anything that is not a prop is up to your game.

### Standing on props
A character controller treats a prop like the floor, so a crate never sinks, tips or moves a player standing on it. `DotPropCarry` fixes that. Call `ride()` once per tick for each player on the ground: it applies their weight to the prop under them and returns how far the prop moved them this tick. `push()` shoves a prop a player walks into.

### Wiring props together
A prop lists what it can send and receive in its `meta`, for example `{"outputs": ["pressed"]}` on a button and `{"inputs": ["open", "close"]}` on a door.

```gdscript
var io := DotPropIO.new()
io.spawner_ref = DotNodeRef.of_path(^"../Props")
add_child(io)

io.link(button.instance_id, &"pressed", door.instance_id, &"open")
io.fire(button.instance_id, &"pressed")       # when somebody presses it
io.input_received.connect(func(target, input, value, source): open_door(target))
```

What "open" means for a door is up to your game.

## Settings
The limits live in a `DotPropLimits` resource. Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before giving it to the spawner:

```gdscript
var limits := DotPropLimits.new()
limits.load_layered("user://props.json")
spawner.limits = limits
```

```bash
DOT_PROPS_PER_PLAYER_BUDGET=100 godot --headless -- --props-world-budget=2048
```

| Setting | Default | What it does |
| --- | --- | --- |
| `per_player_budget` | 64 | Most props one player may have, counted by `cost`. 0 is unlimited |
| `spawn_interval` | 0.15 | Seconds between one player's spawns |
| `per_player_frozen` | 128 | Most props one player may freeze. 0 is unlimited |
| `max_size` | `HUGE` | The largest size class that may be spawned |
| `group_limits` | none | Per-player counts by `limit_group`, such as `{"vehicles": 4}` |
| `world_budget` | 1024 | Most props on the server, from everybody. 0 is unlimited |
| `clean_up_on_leave` | true | Remove a player's props when they leave |
| `undo_depth` | 64 | How many spawns a player can undo |
| `grab_range` | 40 | How far the physics gun reaches, in metres |
| `grab_mass_limit` | 0 | Heaviest prop it can hold, in kilograms. 0 is any |
| `hold_distance_min` / `hold_distance_max` | 1.5 / 25 | How near and far a held prop can be |

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/props_selftest.tscn
```

## Hiding as a prop

For hide-and-seek games, `DotPropDisguise` holds what a player is disguised as and works out the collision capsule, the health and the hitbox turn from the prop's size, the same way on the server and every client. `DotPropTaunts` keeps the taunt list, the cooldown, the points, and the meter that forces a taunt on somebody who has stood still too long.

```gdscript
var rules := DotPropDisguiseRules.new()        # fill from your config
var ok := DotPropDisguise.may_take(size, rules)
var hull := DotPropDisguise.hull(size, rules)  # Vector2(radius, height)
var hp := DotPropDisguise.health(size, rules)

var taunts := DotPropTaunts.new()
taunts.add_all(config_taunts)                  # [{"id", "title", "seconds", "sound"}]
taunts.observe(player_key, position, now)      # every tick
if taunts.due(player_key, now):
    play(taunts.taunt(player_key, now, &"", true, tick))
```

## License
MIT. See [LICENSE](LICENSE).

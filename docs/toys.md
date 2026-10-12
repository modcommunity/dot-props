# Toys

`toys/` is a catalogue of things on a map that players play with: balls to kick, swings to push, see-saws to stand on, trampolines that throw you, switches that turn lamps and fountains on, a horn and a bell. A map places them by data and every game gets the same set. It is not the spawner: a toy is part of the map, placed by its author, not something a player makes.

## Placed by data, paired by index

A map lists `{"toy": "<id>", "at": [x, y, z], "yaw": deg}` (plus `links` for a switch, `on` for a lamp or a fountain). `DotPropToyBox.normal_placement` is the format and `DotPropToyBox.build` builds them in order. **Both ends build the same toys in the same order from the same document**, so a toy's index is the same on every machine, and a game pairs its replicated entity with a toy by index alone: game-hide-n-seek's `TOYS` event carries only the net ids, in toy order. An id the catalogue does not have is left out and listed in `missing`, so a map written for a newer dot-props still plays.

## The kinds, and why there are few

`DotPropToyCatalogue.KINDS` is sixteen behaviours; the eighteen stock toys are those behaviours with numbers (a beach ball and a bowling ball are one kind). A game retunes a toy or adds its own with `merge` from JSON, field by field, without a script: a pack's `class_name` does not resolve, and a toy should be a thing a mapper can add.

## Three kinds of motion

- **Loose** (ball, pin, barrel, tyre): a real `RigidBody3D`, simulated by the server. On the `loose` layer, which people do not collide with: a person walks into a ball and the game's `push_from` sends it on ahead, faster than the walk, instead of the ball being a wall the controller slides along (a character motor never pushes a rigid body; see [damage-and-carry](damage-and-carry.md)). So a bot can never be stuck on one either.
- **Driven** (swing, punching bag, see-saw, wobbly platform, roundabout): an angle or two and a spin about one fixed point, integrated in `DotPropToy._physics_process`, posing a kinematic body. **Not joints**: Godot's own hinge, with a swing pushed at an angle to its bar, sent the seat a thousand kilometres away in half a second, and a pin joint did the same to a bag (2026-10-12, [history](history.md)). An angle cannot leave its pivot and costs no solver iterations. A person's weight on a see-saw or a platform is `stand_on`, a torque about the pivot; a push or a use is `_nudge`, a change of velocity at a point turned into the spins the kind allows.
- **Fixed** (trampoline, bounce pad, switch, lamp, fountain, horn, bell): static bodies; what changes is `on` and `count`.

## Replication: the server's physics, a client's picture

Rigid-body physics is not the same on two machines, so nothing is predicted (the rule [spawning](spawning.md) states for props). On a client every moving part is frozen kinematic and posed from three things a game replicates per toy: `state_transform()` (the moving part's), `on`, and `count`. `show_state` applies them; a client standing on a see-saw stands on the plank the server tipped, an interpolation behind.

**`count` is a use counter, not an event**: a press, a honk, a bounce each move it by one (eight bits, it wraps), and `sense` plays the toy's use sound and its flourish when it sees it move. A lost packet or a joiner costs a late sound, never a missing state.

**Knocks are heard from motion**: `sense` measures the moving part's velocity from its position every tick (authoritative) or frame (a client) and plays the hit sound when it turns sharper than gravity could turn it. That works on a frozen client copy, which has no contacts to report.

## The launchers are movement, not physics

A trampoline or a pad throwing a person is `launch_for(feet, velocity)`: a pure function of where the toy stands, so the game calls it inside its movement code on every end that simulates that person, and a predicting client is thrown on the tick the server throws it. The game counts the bounce (`launched`) on the server only; that is what a client hears.

## Performance

- `DotPropToyRules.cap()`: at most 24 loose toys simulating at once, 8 on a machine without threads (a browser build, whose physics runs between the frames it draws). Past it, the longest untouched are put to sleep, slowest first. Driven toys are not counted: they are a few multiplications, and asleep when still.
- Meshes are made in code (`DotPropToyLook`), matte, untextured, a handful of materials shared by colour: nothing to deliver and cheap under the Compatibility renderer. The lamp's light casts no shadow; the fountain is a `CPUParticles3D` of 90.
- A toy below `kill_y` goes home; `reset` sends them all home (a game calls it at a round's start).

## Footprints

`nav_bodies()` is one static body of boxes on a layer nothing collides with, one per toy that stands in the way, at least two metres tall so a baker never takes a low one (a pad) for a step. A game bakes its bots' walkable mesh round them; loose toys have none, because a bot walks through them like anybody.

## Sounds

`DotPropToySounds.rows()` is the data a game turns into its own audio definitions, like dot-player-char's death sounds: Kenney's CC0 impacts, a switch click, water, a boing, a bell, and a horn made for this addon (`toys/sounds/CREDITS.md`).

## Testing

`props_selftest` builds every stock toy turned 20 degrees (a toy whose axes are the world's hides bugs), a hundred metres up and clear of what earlier sections left falling, and pushes, kicks, stands on, switches, bounces, caps and resets them; a second box is a client's. `examples/toy_gallery.tscn` renders them all (`--kick` to see them moving). game-hide-n-seek's `headless_net` is the replication check.

# Toys

`toys/` is a catalogue of things on a map that players play with: balls to kick, swings to push, see-saws to stand on, trampolines that throw you, switches that turn lamps and fountains on, a horn and a bell. A map places them by data and every game gets the same set. It is not the spawner: a toy is part of the map, placed by its author, not something a player makes.

## Placed by data, paired by index

A map lists `{"toy": "<id>", "at": [x, y, z], "yaw": deg}` (plus `links` for a switch, `on` for a lamp or a fountain). `DotPropToyBox.normal_placement` is the format and `DotPropToyBox.build` builds them in order. **Both ends build the same toys in the same order from the same document**, so a toy's index is the same on every machine, and a game pairs its replicated entity with a toy by index alone: game-hide-n-seek's `TOYS` event carries only the net ids, in toy order. An id the catalogue does not have is left out and listed in `missing`, so a map written for a newer dot-props still plays.

## The kinds, and why there are few

`DotPropToyCatalogue.KINDS` is sixteen behaviours; the eighteen stock toys are those behaviours with numbers (a beach ball and a bowling ball are one kind). A game retunes a toy or adds its own with `merge` from JSON, field by field, without a script: a pack's `class_name` does not resolve, and a toy should be a thing a mapper can add.

## Three kinds of motion

- **Loose** (ball, pin, barrel, crate, tyre): a real `RigidBody3D`, simulated by the server. On the `loose` layer, which people do not collide with: a person walks into a ball and the game's `push_from` sends it on ahead, faster than the walk, instead of the ball being a wall the controller slides along (a character motor never pushes a rigid body; see [damage-and-carry](damage-and-carry.md)). So a bot can never be stuck on one either.
- **Driven** (swing, punching bag, see-saw, wobbly platform, roundabout): an angle or two and a spin about one fixed point, integrated in `DotPropToy._physics_process`, posing a kinematic body. **Not joints**: Godot's own hinge, with a swing pushed at an angle to its bar, sent the seat a thousand kilometres away in half a second, and a pin joint did the same to a bag (2026-10-12, [history](history.md)). An angle cannot leave its pivot and costs no solver iterations. A person's weight on a see-saw or a platform is `stand_on`, a torque about the pivot; a push or a use is `_nudge`, a change of velocity at a point turned into the spins the kind allows.
- **Fixed** (trampoline, bounce pad, switch, lamp, fountain, horn, bell): static bodies; what changes is `on` and `count`.

## Shots and blasts

A shooting game's hit scan asks the box first: `shot(collider, point, direction, damage)` pushes the toy the collider belongs to and returns its index, or -1 when it is not a toy's, so the scan falls through to its own damage. The push is reckoned from the damage as a speed (0.2 m/s a point, 1.5 to 9 m/s) given to a toy of up to 3 kg: a pistol sends a beach ball off at 5 m/s and a barrel, at the mass cap, a quarter of that. A bullet's own momentum would barely move a ball, and an impulse the size of the damage sent one off at 40 m/s. `blast(at, radius, speed)` is an explosion's: every moving toy in the radius away from the centre and a little up at that speed whatever it weighs (a barrel is thrown as a ball is), falling to nothing at the edge. A game whose own trace never meets a toy (an analytic one, or a mask without the toys' layers) calls `shot_along(origin, direction, reach, damage, level_mask)`, which pushes the first toy on the ray unless the level stops it first, and lets the shot go on: a toy is never cover in a shooting game, and never eats a bullet meant for whoever is behind it. A shot bell rings. All three are the server's; a client sees the result in the toy's replicated state.

## A roundabout carries its riders

A person standing on a turning roundabout goes round with it: `carry_for(feet, delta, ground_id)` is how far the deck moves them this tick and how far it turns them, `{offset, yaw, index}`, a **rotation about the hub** rather than the rim's speed along a tangent (which walks a rider outwards a little each tick until they fall off). The game adds the offset to the person's position after the move, on every end that simulates them, the way it calls `launch_for` before it; turning the view by `yaw` is the game's choice. `ground_id` is the motor's collider underfoot (`DotFpsState.ground_id`), and 0 looks for a deck under the feet instead. A game that already rides props through `DotPropCarry` sets `DotPropCarry.toys` and `ride` does it.

The spin is the server's and is not sent. A client measures it from the poses it is shown (`show_state` takes the time since the last one; the wall clock's when left out), so a predicting client carries its own player at nearly the server's rate and the correction is small. A pose after more than half a second is not a spin. Only the roundabout carries: a see-saw's or a platform's tilt is followed by the motor's own ground snap.

## Replication: the server's physics, a client's picture

Rigid-body physics is not the same on two machines, so nothing is predicted (the rule [spawning](spawning.md) states for props). On a client every moving part is frozen kinematic and posed from three things a game replicates per toy: `state_transform()` (the moving part's), `on`, and `count`. `show_state` applies them; a client standing on a see-saw stands on the plank the server tipped, an interpolation behind.

**`count` is a use counter, not an event**: a press, a honk, a bounce each move it by one (eight bits, it wraps), and `sense` plays the toy's use sound and its flourish when it sees it move. A lost packet or a joiner costs a late sound, never a missing state.

**Knocks are heard from motion**: `sense` measures the moving part's velocity from its position every tick (authoritative) or frame (a client) and plays the hit sound when it turns sharper than gravity could turn it. That works on a frozen client copy, which has no contacts to report.

## The launchers are movement, not physics

A trampoline or a pad throwing a person is `launch_for(feet, velocity)`: a pure function of where the toy stands, so the game calls it inside its movement code on every end that simulates that person, and a predicting client is thrown on the tick the server throws it. The game counts the bounce (`launched`) on the server only; that is what a client hears.

## Performance

- `DotPropToyRules.cap()`: at most 24 loose toys simulating at once, 8 on a machine without threads (a browser build, whose physics runs between the frames it draws). Past it, the longest untouched are put to sleep, slowest first. Driven toys are not counted: they are a few multiplications, and asleep when still.
- Meshes are made in code (`DotPropToyLook`), matte, untextured, a handful of materials shared by colour: nothing to deliver and cheap under the Compatibility renderer. The lamp's light casts no shadow; the fountain is a `CPUParticles3D` of 90.
- Measured in a browser (a web export without threads, so the cap is 8; a lobby of 27 toys, 14 of them loose; headless Chromium with software rendering; physics at 128 Hz): asleep toys cost nothing, the same frame time as `sv_toys 0`; an awake loose toy is about 0.5 to 0.7 ms of physics a frame on the one thread; the cap of 8 holds physics to about 4 to 5 ms a frame (5.4 to 5.9 ms with the lobby's asleep cost), where frame rate fell from 55-59 to 45-50; with the cap lifted, 14 awake toys took 10.6 to 15.1 ms of physics a frame, 22 to 41 fps, p95 frames up to 48 ms. At 1280x720 software rendering dominates (123 to 135 ms a frame either way), so the cap matters most on a machine that draws quickly. That is why the threadless cap is 8 and not more.
- A toy below `kill_y` goes home; `reset` sends them all home (a game calls it at a round's start).

## Footprints

`nav_bodies()` is one static body of boxes on a layer nothing collides with, one per toy that stands in the way, at least two metres tall so a baker never takes a low one (a pad) for a step. A game bakes its bots' walkable mesh round them; loose toys have none, because a bot walks through them like anybody. The body is never in the physics space (disabled, `DISABLE_MODE_REMOVE`): the navigation parser reads shapes off the nodes, and a shooting game's hit scan with every bit in its mask stopped on the invisible boxes. `nav_bodies()` is empty while `sv_toys` is 0.

## Sounds

`DotPropToySounds.rows()` is the data a game turns into its own audio definitions, like dot-player-char's death sounds: Kenney's CC0 impacts, a switch click, water, a boing, a bell, and a horn made for this addon (`toys/sounds/CREDITS.md`).

## Testing

`props_selftest` builds every stock toy turned 20 degrees (a toy whose axes are the world's hides bugs), a hundred metres up and clear of what earlier sections left falling, and pushes, kicks, stands on, switches, bounces, caps and resets them; a second box is a client's. `examples/toy_gallery.tscn` renders them all (`--kick` to see them moving). game-hide-n-seek's `headless_net` is the replication check.

`crate` is the toy a game lays at run time for loot or a box: `add_toy(id, at, yaw, def)` builds one (a `def` overrides size and mass) and `remove_toy(toy)` frees it. `sleep_after` (seconds, 0 off) puts an awake toy to sleep once it has lain still that long, so a quiet map simulates nothing.

# A player hiding as a prop (`hunt/`)

The hide-and-seek games turn a player into a prop, and the arithmetic of that is the same in every one of them and has to be the same on both ends of a wire. mg-prop-hunt is the first user.

## `DotPropDisguise`

A value (an id, a size in metres, yaw, pitch, roll, locked) with the statics a game needs:

- `may_take`: too small, too big.
- `hull`: the capsule a motor sweeps. Half the NARROWER footprint, clamped, never shorter than it is wide, so a sofa still fits through the door it came in by.
- `health`: `scale x volume^exponent`, clamped. A cabinet is about nine bottles, not a hundred and fifty.
- `health_after`: changing disguise keeps the fraction, or a hurt player heals by finding a bigger prop.

The hitbox is the other half and IS the prop's box turned by `hit_basis`, because what a seeker shoots at is what they can see. **Both ends compute the hull from the replicated size and never send it.** `DotPropDisguiseRules` is the resource a game fills from its own config.

## `DotPropTaunts`

The noise a hidden player makes: a catalogue (`add_all` from JSON), a cooldown on top of the last taunt's length, points for a chosen one (and, if the server says so, a forced one), and the standing-still meter that forces one on somebody who has not left `auto_radius` of where they settled for `auto_after` seconds. A radius rather than a speed, because a player shuffling on one spot is standing still as far as being found goes.

It plays nothing: where a sound comes from on every client is the game's replication. Simulated seconds are passed in, never a wall clock.

**Neither is a node, and neither depends on anything but dot-core.**

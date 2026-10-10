# Breaking a prop, and standing on one

Both were once listed as deliberately absent, and both came back when a game (mg-buses-from-hell) turned up that is about them: a crate you climb onto to escape a bus, and one you break with a hammer to deny somebody else the same. The old entries were right about the boundary and wrong about the gap.

## `DotPropDamage` holds the health and applies none of it

The numbers live on `DotPropDef` (`max_health`, `break_impact_speed`, `explode_radius`, `explode_damage`, `explode_force`) because a definition has to be checkable without loading the scene. The *state* lives in the `DotPropDamage` node, keyed by the instance id the spawner already hands out, so a breakable prop stays a plain scene with a `RigidBody3D` at its root. That matters: a script on the prop would have to resolve its own `class_name` at load, and a script inside a mounted dot-cloud pack cannot.

**When a barrel goes off, this addon describes the blast and stops.** `exploded` carries a centre, a radius, a damage and a force; dot-combat's `explode()` turns that into hurt people, and the game connects the two. A damage model here would be a second set of rules about who a blast hurts, next to the one that already has hit groups, armour, team scales and falloff. The one thing it *does* apply is the shove to other props, because a prop is the only thing this addon knows about: a player, an NPC and a vehicle each need somebody else's id space and authority rules.

**`break_impact_speed` is a speed and not damage, and that is the whole point.** A crate has to survive being walked into and must not survive a bus, and what separates those is how fast the thing arrived rather than how many times it has been hit. `max_health` is the hammer; `impact()` is the bus. A prop can have either, both, or neither.

**`max_health = 0` is indestructible**, not "dies to anything": every prop written before the field existed decodes to zero, and the other default would make the floor breakable the day a game added a damage source.

## A character motor does not touch a rigid body

`DotPropCarry` is the half that makes a crate an object rather than scenery that happens to be a `RigidBody3D`. `DotFpsMotor`, and every motor like it, sweeps a shape and slides along what it hits, so a crate is exactly as solid as the floor and exactly as immovable: a player stands on one and it does not sink, does not tip, and does not carry them anywhere when something shoves it out from under them. **Every number involved is correct.** There is nothing to notice except standing on a crate and expecting something.

It lives outside the motor on purpose, and the motor already publishes what it needs: `DotFpsState.ground_id` is the instance id of the collider underfoot, a local physics handle that is deliberately *not* part of the simulation. So riding is resolved per frame on each machine from a handle each machine has, rather than becoming another predicted field two machines would have to agree about, which they could not, for the same reason props are not predicted at all.

- **The carried velocity includes the angular part.** A prop that is only sliding moves every point on it at the same speed. A prop that is *turning* moves a player on its edge much faster than its centre, and taking only the linear part makes them drift slowly toward the middle, with no error anywhere.
- **`weight_scale` is not 1.0**, because a swept capsule is not a physics body. A real body resting on a crate settles into an equilibrium the solver finds; a character is teleported to its new position every tick and never settles, so the full weight makes a crate somebody is standing perfectly still on accelerate away downward for ever.

## Testing physics

Two timing facts that each cost a test more than once:

- **An impulse is not readable in `linear_velocity` until the step that consumes it has run.** Check after a physics step, or the shove measures zero.
- **A `mass` assignment is not picked up until the next step**, so an impulse applied in between is divided by the old mass (a 900 kg prop flew twenty times further than a 20 kg one).

**A physics assertion that does not say what it is excluding is measuring gravity.** The check that a crate outside a blast is *not* shoved passed a falling crate at 0.16 m/s, which was one tick of gravity.

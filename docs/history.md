# History

Bugs worth recognising if they come back. None errored. The rule each left is in the topic docs.

- **`DotPropDef.mass` was not put on the spawned body.** It was read in one place, against `grab_mass_limit`, and the body kept its scene's mass: a catalogue saying 900 kg over a scene saved at 20 kg gave a prop the physics gun refused as too heavy and the gravity gun threw like a beach ball. Invisible in this suite, where every fixture is one scene and the check was the limit, not the physics; found by game-playground, which ships one scene for a dozen props.
- **Ownership and undo shared one list**, which was a budget bypass and left props in the world for ever past the undo depth.
- **A prop removed while held was not let go of** until the deferred free landed.
- **`per_player_frozen` and `size` were declared and read by nothing**: documented limits that limited nothing.
- **`DotPhysGun` had no signals**, so a game could not keep a held or frozen prop's collision layer right.
- **In the suite, physics timing, four times**: an impulse read before the step consumed it (measured zero, twice), a mass assignment not yet picked up (the 900 kg prop flew twenty times further), and a "not shoved" check that passed a crate falling at one tick of gravity.
- **Godot's joints blew the first swing apart** (2026-10-12, toys). A swing was a seat hinged to its frame with a `HingeJoint3D`; kicked square to its bar it swung, but a push at an angle to the bar (any toy placed turned, any player not exactly in front) sent the seat a thousand kilometres off within half a second, then to NaN. Re-rooting the body at its mass made it worse. A punching bag on a `PinJoint3D` did the same. Every check passed at first because the suite placed every toy at yaw 0 and kicked along an axis: the swing, the bag, the see-saw, the platform and the roundabout are driven angles now, and the suite's toys are turned 20 degrees.
- **A tyre in the suite was flung three hundred metres** by a crate an earlier section had left falling through the same spot; alone, it stood still. The toy sections build a hundred metres up.
- **A switch's button had no collision**: the use key's ray from a person's eye passed over the post's top, through the drawn button, and the press went to nothing. The button is a shape now, and the prompt test aims at it.

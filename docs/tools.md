# The tools

## What every tool shares

**A tool is not a node and does not own a camera.** It is given an origin and a direction each tick, so the same physics gun works for a player with a first-person camera, a bot, a replay being played back, and a headless test, none of which have a viewport.

**Ownership is deliberately not checked inside the tool.** Whether a player may move somebody else's crate is a server policy (a build server says no, a sandbox says yes, a competitive one says only for admins), and hard-coding either answer means the other needs a fork. The host passes `can_touch_others`. A protected owner is the exception, enforced by `may_act_on` ([spawning.md](spawning.md#protected-owners)).

**One holder at a time**, enforced by `DotPropInstance.held_by`. Two guns pulling one crate toward two players makes it oscillate violently between them and costs ten times the physics step.

**The tools stay 3D.** A physics gun and a gravity gun are first-person tools with an origin and an aim direction, and a 2D game does not want either. The exception is `DotPhysGun.set_frozen`, which handles both bodies: freezing is the one prop operation a 2D game does need (a lobby pins its furniture), and a second copy of "zero the velocities, then set the mode" is a second thing that can forget the first half.

## The physics gun holds with a spring

Teleporting a rigid body to a target transform each tick is the obvious implementation and it is what makes a sandbox unplayable: a body *moved* rather than *pushed* has no velocity, so it passes through walls, wakes nothing it touches, and hands the solver an impossible situation when it is finally released. Setting a velocity toward where the prop should be is a force the solver understands: the prop pushes what is in the way, stops against a wall, and carries its momentum when let go, which is what makes throwing work at all.

`max_speed` is a **safety cap, not a feel dial**. The spring's output is proportional to the distance to the goal, so a player who aims at the sky and then at their feet asks for an arbitrarily large velocity, which tunnels the prop through the world and, at the extreme, produces a non-finite position that poisons its whole physics island.

`hold_rotation` is stored **relative to the view**, so turning your view turns the prop with it. An absolute orientation means the prop keeps facing north while the player walks around it, and building is impossible.

`set_frozen` **zeroes the velocities as well as setting the mode**. Godot keeps a frozen body's velocities and applies them the instant it is unfrozen, so a prop frozen while falling fast leaps away when somebody thaws it, minutes later, with nothing to connect the two.

### Its signals

`grabbed`, `released` and `freeze_changed`. A game needs them to change a prop's collision layer: `DotPhysicsLayout.sandbox_3d` has `held_prop` and `frozen_prop` rows, and without a signal a game sets a prop's layer at spawn and is wrong for the rest of its life (a carried crate that still collides with its carrier shoves them backwards down a corridor).

**`set_frozen` does not emit**, because it is static and a static function cannot emit an instance signal. A game calling it directly changes the state behind the tool's back and gets nothing; go through the gun's instance methods when a listener needs to know.

## The gravity gun is not a smaller physics gun

A physics gun is a building tool: arbitrary distance, free rotation, freezing, and a deliberately soft spring so a piece can be placed precisely. A gravity gun is a weapon and a toy: one fixed carrying position, a stiff hold so the prop tracks the crosshair, and a punt. Shipping one and calling it both gives a building tool that cannot throw and a weapon that cannot build.

A punt is an **impulse**, not a velocity, so a heavy prop goes less far than a light one, which is what makes the tool feel like it has weight, and is free because the solver already divides by the mass.

A frozen prop is **refused** by the gravity gun rather than thawed. The physics gun unfreezes what it grabs, because freezing is its own tool and unfreezing is the obvious undo; a gravity gun that quietly unfroze somebody's build would take a tower apart one piece at a time.

## Deliberately not here

- **Welding, ropes, thrusters, wheels.** Constraints are a much larger surface than spawning, they interact with each other, and a half-built constraint system is worse than none. `DotPropTool` is the hook.

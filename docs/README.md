# dot-props docs

The reasoning behind the sandbox layer, one subject per file. [CLAUDE.md](../CLAUDE.md) has the short rules; these say why.

| File | What it covers |
| --- | --- |
| [spawning.md](spawning.md) | Authority, definitions and mass, 2D, the limits, per-group counts and the resolver, ownership and undo, protected owners, `is_alive`, `DotPropIO`, what is deliberately not here |
| [tools.md](tools.md) | What every tool shares, the physics gun and its signals, the gravity gun |
| [damage-and-carry.md](damage-and-carry.md) | `DotPropDamage`, `DotPropCarry`, and testing physics |
| [pieces.md](pieces.md) | `DotPropPieces`: collision shaped like the model, why it is measured offline, what it costs |
| [hunt.md](hunt.md) | `DotPropDisguise` and `DotPropTaunts`, for players hiding as props |
| [toys.md](toys.md) | The toy catalogue: placed by data, loose, driven and fixed kinds, replication by state and a use counter, the launchers, the awake cap, footprints |
| [history.md](history.md) | The bugs, and how each looked |

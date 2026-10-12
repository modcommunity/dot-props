# Pieces: collision shaped like the model

`DotPropPieces` turns a placed prop's one box into a few convex hulls that follow the model: a tree becomes its trunk, its branches and its leaf clumps; a table its top and legs; a sofa its seat, back and arms.

## Why not one box

The first play test of game-hide-n-seek circled the trees wanting to climb their low branches and met the canopy's box at arm's length, all the way to the ground. A box also fills the space under a table, which is the best spot in a room in a hiding game, and a body pressed against a tree's box looks like it hangs in the air beside the trunk.

## Why convex hulls and not the mesh

A concave (trimesh) shape of a few hundred triangles catches a character on every seam, costs far more per contact, and a map holds hundreds of props. A handful of convex hulls per prop is what the physics engines are fast at, and measured on hide-n-seek's maps it costs little: hs_camp went from 831 to 2078 shapes, a server tick with twelve runners from 1.04 to 1.05 ms, and a ray from 4.7 to 5.9 µs.

## Measured once, offline, read by everybody

`measure(model, frame)` cuts a model up with the engine's own convex decomposition (V-HACD, through `MeshInstance3D.create_multiple_convex_collisions`). That takes about a second per model, needs the meshes, and an export template may not be built with it, so it runs in a game's measuring tool, never at run time. The tool writes `encode(pieces)` into a file the game ships; the server and every client read it with `decode` and build the same shapes with `shapes`. Two ends building collision from two measurements would be a predicting client walking round a branch the server has somewhere else.

- **One decomposition per material.** A model says which part is which by its materials. Decomposing the whole model merged a leaf clump with the trunk beside it into one hull, filling the space above a branch where a person would stand; per material, the bark and the leaves come apart.
- **About three pieces per metre of the prop's longest side**, between 2 and 10 per material (`PIECES_PER_METRE`, `MIN_PIECES`, `MAX_PIECES`).
- **A prop gets no pieces when its box is as good**: under `MIN_SIZE` (0.6 m), one hull, or hulls covering `BOX_FILL` (80%) of the box. The game then collides with its catalogue box, as before.
- **Deterministic.** The same model gives the same numbers, rounded to millimetres, so a tool's `--check` can compare the committed file byte for byte.

`contains(pieces, point, margin)` answers whether a point is inside a prop without a physics space (a shot's impact, a hit test), and `fill` and `planes` are what `measure` uses to decide a box is as good.

## What a game does

game-hide-n-seek is the first: `tools/measure_props.gd` writes `props/pieces.json` next to its catalogue, `HsProps.shapes_of(id)` builds the shapes once per prop id and every copy of the prop shares them, and `HsMap` adds one `CollisionShape3D` per piece. Its `headless_climb` stands a player on a tree's branch and checks a line under a table is clear.

## What Kenney's trees give

Kenney's leaf clumps sit on their branches and the conifers are stacked cones, so most trees have no flat branch to stand on once the box is gone. What a person can reach from the ground: the stubby branches either side of the commonest tree's trunk (1.1 m and 1.5 m up), the roots of the oak, and the trunk itself to hide behind. A tree made for climbing, with limbs a person can stand on, is a model of its own, not something a decomposition can find.

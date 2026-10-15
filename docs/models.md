# Models as props

`DotPropModel` and `DotPropFolder` turn a `.glb` or `.gltf` file into a `DotPropDef` with no code, so a game's menu can offer real objects and a player or operator can add their own by copying a file.

## DotPropModel

- `measure(path, scale, shape_name)` loads a model once and returns `{extent, offset, shape, scale}`: the size in metres after scaling, the offset that centres the model on the body, and the collision shape. The shape is a single convex hull (`convex`), or a primitive (`box`, `sphere`, `cylinder`) when the hull would be a bad fit. A trimesh is never made: a dynamic body cannot use one. A flat or thin model gets a minimum-thickness box, because a hull of a plane has no volume and tunnels through a floor.
- `visual(path, scale, offset)` is a fresh copy for a body to carry. The scale goes on a holder node above the meshes, never on the body (a scaled `RigidBody3D` has a physics scale the solver does not apply to its mass).
- Results are cached per path, scale and shape (`clear_cache()` empties it).
- `repair_textures` gives a material that lost its texture the `Textures/colormap.png` beside the model, which is the delivery trap every vendored kit meets: inside a mounted pack the texture path the importer recorded does not exist.
- A model that measures under 4 cm or over 40 m is refused (`size_ok`), and so is a file over 16 MB.

## DotPropFolder

`load_into(catalogue, dir, scene_path, options)` reads `dir` and adds one prop per model, all built on `scene_path` (the game's one prop scene). A folder that does not exist is not an error. Returns `{added, problems}`.

- **Optional `props.json`** in the folder: `credit` (`author`, `licence`, `url`, `source`), `defaults` (any entry key) and `props`, keyed by file stem, each entry taking `id`, `name`, `category`, `mass`, `scale`, `size_m` (the longest side, in metres), `shape`, `extent` (baked, so nothing is measured), `density`, `cost`, `can_grab`, `can_freeze`, `max_health`, `icon`, `meta` and `credit`.
- **Optional sidecar** `thing.json` beside `thing.glb`, the same keys, for a model the manifest does not list.
- Ids are `sanitize_id(stem)`: lower-case letters, digits and underscores, 48 characters at most. A path is therefore never an id, and a client can only ever name a catalogue entry.
- A sidecar's `icon` may not contain `..`. `thumbs/<stem>.png` or `<stem>.png` beside the model is used when present.
- A dropped file never replaces an existing id unless `options.overwrite` is true. `options.category` is the default category (else the sub-folder name, else `props`). `options.measure = false` trusts baked extents, for a shipped pack.
- At most 600 models, three folders deep.

## What is not solved

A connected client draws a prop from its own copy of the catalogue, so a model that only the server has will not appear on a client. Models that everyone must see belong in the game's pack. See game-playground's `docs/sandbox.md` for the wiring.

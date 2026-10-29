extends RefCounted

## dot-props' API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: hunt/: DotPropDisguise, DotPropDisguiseRules and DotPropTaunts.
# 3: core/: DotPropPieces (collision shaped like the model).
# 4: DotPropDisguise.lean_basis, standing_size, standing_hull, middle_height, model_transform,
#    box_transform: a leant prop rests on the floor.
# 5: toys/: DotPropToyCatalogue, DotPropToyBox, DotPropToy, DotPropToyRules, DotPropToySounds,
#    DotPropToyLook (networked physics toys and interactables placed by a map's data).
# 6: DotPropToy.carry, surface_velocity, show_state's delta; DotPropToyBox.carry_for;
#    DotPropCarry.toys (a roundabout carries the people standing on it); DotPropToyBox.shot
#    shot_along and blast (a hit scan's damage and an explosion turned into a push), a shot
#    bell rings.
# 7: core/: DotPropModel (a model file as a body's picture, hull and mass) and DotPropFolder
#    (a folder of .glb/.gltf files, with optional JSON sidecars, becomes catalogue props).
# 8: tools/: DotToolView (the first-person model of a held tool or toy, joins dot_view_model).
const LEVEL := 8
const OLDEST := 1

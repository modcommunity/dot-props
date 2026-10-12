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
const LEVEL := 5
const OLDEST := 1

"""Builds the toy look models: blender -b --factory-startup --python build_toy_models.py -- <out dir>

Own work, CC0. Materials named c0/c1 take the toy definition's colours at run time;
every other material (steel, rope, dark) keeps its own colour. Z-up here, Y-up in the glb;
each model is centred on its bounding box and scaled to the toy's size by DotPropToyLook.
"""
import bpy, bmesh, math, sys
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {}


def mat(name, rgb):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Roughness"].default_value = 0.7
        MATS[name] = m
    return MATS[name]


PAL = {"c0": (0.6, 0.45, 0.3), "c1": (0.9, 0.7, 0.2), "steel": (0.18, 0.19, 0.21),
       "dark": (0.08, 0.08, 0.09), "rope": (0.8, 0.74, 0.56)}


def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for k in PAL:
        me.materials.append(mat(k, PAL[k]))
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def lathe(bm, profile, seg=20, notch=0.0, shift=(0, 0, 0)):
    """profile: [(r, z, material)] each point's material is used for the segment up to the next point."""
    rings = []
    for (r, z, _m) in profile:
        ring = []
        for i in range(seg):
            a = i / seg * math.tau
            rr = r * (1 - notch) if (notch and i % 2) else r
            ring.append(bm.verts.new((math.cos(a) * rr + shift[0], math.sin(a) * rr + shift[1], z + shift[2])))
        rings.append(ring)
    for k in range(len(profile) - 1):
        mi = list(PAL).index(profile[k][2])
        for i in range(seg):
            j = (i + 1) % seg
            try:
                f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            except ValueError:
                continue
            f.material_index = mi


def box(bm, c, s, m):
    mi = list(PAL).index(m)
    r = bmesh.ops.create_cube(bm, size=1.0)
    verts = r["verts"]
    bmesh.ops.scale(bm, verts=verts, vec=s)
    bmesh.ops.translate(bm, verts=verts, vec=c)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mi


def cap(bm, profile, seg=20):
    """Close the lathe's ends with a fan."""
    pass


def finish(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm)
    return ob


def export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    # centre on the bounding box
    vs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    mid = sum(vs, Vector()) / 8
    for v in ob.data.vertices:
        v.co -= mid
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format="GLB", export_apply=True,
                              export_yup=True, export_materials="EXPORT", use_selection=True)
    bpy.data.objects.remove(ob)


def solid(profile, seg=20, notch=0.0):
    """Lathe with flat closed ends (profile starts and ends on the axis or gets a disc)."""
    bm = bmesh.new()
    p = list(profile)
    if p[0][0] > 0:
        p.insert(0, (0.0, p[0][1], p[0][2]))
    if p[-1][0] > 0:
        p.append((0.0, p[-1][1], p[-1][2]))
    lathe(bm, p, seg, notch)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm


# bowling pin: 1 high, white body, two coloured neck stripes
pin = [(0.0, 0.0, "c0"), (0.26, 0.0, "c0"), (0.36, 0.06, "c0"), (0.4, 0.2, "c0"), (0.34, 0.38, "c0"),
       (0.24, 0.5, "c0"), (0.17, 0.6, "c1"), (0.16, 0.64, "c1"), (0.17, 0.68, "c0"), (0.17, 0.72, "c1"),
       (0.18, 0.76, "c1"), (0.2, 0.84, "c0"), (0.22, 0.92, "c0"), (0.18, 0.98, "c0"), (0.08, 1.0, "c0"), (0.0, 1.0, "c0")]
export([finish("bowling_pin", solid(pin, 24))], "pin")

# barrel: bulged, staves as a faceted notch, two hoops and a lid
bar = [(0.0, 0.0, "c0"), (0.8, 0.0, "c0"), (0.86, 0.03, "c1"), (0.93, 0.12, "c1"), (0.9, 0.18, "c0"),
       (0.98, 0.5, "c0"), (0.9, 0.82, "c0"), (0.93, 0.88, "c1"), (0.86, 0.97, "c1"), (0.8, 1.0, "c1"),
       (0.78, 1.0, "c0"), (0.0, 1.0, "c0")]
bm = bmesh.new()
lathe(bm, bar, 16, notch=0.012)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("barrel", bm)], "barrel")

# crate: dark core, slats (c0) on the faces, corner posts and diagonal braces (c1)
bm = bmesh.new()
box(bm, (0, 0, 0), (0.96, 0.96, 0.96), "dark")
for z in (-0.3, 0.0, 0.3):
    box(bm, (0, 0, z), (1.0, 1.0, 0.24), "c0")
for x in (-0.46, 0.46):
    for y in (-0.46, 0.46):
        box(bm, (x, y, 0), (0.12, 0.12, 1.04), "c1")
for z in (-0.5, 0.5):
    box(bm, (0, 0, z), (1.0, 1.0, 0.06), "c1")
export([finish("crate", bm)], "crate")

# tyre: axle along Z; tread blocks, round shoulders, a rim and hub in c1
bm = bmesh.new()
tyre = [(0.5, -0.5, "dark"), (0.62, -0.5, "dark"), (0.9, -0.44, "dark"), (1.0, -0.3, "dark"), (1.0, -0.2, "dark"),
        (0.97, -0.14, "dark"), (1.0, -0.08, "dark"), (1.0, 0.08, "dark"), (0.97, 0.14, "dark"), (1.0, 0.2, "dark"),
        (1.0, 0.3, "dark"), (0.9, 0.44, "dark"), (0.62, 0.5, "dark"), (0.5, 0.5, "dark"), (0.5, 0.3, "dark"),
        (0.5, -0.3, "dark"), (0.5, -0.5, "dark")]
lathe(bm, tyre, 28)
rim = [(0.0, -0.3, "c1"), (0.52, -0.3, "c1"), (0.52, 0.3, "c1"), (0.0, 0.3, "c1")]
lathe(bm, rim, 20)
lathe(bm, [(0.52, 0.3, "c1"), (0.0, 0.3, "c1")], 20)
lathe(bm, [(0.1, 0.34, "steel"), (0.0, 0.34, "steel")], 8)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("tyre", bm)], "tyre")

# lamp: unit foot radius, height 1; fluted post, collar, open lantern cage round the bulb (added in code), hood
bm = bmesh.new()
post = [(0.0, 0.0, "c0"), (1.0, 0.0, "c0"), (0.9, 0.006, "c0"), (0.6, 0.012, "c0"), (0.42, 0.03, "c0"), (0.3, 0.06, "c0"),
        (0.22, 0.12, "c0"), (0.2, 0.5, "c0"), (0.24, 0.51, "steel"), (0.2, 0.52, "c0"), (0.19, 0.84, "c0"),
        (0.45, 0.85, "steel"), (0.0, 0.85, "steel")]
lathe(bm, post, 16)
for x, y in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
    box(bm, (x * 0.62, y * 0.62, 0.915), (0.07, 0.07, 0.13), "steel")
hood = [(0.0, 0.975, "c0"), (1.0, 0.975, "c0"), (0.95, 0.985, "c0"), (0.5, 0.995, "c0"), (0.2, 1.0, "steel"), (0.0, 1.0, "steel")]
lathe(bm, hood, 16)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("lamp", bm)], "lamp")

# fountain basin: plinth, wall with moulded rim and a band
bm = bmesh.new()
basin = [(0.0, 0.0, "c0"), (0.94, 0.0, "c0"), (1.0, 0.04, "c0"), (1.0, 0.55, "c0"), (0.96, 0.6, "c1"),
         (1.0, 0.68, "c0"), (1.0, 0.9, "c0"), (1.06, 0.93, "c0"), (1.06, 1.0, "c0"), (0.9, 1.0, "c0"),
         (0.0, 1.0, "c0")]
lathe(bm, basin, 32)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("fountain_basin", bm)], "fountain_basin")

# fountain column: vase stem, small bowl, nozzle
bm = bmesh.new()
col = [(0.0, 0.0, "c0"), (0.8, 0.0, "c0"), (0.5, 0.1, "c0"), (0.28, 0.2, "c0"), (0.34, 0.35, "c0"), (0.26, 0.5, "c0"),
       (0.5, 0.6, "c0"), (1.0, 0.8, "c0"), (0.96, 0.84, "c0"), (0.5, 0.78, "c0"), (0.2, 0.84, "c0"), (0.14, 1.0, "c1"),
       (0.0, 1.0, "c1")]
lathe(bm, col, 20)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("fountain_column", bm)], "fountain_column")

# bell: flared body with lip ring, crown loop and clapper
bm = bmesh.new()
bell = [(0.0, 0.0, "c1"), (0.18, 0.02, "c1"), (0.2, 0.2, "c1"), (0.3, 0.45, "c1"), (0.4, 0.7, "c1"), (0.5, 0.88, "c1"),
        (0.52, 0.94, "c0"), (0.45, 1.0, "c0"), (0.5, 1.0, "c0"), (0.5, 0.88, "c1")]
bell = [(0.0, 0.14, "c1"), (0.1, 0.2, "c1"), (0.16, 0.35, "c1"), (0.26, 0.6, "c1"), (0.38, 0.82, "c1"),
        (0.44, 0.96, "c1"), (0.47, 1.0, "steel"), (0.44, 1.04, "steel"), (0.4, 1.0, "steel"), (0.4, 0.2, "steel"), (0.0, 0.2, "steel")]
bell = [(0.0, 1.0, "c1"), (0.06, 0.98, "c1"), (0.2, 0.92, "c1"), (0.3, 0.72, "c1"), (0.36, 0.45, "c1"),
        (0.5, 0.12, "c1"), (0.54, 0.04, "steel"), (0.54, 0.0, "steel"), (0.5, 0.0, "steel"), (0.46, 0.08, "steel")]
lathe(bm, bell, 24)
lathe(bm, [(0.0, 0.07, "dark"), (0.1, 0.07, "dark"), (0.1, 0.0, "dark")], 10, shift=(0, 0, 0.0))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
export([finish("bell", bm)], "bell")

# horn: bell-mouth trumpet along Z, wide mouth at -Z after export
bm = bmesh.new()
horn = [(0.0, 0.0, "c1"), (0.1, 0.0, "c1"), (0.13, 0.15, "c1"), (0.15, 0.4, "c1"), (0.2, 0.62, "c1"),
        (0.32, 0.8, "c1"), (0.5, 0.92, "c1"), (0.55, 1.0, "c0"), (0.5, 1.0, "c0"), (0.3, 0.84, "dark"), (0.0, 0.84, "dark")]
lathe(bm, horn, 20)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
ob = finish("horn_body", bm)
export([ob], "horn")

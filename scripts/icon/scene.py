"""Deepwork app icon — "Silver Lining".

Builds the Blender scene from scratch and renders the two foreground layers of
Resources/Deepwork.icon (the background gradient lives in icon.json):

    cloud.png  the hero cloud, lit from behind by a low sun (silver lining)
    sun.png    the sun orb, sitting behind the cloud's crown
    glow.png   the sun's halo, composited with plus-lighter so it lights the sky

Run:
    blender -b -P scripts/icon/scene.py -- --out Resources/Deepwork.icon/Assets [--preview] [--save scripts/icon/deepwork.blend]

The camera frame is the 1024 pt icon canvas, so every layer is rendered full
canvas and needs no positioning in icon.json.
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--preview", action="store_true", help="few samples, for iterating")
ap.add_argument("--res", type=int, default=1024)
ap.add_argument("--only", choices=["cloud", "sun", "glow"])
ap.add_argument("--save", help="also save the .blend here")
args = ap.parse_args(argv)
OUT = Path(args.out).resolve()
OUT.mkdir(parents=True, exist_ok=True)


def srgb(h, a=1.0):
    """#rrggbb -> linear RGBA for Blender colour sockets."""
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(int(h[1:3], 16)), lin(int(h[3:5], 16)), lin(int(h[5:7], 16)), a)


# ---------------------------------------------------------------- scene reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for d in prefs.devices:
    d.use = d.type == "METAL"
scene.cycles.device = "GPU"
scene.cycles.samples = 96 if args.preview else 1024
scene.cycles.use_denoising = True
scene.cycles.denoiser = "OPENIMAGEDENOISE"
scene.cycles.max_bounces = 16
scene.cycles.transparent_max_bounces = 16
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = args.res
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "16"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.0

# ---------------------------------------------------------------- world
# Dim twilight environment: only seen in reflections / ambient, never directly (film is transparent).
world = bpy.data.worlds.new("Twilight")
scene.world = world
wn = world.node_tree.nodes
wl = world.node_tree.links
wn.clear()
tex = wn.new("ShaderNodeTexCoord")
sep = wn.new("ShaderNodeSeparateXYZ")
ramp = wn.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.35
ramp.color_ramp.elements[0].color = srgb("#ff9a7a")   # warm horizon bounce from below
ramp.color_ramp.elements[1].position = 0.75
ramp.color_ramp.elements[1].color = srgb("#5a5fd8")   # violet sky above
mapr = wn.new("ShaderNodeMapRange")
mapr.inputs["From Min"].default_value = -1
mapr.inputs["From Max"].default_value = 1
bg = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.45
wout = wn.new("ShaderNodeOutputWorld")
wl.new(tex.outputs["Generated"], sep.inputs[0])
wl.new(sep.outputs["Z"], mapr.inputs["Value"])
wl.new(mapr.outputs["Result"], ramp.inputs["Fac"])
wl.new(ramp.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs[0], wout.inputs[0])

# ---------------------------------------------------------------- camera
cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 80
cam_data.sensor_fit = "HORIZONTAL"
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0, -14, 0.25)
cam.rotation_euler = (math.radians(90), 0, 0)
scene.camera = cam

# ---------------------------------------------------------------- cloud
# Exact primitives so the silhouette is designed, not discovered: a horizontal
# capsule gives the flat base with round ends (like the `cloud.fill` glyph),
# three spheres are the puffs. A voxel remesh unions them and a volume-preserving
# Laplacian smooth turns the creases between puffs into soft fillets.
import bmesh  # noqa: E402

BASE_Z, BASE_R, BASE_X0, BASE_X1 = -0.50, 0.50, -1.50, 1.70
PUFFS = [  # (x, z, r)
    (-0.78, 0.02, 0.74),   # left puff
    (0.36, 0.38, 1.00),    # crown, right of centre like the glyph
    (1.30, -0.12, 0.62),   # right puff
]
bm = bmesh.new()
for x, z, r in PUFFS + [(BASE_X0, BASE_Z, BASE_R), (BASE_X1, BASE_Z, BASE_R)]:
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=32, radius=r,
                              matrix=__import__("mathutils").Matrix.Translation((x, 0, z)))
cyl = bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=BASE_R, radius2=BASE_R,
                            depth=BASE_X1 - BASE_X0,
                            matrix=__import__("mathutils").Matrix.Translation(((BASE_X0 + BASE_X1) / 2, 0, BASE_Z))
                            @ __import__("mathutils").Matrix.Rotation(math.radians(90), 4, "Y"))
mesh = bpy.data.meshes.new("Cloud")
bm.to_mesh(mesh)
bm.free()
cloud = bpy.data.objects.new("Cloud", mesh)
scene.collection.objects.link(cloud)
cloud.location = (-0.08, 0, 0.0)
cloud.scale = (1, 0.82, 1)       # a touch thinner front-to-back
rm = cloud.modifiers.new("Union", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = 0.018
sm_ = cloud.modifiers.new("Fillet", "LAPLACIANSMOOTH")
sm_.lambda_factor = 1.0
sm_.iterations = 40
sm_.use_volume_preserve = True
sm_.use_normalized = True
sub = cloud.modifiers.new("Subdiv", "SUBSURF")
sub.levels = sub.render_levels = 1
bpy.context.view_layer.update()
# bake modifiers into the mesh so it can be smooth-shaded and saved compactly
dg = bpy.context.evaluated_depsgraph_get()
baked = bpy.data.meshes.new_from_object(cloud.evaluated_get(dg))
cloud.modifiers.clear()
cloud.data = baked
for p in baked.polygons:
    p.use_smooth = True

cm = bpy.data.materials.new("CloudMat")
cloud.data.materials.append(cm)
n = cm.node_tree.nodes
l = cm.node_tree.links
pb = n["Principled BSDF"]
pb.inputs["Base Color"].default_value = srgb("#ffffff")
pb.inputs["Roughness"].default_value = 0.5
pb.inputs["Subsurface Weight"].default_value = 1.0
pb.inputs["Subsurface Radius"].default_value = (1.0, 0.85, 0.85)  # warm light travels furthest
pb.inputs["Subsurface Scale"].default_value = 0.14
pb.inputs["Specular IOR Level"].default_value = 0.28
pb.inputs["Sheen Weight"].default_value = 0.3
pb.inputs["Sheen Roughness"].default_value = 0.4
pb.inputs["Sheen Tint"].default_value = srgb("#ffffff")
pb.inputs["Coat Weight"].default_value = 0.0
# micro-puff texture: a whisper of noise in the normal so it reads as soft matter, not plastic
coord = n.new("ShaderNodeTexCoord")
noise = n.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 6.0
noise.inputs["Detail"].default_value = 6.0
noise.inputs["Roughness"].default_value = 0.55
bump = n.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = 0.06
bump.inputs["Distance"].default_value = 0.05
l.new(coord.outputs["Object"], noise.inputs["Vector"])
l.new(noise.outputs["Fac"], bump.inputs["Height"])
l.new(bump.outputs["Normal"], pb.inputs["Normal"])

# The silver lining: a thin warm emission on the edges that face the sun.
# facing^1.5 (edge-ness) x max(0, N . to_sun)^2, added on top of the BSDF.
geo = n.new("ShaderNodeNewGeometry")
fres = n.new("ShaderNodeLayerWeight")
fres.inputs["Blend"].default_value = 0.5
to_sun = n.new("ShaderNodeVectorMath")
to_sun.operation = "DOT_PRODUCT"
to_sun.inputs[1].default_value = Vector((0.62, 0.30, 0.72)).normalized()
facing = n.new("ShaderNodeMath")
facing.operation = "MAXIMUM"
facing.inputs[1].default_value = 0.0
focus = n.new("ShaderNodeMath")
focus.operation = "POWER"
focus.inputs[1].default_value = 2.0
edge = n.new("ShaderNodeMath")
edge.operation = "POWER"
edge.inputs[1].default_value = 1.5
lining = n.new("ShaderNodeMath")
lining.operation = "MULTIPLY"
lem = n.new("ShaderNodeEmission")
lem.inputs["Color"].default_value = srgb("#ff8a2e")
glow_k = n.new("ShaderNodeMath")
glow_k.operation = "MULTIPLY"
glow_k.inputs[1].default_value = 7.0
add = n.new("ShaderNodeAddShader")
mout = n["Material Output"]
l.new(geo.outputs["Normal"], to_sun.inputs[0])
l.new(to_sun.outputs["Value"], facing.inputs[0])
l.new(facing.outputs[0], focus.inputs[0])
l.new(fres.outputs["Facing"], edge.inputs[0])
l.new(edge.outputs[0], lining.inputs[0])
l.new(focus.outputs[0], lining.inputs[1])
l.new(lining.outputs[0], glow_k.inputs[0])
l.new(glow_k.outputs[0], lem.inputs["Strength"])
l.new(pb.outputs[0], add.inputs[0])
l.new(lem.outputs[0], add.inputs[1])
l.new(add.outputs[0], mout.inputs["Surface"])


def area(name, loc, target, size, energy, color, shape="DISK"):
    d = bpy.data.lights.new(name, "AREA")
    d.shape = shape
    d.size = size
    d.energy = energy
    d.color = color[:3]
    o = bpy.data.objects.new(name, d)
    scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


# ---------------------------------------------------------------- lighting
# Key: big, soft, cool, from upper left front.
area("Key", (-5.0, -6.0, 8.0), (0, 0, 0), 3.2, 2200, srgb("#f4f5ff"))
# Sun backlight: hot and warm, behind and above the right shoulder -> the silver lining.
area("SunRim", (3.6, 2.6, 4.4), (0.3, 0, 0.4), 1.4, 4200, srgb("#ffa24f"))
# Second rim from the left, cooler, so the left silhouette also separates from the sky.
area("SkyRim", (-4.6, 2.5, 1.8), (0, 0, 0), 2.5, 900, srgb("#9aa6ff"))
# Warm bounce from below (sunset light coming off the "ground").
area("Bounce", (0.5, -5, -5.5), (0, 0, 0), 8.0, 180, srgb("#ff9f8a"))

# ---------------------------------------------------------------- sun orb
# Emissive sphere + a camera-facing halo disc with a radial falloff.
SUN_POS = Vector((1.05, 3.5, 1.20))
sun = bpy.data.objects.new("Sun", bpy.data.meshes.new("SunMesh"))
scene.collection.objects.link(sun)
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=0.95)
bm.to_mesh(sun.data)
bm.free()
for p in sun.data.polygons:
    p.use_smooth = True
sun.location = SUN_POS
sm = bpy.data.materials.new("SunMat")
sun.data.materials.append(sm)
sn = sm.node_tree.nodes
sl = sm.node_tree.links
sn.clear()
lw = sn.new("ShaderNodeLayerWeight")
lw.inputs["Blend"].default_value = 0.55
sramp = sn.new("ShaderNodeValToRGB")
sramp.color_ramp.elements[0].color = srgb("#fff2c2")   # hot core
sramp.color_ramp.elements[1].position = 0.95
sramp.color_ramp.elements[1].color = srgb("#ff8f3a")   # deep orange limb
em = sn.new("ShaderNodeEmission")
em.inputs["Strength"].default_value = 1.0
so = sn.new("ShaderNodeOutputMaterial")
sl.new(lw.outputs["Facing"], sramp.inputs["Fac"])
sl.new(sramp.outputs["Color"], em.inputs["Color"])
sl.new(em.outputs[0], so.inputs[0])

halo = bpy.data.objects.new("Halo", bpy.data.meshes.new("HaloMesh"))
scene.collection.objects.link(halo)
bm = bmesh.new()
bmesh.ops.create_circle(bm, cap_ends=True, segments=128, radius=3.4)
bm.to_mesh(halo.data)
bm.free()
halo.location = SUN_POS + Vector((0, 0.6, 0))
halo.rotation_euler = (math.radians(90), 0, 0)
hm = bpy.data.materials.new("HaloMat")
halo.data.materials.append(hm)
hn = hm.node_tree.nodes
hl = hm.node_tree.links
hn.clear()
hc = hn.new("ShaderNodeTexCoord")
grad = hn.new("ShaderNodeTexGradient")
grad.gradient_type = "SPHERICAL"
hmap = hn.new("ShaderNodeMapping")
hmap.inputs["Scale"].default_value = (1 / 3.4, 1 / 3.4, 1 / 3.4)
hpow = hn.new("ShaderNodeMath")
hpow.operation = "POWER"
hpow.inputs[1].default_value = 2.2
hem = hn.new("ShaderNodeEmission")
hem.inputs["Color"].default_value = srgb("#ffb070")
hem.inputs["Strength"].default_value = 1.35
htr = hn.new("ShaderNodeBsdfTransparent")
hmix = hn.new("ShaderNodeMixShader")
hout = hn.new("ShaderNodeOutputMaterial")
hl.new(hc.outputs["Object"], hmap.inputs["Vector"])
hl.new(hmap.outputs["Vector"], grad.inputs["Vector"])
hl.new(grad.outputs["Fac"], hpow.inputs[0])
hl.new(hpow.outputs[0], hmix.inputs["Fac"])
hl.new(htr.outputs[0], hmix.inputs[1])
hl.new(hem.outputs[0], hmix.inputs[2])
hl.new(hmix.outputs[0], hout.inputs[0])
# Sun objects are art for their own layer; they must not light the cloud (SunRim does that, controllably).
for o in (sun, halo):
    o.visible_diffuse = o.visible_glossy = o.visible_transmission = o.visible_volume_scatter = False
    o.visible_shadow = False

if args.save:
    bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.save).resolve()))


# ---------------------------------------------------------------- render passes
def render(name, show, view="AgX"):
    for o in (cloud, sun, halo):
        o.hide_render = o not in show
    # the cloud needs AgX's highlight roll-off; the emissive sun keeps its saturation under Standard
    scene.view_settings.view_transform = view
    scene.view_settings.look = "AgX - Medium High Contrast" if view == "AgX" else "None"
    # leave highlight headroom on the cloud so the warm lining reads as colour, not as clipped white
    scene.view_settings.exposure = -0.3 if view == "AgX" else 0.0
    scene.render.filepath = str(OUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("wrote", scene.render.filepath)


if args.only in (None, "cloud"):
    render("cloud", {cloud})
if args.only in (None, "sun"):
    render("sun", {sun}, "Standard")
if args.only in (None, "glow"):
    render("glow", {halo}, "Standard")

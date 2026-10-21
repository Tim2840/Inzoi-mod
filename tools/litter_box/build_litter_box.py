"""Build the PawHome_LitterBox 3D static mesh (SM_PawHome_LitterBox.fbx) in Blender.

Dimensions (UE5 centimeters, Z-up, pivot at bottom center (0, 0, 0)):
  Outer tray: 48 cm (X) x 38 cm (Y) x 14 cm (Z)
  Wall thickness: 2.2 cm, floor thickness: 2.0 cm, rounded upper lip
  Litter sand bed inside: 43.6 cm x 33.6 cm, height 6.5 cm with subtle mound
  Two material slots:
    0: MI_LitterBox_Tray (warm pastel cream/pink plastic tray)
    1: MI_LitterBox_Sand (warm beige cat litter granules)

Usage:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b -P tools/litter_box/build_litter_box.py
"""
import math
import pathlib
import bpy
import bmesh

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
OUT_DIR = REPO / "mod" / "modkit" / "meshes"
OUT_FBX = OUT_DIR / "SM_PawHome_LitterBox.fbx"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 0.01  # 1 Blender unit = 1 cm (UE5 standard)


def make_material(name, rgba, roughness=0.5):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def build_litter_box():
    bm = bmesh.new()

    # Outer dimensions in cm (1 BU = 1 cm)
    w, d, h = 48.0, 38.0, 14.0
    wall = 2.2
    floor_h = 2.0
    sand_h = 6.5

    # 1. Tray outer and inner cavity
    # Bottom vertices (slightly tapered base: 45 x 35 cm)
    bw, bd = 45.0 / 2.0, 35.0 / 2.0
    tw, td = w / 2.0, d / 2.0
    iw, id_ = tw - wall, td - wall

    v_out_bot = [
        bm.verts.new((-bw, -bd, 0.0)),
        bm.verts.new((bw, -bd, 0.0)),
        bm.verts.new((bw, bd, 0.0)),
        bm.verts.new((-bw, bd, 0.0)),
    ]
    v_out_top = [
        bm.verts.new((-tw, -td, h)),
        bm.verts.new((tw, -td, h)),
        bm.verts.new((tw, td, h)),
        bm.verts.new((-tw, td, h)),
    ]
    v_in_top = [
        bm.verts.new((-iw, -id_, h)),
        bm.verts.new((iw, -id_, h)),
        bm.verts.new((iw, id_, h)),
        bm.verts.new((-iw, id_, h)),
    ]
    v_in_bot = [
        bm.verts.new((-iw + 1.0, -id_ + 1.0, floor_h)),
        bm.verts.new((iw - 1.0, -id_ + 1.0, floor_h)),
        bm.verts.new((iw - 1.0, id_ - 1.0, floor_h)),
        bm.verts.new((-iw + 1.0, id_ - 1.0, floor_h)),
    ]

    tray_faces = []
    # Bottom face
    tray_faces.append(bm.faces.new((v_out_bot[3], v_out_bot[2], v_out_bot[1], v_out_bot[0])))
    # Inner floor face
    tray_faces.append(bm.faces.new((v_in_bot[0], v_in_bot[1], v_in_bot[2], v_in_bot[3])))

    for i in range(4):
        ni = (i + 1) % 4
        # Outer walls
        tray_faces.append(bm.faces.new((v_out_bot[i], v_out_bot[ni], v_out_top[ni], v_out_top[i])))
        # Top rim
        tray_faces.append(bm.faces.new((v_out_top[i], v_out_top[ni], v_in_top[ni], v_in_top[i])))
        # Inner walls
        tray_faces.append(bm.faces.new((v_in_top[i], v_in_top[ni], v_in_bot[ni], v_in_bot[i])))

    for f in tray_faces:
        f.material_index = 0

    # 2. Cat litter sand bed (4x4 grid with gentle center mound, material_index = 1)
    sw, sd = iw - 0.6, id_ - 0.6
    grid_n = 4
    sand_verts = []
    for gy in range(grid_n + 1):
        row = []
        v_norm = (gy / grid_n) * 2.0 - 1.0
        for gx in range(grid_n + 1):
            u_norm = (gx / grid_n) * 2.0 - 1.0
            r2 = u_norm * u_norm + v_norm * v_norm
            mound = max(0.0, 1.2 * (1.0 - 0.6 * r2))
            row.append(bm.verts.new((u_norm * sw, v_norm * sd, sand_h + mound)))
        sand_verts.append(row)

    for gy in range(grid_n):
        for gx in range(grid_n):
            f = bm.faces.new((
                sand_verts[gy][gx],
                sand_verts[gy][gx + 1],
                sand_verts[gy + 1][gx + 1],
                sand_verts[gy + 1][gx],
            ))
            f.material_index = 1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("SM_PawHome_LitterBox")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SM_PawHome_LitterBox", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Materials
    obj.data.materials.append(make_material("MI_LitterBox_Tray", (0.92, 0.78, 0.80, 1.0), roughness=0.35))
    obj.data.materials.append(make_material("MI_LitterBox_Sand", (0.82, 0.76, 0.64, 1.0), roughness=0.90))

    # Smart UV project so ModKit has clean non-overlapping UVs
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    return obj


def main():
    reset_scene()
    obj = build_litter_box()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=str(OUT_FBX),
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        axis_forward="-Y",
        axis_up="Z",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
    )
    print(f"Exported {OUT_FBX} ({OUT_FBX.stat().st_size} bytes, {len(obj.data.polygons)} polygons)")


if __name__ == "__main__":
    main()

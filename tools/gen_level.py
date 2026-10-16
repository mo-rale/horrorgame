"""Generates scenes/level_map.tscn: the Halverson Works factory.

Run from the project root:  python tools/gen_level.py

The plant is a 3 x 4 grid of rooms (north = +Z, the entrance; the exit gate is
in the south wall). The layout, props and notes are written so the space tells
the story of a night shift that went wrong. See STORY.md for the full story.
"""
import math

T = 0.5                      # wall thickness
H = 5.0                      # wall height
TEX = "res://assets/SBS - Horror Texture Pack 128x128/128x128/"

ext = []          # (id, type, path)
subs = []         # raw sub_resource blocks
nodes = []        # raw node blocks
_ext_ids = {}
_mat_ids = {}


def tex(folder, n):
    kind = {"Stains": "Stain"}.get(folder, folder)
    path = "%s%s/Horror_%s_%02d-128x128.png" % (TEX, folder, kind, n)
    if path in _ext_ids:
        return _ext_ids[path]
    ident = "t%d" % (len(_ext_ids) + 1)
    _ext_ids[path] = ident
    ext.append((ident, "Texture2D", path))
    return ident


def mat(texture=None, color=None, uv=0.35, tri=True, emit=None, energy=1.0,
        alpha=False, rough=None, metal=None):
    key = (texture, color, uv, tri, emit, energy, alpha, rough, metal)
    if key in _mat_ids:
        return _mat_ids[key]
    ident = "m%d" % (len(_mat_ids) + 1)
    _mat_ids[key] = ident
    lines = ['[sub_resource type="StandardMaterial3D" id="%s"]' % ident]
    if alpha:
        lines.append("transparency = 1")
    if texture:
        lines.append('albedo_texture = ExtResource("%s")' % texture)
        lines.append("uv1_scale = Vector3(%s, %s, %s)" % (uv, uv, uv))
        if tri:
            lines.append("uv1_triplanar = true")
    if color:
        lines.append("albedo_color = Color(%s, %s, %s, %s)" % color)
    if rough is not None:
        lines.append("roughness = %s" % rough)
    if metal is not None:
        lines.append("metallic = %s" % metal)
    if emit:
        lines.append("emission_enabled = true")
        lines.append("emission = Color(%s, %s, %s, 1)" % emit)
        lines.append("emission_energy_multiplier = %s" % energy)
    subs.append("\n".join(lines) + "\n")
    return ident


def f(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def node(name, ntype, parent, props, groups=None):
    head = '[node name="%s" type="%s" parent="%s"' % (name, ntype, parent)
    if groups:
        head += ' groups=[%s]' % ", ".join('"%s"' % g for g in groups)
    block = head + "]\n"
    for k, v in props:
        block += "%s = %s\n" % (k, v)
    nodes.append(block)


def vec(x, y, z):
    return "Vector3(%s, %s, %s)" % (f(x), f(y), f(z))


def xform(x, y, z, ry=0.0):
    return "Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)" % (
        f(math.cos(ry)), f(math.sin(ry)), f(-math.sin(ry)), f(math.cos(ry)),
        f(x), f(y), f(z))


_counter = {}


def uname(base):
    _counter[base] = _counter.get(base, 0) + 1
    return "%s%d" % (base, _counter[base])


obstacles = []   # footprints for the spawn sanity check


def csg_box(parent, name, cx, cy, cz, sx, sy, sz, material, ry=0.0, collide=True,
            solid=True):
    props = [("transform", xform(cx, cy, cz, ry)),
             ("material_override", 'SubResource("%s")' % material)]
    if collide:
        props.append(("use_collision", "true"))
    props.append(("size", vec(sx, sy, sz)))
    node(name, "CSGBox3D", parent, props)
    if solid:
        hx, hz = sx / 2, sz / 2
        if abs(math.sin(ry)) > 0.5:
            hx, hz = hz, hx
        obstacles.append((cx - hx, cx + hx, cz - hz, cz + hz, cy + sy / 2))


def csg_cyl(parent, name, cx, cy, cz, radius, height, material, collide=True, sides=16):
    props = [("transform", xform(cx, cy, cz)),
             ("material_override", 'SubResource("%s")' % material)]
    if collide:
        props.append(("use_collision", "true"))
    props += [("radius", f(radius)), ("height", f(height)), ("sides", str(sides))]
    node(name, "CSGCylinder3D", parent, props)
    obstacles.append((cx - radius, cx + radius, cz - radius, cz + radius, cy + height / 2))


def label(name, text, x, y, z, ry=0.0, size=64, color=(0.85, 0.82, 0.7), pixel=0.008):
    node(name, "Label3D", "Signs", [
        ("transform", xform(x, y, z, ry)),
        ("pixel_size", f(pixel)),
        ("modulate", "Color(%s, %s, %s, 1)" % color),
        ("outline_size", "8"),
        ("double_sided", "false"),
        ("text", '"%s"' % text),
        ("font_size", str(size)),
    ])


# ── Materials ───────────────────────────────────────────────────────────────
PLASTER = mat(tex("Wall", 9), uv=0.3)
INDUS = mat(tex("Metal", 12), uv=0.3)
CEIL = mat(tex("Metal", 5), uv=10, tri=False)
FLOORS = {
    "locker": mat(tex("Floor", 2), uv=0.3), "lobby": mat(tex("Floor", 13), uv=0.3),
    "break": mat(tex("Floor", 14), uv=0.3), "steam": mat(tex("Floor", 6), uv=0.3),
    "assembly": mat(tex("Floor", 10), uv=0.3), "elect": mat(tex("Stone", 11), uv=0.3),
    "boiler": mat(tex("Floor", 9), uv=0.3), "press": mat(tex("Floor", 8), uv=0.3),
    "pump": mat(tex("Floor", 7), uv=0.3), "fuel": mat(tex("Stone", 2), uv=0.3),
    "gen": mat(tex("Floor", 4), uv=0.3), "maint": mat(tex("Stone", 12), uv=0.3),
}
LINTEL = mat(tex("Metal", 2), uv=0.3)
CRATE = mat(tex("Wall", 14), uv=0.8)
RUST = mat(tex("Metal", 9), uv=0.5)
LOCKER_M = mat(tex("Metal", 11), uv=0.8)
BENCH = mat(tex("Metal", 10), uv=0.8)
DARK = mat(color=(0.06, 0.05, 0.05, 1), rough=0.9)
PIPE = mat(tex("Metal", 2), uv=0.6, metal=0.6, rough=0.5)
VENDING = mat(color=(0.35, 0.05, 0.05, 1), rough=0.6)
SWITCH = mat(tex("Metal", 14), uv=0.7)
STAIN_MATS = [mat(tex("Stains", n), uv=1, tri=False, alpha=True) for n in (3, 5, 9, 11, 13)]
GLOW_ORANGE = mat(color=(0.9, 0.3, 0.05, 1), emit=(1.0, 0.35, 0.05), energy=2.5)
GLOW_RED = mat(color=(0.9, 0.05, 0.03, 1), emit=(1.0, 0.04, 0.02), energy=2.0)
GLOW = {"red": mat(color=(0.9, 0.05, 0.03, 1), emit=(1, 0.05, 0.03), energy=3.0),
        "blue": mat(color=(0.05, 0.25, 0.9, 1), emit=(0.05, 0.28, 0.95), energy=3.0),
        "yellow": mat(color=(0.95, 0.68, 0.04, 1), emit=(1, 0.7, 0.05), energy=3.0)}
GLASS_PANEL = mat(color=(0.05, 0.08, 0.06, 1), emit=(0.1, 0.5, 0.2), energy=0.6)
EXIT_WALL = mat(tex("Metal", 2), uv=1.0, tri=False)
GATE_MAT = mat(tex("Metal", 13), uv=3.15, tri=False)

# ── Structure ───────────────────────────────────────────────────────────────
DOORS_ROW = [(-2, 2), (-22, -19), (19, 22)]
GAP_X = {45: DOORS_ROW, 28: DOORS_ROW, 8: DOORS_ROW}
DOORS_COL = [(51, 54), (36, 39), (16, 19), (-2, 1)]
GAP_Z = {-12: DOORS_COL, 12: DOORS_COL}


def segments(a, b, gaps):
    cur, out = a, []
    for g0, g1 in sorted(gaps):
        if g0 > cur:
            out.append((cur, g0))
        cur = g1
    if cur < b:
        out.append((cur, b))
    return out


def wall_h(prefix, z, x_from, x_to, gaps):
    wm = PLASTER if z >= 28 else INDUS
    for i, (a, b) in enumerate(segments(x_from, x_to, gaps)):
        csg_box("NavigationRegion3D", "%s%d" % (prefix, i), (a + b) / 2, H / 2, z, b - a, H, T, wm)
    for i, (a, b) in enumerate(sorted(gaps)):
        csg_box("NavigationRegion3D", "%sLintel%d" % (prefix, i), (a + b) / 2, 4.3, z, b - a, 1.4, T,
                LINTEL, solid=False)


def wall_v(prefix, x, z_from, z_to, gaps):
    for i, (a, b) in enumerate(segments(z_from, z_to, gaps)):
        wm = PLASTER if (a + b) / 2 >= 28 else INDUS
        csg_box("NavigationRegion3D", "%s%d" % (prefix, i), x, H / 2, (a + b) / 2, T, H, b - a, wm)
    for i, (a, b) in enumerate(sorted(gaps)):
        csg_box("NavigationRegion3D", "%sLintel%d" % (prefix, i), x, 4.3, (a + b) / 2, T, 1.4, b - a,
                LINTEL, solid=False)


ROOMS = {
    "locker": (-30, -12, 45, 58), "lobby": (-12, 12, 45, 58), "break": (12, 30, 45, 58),
    "steam": (-30, -12, 28, 45), "assembly": (-12, 12, 28, 45), "elect": (12, 30, 28, 45),
    "boiler": (-30, -12, 8, 28), "press": (-12, 12, 8, 28), "pump": (12, 30, 8, 28),
    "fuel": (-30, -12, -10, 8), "gen": (-12, 12, -10, 8), "maint": (12, 30, -10, 8),
}

node("NavigationRegion3D", "NavigationRegion3D", ".", [("navigation_mesh", 'SubResource("NavigationMesh_map")')])
for n in ("Props", "Decor", "Signs", "Notes", "EmergencyLights", "ValveSpawns"):
    node(n, "Node3D", ".", [])

for key, (xa, xb, za, zb) in ROOMS.items():
    csg_box("NavigationRegion3D", "Floor_" + key, (xa + xb) / 2, -0.1, (za + zb) / 2,
            xb - xa, 0.2, zb - za, FLOORS[key], solid=False)

csg_box("NavigationRegion3D", "WestBoundary", -30, 2.5, 24, T, H, 68, PLASTER)
csg_box("NavigationRegion3D", "EastBoundary", 30, 2.5, 24, T, H, 68, PLASTER)
csg_box("NavigationRegion3D", "NorthBoundary", 0, 2.5, 58, 60, H, T, PLASTER)
csg_box("NavigationRegion3D", "SouthBoundary", 16.962, 2.5, -10, 26.076, H, 0.8, INDUS)
csg_box("NavigationRegion3D", "SouthBoundary2", -18.1126, 2.5, -10, 26.076, H, 0.8, INDUS)
for z, gaps in GAP_X.items():
    wall_h("RowWall%d_" % z, z, -30, 30, gaps)
for x, gaps in GAP_Z.items():
    wall_v("ColWall%s_" % ("W" if x < 0 else "E"), x, -10, 58, gaps)

# ── Props ───────────────────────────────────────────────────────────────────
# Tall props live under the NavigationRegion3D so they are carved out of the
# navmesh; low props sit outside it so their tops never become walkable islands.
P = "Props"
R = "NavigationRegion3D"
# Lobby
csg_box(P, "ReceptionDesk", 0, 0.5, 56.3, 5.0, 1.0, 0.9, BENCH)
csg_box(P, "LobbyBench1", -9, 0.25, 47, 2.4, 0.5, 0.6, BENCH)
csg_box(P, "LobbyBench2", 9, 0.25, 47, 2.4, 0.5, 0.6, BENCH)
# Locker room
for i in range(14):
    csg_box(R, "Locker%d" % i, -28.9 + i * 1.05, 1.35, 57.45, 0.9, 2.7, 0.55, LOCKER_M)
csg_box(P, "LockerBench1", -21, 0.25, 51, 6, 0.5, 0.7, BENCH)
csg_box(P, "LockerBench2", -21, 0.25, 48.3, 6, 0.5, 0.7, BENCH)
# Break room
csg_box(P, "BreakTable1", 24, 0.4, 51, 2.4, 0.8, 1.0, BENCH)
csg_box(P, "BreakTable2", 24, 0.4, 47.5, 2.4, 0.8, 1.0, BENCH)
csg_box(R, "VendingMachine", 29.1, 1.35, 56.0, 1.2, 2.7, 1.0, VENDING)
csg_box(P, "OverturnedChair1", 20.2, 0.22, 49.8, 0.5, 0.45, 0.5, BENCH, ry=0.6)
csg_box(P, "OverturnedChair2", 26.8, 0.22, 52.6, 0.5, 0.45, 0.5, BENCH, ry=1.1)
# Steam hall
for (x, z) in [(-20, 32), (-20, 41), (-26, 30.5)]:
    csg_cyl(R, uname("SteamColumn"), x, 2.5, z, 0.35, 5.0, PIPE)
csg_cyl(P, "SteamCeilingPipe1", -27, 4.3, 36.5, 0.25, 16.0, PIPE)
csg_cyl(P, "SteamCeilingPipe2", -16, 4.3, 36.5, 0.25, 16.0, PIPE)
csg_box(P, "PressureGauge", -29.65, 2.5, 33.2, 0.1, 0.9, 0.9, GLOW_RED, solid=False, collide=False)
# Electrical room
for i, z in enumerate((32.5, 35.5, 38.5)):
    csg_box(R, "Switchboard%d" % i, 29.45, 1.35, z, 0.6, 2.7, 2.2, SWITCH)
csg_box(P, "ElectricianDesk", 20, 0.4, 43.4, 2.2, 0.8, 1.0, BENCH)
# Assembly line
csg_box(P, "Conveyor1", -5, 0.4, 37, 1.2, 0.8, 12, BENCH)
csg_box(P, "Conveyor2", 5, 0.4, 37, 1.2, 0.8, 12, BENCH)
csg_box(P, "CrateStackA", -10, 0.6, 43.5, 1.2, 1.2, 1.2, CRATE)
csg_box(P, "CrateStackB", -8.8, 0.4, 43.8, 0.8, 0.8, 0.8, CRATE)
csg_box(P, "CrateStackC", 10, 0.6, 30, 1.2, 1.2, 1.2, CRATE)
# Boiler room
csg_cyl(R, "BoilerTank", -23, 2.4, 17, 2.1, 4.8, RUST, sides=24)
csg_box(P, "BoilerHatch", -20.85, 1.3, 17, 0.16, 1.5, 1.2, GLOW_ORANGE, solid=False, collide=False)
for i, dz in enumerate((-0.45, 0.0, 0.45)):
    csg_box(P, "HatchWeld%d" % i, -20.8, 1.3, 17 + dz, 0.2, 1.5, 0.12, DARK, solid=False, collide=False)
csg_box(P, "HatchWeldBar", -20.78, 1.3, 17, 0.2, 0.14, 1.4, DARK, solid=False, collide=False)
# Press hall
for i, x in enumerate((-6, 6)):
    csg_box(R, "Press%d" % i, x, 1.7, 18, 3.0, 3.4, 3.0, RUST)
    csg_box(P, "PressWarn%d" % i, x, 2.9, 16.45, 2.6, 0.18, 0.06, GLOW_RED, solid=False, collide=False)
csg_box(P, "PressDie1", -6, 0.3, 12.5, 1.6, 0.6, 1.6, DARK)
csg_box(P, "PressDie2", 6, 0.3, 12.5, 1.6, 0.6, 1.6, DARK)
# Pump station
csg_box(P, "Pump1", 24, 0.5, 13.5, 2.0, 1.0, 1.4, RUST)
csg_box(P, "Pump2", 24, 0.5, 22.5, 2.0, 1.0, 1.4, RUST)
# Fuel store
for i, z in enumerate((-7, -3.5, 0, 3.5)):
    csg_box(R, "FuelRack%d" % i, -29.3, 1.35, z, 0.8, 2.7, 2.0, SWITCH)
for i, (x, z) in enumerate([(-16, -8), (-15, -7.3), (-16.7, -7.2), (-14, 6.5), (-15, 6.8)]):
    csg_cyl(P, "Barrel%d" % i, x, 0.5, z, 0.35, 1.0, RUST, sides=12)
csg_box(P, "FuelCrate", -20, 0.5, -8, 1.2, 1.0, 1.2, CRATE)
# Generator hall
csg_box(P, "GenControlDesk", 2.0, 0.5, -3, 3.0, 1.0, 0.9, BENCH)
csg_box(P, "GenPanelGlow", 2.0, 1.15, -3.45, 2.6, 0.5, 0.05, GLASS_PANEL, solid=False, collide=False)
for i, (x, z) in enumerate([(-9, 5.5), (-8.2, 6.2)]):
    csg_cyl(P, "GenBarrel%d" % i, x, 0.5, z, 0.35, 1.0, RUST, sides=12)
# Maintenance shop
for i, z in enumerate((-8, -4, 0)):
    csg_box(P, "Workbench%d" % i, 28.2, 0.45, z, 1.2, 0.9, 3.0, BENCH)
csg_box(P, "Toolbox", 21, 0.3, 5.5, 0.9, 0.6, 0.5, DARK)

# The fuse box on the east wall of the electrical room (front faces west, -X).
node("FuseBox", "StaticBody3D", "Props", [
    ("transform", xform(29.2, 0, 42.2, -math.pi / 2)),
    ("script", 'ExtResource("fusebox_script")')])
# A lit panel above the box so players can find it in the dark.
csg_box(P, "FuseBoxSign", 29.6, 3.3, 42.2, 0.1, 0.5, 1.6, mat(color=(0.9, 0.3, 0.05, 1), emit=(1.0, 0.35, 0.05), energy=0.7), solid=False, collide=False)

# ── Exit corridor (gate, outside yard, victory trigger) ─────────────────────
node("Floor2", "CSGBox3D", ".", [
    ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -1.1435, -0.2368, -20.9892)"),
    ("material_override", 'SubResource("%s")' % mat(tex("Metal", 5), uv=10, tri=False)),
    ("use_collision", "true"), ("size", "Vector3(24.9156, 0.2, 24.4023)")])
node("factorygate", "CSGBox3D", ".", [
    ("transform", "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, -0.5662, 2.5, -10.7807)"),
    ("material_override", 'SubResource("%s")' % GATE_MAT),
    ("use_collision", "true"), ("size", "Vector3(0.8, 5, 9)")])
node("VictoryArea", "Area3D", ".", [("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -22.2233)")])
node("CollisionShape3D", "CollisionShape3D", "VictoryArea", [
    ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -1.3366, 2.5568, 0.513)"),
    ("shape", 'SubResource("BoxShape3D_e6xmq")')])
for nm, tf in (("wall1", "Transform3D(0.9986, 0, 0.0523, 0, 1, 0, -0.0523, 0, 0.9986, 4.2442, 2.5, -14.366)"),
               ("wall", "Transform3D(0.9986, 0, 0.0523, 0, 1, 0, -0.0523, 0, 0.9986, -5.7434, 2.5, -14.6107)")):
    node(nm, "CSGBox3D", ".", [("transform", tf), ("material_override", 'SubResource("%s")' % EXIT_WALL),
                               ("use_collision", "true"), ("size", "Vector3(0.8, 5, 9)")])
node("Ceiling", "CSGBox3D", ".", [
    ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 5.1663, 23.4058)"),
    ("material_override", 'SubResource("%s")' % CEIL), ("use_collision", "true"),
    ("size", "Vector3(60, 0.2, 69.1885)")])

# ── Floor decals ────────────────────────────────────────────────────────────
subs.append('[sub_resource type="QuadMesh" id="StainQuad"]\nsize = Vector2(2.4, 2.4)\n')


def stain(name, x, z, rot, scale=1.0, which=0):
    node(name, "MeshInstance3D", "Decor", [
        ("transform", "Transform3D(%s, %s, 0, 0, 0, 1, %s, %s, 0, %s, 0.02, %s)" % (
            f(math.cos(rot) * scale), f(-math.sin(rot) * scale),
            f(-math.sin(rot) * scale), f(-math.cos(rot) * scale), f(x), f(z))),
        ("material_override", 'SubResource("%s")' % STAIN_MATS[which % len(STAIN_MATS)]),
        ("mesh", 'SubResource("StainQuad")')])


stain("StainHatch1", -19.2, 17.0, 0.3, 1.6, 0)
stain("StainHatch2", -18.0, 20.5, 1.2, 1.0, 1)
stain("StainHatch3", -16.0, 24.0, 2.1, 0.8, 2)
stain("StainDoorBoiler", -14.0, 27.5, 0.7, 0.9, 3)
stain("StainPress1", -6.0, 20.2, 0.0, 1.3, 2)
stain("StainPress2", 6.0, 20.0, 1.0, 1.0, 4)
stain("StainLocker1", -17.0, 53.0, 0.4, 1.2, 1)
stain("StainLocker2", -14.0, 52.5, 1.6, 0.9, 3)
stain("StainSteam", -22.0, 33.0, 0.9, 1.1, 4)
stain("StainGen1", 4.0, -6.0, 0.2, 1.1, 0)
stain("StainGen2", 8.5, -2.5, 2.0, 0.8, 2)
stain("StainFuel", -22.0, 2.0, 1.3, 1.0, 1)

# ── Signs ───────────────────────────────────────────────────────────────────
SIGN = (0.85, 0.8, 0.62)
WARN = (0.9, 0.25, 0.2)
PI = math.pi
label("SignLobby", "HALVERSON WORKS\\nNIGHT SHIFT ENTRANCE", 0, 3.6, 57.7, PI, 72, SIGN)
label("SignLocker", "LOCKER ROOM", -21, 3.9, 57.7, PI, 64, SIGN)
label("SignBreak", "BREAK ROOM", 21, 3.6, 57.7, PI, 64, SIGN)
label("SignSteam", "STEAM HALL\\nVALVE A", -26.0, 3.8, 44.7, PI, 56, WARN)
label("SignAssembly", "ASSEMBLY LINE 3\\nQUOTA 3,100 / 4,000", 0, 3.7, 28.3, 0.0, 64, WARN)
label("SignElect", "ELECTRICAL\\nHIGH VOLTAGE", 25, 3.7, 44.7, PI, 64, WARN)
label("SignBoiler", "BOILER ROOM\\nVALVE B", -26, 3.8, 27.7, PI, 56, WARN)
label("SignPress", "HYDRAULIC PRESS HALL", 0, 3.9, 27.7, PI, 56, SIGN)
label("SignPump", "PUMP STATION\\nVALVE C", 26, 3.8, 27.7, PI, 56, WARN)
label("SignFuel", "FUEL STORE\\nNO FLAMES", -26, 3.8, 7.7, PI, 56, WARN)
label("SignGen", "GENERATOR HALL", 7, 3.9, 7.7, PI, 64, SIGN)
label("SignMaint", "MAINTENANCE", 26, 3.8, 7.7, PI, 56, SIGN)
label("SignGate", "SHIFT SEAL ENGAGED\\nPOWER REQUIRED", -0.57, 3.4, -9.6, 0.0, 64, WARN)
label("SignPSI", "182 PSI", -29.55, 3.4, 33.2, PI / 2, 72, (1.0, 0.15, 0.1))

# ── Story notes ─────────────────────────────────────────────────────────────
NOTES = [
    ("NoteLobby", (-11.7, 1.5, 56.4), 0.0, (0.05, 0.75, 0.55), "NIGHT SHIFT NOTICE",
     "HALVERSON WORKS - NIGHT SHIFT\\n\\nOutput target: 4,000 units by 06:00.\\nBoiler pressure limit: 140 PSI. Do NOT override.\\n\\n"
     "In a power loss the gate SEAL engages automatically. It releases only when the plant generator is running.\\n\\n- Plant Management"),
    ("NoteLocker", (-21.4, 0.55, 51.0), 0.4, (0.4, 0.03, 0.3), "A LETTER, NEVER SENT",
     "Dad,\\n\\nEllis cancelled our break again. Nobody leaves until quota, he says. Half of us haven't slept.\\n\\n"
     "I keep hearing someone walking the catwalks after the lights flicker. Nobody will say it out loud, but we've all heard it.\\n\\n"
     "If I'm late home, tell Ma I'm okay.\\n\\n- Mara"),
    ("NoteBreak", (24.0, 0.83, 51.0), -0.3, (0.4, 0.03, 0.3), "FOREMAN'S MEMO",
     "ATTN ALL HANDS\\n\\nLine 3 is behind. The valves stay OPEN. Pressure is a number on a dial - production is the job.\\n\\n"
     "Anyone who touches those valves answers to me. Nobody clocks out until the shift is done.\\n\\n- F. Ellis, Night Foreman"),
    ("NoteSteam", (-29.7, 1.55, 40.5), 0.0, (0.05, 0.6, 0.45), "PRESSURE LOG",
     "02:07 - Gauge past 180 PSI and still climbing. Line 3 split. Steam everywhere.\\n\\n"
     "Ellis screamed at us to keep running. I'm closing valve A anyway.\\n\\nSomebody has to shut B and C too, or this whole place goes.\\n\\n"
     "Ellis went down to the boiler room to override B himself."),
    ("NoteElect", (20.0, 0.83, 43.4), 0.2, (0.4, 0.03, 0.3), "ELECTRICIAN'S NOTE",
     "02:11 - Main breaker tripped. The whole plant is dark and the gate seal clamped shut on its own.\\n\\n"
     "I pulled the generator fuses and hid them around the plant. If Ellis restarts the line, he'll send more men into that boiler.\\n\\n"
     "Whoever reads this: you need three fuses - red, blue, yellow. Push them into the FUSE BOX on this wall. Close the pressure valves first, or the plant will blow."),
    ("NoteFuel", (-20.0, 1.03, -8.0), 0.5, (0.4, 0.03, 0.3), "SCRAWLED ON A CRATE",
     "Generator fuel is kept here. Three cans left, maybe four.\\n\\nSomething walks the catwalk above us. Slow. Patient. It stops whenever I look at it.\\n\\n"
     "Don't look away from it. And don't let it get behind you."),
    ("NoteBoiler", (-29.7, 1.5, 21.5), 0.0, (0.05, 0.6, 0.45), "BOILER ROOM LOG",
     "The boiler hatch is welded shut - from the INSIDE.\\n\\nWe heard Ellis hammering and shouting for an hour. Then quiet. Then the hatch started to glow.\\n\\n"
     "Then the first of us went missing.\\n\\nIt isn't done with the shift."),
    ("NoteGen", (-11.7, 1.5, 4.6), 0.0, (0.05, 0.6, 0.45), "FOREMAN'S LAST LOG",
     "SHIFT LOG - F. ELLIS\\n\\n02:40 - Pressure holding. Quota on track.\\n\\nThe men keep leaving. That's fine. I'll keep working until the next shift arrives.\\n\\n"
     "The gate opens when the plant runs. It always opens... for the next shift.\\n\\nDon't stop. Don't stop. Don't stop."),
]
for name, (x, y, z), ry, (sx, sy, sz), title, body in NOTES:
    node(name, "StaticBody3D", "Notes", [
        ("transform", xform(x, y, z, ry)),
        ("script", 'ExtResource("note_script")'),
        ("title", '"%s"' % title), ("body", '"%s"' % body),
        ("paper_size", vec(sx, sy, sz))])

# ── Lights ──────────────────────────────────────────────────────────────────
EMERGENCY = {
    "locker": ((-21, 4.1, 51.5), (1.0, 0.6, 0.25)), "lobby": ((0, 4.1, 52), (1.0, 0.65, 0.3)),
    "break": ((21, 4.1, 51.5), (1.0, 0.7, 0.35)), "steam": ((-21, 4.1, 36.5), (1.0, 0.25, 0.15)),
    "assembly": ((0, 4.1, 36.5), (0.9, 0.5, 0.25)), "elect": ((21, 4.1, 36.5), (1.0, 0.6, 0.25)),
    "boiler": ((-21, 4.1, 18), (1.0, 0.35, 0.1)), "press": ((0, 4.1, 18), (1.0, 0.2, 0.12)),
    "pump": ((21, 4.1, 18), (0.9, 0.35, 0.2)), "fuel": ((-21, 4.1, 0), (1.0, 0.55, 0.25)),
    "gen": ((0, 4.1, 0), (1.0, 0.4, 0.2)), "maint": ((21, 4.1, 0), (0.9, 0.5, 0.25)),
}
for key, ((x, y, z), (r, g, b)) in EMERGENCY.items():
    node("Emergency_" + key, "OmniLight3D", "EmergencyLights", [
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % (f(x), f(y), f(z))),
        ("script", 'ExtResource("flicker_script")'),
        ("light_color", "Color(%s, %s, %s, 1)" % (r, g, b)),
        ("light_energy", "1.0"), ("omni_range", "10.5")])

node("lights", "Node3D", ".", [])
for i, (x, z) in enumerate([(0, 52), (-21, 36), (21, 36), (0, 18), (-21, 0), (0, 0), (21, 0)]):
    node("OmniLight3D%d" % (i + 1), "OmniLight3D", "lights", [
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 4.4, %s)" % (f(x), f(z))),
        ("light_energy", "8.6"), ("shadow_enabled", "true"), ("omni_range", "30.0")])

# ── Spawn points ────────────────────────────────────────────────────────────
node("SpawnPoints", "Node3D", ".", [])
for name, pos in (("PlayerSpawn", (0, 0.05, 52)), ("EnemySpawn", (-20.6727, 0.95, -2.8758)),
                  ("GeneratorSpawn", (7.0392, 1.0, -7.0138))):
    node(name, "Marker3D", "SpawnPoints", [
        ("unique_name_in_owner", "true"),
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % tuple(f(v) for v in pos))])

GAS = [(-26, -5), (-26, 1), (-18, -3), (-22, 4), (-26, 24), (-26, 33), (16, 12), (28, 14), (16, 4)]
FUSE = [(-15, 47), (16, 48), (16, 32), (24, 31), (0, 41), (16, -6), (18, 3), (-16, 56)]
node("GasSpawnPoints", "Node3D", ".", [("unique_name_in_owner", "true")])
for i, (x, z) in enumerate(GAS):
    node("GasSpawn%02d" % (i + 1), "Marker3D", "GasSpawnPoints", [
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0.75, %s)" % (f(x), f(z)))],
        groups=["gas_spawn"])
for i, (x, z) in enumerate(FUSE):
    node("FuseSpawn%02d" % (i + 1), "Marker3D", "GasSpawnPoints", [
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0.75, %s)" % (f(x), f(z)))],
        groups=["fuse_spawn"])

for name, (x, y, z), ry in [("ValveA", (-29.0, 0, 36.5), PI / 2), ("ValveB", (-29.0, 0, 12.0), PI / 2),
                            ("ValveC", (29.0, 0, 18.0), -PI / 2)]:
    node(name, "Marker3D", "ValveSpawns", [("transform", xform(x, y, z, ry))])

# Three extra gas cans from an earlier edit stay beside the generator.
for i, (x, z) in enumerate([(2.5603, 0.1863), (3.4468, 0.2839), (4.3093, 0.4749)]):
    nodes.append('[node name="%s" parent="." instance=ExtResource("gascan_scene")]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0.375, %s)\n' % (
                     "gascan" if i == 0 else "gascan%d" % (i + 1), f(x), f(z)))


def check_spawns():
    bad = []
    for kind, pts in (("gas", GAS), ("fuse", FUSE)):
        for (x, z) in pts:
            for (xa, xb, za, zb, top) in obstacles:
                if xa - 0.4 <= x <= xb + 0.4 and za - 0.4 <= z <= zb + 0.4 and top > 0.3:
                    bad.append((kind, x, z))
                    break
    if bad:
        raise SystemExit("Spawn markers overlap props: %s" % bad)


check_spawns()

# ── Write the scene ─────────────────────────────────────────────────────────
head = ['[gd_scene format=3 uid="uid://dvuhqut63xyl0"]\n',
        '[ext_resource type="Script" uid="uid://b7e6t4f133m6o" path="res://scripts/level_map.gd" id="1_map"]',
        '[ext_resource type="Script" path="res://scripts/story_note.gd" id="note_script"]',
        '[ext_resource type="Script" path="res://scripts/flicker_light.gd" id="flicker_script"]',
        '[ext_resource type="Script" path="res://scripts/fuse_box.gd" id="fusebox_script"]',
        '[ext_resource type="PackedScene" uid="uid://cp861k7cohx8e" path="res://scenes/gas_can.tscn" id="gascan_scene"]']
for ident, ttype, path in ext:
    head.append('[ext_resource type="%s" path="%s" id="%s"]' % (ttype, path, ident))
fixed_subs = [
    '[sub_resource type="NavigationMesh" id="NavigationMesh_map"]\nagent_height = 1.8\nagent_radius = 0.45\n'
    'agent_max_climb = 0.4\nfilter_baking_aabb = AABB(-30, -0.5, -10, 60, 3, 68)\n',
    '[sub_resource type="BoxShape3D" id="BoxShape3D_e6xmq"]\nsize = Vector3(23.749, 6.1136, 13.7307)\n',
]
out = "\n".join(head) + "\n\n" + "\n".join(fixed_subs) + "\n" + "\n".join(subs) + "\n"
out += '[node name="LevelMap" type="Node3D"]\nscript = ExtResource("1_map")\n\n'
out += "\n".join(nodes)
open("scenes/level_map.tscn", "w", encoding="utf-8", newline="\n").write(out)
print("wrote scenes/level_map.tscn with %d nodes" % (len(nodes) + 1))

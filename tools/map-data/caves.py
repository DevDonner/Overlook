"""Generates Data/Caves.lua: the minimap images of caves and building interiors (WMOs) on the two
continents, and where each one sits, so the far view can draw the inside of a cave the way the
native minimap does indoors.

Runs on the developer's machine against a local game install (read-only, game closed or open):
    python tools/map-data/caves.py "C:/Program Files (x86)/World of Warcraft" > Data/Caves.lua
The output only holds file IDs and numbers.

Where the data comes from:
  * WMOMinimapTexture.db2: per WMO (MOHD wmoID), per group: blocks (BlockX, BlockY) -> image file ID.
  * Continent WDT -> each tile's _obj0.adt -> MODF: placed WMOs (position, rotation, bounds, scale).
  * WMO root: MOHD (wmoID) and MOGI (group bounding boxes, local yards, Z up).

Image layout, checked in game in Wailing Caverns: 2 px per yard; image columns run along local +X,
image rows run down along local -Y; block (bx, by) starts at the group's bounding-box minimum plus
128 yards per block step. A placement turns local (X, Y) into world (north, west) by the angle
MODF rot.y - 180 degrees, about the placement's position.
"""
import math
import os
import struct
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casc import Casc  # noqa: E402
from chunks import chunks  # noqa: E402
from db2 import read_wdc5  # noqa: E402

WMO_MINIMAP_TEXTURE_DB2 = 1323241
CONTINENTS = {0: 775971, 1: 782779}  # instance -> WDT file ID (Azeroth, Kalimdor)
HALF = 32 * 1600 / 3                  # 17066.67: world origin offset of ADT placement space
FLOOR_GAP = 10.0                      # yards between floor heights that start a new level


def build_key(install):
    with open(os.path.join(install, ".build.info"), encoding="utf-8") as f:
        head = f.readline().strip().split("|")
        for line in f:
            vals = line.strip().split("|")
            row = dict(zip((h.split("!")[0] for h in head), vals))
            if row.get("Active") == "1" and row.get("Product") == "wowf":
                return row["Build Key"], row.get("Version")
    raise SystemExit("no active wowf build in .build.info")


def image_size(c, fd):
    """Width and height of a BLP image (from its header)."""
    b = c.read_fdid(fd)
    if b[:4] != b"BLP2":
        raise ValueError("not a BLP2 image: %d" % fd)
    return struct.unpack_from("<II", b, 12)


def wmo_groups(c, fd):
    """(wmoID, [(minX, minY, minZ, maxX, maxY, maxZ)]) from a WMO root file."""
    root = dict(chunks(c.read_fdid(fd)))
    wmoid = struct.unpack_from("<I", root["MOHD"], 32)[0]
    mogi = root.get("MOGI", b"")
    boxes = [struct.unpack_from("<6f", mogi, g * 32 + 4) for g in range(len(mogi) // 32)]
    return wmoid, boxes


def levels(floors):
    """floors: {group: floor height (bounding-box bottom, local yards)} -> {group: level}.

    Level 1 is the top. Groups are taken from the highest floor down; a gap of FLOOR_GAP or more
    to the next floor starts a new level, so a ramp of small steps stays one level.
    """
    order = sorted(floors, key=lambda g: -floors[g])
    level, out, prev = 1, {}, None
    for g in order:
        if prev is not None and prev - floors[g] >= FLOOR_GAP:
            level += 1
        out[g] = level
        prev = floors[g]
    return out


def main():
    install = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\World of Warcraft"
    key, version = build_key(install)
    c = Casc(os.path.join(install, "Data"), key)
    log = sys.stderr

    tex = defaultdict(lambda: defaultdict(list))  # wmoID -> group -> [(bx, by, fd)]
    for r in read_wdc5(c.read_fdid(WMO_MINIMAP_TEXTURE_DB2)):
        g, bx, by, fd = r["f"]
        if not 256 <= by < 512:
            raise SystemExit("unexpected BlockY %d: table layout changed" % by)
        tex[r["rel"]][g].append((bx, by - 256, fd))

    placements = {}  # instance -> {uid: (wmoFd, N, W, yaw, nMin, nMax, wMin, wMax, scale)}
    unnamed = 0
    for inst, wdt_fd in CONTINENTS.items():
        maid = dict(chunks(c.read_fdid(wdt_fd)))["MAID"]
        seen = {}
        for i in range(4096):
            obj0 = struct.unpack_from("<8I", maid, i * 32)[1]
            if not obj0 or not c.has(obj0):
                continue
            modf = dict(chunks(c.read_fdid(obj0))).get("MODF", b"")
            for k in range(len(modf) // 64):
                e = struct.unpack_from("<II3f3f6fHHHH", modf, k * 64)
                fd, uid, (px, py, pz), rot, ext, flags, scale = e[0], e[1], e[2:5], e[5:8], e[8:14], e[14], e[17]
                if not flags & 0x8:
                    unnamed += 1  # placed by file name, not ID: not seen on 1.60.1
                    continue
                if uid in seen:
                    continue
                n_ext = sorted((HALF - ext[2], HALF - ext[5]))
                w_ext = sorted((HALF - ext[0], HALF - ext[3]))
                seen[uid] = (fd, HALF - pz, HALF - px, math.radians(rot[1] - 180),
                             n_ext[0], n_ext[1], w_ext[0], w_ext[1], (scale or 1024) / 1024)
        placements[inst] = seen
        print("instance %d: %d placed WMOs" % (inst, len(seen)), file=log)
    if unnamed:
        print("skipped %d placements by file name" % unnamed, file=log)

    wmos = {}
    used = sorted({p[0] for ps in placements.values() for p in ps.values()})
    for i, fd in enumerate(used):
        if not c.has(fd):
            continue
        try:
            wmoid, boxes = wmo_groups(c, fd)
        except (KeyError, struct.error, PermissionError):
            continue
        if wmoid not in tex:
            continue
        groups, info = {}, {}
        for g, blocks in tex[wmoid].items():
            if g >= len(boxes):
                continue
            minX, minY, minZ = boxes[g][0:3]
            tiles = []
            for bx, by, tfd in sorted(blocks):
                if not c.has(tfd):
                    continue
                w, h = image_size(c, tfd)
                tiles.append((tfd, bx, by, w, h))
            if tiles:
                groups[g] = minZ
                info[g] = (minX, minY, tiles)
        if not groups:
            continue
        lv = levels(groups)
        wmos[fd] = [(lv[g],) + info[g] for g in sorted(groups)]
        if i % 200 == 0:
            print("  %d / %d WMOs" % (i, len(used)), file=log)

    out = sys.stdout
    out.write("-- Generated by tools/map-data/caves.py from build %s; regenerate rather than edit.\n" % version)
    out.write("-- Caves and building interiors: the native minimap's indoor images and where they sit.\n")
    out.write("--  wmo[file ID] = { group, ... }, group = { level, minX, minY, file, bx, by, w, h, ... }\n")
    out.write("--    (level 1 is the top floor; local yards; w, h in px at 2 px per yard; 128 yards per block)\n")
    out.write("--  [instance] = { { wmo, north, west, yaw, nMin, nMax, wMin, wMax [, scale] }, ... }\n\n")
    out.write("local _, ns = ...\n\nns.CaveData = {\n\twmo = {\n")
    for fd in sorted(wmos):
        out.write("\t\t[%d] = {\n" % fd)
        for lvl, minX, minY, tiles in wmos[fd]:
            parts = ["%d, %.1f, %.1f" % (lvl, minX, minY)]
            parts += ["%d, %d, %d, %d, %d" % t for t in tiles]
            out.write("\t\t\t{ %s },\n" % ", ".join(parts))
        out.write("\t\t},\n")
    out.write("\t},\n")
    total = 0
    for inst in sorted(placements):
        out.write("\t[%d] = {\n" % inst)
        for uid in sorted(placements[inst]):
            fd, n, w, yaw, n0, n1, w0, w1, scale = placements[inst][uid]
            if fd not in wmos:
                continue
            total += 1
            s = "" if abs(scale - 1) < 1e-3 else ", %.3f" % scale
            out.write("\t\t{ %d, %.1f, %.1f, %.4f, %.1f, %.1f, %.1f, %.1f%s },\n" % (fd, n, w, yaw, n0, n1, w0, w1, s))
        out.write("\t},\n")
    out.write("}\n")
    print("wrote %d WMOs, %d placements" % (len(wmos), total), file=log)


if __name__ == "__main__":
    main()

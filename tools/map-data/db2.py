"""Minimal WDC5 (DB2) reader: enough for small, non-sparse tables such as WMOMinimapTexture.

read_wdc5 returns rows as {"id", "f" (inline field values in file order), "rel" (relation id)}.
Encrypted sections whose key isn't public come out of casc.py zero-filled and are skipped.
"""
import struct

_HEADER = "<9I2H7I"
_SECTION = "<Q8I"


def read_wdc5(b):
    if b[:4] != b"WDC5":
        raise ValueError("not a WDC5 file: %r" % b[:4])
    off = 4 + 4 + 128  # magic, version, schema string
    (_, field_count, rec_size, _, _, _, _, _, _, flags, _, _, _, _, fsi_size, common_size,
     pallet_size, section_count) = struct.unpack_from(_HEADER, b, off)
    if flags & 1:
        raise NotImplementedError("sparse (offset-map) tables")
    off += struct.calcsize(_HEADER)
    sections = []
    for _ in range(section_count):
        sections.append(struct.unpack_from(_SECTION, b, off))
        off += struct.calcsize(_SECTION)
    off += 4 * field_count  # field structure
    fsi = [struct.unpack_from("<HHIIIII", b, off + 24 * k) for k in range(fsi_size // 24)]
    off += fsi_size
    pallet_start = off
    common_start = off + pallet_size

    # Per-field offsets into the pallet and common blocks.
    pal_off, commons = [], []
    p = c = 0
    for bit_off, bit_size, add, comp, v1, v2, v3 in fsi:
        pal_off.append(p)
        d = {}
        if comp in (3, 4):
            p += add
        if comp == 2:
            for k in range(add // 8):
                rid, val = struct.unpack_from("<II", b, common_start + c + 8 * k)
                d[rid] = val
            c += add
        commons.append(d)

    rows = []
    for tact, foff, srec, sstr, _, idlist_size, rel_size, offmap_count, copy_count in sections:
        recs = foff
        o = foff + srec * rec_size + sstr
        ids = struct.unpack_from("<%dI" % (idlist_size // 4), b, o)
        o += idlist_size
        copies = [struct.unpack_from("<II", b, o + 8 * k) for k in range(copy_count)]
        o += 8 * copy_count + 6 * offmap_count
        rel = {}
        if rel_size:
            n = struct.unpack_from("<I", b, o)[0]
            for k in range(n):
                fid, ridx = struct.unpack_from("<II", b, o + 12 + 8 * k)
                rel[ridx] = fid
        if tact != 0 and not any(b[recs:recs + srec * rec_size]):
            continue  # encrypted, key not public
        by_id = {}
        for r in range(srec):
            raw = int.from_bytes(b[recs + r * rec_size:recs + (r + 1) * rec_size] + b"\0" * 8, "little")
            rid = ids[r] if ids else None
            vals = []
            for i, (bit_off, bit_size, add, comp, v1, v2, v3) in enumerate(fsi):
                v = (raw >> bit_off) & ((1 << bit_size) - 1)
                if comp == 5 and v & (1 << (bit_size - 1)):
                    v -= 1 << bit_size  # signed bitpacked
                elif comp == 2:
                    v = commons[i].get(rid, v1)
                elif comp in (3, 4):
                    v = struct.unpack_from("<I", b, pallet_start + pal_off[i] + 4 * v)[0]
                vals.append(v)
            row = {"id": rid, "f": vals, "rel": rel.get(r)}
            rows.append(row)
            by_id[rid] = row
        for new, old in copies:
            src = by_id.get(old)
            if src:
                rows.append({"id": new, "f": list(src["f"]), "rel": src["rel"]})
    return rows

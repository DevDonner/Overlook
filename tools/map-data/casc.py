"""Minimal read-only local CASC reader (enough to fetch files by FileDataID)."""
import os, struct, zlib, glob

class Casc:
    def __init__(self, data_dir, build_key):
        self.dir = data_dir
        self.cfg = self._config(build_key)
        self.index = {}
        self._load_indices()
        enc_ekey = bytes.fromhex(self.cfg["encoding"].split()[1])
        self.enc = self._parse_encoding(self.read_ekey(enc_ekey))
        root_ckey = bytes.fromhex(self.cfg["root"].split()[0])
        self.root = self._parse_root(self.read_ckey(root_ckey))

    def _config(self, key):
        p = os.path.join(self.dir, "config", key[0:2], key[2:4], key)
        out = {}
        for line in open(p, encoding="utf-8"):
            if " = " in line:
                k, v = line.strip().split(" = ", 1)
                out[k] = v
        return out

    def _load_indices(self):
        best = {}
        for p in glob.glob(os.path.join(self.dir, "data", "*.idx")):
            name = os.path.basename(p)
            bucket, ver = int(name[0:2], 16), int(name[2:10], 16)
            if bucket not in best or ver > best[bucket][0]:
                best[bucket] = (ver, p)
        for _, p in best.values():
            b = open(p, "rb").read()
            hsize = struct.unpack_from("<I", b, 0)[0]
            ksize = b[8 + 7]  # ekey len
            off = (8 + hsize + 15) & ~15
            esize = struct.unpack_from("<I", b, off)[0]
            off += 8
            for i in range(off, off + esize, 18):
                key = b[i:i + 9]
                hi = b[i + 9]
                lo = struct.unpack_from(">I", b, i + 10)[0]
                arch = (hi << 2) | (lo >> 30)
                offset = lo & 0x3FFFFFFF
                size = struct.unpack_from("<I", b, i + 14)[0]
                if key not in self.index:
                    self.index[key] = (arch, offset, size)

    def read_ekey(self, ekey):
        arch, offset, size = self.index[ekey[:9]]
        with open(os.path.join(self.dir, "data", "data.%03d" % arch), "rb") as f:
            f.seek(offset)
            raw = f.read(size)
        return blte(raw[0x1E:])

    def read_ckey(self, ckey):
        for ek in self.enc[ckey]:
            if ek[:9] in self.index:
                return self.read_ekey(ek)
        raise KeyError("no local ekey for " + ckey.hex())

    def read_fdid(self, fdid):
        return self.read_ckey(self.root[fdid])

    def has(self, fdid):
        ck = self.root.get(fdid)
        return ck is not None and ck in self.enc and any(e[:9] in self.index for e in self.enc[ck])

    def _parse_encoding(self, b):
        assert b[0:2] == b"EN"
        ck, ek = b[3], b[4]
        cpage = struct.unpack_from(">H", b, 5)[0] * 1024
        ccount = struct.unpack_from(">I", b, 9)[0]
        espec = struct.unpack_from(">I", b, 18)[0]
        off = 22 + espec + ccount * (ck + 16)
        enc = {}
        for _ in range(ccount):
            p, end = off, off + cpage
            while p < end:
                n = b[p]
                if n == 0:
                    break
                ckey = b[p + 6:p + 6 + ck]
                keys = [b[p + 6 + ck + j * ek:p + 6 + ck + (j + 1) * ek] for j in range(n)]
                enc[ckey] = keys
                p += 6 + ck + n * ek
            off = end
        return enc

    def _parse_root(self, b):
        root = {}
        off = 0
        magic = b[0:4]
        version = 0
        if magic == b"TSFM":
            hsize, version = struct.unpack_from("<II", b, 4)
            if hsize < 0x18 or version > 3:  # old header without size/version
                hsize, version = 12, 0
            off = hsize
        while off < len(b):
            n = struct.unpack_from("<I", b, off)[0]
            if version >= 2:
                loc, cf1, cf2, cf3 = struct.unpack_from("<IIIB", b, off + 4)
                content = cf1 | cf2 | (cf3 << 17)
                off += 17
            else:
                content, loc = struct.unpack_from("<II", b, off + 4)
                off += 12
            deltas = struct.unpack_from("<%di" % n, b, off)
            off += 4 * n
            fd = -1
            ids = []
            for d in deltas:
                fd += d + 1
                ids.append(fd)
            no_names = bool(content & 0x10000000) if magic == b"TSFM" else False
            if magic == b"TSFM":
                for i, fid in enumerate(ids):
                    ck = b[off + 16 * i:off + 16 * i + 16]
                    if (loc & 0x2) or loc == 0xFFFFFFFF or fid not in root:  # enUS preferred
                        root[fid] = ck
                off += 16 * n
                if not no_names:
                    off += 8 * n
            else:
                for i, fid in enumerate(ids):
                    ck = b[off + 24 * i:off + 24 * i + 16]
                    if (loc & 0x2) or fid not in root:
                        root[fid] = ck
                off += 24 * n
        return root


def blte(b):
    assert b[0:4] == b"BLTE", b[0:4]
    hsize = struct.unpack_from(">I", b, 4)[0]
    if hsize == 0:
        return _chunk(b[8:])
    count = int.from_bytes(b[9:12], "big")
    chunks = []
    p = 12
    for _ in range(count):
        cs, ds = struct.unpack_from(">II", b, p)
        chunks.append((cs, ds))
        p += 24
    out = bytearray()
    p = hsize
    for cs, ds in chunks:
        try:
            out += _chunk(b[p:p + cs])
        except PermissionError:
            out += bytes(ds)  # encrypted section (key not public): zero-filled
        p += cs
    return bytes(out)


def _chunk(c):
    m = c[0:1]
    if m == b"N":
        return c[1:]
    if m == b"Z":
        return zlib.decompress(c[1:])
    if m == b"E":
        raise PermissionError("encrypted chunk")
    raise ValueError("chunk mode %r" % m)

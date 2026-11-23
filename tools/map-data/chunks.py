import struct
def chunks(b):
    o = 0
    while o + 8 <= len(b):
        tag = b[o:o+4][::-1].decode("latin1"); n = struct.unpack_from("<I", b, o+4)[0]
        yield tag, b[o+8:o+8+n]
        o += 8 + n

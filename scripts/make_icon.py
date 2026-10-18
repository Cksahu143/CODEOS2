#!/usr/bin/env python3
"""Draws CodeOS's app icon with only the Python standard library, then builds Resources/AppIcon.icns.
Run from the CodeOS folder: python3 scripts/make_icon.py   (iconutil needs macOS)."""
import math, os, struct, subprocess, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
# (point size, scale) pairs that an .iconset needs.
SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def write_png(path, size, pixels):
    stride = size * 4
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def distance_to_segment(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def render(size):
    pixels = bytearray(size * size * 4)
    radius = size * 0.22
    stroke = size * 0.085
    # The < and > marks, in fractions of the icon width and height.
    marks = [((0.42, 0.30), (0.20, 0.50)), ((0.20, 0.50), (0.42, 0.70)),
             ((0.58, 0.30), (0.80, 0.50)), ((0.80, 0.50), (0.58, 0.70))]
    segments = [((a[0] * size, a[1] * size), (b[0] * size, b[1] * size)) for a, b in marks]
    for y in range(size):
        for x in range(size):
            cx = min(max(x + 0.5, radius), size - radius)
            cy = min(max(y + 0.5, radius), size - radius)
            if math.hypot(x + 0.5 - cx, y + 0.5 - cy) > radius:
                continue  # outside the rounded corners stays transparent
            t = (x + y) / (2.0 * size)
            r, g, b = int(30 + 30 * t), int(35 + 45 * t), int(48 + 72 * t)
            for (ax, ay), (bx, by) in segments:
                if distance_to_segment(x + 0.5, y + 0.5, ax, ay, bx, by) <= stroke / 2:
                    r, g, b = 120, 220, 255
                    break
            i = (y * size + x) * 4
            pixels[i:i + 4] = bytes((r, g, b, 255))
    return pixels


def main():
    iconset = os.path.join(ROOT, "build", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    cache = {}
    for base, scale in SIZES:
        pixel_size = base * scale
        if pixel_size not in cache:
            cache[pixel_size] = render(pixel_size)
        name = "icon_%dx%d%s.png" % (base, base, "@2x" if scale == 2 else "")
        write_png(os.path.join(iconset, name), pixel_size, cache[pixel_size])
    os.makedirs(os.path.join(ROOT, "Resources"), exist_ok=True)
    icns = os.path.join(ROOT, "Resources", "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print("Wrote", icns)


if __name__ == "__main__":
    main()

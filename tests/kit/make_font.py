"""OnAir's fonts, written as TrueType files without any font library.

OnAir Mono: the pixel font for timecodes and camera-screen text. Each glyph is a 5x7 grid of
square pixels (descenders and accents add rows below and above); one pixel is 100 units, an em is
1000, every glyph is 600 wide. Latin letters (with the Western European accents), digits,
punctuation and the marks a readout needs: dots, triangles, a battery's bars.

OnAir Blank: a font with no ink (see build_blank).

python tests/kit/make_font.py   (writes Media/OnAirMono.ttf and Media/OnAirBlank.ttf)
"""
import os
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "Media", "OnAirMono.ttf")
BLANK_OUT = os.path.join(ROOT, "Media", "OnAirBlank.ttf")

# Rows from the top of a capital (7 rows); "|" then up to 2 rows below the baseline.
G = {
    " ": "..... ..... ..... ..... ..... ..... .....",
    "0": ".###. #...# #..## #.#.# ##..# #...# .###.",
    "1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
    "2": ".###. #...# ....# ...#. ..#.. .#... #####",
    "3": "##### ...#. ..#.. ...#. ....# #...# .###.",
    "4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
    "5": "##### #.... ####. ....# ....# #...# .###.",
    "6": "..##. .#... #.... ####. #...# #...# .###.",
    "7": "##### ....# ...#. ..#.. .#... .#... .#...",
    "8": ".###. #...# #...# .###. #...# #...# .###.",
    "9": ".###. #...# #...# .#### ....# ...#. .##..",
    "A": ".###. #...# #...# ##### #...# #...# #...#",
    "B": "####. #...# #...# ####. #...# #...# ####.",
    "C": ".###. #...# #.... #.... #.... #...# .###.",
    "D": "###.. #..#. #...# #...# #...# #..#. ###..",
    "E": "##### #.... #.... ####. #.... #.... #####",
    "F": "##### #.... #.... ####. #.... #.... #....",
    "G": ".###. #...# #.... #.### #...# #...# .####",
    "H": "#...# #...# #...# ##### #...# #...# #...#",
    "I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
    "J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
    "K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
    "L": "#.... #.... #.... #.... #.... #.... #####",
    "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
    "N": "#...# #...# ##..# #.#.# #..## #...# #...#",
    "O": ".###. #...# #...# #...# #...# #...# .###.",
    "P": "####. #...# #...# ####. #.... #.... #....",
    "Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
    "R": "####. #...# #...# ####. #.#.. #..#. #...#",
    "S": ".#### #.... #.... .###. ....# ....# ####.",
    "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    "U": "#...# #...# #...# #...# #...# #...# .###.",
    "V": "#...# #...# #...# #...# #...# .#.#. ..#..",
    "W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
    "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
    "Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
    "Z": "##### ....# ...#. ..#.. .#... #.... #####",
    "a": "..... ..... .###. ....# .#### #...# .####",
    "b": "#.... #.... #.##. ##..# #...# #...# ####.",
    "c": "..... ..... .###. #.... #.... #...# .###.",
    "d": "....# ....# .##.# #..## #...# #...# .####",
    "e": "..... ..... .###. #...# ##### #.... .###.",
    "f": "..##. .#..# .#... ###.. .#... .#... .#...",
    "g": "..... ..... .#### #...# #...# #...# .#### | ....# .###.",
    "h": "#.... #.... #.##. ##..# #...# #...# #...#",
    "i": "..#.. ..... .##.. ..#.. ..#.. ..#.. .###.",
    "j": "...#. ..... ..##. ...#. ...#. ...#. ...#. | #..#. .##..",
    "k": "#.... #.... #..#. #.#.. ##... #.#.. #..#.",
    "l": ".##.. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
    "m": "..... ..... ##.#. #.#.# #.#.# #.#.# #.#.#",
    "n": "..... ..... #.##. ##..# #...# #...# #...#",
    "o": "..... ..... .###. #...# #...# #...# .###.",
    "p": "..... ..... ####. #...# #...# #...# ####. | #.... #....",
    "q": "..... ..... .#### #...# #...# #...# .#### | ....# ....#",
    "r": "..... ..... #.##. ##..# #.... #.... #....",
    "s": "..... ..... .#### #.... .###. ....# ####.",
    "t": ".#... .#... ###.. .#... .#... .#..# ..##.",
    "u": "..... ..... #...# #...# #...# #..## .##.#",
    "v": "..... ..... #...# #...# #...# .#.#. ..#..",
    "w": "..... ..... #...# #...# #.#.# #.#.# .#.#.",
    "x": "..... ..... #...# .#.#. ..#.. .#.#. #...#",
    "y": "..... ..... #...# #...# #...# #...# .#### | ....# .###.",
    "z": "..... ..... ##### ...#. ..#.. .#... #####",
    "!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
    '"': ".#.#. .#.#. ..... ..... ..... ..... .....",
    "#": ".#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.",
    "$": "..#.. .#### #.#.. .###. ..#.# ####. ..#..",
    "%": "##... ##..# ...#. ..#.. .#... #..## ...##",
    "&": ".##.. #..#. #.#.. .#... #.#.# #..#. .##.#",
    "'": "..#.. ..#.. ..... ..... ..... ..... .....",
    "(": "...#. ..#.. .#... .#... .#... ..#.. ...#.",
    ")": ".#... ..#.. ...#. ...#. ...#. ..#.. .#...",
    "*": "..... ..#.. #.#.# .###. #.#.# ..#.. .....",
    "+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
    ",": "..... ..... ..... ..... ..... ..##. ..##. | ...#. ..#..",
    "-": "..... ..... ..... .###. ..... ..... .....",
    ".": "..... ..... ..... ..... ..... .##.. .##..",
    "/": "..... ....# ...#. ..#.. .#... #.... .....",
    ":": "..... .##.. .##.. ..... .##.. .##.. .....",
    ";": "..... .##.. .##.. ..... .##.. .##.. ..#.. | .#...",
    "<": "...#. ..#.. .#... #.... .#... ..#.. ...#.",
    "=": "..... ..... ##### ..... ##### ..... .....",
    ">": ".#... ..#.. ...#. ....# ...#. ..#.. .#...",
    "?": ".###. #...# ....# ...#. ..#.. ..... ..#..",
    "@": ".###. #...# ....# .##.# #.#.# #.#.# .###.",
    "[": ".###. .#... .#... .#... .#... .#... .###.",
    "\\": "..... #.... .#... ..#.. ...#. ....# .....",
    "]": ".###. ...#. ...#. ...#. ...#. ...#. .###.",
    "^": "..#.. .#.#. #...# ..... ..... ..... .....",
    "_": "..... ..... ..... ..... ..... ..... #####",
    "`": ".#... ..#.. ..... ..... ..... ..... .....",
    "{": "...#. ..#.. ..#.. .#... ..#.. ..#.. ...#.",
    "|": "..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    "}": ".#... ..#.. ..#.. ...#. ..#.. ..#.. .#...",
    "~": "..... ..... .#... #.#.# ...#. ..... .....",
    "·": "..... ..... ..... ..#.. ..... ..... .....",
    "•": "..... ..... .###. .###. .###. ..... .....",
    "●": "..... .###. ##### ##### ##### .###. .....",
    "▸": "..... .#... .##.. .###. .##.. .#... .....",
    "◂": "..... ...#. ..##. .###. ..##. ...#. .....",
    "▲": "..... ..... ..#.. .###. ##### ..... .....",
    "▼": "..... ..... ##### .###. ..#.. ..... .....",
    "▮": ".###. .###. .###. .###. .###. .###. .###.",
    "▯": ".###. .#.#. .#.#. .#.#. .#.#. .#.#. .###.",
    "■": "..... ##### ##### ##### ##### ##### .....",
    "□": "..... ##### #...# #...# #...# ##### .....",
    "…": "..... ..... ..... ..... ..... ..... #.#.#",
    "–": "..... ..... ..... ##### ..... ..... .....",
    "—": "..... ..... ..... ##### ..... ..... .....",
    "°": ".##.. #..#. .##.. ..... ..... ..... .....",
    "×": "..... #...# .#.#. ..#.. .#.#. #...# .....",
    "«": "..... ..#.# .#.#. #.#.. .#.#. ..#.# .....",
    "»": "..... #.#.. .#.#. ..#.# .#.#. #.#.. .....",
    "Æ": ".#### #.#.. #.#.. #.### ###.. #.#.. #.###",
    "æ": "..... ..... ##.#. ..#.# ##### #.#.. .####",
    "Ø": ".###. #..## #.#.# #.#.# #.#.# ##..# .###.",
    "ø": "..... ..... .###. #..## #.#.# ##..# .###.",
    "ß": ".##.. #..#. #..#. #.#.. #..#. #...# #.##.",
    "Ð": "###.. #..#. #...# ###.# #...# #..#. ###..",
    "ı": "..... ..... .##.. ..#.. ..#.. ..#.. .###.",
}

# Accents: rows above a capital, or over a small letter's x-height (rows 0-1).
ACCENTS = {
    "grave": [".#...", "..#.."],
    "acute": ["...#.", "..#.."],
    "circ": ["..#..", ".#.#."],
    "tilde": [".#.#.", "#.#.."],
    "uml": [".#.#.", "....."],
    "ring": [".##..", ".##.."],
}
COMPOSED = {}
for base, marks in (("A", "ÀÁÂÃÄÅ"), ("a", "àáâãäå")):
    for ch, accent in zip(marks, ("grave", "acute", "circ", "tilde", "uml", "ring")):
        COMPOSED[ch] = (base, accent)
for base, marks in (("E", "ÈÉÊË"), ("e", "èéêë"),
                    ("I", "ÌÍÎÏ"), ("ı", "ìíîï"),
                    ("U", "ÙÚÛÜ"), ("u", "ùúûü")):
    for ch, accent in zip(marks, ("grave", "acute", "circ", "uml")):
        COMPOSED[ch] = (base, accent)
for base, marks in (("O", "ÒÓÔÕÖ"), ("o", "òóôõö")):
    for ch, accent in zip(marks, ("grave", "acute", "circ", "tilde", "uml")):
        COMPOSED[ch] = (base, accent)
COMPOSED.update({"Ñ": ("N", "tilde"), "ñ": ("n", "tilde"), "Ý": ("Y", "acute"),
                 "ý": ("y", "acute"), "ÿ": ("y", "uml")})
CEDILLA = {"Ç": "C", "ç": "c"}


def rows_of(spec):
    """{row index: pattern}; row 0 is the top of a capital, 7-8 below the baseline."""
    main, _, below = spec.partition("|")
    rows = {}
    for i, pattern in enumerate(main.split()):
        rows[i] = pattern
    for i, pattern in enumerate(below.split()):
        rows[7 + i] = pattern
    return rows


def glyph_rows(ch):
    if ch in G:
        return rows_of(G[ch])
    if ch in COMPOSED:
        base, accent = COMPOSED[ch]
        rows = rows_of(G[base])
        top = -2 if base.isupper() else 0
        for i, pattern in enumerate(ACCENTS[accent]):
            rows[top + i] = pattern
        return rows
    if ch in CEDILLA:
        rows = rows_of(G[CEDILLA[ch]])
        rows[7], rows[8] = "..#..", ".#..."
        return rows
    raise KeyError(ch)


PIXEL = 100
ADVANCE = 600
LEFT = 50


def contours(rows):
    """The outline of all the glyph's pixels together: outer contours clockwise (as TrueType wants),
    holes the other way, straight runs as one line. One piece per glyph, not a rectangle per row:
    rows stacked as separate shapes leave seams that FreeType draws as a faint line through the
    letters at sizes like 11 and 12."""
    edges = set()
    for r, pattern in rows.items():
        for c, ch in enumerate(pattern):
            if ch != "#":
                continue
            x0, y0 = LEFT + c * PIXEL, 600 - PIXEL * r
            x1, y1 = x0 + PIXEL, y0 + PIXEL
            for a, b in (((x0, y0), (x0, y1)), ((x0, y1), (x1, y1)), ((x1, y1), (x1, y0)), ((x1, y0), (x0, y0))):
                if (b, a) in edges:
                    edges.discard((b, a))  # shared by two pixels: inside the shape
                else:
                    edges.add((a, b))
    nexts = {}
    for a, b in sorted(edges):
        nexts.setdefault(a, []).append(b)
    out = []
    while nexts:
        start = min(nexts)
        path, point, came = [start], start, None
        while True:
            options = nexts[point]
            if came is None or len(options) == 1:
                nxt = options[0]
            else:
                # Two pieces touch at a corner: take the sharpest right turn, so each stays simple.
                dx, dy = point[0] - came[0], point[1] - came[1]
                nxt = min(options, key=lambda o: dx * (o[1] - point[1]) - dy * (o[0] - point[0]))
            options.remove(nxt)
            if not options:
                del nexts[point]
            came, point = point, nxt
            if point == start:
                break
            path.append(point)
        n = len(path)
        out.append([p for i, p in enumerate(path)
                    if not (path[i - 1][0] == p[0] == path[(i + 1) % n][0]
                            or path[i - 1][1] == p[1] == path[(i + 1) % n][1])])
    return out


def glyf_data(shapes):
    if not shapes:
        return b"", (0, 0, 0, 0), 0, 0
    xs = [p[0] for s in shapes for p in s]
    ys = [p[1] for s in shapes for p in s]
    box = (min(xs), min(ys), max(xs), max(ys))
    data = struct.pack(">hhhhh", len(shapes), *box)
    end = -1
    for s in shapes:
        end += len(s)
        data += struct.pack(">H", end)
    data += struct.pack(">H", 0)  # no instructions
    points = [p for s in shapes for p in s]
    data += bytes([1] * len(points))  # on-curve, 16-bit deltas
    last = 0
    for x, _ in points:
        data += struct.pack(">h", x - last)
        last = x
    last = 0
    for _, y in points:
        data += struct.pack(">h", y - last)
        last = y
    while len(data) % 4:
        data += b"\0"
    return data, box, len(points), len(shapes)


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def name_table(family):
    """The font's names (Windows, English): family, style, unique name, full name, version, PostScript."""
    names = {1: family, 2: "Regular", 3: family + " Regular 1.0", 4: family,
             5: "Version 1.0", 6: family.replace(" ", "") + "-Regular"}
    records, strings = b"", b""
    for name_id, text in names.items():
        raw = text.encode("utf-16-be")
        records += struct.pack(">HHHHHH", 3, 1, 0x409, name_id, len(raw), len(strings))
        strings += raw
    return struct.pack(">HHH", 0, len(names), 6 + len(records)) + records + strings


def assemble(tables):
    """The file: the table directory, each table 4-byte aligned, the whole file's checksum in head."""
    tags = sorted(tables)
    count = len(tags)
    search = 2 ** (count.bit_length() - 1)
    font = struct.pack(">IHHHH", 0x00010000, count, search * 16, search.bit_length() - 1, count * 16 - search * 16)
    offset = 12 + 16 * count
    directory, body = b"", b""
    for tag in tags:
        data = tables[tag]
        directory += struct.pack(">4sIII", tag.encode("ascii"), checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    font += directory + body
    adjust = (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF
    head_at = offset + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index("head")])
    return font[:head_at + 8] + struct.pack(">I", adjust) + font[head_at + 12:]


def build():
    chars = sorted(set(G) | set(COMPOSED) | set(CEDILLA), key=ord)
    chars = [c for c in chars if c != "ı" or True]
    notdef = [[(LEFT, 0), (LEFT, 700), (LEFT + 500, 700), (LEFT + 500, 0)],
              [(LEFT + 100, 100), (LEFT + 400, 100), (LEFT + 400, 600), (LEFT + 100, 600)]]
    glyphs = [glyf_data(notdef)] + [glyf_data(contours(glyph_rows(c))) for c in chars]
    n = len(glyphs)

    glyf, loca = b"", [0]
    for data, _, _, _ in glyphs:
        glyf += data
        loca.append(len(glyf))
    loca_data = struct.pack(">%dI" % len(loca), *loca)

    boxes = [g[1] for g in glyphs if g[0]]
    xmin = min(b[0] for b in boxes)
    ymin = min(b[1] for b in boxes)
    xmax = max(b[2] for b in boxes)
    ymax = max(b[3] for b in boxes)
    max_points = max(g[2] for g in glyphs)
    max_contours = max(g[3] for g in glyphs)

    head = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, 1000,
                       0, 0, xmin, ymin, xmax, ymax, 0, 8, 2, 1, 0)
    hhea = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, 900, -200, 0, ADVANCE, 0, 0, xmax, 1, 0, 0,
                       0, 0, 0, 0, 0, n)
    maxp = struct.pack(">I" + "H" * 14, 0x00010000, n, max_points, max_contours, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    hmtx = b"".join(struct.pack(">Hh", ADVANCE, g[1][0] if g[0] else 0) for g in glyphs)

    codes = [ord(c) for c in chars]
    first, last = min(codes), max(codes)
    os2 = struct.pack(">HhHHH" + "h" * 11 + "10s" + "IIII" + "4s" + "HHH" + "hhh" + "HH" + "II" + "hh" + "HHH",
                      4, ADVANCE, 400, 5, 0,
                      600, 700, 0, 140, 600, 700, 0, 480, 100, 300, 0,
                      bytes([2, 11, 6, 9, 0, 0, 0, 0, 0, 0]),
                      (1 << 0) | (1 << 1) | (1 << 31), 1 << (45 - 32), 0, 0,
                      b"ONAR", 0x40, first, min(last, 0xFFFF),
                      900, -200, 0, 900, 200, 1, 0, 500, 700, 0, 32, 1)

    # cmap: one segment per run of consecutive codes (glyph ids run alongside, 1 + index).
    segs = []
    for i, code in enumerate(codes):
        gid = i + 1
        if segs and code == segs[-1][1] + 1 and gid - code == segs[-1][2]:
            segs[-1][1] = code
        else:
            segs.append([code, code, gid - code])
    segs.append([0xFFFF, 0xFFFF, 1])
    seg_count = len(segs)
    search = 2 ** (seg_count.bit_length() - 1)
    entry = search.bit_length() - 1
    sub = struct.pack(">HHHHHHH", 4, 0, 0, seg_count * 2, search * 2, entry, seg_count * 2 - search * 2)
    sub += struct.pack(">%dH" % seg_count, *[s[1] for s in segs]) + struct.pack(">H", 0)
    sub += struct.pack(">%dH" % seg_count, *[s[0] for s in segs])
    sub += struct.pack(">%dH" % seg_count, *[s[2] % 65536 for s in segs])
    sub += struct.pack(">%dH" % seg_count, *[0] * seg_count)
    sub = sub[:2] + struct.pack(">H", len(sub)) + sub[4:]
    cmap = struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub

    post = struct.pack(">IihhIIIII", 0x00030000, 0, -100, 100, 1, 0, 0, 0, 0)

    tables = {"OS/2": os2, "cmap": cmap, "glyf": glyf, "head": head, "hhea": hhea, "hmtx": hmtx,
              "loca": loca_data, "maxp": maxp, "name": name_table("OnAir Mono"), "post": post}
    return assemble(tables), len(chars)


BLANK_ADVANCE = 250  # a space's width
BLANK_FIRST, BLANK_LAST = 0x20, 0xFFFD
BLANK_SPAN = 512


def build_blank():
    """OnAir Blank: a font with no ink. Every character from a space to U+FFFD (Latin, Cyrillic,
    Korean, Chinese, every alphabet a name can use) is one empty glyph a space wide, so text set in
    it keeps its room and draws nothing. The missing-glyph one is empty too (and has no width:
    that tells a test the map reached a character). The game draws names above heads with it when
    the blank name font is on."""
    n = 2  # .notdef and the blank
    # No outlines anywhere. A glyf table with nothing in it at all confuses some readers: one byte.
    glyf = b"\0"
    loca = struct.pack(">3I", 0, 0, 0)
    # The usual box and line metrics (as OnAir Mono's), so the game lays the text out as it would any.
    head = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, 1000,
                       0, 0, 0, -200, BLANK_ADVANCE, 900, 0, 8, 2, 1, 0)
    hhea = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, 900, -200, 0, BLANK_ADVANCE, 0, 0, 0, 1, 0, 0,
                       0, 0, 0, 0, 0, n)
    maxp = struct.pack(">I" + "H" * 14, 0x00010000, n, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    hmtx = struct.pack(">HhHh", 0, 0, BLANK_ADVANCE, 0)
    # Unicode ranges and code pages: Latin, Cyrillic, Hangul, CJK.
    os2 = struct.pack(">HhHHH" + "h" * 11 + "10s" + "IIII" + "4s" + "HHH" + "hhh" + "HH" + "II" + "hh" + "HHH",
                      4, BLANK_ADVANCE, 400, 5, 0,
                      600, 700, 0, 140, 600, 700, 0, 480, 100, 300, 0,
                      bytes(10),
                      (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 9), (1 << (56 - 32)) | (1 << (59 - 32)), 0, 0,
                      b"ONAR", 0x40, BLANK_FIRST, BLANK_LAST,
                      900, -200, 0, 900, 200, (1 << 0) | (1 << 2) | (1 << 18) | (1 << 19) | (1 << 20), 0,
                      500, 700, 0, 32, 0)

    # cmap, format 4, which has to give each code its glyph: the codes go in segments of BLANK_SPAN,
    # and every segment reads the same run of BLANK_SPAN blanks (its idRangeOffset counts the bytes
    # from itself to the start of the one glyph id array). Then the closing 0xFFFF segment.
    segs = [(s, min(s + BLANK_SPAN - 1, BLANK_LAST)) for s in range(BLANK_FIRST, BLANK_LAST + 1, BLANK_SPAN)]
    seg_count = len(segs) + 1
    search = 2 ** (seg_count.bit_length() - 1)
    sub = struct.pack(">HHHHHHH", 4, 0, 0, seg_count * 2, search * 2, search.bit_length() - 1,
                      seg_count * 2 - search * 2)
    sub += struct.pack(">%dH" % seg_count, *[e for _, e in segs], 0xFFFF) + struct.pack(">H", 0)
    sub += struct.pack(">%dH" % seg_count, *[s for s, _ in segs], 0xFFFF)
    sub += struct.pack(">%dH" % seg_count, *[0] * len(segs), 1)
    sub += struct.pack(">%dH" % seg_count, *[2 * (seg_count - i) for i in range(len(segs))], 0)
    sub += struct.pack(">%dH" % BLANK_SPAN, *[1] * BLANK_SPAN)
    sub = sub[:2] + struct.pack(">H", len(sub)) + sub[4:]
    cmap = struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub

    post = struct.pack(">IihhIIIII", 0x00030000, 0, -100, 50, 0, 0, 0, 0, 0)

    tables = {"OS/2": os2, "cmap": cmap, "glyf": glyf, "head": head, "hhea": hhea, "hmtx": hmtx,
              "loca": loca, "maxp": maxp, "name": name_table("OnAir Blank"), "post": post}
    return assemble(tables)


if __name__ == "__main__":
    data, count = build()
    with open(OUT, "wb") as f:
        f.write(data)
    print(f"wrote {OUT}: {count} characters, {len(data)} bytes")
    blank = build_blank()
    with open(BLANK_OUT, "wb") as f:
        f.write(blank)
    print(f"wrote {BLANK_OUT}: {BLANK_LAST - BLANK_FIRST + 1} characters, {len(blank)} bytes")

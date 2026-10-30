"""Draws the addon's textures into Media/: the logo, the minimap icon, the UI shapes and the
glyph icons. Everything is drawn white (except the logos) at 4x and scaled down, so the game can
tint it with SetVertexColor and the edges stay smooth.

python tests/kit/make_media.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MEDIA = os.path.join(ROOT, "Media")
ICONS = os.path.join(MEDIA, "Icons")
S = 4  # supersampling
RED = (255, 59, 48, 255)
INK = (18, 19, 22, 255)
WHITE = (255, 255, 255, 255)


def canvas(size):
    return Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))


def save(img, path, size):
    img = img.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def broadcast(d, cx, cy, unit, color, dot=True):
    """The OnAir mark: a dot with two waves on each side."""
    w = int(unit * 0.11)
    if dot:
        r = unit * 0.13
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    for radius in (unit * 0.30, unit * 0.47):
        box = (cx - radius, cy - radius, cx + radius, cy + radius)
        d.arc(box, -38, 38, fill=color, width=w)
        d.arc(box, 142, 218, fill=color, width=w)


def logo():
    size = 128
    img = canvas(size)
    d = ImageDraw.Draw(img)
    u = size * S
    d.rounded_rectangle((0, 0, u - 1, u - 1), radius=u * 0.22, fill=INK)
    # soft red glow behind the dot
    glow = canvas(size)
    gd = ImageDraw.Draw(glow)
    r = u * 0.24
    gd.ellipse((u / 2 - r, u / 2 - r, u / 2 + r, u / 2 + r), fill=(255, 59, 48, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(u * 0.07))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    broadcast(d, u / 2, u / 2, u * 0.95, RED)
    save(img, os.path.join(MEDIA, "Logo.tga"), size)


def minimap_icon():
    size = 64
    img = canvas(size)
    d = ImageDraw.Draw(img)
    u = size * S
    d.ellipse((0, 0, u - 1, u - 1), fill=INK)
    broadcast(d, u / 2, u / 2, u * 0.9, WHITE)
    save(img, os.path.join(MEDIA, "MinimapIcon.tga"), size)
    # the dot alone, white, so it can glow red while live
    img = canvas(size)
    d = ImageDraw.Draw(img)
    r = u * 0.9 * 0.13
    d.ellipse((u / 2 - r, u / 2 - r, u / 2 + r, u / 2 + r), fill=WHITE)
    save(img, os.path.join(MEDIA, "MinimapDot.tga"), size)
    # the waves alone
    img = canvas(size)
    d = ImageDraw.Draw(img)
    broadcast(d, u / 2, u / 2, u * 0.9, WHITE, dot=False)
    save(img, os.path.join(MEDIA, "MinimapWaves.tga"), size)


def shapes():
    size = 64
    u = size * S
    img = canvas(size)
    ImageDraw.Draw(img).ellipse((0, 0, u - 1, u - 1), fill=WHITE)
    save(img, os.path.join(MEDIA, "Dot.tga"), size)

    img = canvas(size)
    ImageDraw.Draw(img).ellipse((S * 2, S * 2, u - 1 - S * 2, u - 1 - S * 2), outline=WHITE, width=S * 4)
    save(img, os.path.join(MEDIA, "Ring.tga"), size)

    size = 128
    u = size * S
    img = canvas(size)
    d = ImageDraw.Draw(img)
    r = u * 0.28
    d.ellipse((u / 2 - r, u / 2 - r, u / 2 + r, u / 2 + r), fill=WHITE)
    img = img.filter(ImageFilter.GaussianBlur(u * 0.09))
    save(img, os.path.join(MEDIA, "Glow.tga"), size)

    # Tiles (the game repeats them): the slate's diagonal clapper stripes, film sprocket holes.
    img = Image.new("RGBA", (32 * S, 32 * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for k in range(-2, 3):
        o = k * 32 * S
        d.polygon([(o, 0), (o + 16 * S, 0), (o + 16 * S + 32 * S, 32 * S), (o + 32 * S, 32 * S)], fill=WHITE)
    save(img, os.path.join(MEDIA, "Stripes.tga"), 32)
    img = Image.new("RGBA", (16 * S, 8 * S), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((4 * S, 2 * S, 12 * S, 6 * S), radius=S, fill=WHITE)
    img = img.resize((16, 8), Image.LANCZOS)
    img.save(os.path.join(MEDIA, "Sprocket.tga"))
    # A dotted line (a camera menu's leaders and rules): one pixel on, three off.
    img = Image.new("RGBA", (4, 2), (0, 0, 0, 0))
    img.putpixel((0, 0), WHITE)
    img.putpixel((0, 1), WHITE)
    img.save(os.path.join(MEDIA, "Dots.tga"))


# ---------------------------------------------------------------------------- glyph icons
# Drawn on a 256 grid (x4 supersampled to 1024), stroke ~20.

G = 256
SW = 20


def icon(name, draw_fn):
    img = canvas(64)
    d = ImageDraw.Draw(img)
    k = 64 * S / G

    def P(*xy):
        return [v * k for v in xy]

    draw_fn(d, P, int(SW * k))
    save(img, os.path.join(ICONS, name + ".tga"), 64)


def i_live(d, P, w):
    cx, cy = 128, 128
    d.ellipse(P(cx - 26, cy - 26, cx + 26, cy + 26), fill=WHITE)
    for r in (64, 104):
        d.arc(P(cx - r, cy - r, cx + r, cy + r), -40, 40, fill=WHITE, width=w)
        d.arc(P(cx - r, cy - r, cx + r, cy + r), 140, 220, fill=WHITE, width=w)


def i_names(d, P, w):  # an ID badge
    d.rounded_rectangle(P(28, 60, 228, 196), radius=22 * P(1)[0], outline=WHITE, width=w)
    d.ellipse(P(66, 92, 112, 138), fill=WHITE)
    d.pieslice(P(52, 140, 126, 214), 180, 360, fill=WHITE)
    d.rounded_rectangle(P(140, 100, 200, 116), radius=8 * P(1)[0], fill=WHITE)
    d.rounded_rectangle(P(140, 136, 186, 152), radius=8 * P(1)[0], fill=WHITE)


def i_hide(d, P, w):  # eye with a slash
    r = 130
    d.arc(P(128 - r, 214 - r, 128 + r, 214 + r), 222, 318, fill=WHITE, width=w)  # upper lid
    d.arc(P(128 - r, 42 - r, 128 + r, 42 + r), 42, 138, fill=WHITE, width=w)  # lower lid
    d.ellipse(P(100, 100, 156, 156), fill=WHITE)
    d.line(P(52, 212, 204, 44), fill=WHITE, width=w)


def i_custom(d, P, w):  # pencil
    c, s = math.cos(math.radians(45)), math.sin(math.radians(45))

    def rot(x, y):
        return (128 + (x * c - y * s), 128 + (x * s + y * c))

    body = [rot(-90, -18), rot(60, -18), rot(60, 18), rot(-90, 18)]
    tip = [rot(60, -18), rot(100, 0), rot(60, 18)]
    d.polygon([v for p in body for v in P(*p)], fill=WHITE)
    d.polygon([v for p in tip for v in P(*p)], fill=WHITE)
    cap = [rot(-110, -18), rot(-96, -18), rot(-96, 18), rot(-110, 18)]
    d.polygon([v for p in cap for v in P(*p)], fill=WHITE)


def i_about(d, P, w):
    d.ellipse(P(28, 28, 228, 228), outline=WHITE, width=w)
    d.ellipse(P(114, 70, 142, 98), fill=WHITE)
    d.rounded_rectangle(P(116, 114, 140, 188), radius=10 * P(1)[0], fill=WHITE)


def i_chat(d, P, w):
    d.rounded_rectangle(P(28, 44, 228, 176), radius=34 * P(1)[0], outline=WHITE, width=w)
    d.polygon(P(70, 166, 70, 222, 126, 166), fill=WHITE)
    for x in (88, 128, 168):
        d.ellipse(P(x - 13, 97, x + 13, 123), fill=WHITE)


def i_nameplate(d, P, w):
    d.rounded_rectangle(P(56, 54, 200, 82), radius=12 * P(1)[0], fill=WHITE)
    d.rounded_rectangle(P(24, 120, 232, 184), radius=16 * P(1)[0], outline=WHITE, width=w)
    d.rounded_rectangle(P(44, 140, 150, 164), radius=8 * P(1)[0], fill=WHITE)


def i_unitframe(d, P, w):
    d.ellipse(P(20, 72, 112, 164), outline=WHITE, width=w)
    d.rounded_rectangle(P(128, 82, 236, 112), radius=10 * P(1)[0], fill=WHITE)
    d.rounded_rectangle(P(128, 128, 210, 150), radius=10 * P(1)[0], fill=WHITE)


def i_group(d, P, w):
    for row in range(2):
        for col in range(3):
            x, y = 28 + col * 70, 66 + row * 70
            d.rounded_rectangle(P(x, y, x + 56, y + 56), radius=12 * P(1)[0], outline=WHITE, width=int(w * 0.8))


def i_tooltip(d, P, w):
    d.rounded_rectangle(P(28, 56, 228, 212), radius=22 * P(1)[0], outline=WHITE, width=w)
    d.polygon(P(56, 60, 56, 20, 100, 60), fill=WHITE)
    for y, x2 in ((98, 188), (134, 160), (170, 176)):
        d.rounded_rectangle(P(62, y - 8, x2, y + 8), radius=8 * P(1)[0], fill=WHITE)


def i_meter(d, P, w):
    for i, x2 in enumerate((228, 190, 150, 104)):
        y = 44 + i * 46
        d.rounded_rectangle(P(28, y, x2, y + 30), radius=10 * P(1)[0], fill=WHITE)


def i_social(d, P, w):
    d.ellipse(P(60, 56, 120, 116), fill=WHITE)
    d.pieslice(P(30, 128, 150, 248), 180, 360, fill=WHITE)
    d.ellipse(P(146, 74, 196, 124), outline=WHITE, width=int(w * 0.8))
    d.arc(P(122, 138, 222, 238), 180, 360, fill=WHITE, width=int(w * 0.8))


def i_lfg(d, P, w):
    d.ellipse(P(32, 32, 166, 166), outline=WHITE, width=w)
    d.line(P(150, 150, 222, 222), fill=WHITE, width=int(w * 1.5))


def i_pet(d, P, w):
    d.ellipse(P(78, 126, 178, 214), fill=WHITE)
    for x, y in ((50, 100), (92, 60), (146, 60), (190, 100)):
        d.ellipse(P(x - 22, y - 26, x + 22, y + 26), fill=WHITE)


def i_bnet(d, P, w):
    d.ellipse(P(28, 28, 228, 228), outline=WHITE, width=w)
    d.ellipse(P(86, 28, 170, 228), outline=WHITE, width=int(w * 0.8))
    d.line(P(36, 128, 220, 128), fill=WHITE, width=int(w * 0.8))


def i_guild(d, P, w):
    d.polygon(P(56, 28, 200, 28, 200, 228, 128, 182, 56, 228), outline=WHITE, width=w)
    d.ellipse(P(108, 82, 148, 122), fill=WHITE)


def i_overhead(d, P, w):
    d.rounded_rectangle(P(56, 22, 200, 50), radius=12 * P(1)[0], fill=WHITE)
    d.ellipse(P(96, 76, 160, 140), fill=WHITE)
    d.pieslice(P(56, 150, 200, 294), 180, 360, fill=WHITE)


def i_trash(d, P, w):
    d.rounded_rectangle(P(36, 56, 220, 76), radius=8 * P(1)[0], fill=WHITE)
    d.rounded_rectangle(P(100, 30, 156, 56), radius=8 * P(1)[0], outline=WHITE, width=int(w * 0.7))
    d.rounded_rectangle(P(60, 88, 196, 226), radius=16 * P(1)[0], outline=WHITE, width=w)
    for x in (104, 152):
        d.line(P(x, 118, x, 196), fill=WHITE, width=int(w * 0.7))


def i_dice(d, P, w):
    d.rounded_rectangle(P(32, 32, 224, 224), radius=36 * P(1)[0], outline=WHITE, width=w)
    for x, y in ((84, 84), (172, 84), (128, 128), (84, 172), (172, 172)):
        d.ellipse(P(x - 17, y - 17, x + 17, y + 17), fill=WHITE)


def i_shuffle(d, P, w):  # circular arrow
    d.arc(P(40, 40, 216, 216), 40, 320, fill=WHITE, width=w)
    a = math.radians(40)
    nx, ny = math.cos(a), math.sin(a)  # outward
    tx, ty = ny, -nx  # tangent, pointing back along the arc's start
    x, y = 128 + 88 * nx, 128 + 88 * ny
    tip = (x + tx * 34, y + ty * 34)
    b1 = (x - tx * 6 + nx * 30, y - ty * 6 + ny * 30)
    b2 = (x - tx * 6 - nx * 30, y - ty * 6 - ny * 30)
    d.polygon(P(*tip, *b1, *b2), fill=WHITE)


def i_close(d, P, w):
    d.line(P(64, 64, 192, 192), fill=WHITE, width=w)
    d.line(P(64, 192, 192, 64), fill=WHITE, width=w)


def i_plus(d, P, w):
    d.line(P(128, 52, 128, 204), fill=WHITE, width=w)
    d.line(P(52, 128, 204, 128), fill=WHITE, width=w)


def i_check(d, P, w):
    d.line(P(52, 134, 104, 186), fill=WHITE, width=w)
    d.line(P(98, 186, 208, 72), fill=WHITE, width=w)


def i_chevron(d, P, w):
    d.line(P(64, 100, 132, 168), fill=WHITE, width=w)
    d.line(P(124, 168, 192, 100), fill=WHITE, width=w)


def i_world(d, P, w):  # "everywhere else": a window
    d.rounded_rectangle(P(28, 40, 228, 216), radius=18 * P(1)[0], outline=WHITE, width=w)
    d.line(P(36, 88, 220, 88), fill=WHITE, width=w)
    for x in (60, 88, 116):
        d.ellipse(P(x - 9, 55, x + 9, 73), fill=WHITE)


def i_me(d, P, w):  # a star
    pts = []
    for i in range(10):
        r = 104 if i % 2 == 0 else 44
        a = math.radians(-90 + i * 36)
        pts += [128 + r * math.cos(a), 136 + r * math.sin(a)]
    d.polygon(P(*pts), fill=WHITE)


def i_camera(d, P, w):  # a film camera: body, lens, two reels
    d.rounded_rectangle(P(28, 104, 176, 208), radius=18 * P(1)[0], outline=WHITE, width=w)
    d.polygon(P(176, 136, 228, 108, 228, 204, 176, 176), fill=WHITE)
    d.ellipse(P(36, 32, 100, 96), outline=WHITE, width=int(w * 0.8))
    d.ellipse(P(108, 40, 164, 96), outline=WHITE, width=int(w * 0.8))


def i_orbit(d, P, w):  # a figure with a tilted ring around it, arrow on the front
    clear = (0, 0, 0, 0)
    cx, cy, rx, ry = 128, 166, 98, 40
    box = P(cx - rx, cy - ry, cx + rx, cy + ry)
    d.arc(box, 180, 360, fill=WHITE, width=w)            # the back of the ring
    d.ellipse(P(96, 26, 160, 90), fill=clear)              # a gap around the figure
    d.rounded_rectangle(P(80, 94, 176, 214), radius=40 * P(1)[0], fill=clear)
    d.ellipse(P(106, 36, 150, 80), fill=WHITE)             # head
    d.rounded_rectangle(P(92, 104, 164, 204), radius=30 * P(1)[0], fill=WHITE)
    d.arc(P(cx - rx - 14, cy - ry - 14, cx + rx + 14, cy + ry + 14), 8, 164, fill=clear, width=w * 2)
    d.arc(box, 10, 160, fill=WHITE, width=w)              # the front, over the figure
    t = math.radians(160)
    x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
    tx, ty = -rx * math.sin(t), ry * math.cos(t)
    n = math.hypot(tx, ty)
    tx, ty = tx / n, ty / n
    nx, ny = -ty, tx
    tip = (x + tx * 40, y + ty * 40)
    b1 = (x - tx * 4 + nx * 28, y - ty * 4 + ny * 28)
    b2 = (x - tx * 4 - nx * 28, y - ty * 4 - ny * 28)
    d.polygon(P(*tip, *b1, *b2), fill=WHITE)


def i_layout(d, P, w):  # a screen with its center guides and a piece snapped onto them
    d.rounded_rectangle(P(24, 40, 232, 216), radius=16 * P(1)[0], outline=WHITE, width=w)
    for y in range(52, 206, 26):
        d.line(P(128, y, 128, y + 12), fill=WHITE, width=int(w * 0.5))
    for x in range(36, 222, 26):
        d.line(P(x, 128, x + 12, 128), fill=WHITE, width=int(w * 0.5))
    d.rounded_rectangle(P(128, 72, 196, 128), radius=8 * P(1)[0], fill=WHITE)


def i_flag(d, P, w):  # a marker flag
    d.line(P(64, 28, 64, 232), fill=WHITE, width=w)
    d.polygon(P(64, 36, 212, 76, 64, 128), fill=WHITE)


def i_shield(d, P, w):
    d.polygon(P(128, 24, 216, 56, 208, 140, 128, 230, 48, 140, 40, 56), outline=WHITE, width=w)
    d.line(P(92, 124, 120, 152), fill=WHITE, width=w)
    d.line(P(114, 152, 168, 96), fill=WHITE, width=w)


def i_copy(d, P, w):
    d.rounded_rectangle(P(84, 28, 220, 176), radius=18 * P(1)[0], outline=WHITE, width=w)
    d.rounded_rectangle(P(36, 80, 172, 228), radius=18 * P(1)[0], outline=WHITE, width=w)


def i_clapper(d, P, w):  # a clapperboard
    d.rounded_rectangle(P(28, 104, 228, 220), radius=14 * P(1)[0], outline=WHITE, width=w)
    d.polygon(P(28, 92, 216, 40, 224, 72, 36, 124), fill=WHITE)
    for x in (88, 148):
        d.line(P(x, 104, x - 20, 136), fill=(0, 0, 0, 0), width=int(w * 0.8))


ICON_FUNCS = {
    "Camera": i_camera, "Orbit": i_orbit, "Layout": i_layout, "Flag": i_flag, "Shield": i_shield, "Copy": i_copy,
    "Clapper": i_clapper,
    "Live": i_live, "Names": i_names, "Hide": i_hide, "Custom": i_custom, "About": i_about,
    "Chat": i_chat, "Nameplate": i_nameplate, "UnitFrame": i_unitframe, "Group": i_group,
    "Tooltip": i_tooltip, "Meter": i_meter, "Social": i_social, "LFG": i_lfg, "Pet": i_pet,
    "BNet": i_bnet, "Guild": i_guild, "Overhead": i_overhead, "Trash": i_trash, "Dice": i_dice,
    "Shuffle": i_shuffle, "Close": i_close, "Plus": i_plus, "Check": i_check, "Chevron": i_chevron,
    "World": i_world, "Me": i_me,
}

if __name__ == "__main__":
    logo()
    minimap_icon()
    shapes()
    for name, fn in ICON_FUNCS.items():
        icon(name, fn)
    print("media written to", MEDIA)

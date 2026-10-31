"""OnAir going live, as a short loop for the project pages: only OnAir's own widgets, at their real
size and with their real motion (the Viewfinder look), over a quiet backdrop. The Deck's handle
turns from STBY to REC, the ON AIR slate plays (Moments.lua), the stream chat fades in and fills
(a marked moment comes in as a note), and at the end the chat goes and the "Real names are back"
banner slides in (Extras.lua). The icons and the pixel font are OnAir's own (Media/).

python tests/kit/make_animation.py   (writes release/gallery/00-how-it-works.gif)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "release", "gallery", "00-how-it-works.gif")
MEDIA = os.path.join(ROOT, "Media")
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")

FPS, LENGTH = 20, 8.6
W, H = 960, 540         # the screen, in UI units: widgets at their real size
F = 2                   # drawn at twice the size, then scaled down (smooth edges)

# OnAir's colors (UIKit.lua) and the game's chat colors.
PANEL = (13, 14, 16)
LINE, TEXT, MUTED, FAINT = (42, 45, 50), (237, 237, 240), (143, 148, 158), (87, 92, 102)
RED, RED_DEEP, OFF = (255, 59, 48), (140, 23, 18), (69, 74, 82)
LOOT, EPIC, WHITE, YELL, SAY, NOTE = (0, 170, 0), (163, 53, 238), (255, 255, 255), (255, 64, 64), (255, 255, 159), (217, 219, 224)

# When things happen (seconds).
GO_LIVE, END = 0.7, 5.4
SLATE_TIME = 1.7                 # Moments.lua
BANNER_IN, BANNER_HOLD, BANNER_OUT = 0.3, 2.2, 0.4   # Extras.lua
# The stream chat while live: what comes in, when. A marked moment arrives as a note.
LINES = [(1.4, [("You receive loot: ", LOOT), ("[Voidbound Signet]", EPIC)]),
         (2.2, [("Halduron Brightwing yells: Silvermoon, to arms!", YELL)]),
         (3.0, "note"),
         (3.7, [("Innkeeper Allison says: Welcome, The Star!", SAY)]),
         (4.4, [("You receive loot: ", LOOT), ("[Linen Cloth]x2", WHITE)])]


def font(name, size, variation=None):
    path = name if os.sep in name else os.path.join(FONTS, name)
    f = ImageFont.truetype(path, round(size * F))
    if variation:
        f.set_variation_by_name(variation)
    return f


CHAT_FONT = font("segoeui.ttf", 14)
TAB_FONT = font("segoeuib.ttf", 10)
TITLE_MONO = font(os.path.join(MEDIA, "OnAirMono.ttf"), 11)
SLATE_TITLE, SLATE_CLOCK = font("segoeui.ttf", 22), font("segoeui.ttf", 13)
BANNER_TITLE, BANNER_SUB = font("segoeui.ttf", 20), font("segoeui.ttf", 12)


def p(*v):
    """UI units -> drawing pixels."""
    return tuple(round(x * F) for x in v) if len(v) > 1 else round(v[0] * F)


def ease(t):
    t = min(1.0, max(0.0, t))
    return 1 - (1 - t) ** 3


def icon(name, size, color):
    """An OnAir icon or shape (white in Media), tinted, size in UI units."""
    path = os.path.join(MEDIA, "Icons", name + ".tga")
    if not os.path.isfile(path):
        path = os.path.join(MEDIA, name + ".tga")
    mask = Image.open(path).convert("RGBA").resize((p(size), p(size)), Image.LANCZOS).getchannel("A")
    out = Image.new("RGBA", mask.size, color + (255,))
    out.putalpha(mask)
    return out


CLAPPER = icon("Clapper", 36, TEXT)


def faded(layer, a):
    """The layer at alpha a (0..1)."""
    if a < 1:
        layer.putalpha(layer.getchannel("A").point(lambda v: round(v * a)))
    return layer


def corners(d, box, length, thick, color, inset):
    """Viewfinder brackets on a box's corners (Kit.Corners): inset > 0 inward, < 0 outward."""
    x0, y0, x1, y1 = box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset
    for cx, cy, dx, dy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        for w, h in ((length, thick), (thick, length)):  # the arm along, then the arm down
            xs, ys = sorted((cx, cx + dx * w)), sorted((cy, cy + dy * h))
            d.rectangle((xs[0], ys[0], xs[1], ys[1]), fill=color)


def dot(d, center, size, color):
    x, y = center
    d.ellipse(p(x - size / 2, y - size / 2, x + size / 2, y + size / 2), fill=color)


# ------------------------------------------------------------------------------------------- backdrop

def blend(stops, k):
    """The color at k along stops [(k, color), ...]."""
    for (k0, c0), (k1, c1) in zip(stops, stops[1:]):
        if k <= k1:
            t = max(0.0, (k - k0) / (k1 - k0))
            return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return stops[-1][1]


def backdrop():
    """A sunset over three ridges: lighter than the widgets, so they stand out as they do over the
    game's world, and blue where their red shows. Drawn at the size shown."""
    w, h = W, H
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    sky = [(0.0, (36, 52, 104)), (0.30, (84, 92, 160)), (0.50, (196, 122, 152)), (0.64, (250, 182, 134))]
    for y in range(h):
        d.line((0, y, w, y), fill=blend(sky, y / h))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((w * 0.60, h * 0.34, w * 0.82, h * 0.70), fill=(255, 222, 176, 150))
    img = Image.alpha_composite(img.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(h * 0.08)))
    d = ImageDraw.Draw(img)
    ridges = [((132, 112, 172), 0.60, 0.10, 1.0), ((92, 84, 150), 0.72, 0.12, 2.3), ((60, 58, 116), 0.86, 0.09, 4.1)]
    for color, base, amp, seed in ridges:
        pts = [(0, h)]
        for x in range(0, w + 8, 8):
            u = x / w
            y = base - amp * (0.55 * math.sin(u * 7.1 + seed) + 0.3 * math.sin(u * 15.3 + seed * 2.1)
                              + 0.15 * math.sin(u * 31.7 + seed * 3.7))
            pts.append((x, y * h))
        pts.append((w, h))
        d.polygon(pts, fill=color)
    return img


# ------------------------------------------------------------------------------------------- widgets

def handle(layer, live):
    """The Deck tucked away at the top: its handle, arrow, dot and word (Deck.lua, DeckTab)."""
    d = ImageDraw.Draw(layer)
    word = "REC" if live else "STBY"
    ww = d.textlength(word, font=TAB_FONT) / F
    width = 7 + 10 + 6 + 6 + 5 + ww + 8
    x0, y0, x1, y1 = W / 2 - width / 2, 0, W / 2 + width / 2, 19
    d.rectangle(p(x0, y0, x1, y1), fill=PANEL + (240,), outline=RED if live else LINE, width=p(1))
    ax, ay = x0 + 7 + 5, 9.5  # the arrow: a chevron pointing down
    d.line(p(ax - 4, ay - 2, ax, ay + 2, ax + 4, ay - 2), fill=TEXT, width=p(1.5))
    dot(d, (x0 + 7 + 10 + 6 + 3, 9.5), 6, RED if live else MUTED)
    d.text(p(x0 + 7 + 10 + 6 + 6 + 5, 9.5), word, font=TAB_FONT, fill=TEXT if live else MUTED, anchor="lm")


def slate(layer, t):
    """Moments.lua's slate, Viewfinder look, t seconds in."""
    out = 1 - ease((t - (SLATE_TIME - 0.45)) / 0.45)
    whole = min(ease(t / 0.15), out)
    if whole <= 0:
        return
    part = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(part)
    # the screen's corners close in
    corners(d, (0, 0, part.width, part.height), p(70), p(3), RED, p(28 + 40 * (1 - ease(t / 0.4))))
    # the card: 250 x 76, 140 above the middle, rising a little as it goes
    cw, ch = 250, 76
    cx, cy = W / 2, H / 2 - (140 + 10 * (1 - out))
    card = Image.new("RGBA", p(cw, ch), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rectangle((0, 0, card.width - 1, card.height - 1), fill=PANEL + (240,), outline=RED_DEEP, width=p(1))
    cd.rectangle((0, 0, p(3), card.height), fill=RED)
    # SetRotation(-0.35 ...) as in the game: tilted, then it claps shut
    clap = CLAPPER.rotate(math.degrees(-0.35 * (1 - ease((t - 0.1) / 0.15))), resample=Image.BICUBIC)
    card.alpha_composite(clap, (p(20), (card.height - clap.height) // 2))
    dot(cd, (77, 29), 10, RED + (round(255 * (0.55 + 0.45 * abs(math.cos(t * 4)))),))
    cd.text(p(90, 29), "REC", font=SLATE_TITLE, fill=TEXT, anchor="lm")
    cd.text(p(72, 44), "00:00  rolling", font=SLATE_CLOCK, fill=MUTED)
    left, top = p(cx - cw / 2), p(cy - ch / 2)
    part.alpha_composite(faded(card, ease(t / 0.3)), (left, top))
    # the brackets close in on the card, then lock (red)
    lock = ease(t / 0.35)
    corners(d, (left, top, left + card.width, top + card.height), p(14), p(2),
            RED if lock >= 0.99 else TEXT, p(-40 * (1 - lock)))
    layer.alpha_composite(faded(part, whole))


def stream_chat(layer, t):
    """The stream chat over yours while live (StreamChat.lua): fades in, gone at once at the end."""
    if not GO_LIVE <= t < END:
        return
    x0, y0, w, h = 24, 318, 420, 198
    part = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(part)
    d.rectangle(p(x0, y0, x0 + w, y0 + h), fill=PANEL + (235,), outline=LINE, width=p(1))
    corners(d, p(x0, y0, x0 + w, y0 + h), p(10), p(2), TEXT + (180,), p(3))
    # the title bar: a glowing red dot and "REC  CHAT"
    glow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(p(x0 + 6, y0 + 4, x0 + 22, y0 + 20), fill=RED + (150,))
    part.alpha_composite(glow.filter(ImageFilter.GaussianBlur(p(4))))
    d = ImageDraw.Draw(part)
    dot(d, (x0 + 14, y0 + 12), 8, RED)
    d.text(p(x0 + 26, y0 + 12), "REC  CHAT", font=TITLE_MONO, fill=MUTED, anchor="lm")
    # the corner grip
    for k in (5, 9, 13):
        d.line(p(x0 + w - 5 - k, y0 + h - 5, x0 + w - 5, y0 + h - 5 - k), fill=FAINT, width=p(1))
    # the lines so far, newest at the bottom
    shown = [parts for at, parts in LINES if at <= t]
    y = y0 + h - 12
    for parts in reversed(shown):
        y -= 22
        x = p(x0 + 12)
        if parts == "note":
            elapsed = int(3.0 - GO_LIVE)
            dot(d, (x0 + 16, y + 10), 7, RED)
            parts, x = [(f"00:{elapsed:02d}  Marked", NOTE)], p(x0 + 26)
        for text, color in parts:
            d.text((x, p(y)), text, font=CHAT_FONT, fill=color, stroke_width=p(1), stroke_fill=(0, 0, 0))
            x += d.textlength(text, font=CHAT_FONT)
    layer.alpha_composite(faded(part, ease((t - GO_LIVE) / 0.25)))


def banner(layer, t):
    """The banner (Extras.lua) when the broadcast ends: slides in, waits, fades."""
    k = t - END
    if k < 0 or k > BANNER_IN + BANNER_HOLD + BANNER_OUT:
        return
    slide = ease(k / BANNER_IN)
    a = slide if k < BANNER_IN + BANNER_HOLD else 1 - ease((k - BANNER_IN - BANNER_HOLD) / BANNER_OUT)
    bw, bh = 340, 54
    x0, y0 = W / 2 - bw / 2, 70 + 20 * slide
    part = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(part)
    d.rectangle(p(x0, y0, x0 + bw, y0 + bh), fill=PANEL + (242,), outline=LINE, width=p(1))
    d.rectangle(p(x0, y0, x0 + 3, y0 + bh), fill=OFF)
    corners(d, p(x0, y0, x0 + bw, y0 + bh), p(10), p(2), TEXT, 0)
    dot(d, (x0 + 28, y0 + bh / 2), 12, OFF)
    d.text(p(x0 + 44, y0 + 19), "STBY", font=BANNER_TITLE, fill=TEXT, anchor="lm")
    d.text(p(x0 + 44, y0 + 32), "Real names are back.", font=BANNER_SUB, fill=MUTED)
    layer.alpha_composite(faded(part, a))


# ------------------------------------------------------------------------------------------- frames

def widgets(t):
    """Everything OnAir shows at t, on a clear layer at the size shown."""
    layer = Image.new("RGBA", p(W, H), (0, 0, 0, 0))
    stream_chat(layer, t)
    handle(layer, GO_LIVE <= t < END)
    if GO_LIVE <= t < GO_LIVE + SLATE_TIME:
        slate(layer, t - GO_LIVE)
    banner(layer, t)
    return layer.resize((W, H), Image.LANCZOS)


def ramps():
    """Every widget and chat color, and its blends into the panel (the edges of the letters)."""
    out = []
    for color in (RED, RED_DEEP, TEXT, MUTED, FAINT, LINE, OFF, LOOT, EPIC, WHITE, YELL, SAY, NOTE):
        for k in (0.3, 0.55, 0.8, 1.0):
            out += [round(a + (b - a) * k) for a, b in zip(PANEL, color)]
    return out


def main():
    times = [i / FPS for i in range(round(LENGTH * FPS))]
    layers = [widgets(t) for t in times]
    back = backdrop()
    # One palette for all: the backdrop's sunset; every widget and chat color with its blends, since
    # a few letters' colors (the loot line's green) are too rare to win a place of their own; and the
    # rest from the widgets' own pixels, at moments that show every widget. The backdrop is dithered
    # once, with the sunset's colors only (not the widgets' reds), so it stays smooth and still while
    # the widgets move over it.
    shown = []
    for t in (0.2, GO_LIVE + 0.4, 4.6, END + 1.0):
        layer = layers[round(t * FPS)]
        frame = Image.alpha_composite(back, layer).convert("RGB")
        shown += [c for c, a in zip(frame.get_flattened_data(), layer.getchannel("A").get_flattened_data()) if a > 16]
    strip = Image.new("RGB", (len(shown), 1))
    strip.putdata(shown)
    fixed = ramps()
    room = 256 - 112 - len(fixed) // 3
    # (max coverage: median cut leaves too few of the sun glow's blends, and its edge dithers into dots)
    dusk = back.convert("RGB").quantize(colors=112, method=Image.Quantize.MAXCOVERAGE).getpalette()[:112 * 3]
    ui = strip.quantize(colors=room, method=Image.Quantize.MEDIANCUT).getpalette()[:room * 3]
    palette, sunset = Image.new("P", (1, 1)), Image.new("P", (1, 1))
    palette.putpalette(dusk + fixed + ui)
    sunset.putpalette(dusk + dusk[-3:] * (256 - len(dusk) // 3))
    still = back.convert("RGB").quantize(palette=sunset, dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")
    gif = [Image.alpha_composite(still, layer).convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
           for layer in layers]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    gif[0].save(OUT, save_all=True, append_images=gif[1:], duration=round(1000 / FPS), loop=0, optimize=True)
    print(f"wrote {OUT}: {len(gif)} frames, {os.path.getsize(OUT) // 1024} KB")


if __name__ == "__main__":
    main()

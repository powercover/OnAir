"""The project pages' gallery (CurseForge, Wago): 1920 x 1080 cards, each a headline, a line of detail
and a real OnAir window drawn by the offline renderer (render.py), in the addon's own colors.
Screenshots from the game can be framed the same way: put them in release/shots/ under the names in
SHOTS (png or jpg) and they become cards too.

python tests/kit/make_gallery.py   (writes release/gallery/)
"""
import os
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_media  # noqa: E402
import render  # noqa: E402

ROOT = render.ROOT
OUT = os.path.join(ROOT, "release", "gallery")
SHOTS_DIR = os.path.join(ROOT, "release", "shots")
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
# The brand on every card: the ON AIR lamp (the project logo's), with room around it for its glow.
LAMP_W = 190
LAMP = make_media.lamp(LAMP_W)
LAMP_PAD = LAMP_W // 4
W, H = 1920, 1080
TEXT_X, TEXT_W = 110, 650
BG_TOP, BG_BOTTOM = (15, 16, 19), (24, 25, 30)
RED, TEXT, MUTED = (255, 59, 48), (240, 241, 244), (160, 165, 176)
SKINS = (("viewfinder", "Viewfinder"), ("mixer", "Vision mixer"), ("slate", "Film slate"), ("studio", "Studio"))

# An hour live, for the Moments card (texts as OnAir writes them; names already aliases). The clock
# is fixed, so the card's session date comes out the same every time.
DEMO_MOMENTS = r"""
local OA = ...
local now = os.time({ year = 2026, month = 10, day = 31, hour = 21, min = 10 })
time = function() return now end
local session = OA.Moments.Current()
if session then
  session.started, session.gt = time() - 4210, GetTime() - 4210
  session.moments = {
    { t = 0, kind = "start", text = "Broadcast starts" },
    { t = 312, kind = "key", text = "Key started: Windrunner Spire +14" },
    { t = 1105, kind = "mark", text = "Clutch interrupt" },
    { t = 1530, kind = "death", text = "You died" },
    { t = 2179, kind = "keyEnd", text = "Key in time: Windrunner Spire +14, 31:07 (+2)" },
    { t = 2210, kind = "loot", text = "Loot: [Voidbound Signet]" },
    { t = 2675, kind = "pull", text = "Pull: Plexus Sentinel" },
    { t = 2927, kind = "kill", text = "Killed: Plexus Sentinel (4:12)" },
    { t = 3390, kind = "achievement", text = "Achievement: Keystone Hero" },
    { t = 3958, kind = "mark", text = "Floor Manager 39 carries the team" },
  }
end
OA.UI.Refresh()
"""

# Cards from OnAir's own windows. scroll: the page drawn that far down.
CARDS = [
    dict(name="01-go-live", kicker="STREAMER MODE FOR WORLD OF WARCRAFT", head="Go live without giving anyone away.",
         detail="Every player name in your interface becomes an alias, and comes back the moment you end. No reload.",
         skin="viewfinder", page="broadcast", live=True),
    dict(name="02-aliases", kicker="ALIASES, NOT BLANKS", head="A cast your viewers can follow.",
         detail="You, your group, strangers, Battle.net friends, guilds and pets: each gets an alias that stays the "
                "same every session. Four themes, or your own templates.",
         skin="slate", page="names", live=False),
    dict(name="03-everywhere", kicker="EVERYWHERE", head="Chat, plates, frames, meters, tooltips.",
         detail="Other addons' text too, and damage meters even in combat. Pick whose names are hidden, and where.",
         skin="mixer", page="hide", live=False),
    dict(name="04-moments", kicker="MOMENTS", head="One key: a timestamp and a screenshot.",
         detail="Bind it to OBS's replay buffer too, and each press saves a clip. Bosses, keys and deaths mark "
                "themselves. Export YouTube chapters.",
         skin="viewfinder", page="moments", live=True, scroll=430),
    dict(name="05-shield", kicker="SHIELD", head="Keep stream snipers out.",
         detail="While you're live, strangers' whispers wait, their invites, duels and trades are declined, and your "
                "zone and minimap can stay hidden.",
         skin="studio", page="shield", live=False),
    dict(name="06-camera", kicker="CAMERA", head="A cinematic camera, built in.",
         detail="Presets, zoom, field of view, shoulder offset and a slow orbit. Your own camera comes back when you "
                "end.",
         skin="studio", page="camera", live=False),
]

LOOKS = dict(name="07-looks", kicker="FOUR LOOKS", head="Pick your studio.",
             detail="A camera viewfinder, a vision mixer, a film slate or a clean console. The Deck, the stream "
                    "chat and the go-live moment follow.")

DECK = dict(name="08-deck", kicker="THE DECK", head="Run the show with the UI hidden.",
            detail="A small control bar that stays on screen when you hide the UI (Alt+Z): go live, mark, camera, "
                   "orbit, layout. It tucks away to a small handle.")

# Screenshots from the game (release/shots/<name>.png or .jpg).
SHOTS = [
    dict(name="chat", kicker="CHAT", head="Chat stays readable.",
         detail="Senders, names inside messages and whispers all read as aliases."),
    dict(name="nameplates", kicker="NAMEPLATES", head="Names above heads, covered.",
         detail="While live, friendly players show their alias above their heads."),
    dict(name="meters", kicker="DAMAGE METERS", head="Meters too, even in combat.",
         detail="Blizzard's and EllesmereUI's damage meters keep every alias in combat."),
    dict(name="frames", kicker="FRAMES", head="Every frame, an alias.",
         detail="Your frame, your target's, party and raid frames, other addons' frames too: all show aliases."),
    dict(name="stream-chat", kicker="STREAM CHAT", head="A clean chat for your viewers.",
         detail="Only the lines you pick, names already swapped. Your real chat keeps running underneath."),
]


def font(name, size, variation=None):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    if variation:
        f.set_variation_by_name(variation)
    return f


HEAD = font("bahnschrift.ttf", 84, "Bold")
KICKER = font("bahnschrift.ttf", 26, "SemiBold")
BODY = font("segoeui.ttf", 33)
FOOT = font("bahnschrift.ttf", 24, "SemiLight")
LABEL = font("bahnschrift.ttf", 24, "SemiBold")


def background():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        p = y / (H - 1)
        d.line((0, y, W, y), fill=tuple(int(a + (b - a) * p) for a, b in zip(BG_TOP, BG_BOTTOM)))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((1080, 160, 1900, 960), fill=RED + (34,))
    return Image.alpha_composite(img.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(160)))


def wrap(d, text, fnt, width):
    """Lines of text that fit the width."""
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if d.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line] if line else lines


def tracked(d, xy, text, fnt, fill, width):
    """Spaced-out capitals, the spacing shrunk to fit the width."""
    spacing = 6
    while spacing > 0 and sum(d.textlength(c, font=fnt) for c in text) + spacing * (len(text) - 1) > width:
        spacing -= 1
    x, y = xy
    for c in text:
        d.text((x, y), c, font=fnt, fill=fill)
        x += d.textlength(c, font=fnt) + spacing


def text_block(img, card):
    d = ImageDraw.Draw(img)
    x = TEXT_X
    head_lines = wrap(d, card["head"], HEAD, TEXT_W)
    body_lines = wrap(d, card["detail"], BODY, TEXT_W - 20)
    height = 40 + 30 + len(head_lines) * 96 + 30 + len(body_lines) * 48
    y = (H - height) // 2 + 30
    tracked(d, (x, y), card["kicker"], KICKER, RED, TEXT_W)
    y += 40
    d.rectangle((x, y, x + 56, y + 6), fill=RED)
    y += 30
    for line in head_lines:
        d.text((x, y), line, font=HEAD, fill=TEXT)
        y += 96
    y += 30
    for line in body_lines:
        d.text((x, y), line, font=BODY, fill=MUTED)
        y += 48
    # the brand, top left; the games, bottom left
    img.alpha_composite(LAMP, (x - LAMP_PAD, 70 - LAMP_PAD))
    d.text((x, H - 100), "Retail  ·  WoW Forever", font=FOOT, fill=MUTED)


def trim(shot):
    """The render without the plain margin the renderer leaves around a window."""
    shot = shot.convert("RGBA")
    edge = shot.getpixel((0, 0))
    # By color: an RGBA image's own bounding box looks at its alpha only.
    box = ImageChops.difference(shot, Image.new("RGBA", shot.size, edge)).convert("L").getbbox()
    return shot.crop(box) if box else shot


def place(img, shot, box, pixel=False, most=4):
    """The picture as big as fits in the box, with a soft shadow. Pixel art (the Deck's font) and
    small screenshots are scaled up by whole steps (at most `most`) so they stay sharp; anything
    else is only ever scaled down."""
    bx, by, bw, bh = box
    if pixel and shot.width <= bw and shot.height <= bh:
        step = max(1, min(bw // shot.width, bh // shot.height, most))
        shot = shot.resize((shot.width * step, shot.height * step), Image.NEAREST)
    else:
        scale = min(bw / shot.width, bh / shot.height, 1.0)
        shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    x, y = bx + (bw - shot.width) // 2, by + (bh - shot.height) // 2
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x + 10, y + 24, x + shot.width + 10, y + shot.height + 24), 18,
                                         fill=(0, 0, 0, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(28)))
    img.alpha_composite(shot.convert("RGBA"), (x, y))
    return x, y, shot.width, shot.height


def key_out(part, bg):
    """The game world left inside a window's box (beside a short row of icons) made clear: the
    world's color reached from the edges, stopping at the window's own colors and outlines."""
    part = part.convert("RGBA")
    px = part.load()
    w, h = part.size
    seen = set()
    todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while todo:
        x, y = todo.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, _ = px[x, y]
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 80:
            continue
        px[x, y] = (0, 0, 0, 0)
        todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return part


def windows(shot):
    """A screenshot's windows without the game world around and between them, stacked: kept only
    when the world behind is one bright color (its four corners agree). A dark background is left
    as it is: it could be the window itself (a chat), and cutting there would split its lines."""
    rgb = shot.convert("RGB")
    w, h = rgb.size
    corners = [rgb.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    bg = [sum(c[i] for c in corners) // 4 for i in range(3)]
    if max(max(abs(c[i] - bg[i]) for i in range(3)) for c in corners) > 40 or sum(bg) < 180:
        return shot
    px = rgb.load()
    ui = [[sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 80 for x in range(w)] for y in range(h)]
    bands, start = [], None
    for y in range(h + 1):
        on = y < h and sum(ui[y]) > w * 0.25
        if on and start is None:
            start = y
        elif not on and start is not None:
            if bands and start - bands[-1][1] < 12:
                bands[-1] = (bands[-1][0], y)  # a thin gap: the same window
            else:
                bands.append((start, y))
            start = None
    parts = []
    for top, bottom in bands:
        if bottom - top < 6:
            continue
        cols = [x for x in range(w) if sum(ui[y][x] for y in range(top, bottom)) > (bottom - top) * 0.15]
        if cols:
            parts.append(key_out(shot.crop((cols[0], top, cols[-1] + 1, bottom)), bg))
    if not parts:
        return shot
    gap = 28
    out = Image.new("RGBA", (max(p.width for p in parts), sum(p.height for p in parts) + gap * (len(parts) - 1)))
    y = 0
    for part in parts:
        out.paste(part, (0, y))
        y += part.height + gap
    return out


def find_shot(name):
    """The screenshot saved for a card: release/shots/<name>.png or .jpg, any case ("stream chat"
    and "stream_chat" count as "stream-chat")."""
    if not os.path.isdir(SHOTS_DIR):
        return None
    for file in sorted(os.listdir(SHOTS_DIR)):
        base, ext = os.path.splitext(file)
        if ext.lower() in (".png", ".jpg", ".jpeg") and base.lower().replace(" ", "-").replace("_", "-") == name:
            return os.path.join(SHOTS_DIR, file)
    return None


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    img.convert("RGB").save(path, optimize=True)
    print(path)


def scrolled(shift):
    """render.py draws a page from its top; this moves scrolling content up by shift pixels."""
    orig = render.Renderer._rect

    def _rect(self, obj, depth):
        pts = self.get(obj, "_pts")
        if not (pts and list(pts.items())) and self.get(obj, "_scrollParent") is not None:
            r = orig(self, obj, depth)
            return r and (r[0], r[1] + shift, r[2], r[3] + shift)
        return orig(self, obj, depth)

    return orig, _rect


def renders():
    """OnAir's windows, by (skin, page, live, scroll): one game per skin, state and scroll, the live
    ones with an hour of moments. Every skin's broadcast page and Deck, live, for the looks and the Deck."""
    jobs = {}
    for card in CARDS:
        jobs.setdefault((card["skin"], card["live"], card.get("scroll", 0)), set()).add(card["page"])
    for skin, _ in SKINS:
        jobs.setdefault((skin, True, 0), set()).add("broadcast")
    tmp = tempfile.mkdtemp(prefix="onair-gallery-")
    drive, rect = render.DRIVE, render.Renderer._rect
    made = {}
    try:
        for (skin, live, scroll), pages in jobs.items():
            render.DRIVE = drive + DEMO_MOMENTS if live else drive
            render.Renderer._rect = scrolled(scroll)[1] if scroll else rect
            folder = os.path.join(tmp, f"{skin}-{live}-{scroll}")
            for path in render.render(skin, sorted(pages), live, folder):
                what = os.path.basename(path)[len(skin) + 1:-4].replace("-live", "")
                made[(skin, what, live, scroll)] = path
    finally:
        render.DRIVE, render.Renderer._rect = drive, rect
    return made


def main():
    made = renders()
    for card in CARDS:
        img = background()
        text_block(img, card)
        shot = trim(Image.open(made[(card["skin"], card["page"], card["live"], card.get("scroll", 0))]))
        place(img, shot, (790, 90, 1050, 900))
        save(img, card["name"])

    img = background()
    text_block(img, LOOKS)
    for i, (skin, _) in enumerate(SKINS):
        shot = trim(Image.open(made[(skin, "broadcast", True, 0)]))
        shot = shot.resize((shot.width // 2, shot.height // 2), Image.LANCZOS)
        place(img, shot, (800 + (i % 2) * 520, 170 + (i // 2) * 370, 500, 350))
    save(img, LOOKS["name"])

    # The Deck in each look, one under another, its pixel font kept sharp.
    img = background()
    text_block(img, DECK)
    d = ImageDraw.Draw(img)
    for i, (skin, label) in enumerate(SKINS):
        top = 150 + i * 200
        x, y, w, h = place(img, trim(Image.open(made[(skin, "deck", True, 0)])), (800, top, 1040, 140), pixel=True)
        d.text((x, y + h + 14), label, font=LABEL, fill=MUTED)
    save(img, DECK["name"])

    # Screenshots from the game: whole, a small crop enlarged by whole steps (no blur).
    for shot_card in SHOTS:
        path = find_shot(shot_card["name"])
        if path:
            img = background()
            text_block(img, shot_card)
            place(img, windows(Image.open(path).convert("RGBA")), (780, 110, 1100, 860), pixel=True, most=3)
            save(img, "shot-" + shot_card["name"])


if __name__ == "__main__":
    main()

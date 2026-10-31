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

# An hour live, for the Moments card (texts as OnAir writes them; names already aliases).
DEMO_MOMENTS = r"""
local OA = ...
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
    dict(name="frames", kicker="FRAMES", head="Party and raid frames.",
         detail="Every frame and window: friends, guild, group finder, mail."),
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


def place(img, shot, box, pixel=False):
    """The picture as big as fits in the box, with a soft shadow. Pixel art (the Deck's font) is
    scaled up by whole steps so it stays sharp; anything else is only ever scaled down."""
    bx, by, bw, bh = box
    if pixel:
        step = max(1, min(bw // shot.width, bh // shot.height))
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


def cover(shot, w, h):
    """A game screenshot cut to fill w x h (the middle kept)."""
    scale = max(w / shot.width, h / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    left, top = (shot.width - w) // 2, (shot.height - h) // 2
    return shot.crop((left, top, left + w, top + h))


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

    for shot_card in SHOTS:
        for ext in (".png", ".jpg", ".jpeg"):
            path = os.path.join(SHOTS_DIR, shot_card["name"] + ext)
            if os.path.isfile(path):
                img = background()
                text_block(img, shot_card)
                place(img, cover(Image.open(path).convert("RGB"), 1040, 640), (790, 220, 1050, 640))
                save(img, "shot-" + shot_card["name"])
                break


if __name__ == "__main__":
    main()

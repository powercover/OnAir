"""Draws OnAir's console and Deck to PNG files, offline: the addon runs on the mocked frame API
(ui_smoke.MOCK), the frames' anchors are solved like WoW does, and textures and text are drawn
with PIL. Not pixel-exact (no Arial Narrow here: Arial squeezed to 82%; no blend modes), but the
layout, colors and fonts are the addon's own, so it shows what a skin looks like before the game
does.

python tests/kit/render.py [skin ...] [--page KEY ...] [--live] [--out DIR]
"""
import os
import re
import sys

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ui_smoke  # noqa: E402

ROOT = ui_smoke.ROOT
FONTS = "C:/Windows/Fonts/"
NARROW = 0.82  # Arial Narrow is about this much of Arial's width

_fonts = {}


def font_for(file, size):
    file = (file or "").replace("\\", "/")
    mono = file.endswith("OnAirMono.ttf")
    path = os.path.join(ROOT, "Media", "OnAirMono.ttf") if mono else FONTS + "arial.ttf"
    key = (path, int(round(size)))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, max(1, int(round(size))))
    return _fonts[key], (1.0 if mono else NARROW)


COLOR_CODE = re.compile(r"\|c[0-9a-fA-F]{8}|\|r")


def plain(text):
    return COLOR_CODE.sub("", text or "")


def text_width(file, size, text):
    font, squeeze = font_for(file, size)
    return font.getlength(plain(text)) * squeeze


def wrap(file, size, text, width):
    lines = []
    for para in plain(text).split("\n"):
        words, line = para.split(" "), ""
        for word in words:
            test = (line + " " + word) if line else word
            if line and text_width(file, size, test) > width:
                lines.append(line)
                line = word
            else:
                line = test
        lines.append(line)
    return lines


def measure(file, size, text, width, wrapping):
    if text is None:
        return 0, 0
    if width and wrapping:
        lines = wrap(file, size, text, width)
        return width, len(lines) * size * 1.25
    return text_width(file, size, text), size * 1.25


PATCH = r"""
local measure, solve = ...
local kinds = { "Frame", "Button", "Texture", "FontString", "EditBox", "ScrollFrame", "StatusBar", "ScrollingMessageFrame" }
local probe = {
  Frame = CreateFrame("Frame"), Button = CreateFrame("Button"), EditBox = CreateFrame("EditBox"),
  ScrollFrame = CreateFrame("ScrollFrame"), StatusBar = CreateFrame("StatusBar"),
  ScrollingMessageFrame = CreateFrame("ScrollingMessageFrame"),
}
probe.Texture = probe.Frame:CreateTexture()
probe.FontString = probe.Frame:CreateFontString()
local origTexture, origFont = probe.Frame.CreateTexture, probe.Frame.CreateFontString
local origSize = probe.Frame.SetSize
local fns = {}
function fns:SetPoint(p, a, b, c, d)
  local rel, rp, x, y
  if type(a) == "number" then rel, rp, x, y = self._parent, p, a, b
  elseif type(b) == "number" then rel, rp, x, y = a, p, b, c
  else rel, rp, x, y = a or self._parent, b or p, c or 0, d or 0 end
  self._pts = self._pts or {}
  self._pts[p] = { rel = rel, rp = rp, x = x or 0, y = y or 0 }
  table.insert(self._points, { p, rel })
end
function fns:SetAllPoints(rel)
  rel = rel or self._parent
  self._pts = { TOPLEFT = { rel = rel, rp = "TOPLEFT", x = 0, y = 0 }, BOTTOMRIGHT = { rel = rel, rp = "BOTTOMRIGHT", x = 0, y = 0 } }
end
function fns:ClearAllPoints() self._points = {}; self._pts = {} end
function fns:SetSize(w, h) self._w, self._h, self._wset, self._hset = w, h, true, true end
function fns:SetWidth(w) self._w, self._wset = w, true end
function fns:SetHeight(h) self._h, self._hset = h, true end
function fns:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 }; self._file = nil end
function fns:SetTexture(file, h, v) self._file = file; self._color = nil; if h == "REPEAT" then self._tile = true end end
function fns:SetVertexColor(r, g, b, a) self._vc = { r, g, b, a or 1 } end
function fns:SetRotation(r) self._rot = r end
function fns:SetBlendMode(m) self._blend = m end
function fns:SetFont(file, size) self._fontspec = { file = file, size = size } end
function fns:SetFontObject(fo) self._fontspec = fo and fo._fontspec end
function fns:SetTextColor(r, g, b, a) self._tc = { r, g, b, a or 1 } end
function fns:SetJustifyH(j) self._jh = j end
function fns:SetWordWrap(w) self._wrap = w end
function fns:SetScrollChild(child) child._scrollParent = self; self._child = child end
function fns:SetScale(s) self._scale = s end
function fns:SetTextInsets(l) self._inset = l end
function fns:CreateTexture(name, layer, inherits, sub)
  local t = origTexture(self); t._layer = layer or "ARTWORK"; t._sub = sub or 0; t._order = NEXT_ORDER(); return t
end
function fns:CreateFontString(name, layer)
  local t = origFont(self); t._layer = layer or "OVERLAY"; t._sub = 0; t._order = NEXT_ORDER(); return t
end
function fns:GetStringWidth()
  local spec = self._fontspec or { size = 12 }
  local w = measure(spec.file, spec.size, self._text and tostring(self._text) or "", nil, false)
  return w
end
function fns:GetStringHeight()
  local spec = self._fontspec or { size = 12 }
  local _, h = measure(spec.file, spec.size, self._text and tostring(self._text) or "", self._wset and self._w or nil, self._wrap)
  return h
end
-- Sizes as laid out (a frame stretched between two anchors knows its width only from them).
function fns:GetWidth() local w = solve(self, 1); if w then return w end return self._w end
function fns:GetHeight() local h = solve(self, 2); if h then return h end return self._h end
local n = 0
function NEXT_ORDER() n = n + 1; return n end
for _, kind in ipairs(kinds) do
  local index = getmetatable(probe[kind]).__index
  for k, fn in pairs(fns) do index[k] = fn end
end
"""

DRIVE = r"""
local OA, skin, pages, live = ...
local function run(seconds)
  for _ = 1, math.ceil(seconds / 0.05) do
    for _, f in ipairs(FRAMES) do
      local fn = f._scripts and f._scripts.OnUpdate
      if fn then fn(f, 0.05) end
    end
  end
end
local function fire(event, ...)
  for _, f in ipairs(FRAMES) do
    if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
RUN = run
UIParent._w, UIParent._h = 1920, 1080
WorldFrame._w, WorldFrame._h = 1920, 1080
fire("ADDON_LOADED", "OnAir")
fire("PLAYER_LOGIN")
OA.db.deck.show = "always"; OA.db.deck.hide = "never"
if live then OA.GoLive() end
OA.UI.SetSkin(skin)
OA.UI.ShowConsole()
OA.Deck.Refresh()
run(1)
"""

LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}


class Renderer:
    def __init__(self, lua):
        self.lua = lua
        self.rects = {}

    def get(self, obj, key):
        try:
            return obj[key]
        except Exception:  # noqa: BLE001
            return None

    def rect(self, obj, depth=0):
        """(left, bottom, right, top) in WoW coordinates (y up), or None if not placed."""
        key = id(obj) if not hasattr(obj, "__hash__") else obj
        try:
            if key in self.rects:
                return self.rects[key]
        except TypeError:
            pass
        r = self._rect(obj, depth)
        try:
            self.rects[key] = r
        except TypeError:
            pass
        return r

    def size(self, obj):
        w, h = self.get(obj, "_w") or 0, self.get(obj, "_h") or 0
        if self.get(obj, "_kind") == "FontString":
            spec = self.get(obj, "_fontspec")
            file, fsize = (spec["file"], spec["size"]) if spec else (None, 12)
            text = self.get(obj, "_text")
            text = "" if text is None else str(text)
            mw, mh = measure(file, fsize, text, w if self.get(obj, "_wset") else None, self.get(obj, "_wrap"))
            if not self.get(obj, "_wset"):
                w = mw
            if not self.get(obj, "_hset"):
                h = mh
        return w, h

    def _rect(self, obj, depth):
        if depth > 60:
            return None
        name = self.get(obj, "_name")
        if name in ("UIParent", "WorldFrame"):
            return (0, 0, 1920, 1080)
        pts = self.get(obj, "_pts")
        anchors = list(pts.items()) if pts else []
        if not anchors:
            sp = self.get(obj, "_scrollParent")
            if sp is not None:
                pr = self.rect(sp, depth + 1)
                if not pr:
                    return None
                w, h = self.size(obj)
                return (pr[0], pr[3] - h, pr[0] + w, pr[3])
            return None
        w, h = self.size(obj)
        left = right = cx = top = bottom = cy = None
        for p, a in anchors:
            rel = a["rel"]
            if rel is None:
                continue
            rr = self.rect(rel, depth + 1)
            if not rr:
                continue
            rp = a["rp"]
            ax = rr[0] if "LEFT" in rp else (rr[2] if "RIGHT" in rp else (rr[0] + rr[2]) / 2)
            ay = rr[3] if "TOP" in rp else (rr[1] if "BOTTOM" in rp else (rr[1] + rr[3]) / 2)
            ax += a["x"] or 0
            ay += a["y"] or 0
            if "LEFT" in p:
                left = ax
            elif "RIGHT" in p:
                right = ax
            else:
                cx = ax
            if "TOP" in p:
                top = ay
            elif "BOTTOM" in p:
                bottom = ay
            else:
                cy = ay
        if left is None and right is None and cx is None:
            return None
        if left is not None and right is not None:
            pass
        elif left is not None:
            right = left + w
        elif right is not None:
            left = right - w
        else:
            left, right = cx - w / 2, cx + w / 2
        if top is not None and bottom is not None:
            pass
        elif top is not None:
            bottom = top - h
        elif bottom is not None:
            top = bottom + h
        else:
            bottom, top = cy - h / 2, cy + h / 2
        return (left, bottom, right, top)

    # ------------------------------------------------------------------ drawing

    def draw(self, root, crop):
        x0, y0, x1, y1 = crop
        self.ox, self.oy = x0, y1
        img = Image.new("RGBA", (int(x1 - x0), int(y1 - y0)), (40, 44, 52, 255))
        self.img = img
        self.walk(root, 1.0, None)
        return img

    def to_px(self, r):
        return (r[0] - self.ox, self.oy - r[3], r[2] - self.ox, self.oy - r[1])

    def walk(self, obj, alpha, clip):
        if not self.get(obj, "_shown"):
            return
        a = alpha * (self.get(obj, "_alpha") if self.get(obj, "_alpha") is not None else 1)
        if a <= 0.01:
            return
        kind = self.get(obj, "_kind")
        if kind == "ScrollFrame":
            r = self.rect(obj)
            if r:
                clip = self.to_px(r)
        regions = []
        rs = self.get(obj, "_regions")
        if rs:
            for i in range(1, len(rs) + 1):
                regions.append(rs[i])
        regions.sort(key=lambda t: (LAYERS.get(self.get(t, "_layer") or "ARTWORK", 2), self.get(t, "_sub") or 0,
                                    self.get(t, "_order") or 0))
        for t in regions:
            if self.get(t, "_shown"):
                ta = a * (self.get(t, "_alpha") if self.get(t, "_alpha") is not None else 1)
                if ta > 0.01:
                    if self.get(t, "_kind") == "Texture":
                        self.texture(t, ta, clip)
                    else:
                        self.text(t, ta, clip)
        if kind == "EditBox":
            self.text(obj, a, clip, inset=self.get(obj, "_inset") or 0)
        kids = []
        cs = self.get(obj, "_children")
        if cs:
            for i in range(1, len(cs) + 1):
                kids.append((self.get(cs[i], "_level") or 0, i, cs[i]))
        kids.sort(key=lambda k: (k[0], k[1]))
        for _, _, c in kids:
            self.walk(c, a, clip)

    def paste(self, layer, box, clip):
        x0, y0 = int(round(box[0])), int(round(box[1]))
        if clip:
            mask = Image.new("L", self.img.size, 0)
            ImageDraw.Draw(mask).rectangle([clip[0], clip[1], clip[2] - 1, clip[3] - 1], fill=255)
            full = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
            full.paste(layer, (x0, y0))
            alpha = full.getchannel("A")
            from PIL import ImageChops
            full.putalpha(ImageChops.multiply(alpha, mask))
            self.img.alpha_composite(full)
        else:
            if x0 >= self.img.width or y0 >= self.img.height:
                return
            self.img.alpha_composite(layer, (max(0, x0), max(0, y0)),
                                     (max(0, -x0), max(0, -y0)))

    def texture(self, t, alpha, clip):
        r = self.rect(t)
        if not r:
            return
        box = self.to_px(r)
        w, h = int(round(box[2] - box[0])), int(round(box[3] - box[1]))
        if w <= 0 or h <= 0 or w > 4000 or h > 4000:
            return
        color = self.get(t, "_color")
        if color:
            c = [color[i] for i in range(1, 5)]
            layer = Image.new("RGBA", (w, h), (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * (c[3] or 1) * alpha)))
            self.paste(layer, box, clip)
            return
        file = self.get(t, "_file")
        if not file or not isinstance(file, str):
            return
        path = file.replace("\\", "/").split("/AddOns/OnAir/", 1)[-1]
        full = os.path.join(ROOT, path)
        if not os.path.exists(full):
            full += ".tga"
        if not os.path.exists(full):
            return
        src = Image.open(full).convert("RGBA")
        if self.get(t, "_tile"):
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            for yy in range(0, h, src.height):
                for xx in range(0, w, src.width):
                    layer.paste(src, (xx, yy))
        else:
            layer = src.resize((w, h), Image.LANCZOS)
        rot = self.get(t, "_rot")
        if rot:
            import math
            layer = layer.rotate(math.degrees(rot), resample=Image.BICUBIC)
        vc = self.get(t, "_vc")
        c = [vc[i] for i in range(1, 5)] if vc else [1, 1, 1, 1]
        pr, pg, pb, pa = layer.split()
        pr = pr.point(lambda v: int(v * c[0]))
        pg = pg.point(lambda v: int(v * c[1]))
        pb = pb.point(lambda v: int(v * c[2]))
        k = (c[3] if c[3] is not None else 1) * alpha * (0.6 if self.get(t, "_blend") == "ADD" else 1)
        pa = pa.point(lambda v: int(v * k))
        self.paste(Image.merge("RGBA", (pr, pg, pb, pa)), box, clip)

    def text(self, t, alpha, clip, inset=0):
        raw = self.get(t, "_text")
        if raw is None or not isinstance(raw, (str, int, float)):
            return
        text = plain(str(raw))
        if not text:
            return
        r = self.rect(t)
        if not r:
            return
        spec = self.get(t, "_fontspec")
        file, size = (spec["file"], spec["size"]) if spec else (None, 12)
        font, squeeze = font_for(file, size)
        tc = self.get(t, "_tc")
        c = [tc[i] for i in range(1, 5)] if tc else [1, 0.82, 0, 1]
        box = self.to_px(r)
        width = box[2] - box[0]
        pts = self.get(t, "_pts")
        stretched = pts is not None and any("LEFT" in p for p in pts.keys()) and any("RIGHT" in p for p in pts.keys())
        lines = wrap(file, size, text, width) if (self.get(t, "_wrap") and (self.get(t, "_wset") or stretched)) else [text]
        line_h = size * 1.25
        total = line_h * len(lines)
        y = box[1] + ((box[3] - box[1]) - total) / 2
        jh = self.get(t, "_jh") or ("LEFT" if self.get(t, "_kind") == "EditBox" else "CENTER")
        for line in lines:
            tw = int(font.getlength(line)) + 4
            th = int(line_h) + 4
            layer = Image.new("RGBA", (max(1, tw), th), (0, 0, 0, 0))
            ImageDraw.Draw(layer).text((0, 1), line, font=font,
                                       fill=(int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * (c[3] or 1) * alpha)))
            if squeeze != 1:
                layer = layer.resize((max(1, int(tw * squeeze)), th), Image.LANCZOS)
            lw = layer.width - 4 * squeeze
            if jh == "LEFT":
                x = box[0] + inset
            elif jh == "RIGHT":
                x = box[2] - lw
            else:
                x = box[0] + (width - lw) / 2
            # Text wider than its box is cut (WoW shows "..."), unless it's a free label.
            if self.get(t, "_wset") and not self.get(t, "_wrap") and lw > width + 1:
                layer = layer.crop((0, 0, max(1, int(width)), th))
            self.paste(layer, (x, y), clip)
            y += line_h


def render(skin, pages, live, out):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(ui_smoke.MOCK, 120100)
    lua.execute('OnAirDB = { look = "%s" }; LOOK = "%s"' % (skin, skin))
    lua.execute(r"""
    FRAMES = {}
    local create = CreateFrame
    function CreateFrame(kind, name, parent)
      local f = create(kind, name, parent)
      f._events = {}
      f.RegisterEvent = function(self, e) self._events[e] = true end
      f.RegisterUnitEvent = function(self, e) self._events[e] = true end
      table.insert(FRAMES, f)
      return f
    end
    """)
    holder = {}

    def solve(obj, axis):
        rend = holder.get("r")
        if rend is None or holder.get("busy"):
            return None
        holder["busy"] = True
        try:
            rend.rects = {}
            r = rend.rect(obj)
        finally:
            holder["busy"] = False
        if not r:
            return None
        return (r[2] - r[0]) if axis == 1 else (r[3] - r[1])

    lua.execute(PATCH, lambda f, s, t, w, wr: measure(f, s, t, w, wr), solve)
    holder["r"] = Renderer(lua)
    oa = lua.eval("{}")
    toc = open(os.path.join(ROOT, "OnAir.toc"), encoding="utf-8").read()
    for rel in [l.strip().replace("\\", "/") for l in toc.splitlines() if l.strip().endswith(".lua")]:
        lua.execute(open(os.path.join(ROOT, rel), encoding="utf-8").read(), "OnAir", oa)
    lua.execute(DRIVE, oa, skin, None, live)
    g = lua.globals()
    os.makedirs(out, exist_ok=True)
    written = []
    for page in pages:
        lua.execute("local OA, page = ...; OA.UI.ShowPage(page, false); OA.UI.Refresh(); RUN(1)", oa, page)
        rend = Renderer(lua)
        console = g.OnAirConsole
        r = rend.rect(console)
        img = rend.draw(console, (r[0] - 20, r[1] - 20, r[2] + 20, r[3] + 20))
        path = os.path.join(out, f"{skin}-{page}{'-live' if live else ''}.png")
        img.save(path)
        written.append(path)
    rend = Renderer(lua)
    deck = g.OnAirDeck
    r = rend.rect(deck)
    if r:
        img = rend.draw(deck, (r[0] - 16, r[1] - 16, r[2] + 16, r[3] + 16))
        path = os.path.join(out, f"{skin}-deck{'-live' if live else ''}.png")
        img.save(path)
        written.append(path)
    guarded = [g.GUARDED[i] for i in range(1, len(g.GUARDED) + 1)]
    if guarded:
        print("guarded errors:", guarded)
    return written


if __name__ == "__main__":
    args = sys.argv[1:]
    out = os.path.join(ROOT, "tests", "renders")
    if "--out" in args:
        out = args[args.index("--out") + 1]
    pages = ["broadcast"]
    if "--page" in args:
        pages = [a for i, a in enumerate(args) if i > 0 and args[i - 1] == "--page"]
    skins = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--page", "--out"))]
    for skin in skins or ["viewfinder", "mixer", "slate", "studio"]:
        for path in render(skin, pages, "--live" in args, out):
            print(path)

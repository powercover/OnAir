local _, OA = ...

-- The console: OnAir's own window (/onair, the minimap button, the Deck, a key binding).
-- The window itself is only a frame that remembers its place; what's inside is drawn by the
-- active skin (Skin*.lua): its own chrome (a camera screen, a vision mixer desk, a film slate,
-- the studio console), its own way to switch pages and its own controls. The pages here only
-- say what they hold ("a switch for this, a choice of these, a slider from 1 to 100"), so every
-- skin can draw them its way. Each skin's face is built the first time it's shown and kept:
-- switching skins is instant and needs no reload.
OA.UI = OA.UI or {}

local UI = OA.UI
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Names = OA.Names
local Utils = OA.Utils

local W, H = 880, 620

local console     -- the window: position, Esc, opening and closing
local faces = {}  -- skin key -> its face (chrome, pages, refreshers)
local face        -- the face on screen
local building    -- the face being built (pages add themselves to it)
local current     -- the page on screen, kept across skins

function UI.Refresh()
    if UI.UpdateExtras then
        UI.UpdateExtras()
    end
    if not face then
        return
    end
    for _, fn in ipairs(face.refreshers) do
        fn()
    end
end

local function Save(fn)
    return function(...)
        fn(...)
        OA.NamesChanged(false)
    end
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
end

---------------------------------------------------------------------------------------------- pages

local SECTIONS = {
    { title = L["LIVE"], items = {
        { key = "broadcast", icon = "Live", text = L["Broadcast"],
            desc = L["Go live, check what viewers see, and pick what shows on screen."] },
        { key = "stream", icon = "Chat", text = L["Stream chat"],
            desc = L["While live, a clean chat window covers yours and shows only what you pick, every name already an alias. Your real chat keeps running underneath."] },
        { key = "moments", icon = "Flag", text = L["Moments"],
            desc = L["Going live starts a clock at 00:00. Start your recording at the same time: a short slate marks 00:00 in the video, so these timecodes match it exactly."] },
    } },
    { title = L["PRIVACY"], items = {
        { key = "names", icon = "Names", text = L["Names"],
            desc = L["Your stage name, what everyone else is called, and NPC names."] },
        { key = "hide", icon = "Hide", text = L["Hide"],
            desc = L["Whose names are swapped, and where."] },
        { key = "custom", icon = "Custom", text = L["Custom"],
            desc = L["Give a player the same alias always, e.g. your duo partner. This page holds real names: they stay masked unless you reveal them."] },
        { key = "shield", icon = "Shield", text = L["Shield"],
            desc = L["Against stream snipers and griefers, while live. Friends, Battle.net friends, your guild, your group and the players on the Custom page always get through."] },
    } },
    { title = L["PRODUCTION"], items = {
        { key = "camera", icon = "Camera", text = L["Camera"],
            desc = L["Cinematic camera for recording: zoom, field of view, shoulder offset, smoother motion, orbit."] },
        { key = "deck", icon = "Group", text = L["Deck"],
            desc = L["A small control bar that stays on screen even with the UI hidden (Alt+Z). Drag it to any edge or corner."] },
        { key = "look", icon = "Clapper", text = L["Look"],
            desc = L["How OnAir looks: a camera viewfinder, a vision mixer, a film slate or the plain studio console. The console, the Deck, the stream chat and the go-live moment all follow, right away."] },
        { key = "layout", icon = "Layout", text = L["Layout"],
            desc = L["Place the stream chat and the Deck on screen, and how they snap while you drag them."] },
    } },
    { items = {
        { key = "about", icon = "About", text = L["About"],
            desc = L["Streamer & recording mode for World of Warcraft."] },
    } },
}

local ITEMS = {}
for _, section in ipairs(SECTIONS) do
    for _, item in ipairs(section.items) do
        item.section = section.title
        ITEMS[item.key] = item
    end
end

-- What the skins get to draw their chrome with.
local API = {
    W = W, H = H,
    sections = SECTIONS,
    items = ITEMS,
    FormatTime = FormatTime,
}

function API.Show(key)
    UI.ShowPage(key, true)
end

function API.Close()
    UI.HideConsole()
end

function API.Current()
    return current
end

-- "live", "preview" or "off".
function API.State()
    if OA.live and OA.rehearsal then
        return "preview"
    elseif OA.live then
        return "live"
    end
    return "off"
end

function API.Clock()
    return (OA.live and not OA.rehearsal) and FormatTime(OA.Moments.Elapsed()) or "--:--:--"
end

-- The region drags the whole window.
function API.Drag(region)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function() console:StartMoving() end)
    region:SetScript("OnDragStop", function()
        console:StopMovingOrSizing()
        local point, _, relPoint, x, y = console:GetPoint()
        OA.db.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
end

-- One line per system, for the skin's status strip: text, its color, and the page it opens.
API.status = {
    { page = "broadcast", text = function()
        local state = API.State()
        if state == "preview" then
            return Kit.Word("preview"), C.amber
        elseif state == "live" then
            return Kit.Word("live") .. "  " .. FormatTime(OA.Moments.Elapsed()), C.red
        end
        return Kit.Word("off"), C.off
    end },
    { page = "names", text = function()
        return string.format(L["%d masked"], Names.Count()), OA.live and C.red or C.off
    end },
    { page = "stream", text = function()
        local on = OA.db.stream.enabled
        return L["STREAM CHAT"] .. " " .. (on and L["on"] or L["off"]), on and C.green or C.off
    end },
    { page = "moments", text = function()
        local session = OA.Moments.Current()
        local n = session and #session.moments or 0
        return string.format(L["%d moments"], n), n > 0 and C.text or C.off
    end },
    { page = "shield", text = function()
        local held = OA.Shield.HeldCount()
        if held > 0 then
            return string.format(L["SHIELD  %d held"], held), C.amber
        end
        return L["SHIELD"] .. " " .. (OA.db.shield.whispers and L["on"] or L["off"]), OA.db.shield.whispers and C.green or C.off
    end },
    { page = "camera", text = function()
        local cam = OA.db.camera
        local on = OA.Camera.Active()
        return L["CAM"] .. " " .. (on and cam.preset or L["off"]), on and C.green or C.off
    end },
}

---------------------------------------------------------------------------------------------- page builder

-- A page: a scroll area in the skin's page area, the skin's header, then the controls top to
-- bottom. The builder (P) places what a page asks for; the skin draws each control, and says
-- how many go side by side (studio tiles two to a row, a vision mixer's four, a viewfinder's
-- menu one per row).
local function Builder(f, page, top)
    local skin, shell = f.skin, f.shell
    local body, width, x0 = page.body, shell.width, shell.pad
    local y, row = top, nil
    local P = { body = body, width = width, skin = skin, page = page }

    local function OnRefresh(fn)
        f.refreshers[#f.refreshers + 1] = fn
    end
    P.OnRefresh = OnRefresh

    local function EndRow()
        if row then
            y = y + row.h + skin.gap
            row = nil
        end
    end
    local function Put(frame, gap)
        EndRow()
        frame:SetPoint("TOPLEFT", body, "TOPLEFT", x0, -y)
        y = y + frame:GetHeight() + (gap or skin.gap)
        return frame
    end
    local function ColWidth(cols)
        return cols > 1 and (width - (cols - 1) * skin.colGap) / cols or width
    end
    -- Side by side with the same kind before it, while the row has room.
    local function Cell(kind, frame, cols)
        if cols <= 1 then
            return Put(frame)
        end
        if not row or row.kind ~= kind or row.n >= cols then
            EndRow()
            row = { kind = kind, n = 0, h = 0 }
        end
        frame:SetPoint("TOPLEFT", body, "TOPLEFT", x0 + row.n * (ColWidth(cols) + skin.colGap), -y)
        row.n = row.n + 1
        row.h = math.max(row.h, frame:GetHeight())
        return frame
    end
    local function Enabled(widget, spec)
        if spec.enabled then
            OnRefresh(function()
                local on = spec.enabled() and true or false
                if widget.SetEnabledLook then
                    widget:SetEnabledLook(on)
                else
                    widget.oaAlpha = on and 1 or 0.4
                    widget:SetAlpha(widget.oaAlpha)
                end
            end)
        end
    end

    function P.Heading(text, hint)
        EndRow()
        return Put(skin.Heading(body, text, hint, width), skin.headingGap)
    end
    function P.Toggle(spec)
        local cols = skin.cols.toggle
        local t = skin.Toggle(body, spec, ColWidth(cols))
        OnRefresh(function() t:Refresh(true) end)
        Enabled(t, spec)
        return Cell("toggle", t, cols)
    end
    function P.Choice(spec)
        local c = skin.Choice(body, spec, width)
        OnRefresh(function() c:Refresh(true) end)
        Enabled(c, spec)
        return Put(c)
    end
    function P.Slider(spec)
        local cols = skin.cols.slider
        local s = skin.Slider(body, spec, ColWidth(cols))
        OnRefresh(function() s:Refresh() end)
        Enabled(s, spec)
        return Cell("slider", s, cols)
    end
    function P.Input(spec)
        local i = skin.Input(body, spec, width)
        OnRefresh(function() i:Refresh() end)
        Enabled(i, spec)
        return Put(i)
    end
    -- A row of short text fields (aliases, labels), each with its own label.
    function P.Fields(spec)
        local fields = skin.Fields(body, spec, width)
        OnRefresh(function() fields:Refresh() end)
        for i, item in ipairs(spec.items) do
            Enabled(fields.inputs[i], item)
        end
        return Put(fields)
    end
    -- Buttons in a row. A button's text can be a function (it's asked again on each refresh).
    function P.Buttons(list)
        local holder = CreateFrame("Frame", nil, body)
        local x, h = 0, 0
        local made = {}
        for i, spec in ipairs(list) do
            local text = type(spec.text) == "function" and spec.text() or spec.text
            local b = skin.Button(holder, { text = text, kind = spec.kind, click = spec.click, tip = spec.tip, width = spec.width })
            b:SetPoint("TOPLEFT", x, 0)
            x = x + b:GetWidth() + skin.colGap
            h = math.max(h, b:GetHeight())
            if type(spec.text) == "function" then
                OnRefresh(function() b:SetLabel(spec.text()) end)
            end
            Enabled(b, spec)
            made[i] = b
        end
        holder:SetSize(width, h)
        Put(holder)
        return unpack(made)
    end
    function P.Button(spec)
        return P.Buttons({ spec })
    end
    -- Text under the controls. Given as a function, it's asked again on each refresh (keep that
    -- to one line: the page is laid out once).
    function P.Note(text, big)
        local live = type(text) == "function"
        local note = Put(skin.Note(body, live and text() or text, width, big))
        if live then
            OnRefresh(function() note.text:SetText(text()) end)
        end
        return note
    end
    -- Anything a page draws itself (frame width: P.width).
    function P.Custom(frame, gap)
        return Put(frame, gap)
    end
    function P.Space(h)
        EndRow()
        y = y + h
    end
    function P.Y()
        EndRow()
        return y
    end
    function P.Finish()
        EndRow()
        page.scroll:SetContentHeight(y + skin.gap)
    end
    return P
end

local function NewPage(key)
    local f = building
    local shell = f.shell
    local page = CreateFrame("Frame", nil, shell.area)
    page:SetPoint("TOPLEFT")
    page:SetPoint("BOTTOMRIGHT")
    local scroll = Kit.Scroll(page, shell.areaWidth - 8)
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    page.body = scroll.child
    page.scroll = scroll
    local top = f.skin.Page(shell, page.body, ITEMS[key], API)
    page:Hide()
    f.pages[key] = page
    return Builder(f, page, top)
end

---------------------------------------------------------------------------------------------- broadcast page

local function BuildBroadcast()
    local P = NewPage("broadcast")
    P.Heading(L["Go live"])
    P.Custom(P.skin.Live(P.body, P.width, API, P.OnRefresh), 24)

    P.Heading(L["What viewers see"], L["Real names are never shown here, so it's safe to open the console on stream."])
    P.Custom(P.skin.Table(P.body, P.width, {
        { icon = "Me", text = L["You"], value = function() return Names.MyAlias() end },
        { icon = "Group", text = L["Party member"], value = function() return Names.Sample("crew", 1, "crew:a") end },
        { icon = "Group", text = L["Party member"], value = function() return Names.Sample("crew", 2, "crew:b") end },
        { icon = "Social", text = L["Stranger"], value = function() return Names.Sample("others", 1, "other:a") end },
        { icon = "Guild", text = L["Your guild"], value = function() return Names.Fill(OA.db.guildAlias, 0) end },
        { icon = "Pet", text = L["Your pet"], value = function()
            return (OA.db.petTemplate:gsub("{owner}", function() return Names.MyAlias() end))
        end },
    }, P.OnRefresh), 24)

    P.Heading(L["On screen"])
    P.Toggle({ icon = "Overhead", title = L["Go-live banner"], help = L["A short banner when you go live or end."],
        get = function() return OA.db.toast end, set = function(v) OA.db.toast = v end })
    P.Toggle({ icon = "World", title = L["Minimap button"], help = L["Left-click: go live or end. Right-click: console."],
        get = function() return OA.db.minimap.show end, set = function(v) OA.db.minimap.show = v end })
    P.Finish()
end

---------------------------------------------------------------------------------------------- names page

local MODES = {
    { value = "cast", text = L["Cast names"] },
    { value = "template", text = L["Template"] },
}

local function GroupControls(P, group, title, hint)
    P.Choice({ label = title, hint = hint, options = MODES,
        get = function() return group.mode end, set = Save(function(v) group.mode = v end) })
    P.Input({ get = function() return group.template end,
        set = Save(function(v) if v ~= "" then group.template = v end end),
        enabled = function() return group.mode == "template" end })
end

local function BuildNames()
    local P = NewPage("names")
    local db = OA.db

    P.Input({ label = L["Your stage name"], hint = L["Replaces your name everywhere: frames, chat, meters, tooltips."],
        get = function() return db.me end, set = Save(function(v) if v ~= "" then db.me = v end end),
        action = { icon = "Dice", title = L["Suggest a name"], help = L["A random stage name from the theme."], click = function()
            db.me = OA.Cast.SuggestStage(db.theme, db.me)
            OA.NamesChanged(false)
        end } })

    local themes = {}
    for _, theme in ipairs(OA.Cast.THEMES) do
        themes[#themes + 1] = { value = theme.key, text = theme.name }
    end
    P.Choice({ label = L["Theme"], hint = L["Where cast names come from."], options = themes,
        get = function() return db.theme end,
        set = function(v)
            db.theme = v
            OA.NamesChanged(true)
        end })

    GroupControls(P, db.crew, L["Crew: party & raid"], L["Tokens: {me} your stage name, {n} a number, {role} tank/healer/DPS, {class} their class."])
    GroupControls(P, db.others, L["Everyone else"], L["Strangers, guildmates, friends, people in lists and chat."])

    P.Fields({ label = L["Guild & pets"], hint = L["Your guild's name, other guilds ({n} counts them), and pets ({owner} is their owner's alias)."], items = {
        { label = L["Your guild"], get = function() return db.guildAlias end, set = Save(function(v) if v ~= "" then db.guildAlias = v end end) },
        { label = L["Other guilds"], get = function() return db.otherGuild end, set = Save(function(v) if v ~= "" then db.otherGuild = v end end) },
        { label = L["Pets"], get = function() return db.petTemplate end, set = Save(function(v) if v ~= "" then db.petTemplate = v end end) },
    } })

    local npc = db.npc
    local function NpcChanged()
        if OA.live then
            OA.Hide.RestoreCVars()
            OA.Hide.ApplyCVars()
            OA.Hide.AllNamePlates()
            OA.Hide.UnitFrames()
        end
        UI.Refresh()
    end
    local function Generic()
        return npc.mode == "generic"
    end
    P.Choice({ label = L["NPC names"], hint = L["Real names, a generic label, or nothing: on nameplates, target frames, tooltips and chat. Names above heads are drawn by the game, so Generic and Hidden switch those off (also with the UI hidden)."],
        options = {
            { value = "real", text = L["Real names"] },
            { value = "generic", text = L["Generic"] },
            { value = "hide", text = L["Hidden"] },
        },
        get = function() return npc.mode end,
        set = function(v)
            npc.mode = v
            NpcChanged()
        end })
    P.Fields({ items = {
        { label = L["Enemies"], enabled = Generic, get = function() return npc.enemy end, set = function(v) if v ~= "" then npc.enemy = v; NpcChanged() end end },
        { label = L["Friendly NPCs"], enabled = Generic, get = function() return npc.friendly end, set = function(v) if v ~= "" then npc.friendly = v; NpcChanged() end end },
        { label = L["Bosses"], enabled = Generic, get = function() return npc.boss end, set = function(v) if v ~= "" then npc.boss = v; NpcChanged() end end },
    } })

    P.Heading(L["Start over"], L["Everyone draws a new alias. Names you set on the Custom page stay."])
    P.Button({ text = L["Reshuffle everyone"], click = function()
        OA.NamesChanged(true)
        Utils.Print(L["Everyone drew a new name."])
    end })
    P.Finish()
end

---------------------------------------------------------------------------------------------- hide page

-- The blank name font: what a switch does, said in chat, and where it stands, on the page. The
-- game only takes a change at the next login.
local BLANK_SAYS = {
    ["on-next"] = L["Blank name font on. Names above heads go away after you log out and back in (or restart the game). /reload is not enough."],
    ["on"] = L["Blank name font on. Names above heads stay hidden."],
    ["off-next"] = L["Blank name font off. Names above heads stay hidden until you log out and back in (or restart the game)."],
    ["off"] = L["Blank name font off. Names above heads show as usual."],
}
local BLANK_NOW = {
    ["on-next"] = L["Now: names still show. Log out and back in to hide them."],
    ["on"] = L["Now: on. No names above heads."],
    ["off-next"] = L["Now: names still hidden. Log out and back in to bring them back."],
    ["off"] = L["Now: off. Names above heads show as usual."],
}

local function BuildHide()
    local P = NewPage("hide")
    local db = OA.db

    local function CVars()
        OA.Hide.RestoreCVars()
        OA.Hide.ApplyCVars()
    end
    local function Group(specs, root)
        for _, spec in ipairs(specs) do
            P.Toggle({ icon = spec[1], title = spec[2], help = spec[3],
                get = function() return root[spec[4]] ~= false end,
                set = function(v)
                    root[spec[4]] = v
                    OA.NamesChanged(false)
                    if OA.live and spec[5] then
                        spec[5]()
                    end
                end })
        end
    end

    P.Heading(L["Whose names"])
    Group({
        { "Me", L["Your name"], L["Every character you play."], "me", CVars },
        { "Group", L["Party & raid"], L["Your crew while grouped."], "crew", CVars },
        { "Social", L["Everyone else"], L["Strangers, guild, lists."], "others", CVars },
        { "BNet", L["Battle.net friends"], L["Real names and BattleTags."], "friends" },
        { "Guild", L["Guild names"], L["Yours and everyone's."], "guilds" },
        { "Pet", L["Pets & minions"], L["They carry their owner's name."], "pets", CVars },
    }, db.who)

    P.Heading(L["Where"])
    Group({
        { "Chat", L["Chat"], L["Senders, names in messages, whispers."], "chat" },
        { "Trash", L["Clear chat on go live"], L["Wipes old lines with real names."], "clearChat" },
        { "Nameplate", L["Nameplates & overhead"], L["Plates and names above heads."], "nameplates", CVars },
        { "Tooltip", L["Tooltips"], L["Unit tooltips, guild lines, lists."], "tooltips" },
        { "Meter", L["Damage meters"], L["Blizzard's and EllesmereUI's, also in combat."], "meters" },
        { "UnitFrame", L["Interface text"], L["Unit & raid frames, character, friends, guild, LFG, mail."], "interface" },
    }, db.where)

    P.Note(L["Changes apply right away, also while live. Ending the broadcast brings every real name back, no reload needed. Chat lines written while live keep their aliases."])

    -- The one switch that waits for a logout.
    P.Heading(L["Names above heads"], L["The game draws these itself. Addons can't change that text, only its font, and the game reads the font only when you log in."])
    P.Toggle({ icon = "Overhead", title = L["Blank name font"], help = L["No names above any head. Needs a logout."],
        get = function() return db.blankNames == true end,
        set = function(v)
            db.blankNames = v
            Utils.Print(BLANK_SAYS[OA.Hide.BlankFontState()])
        end })
    P.Note(function() return BLANK_NOW[OA.Hide.BlankFontState()] end, true)
    P.Note(L["Hides every name the game draws above heads: players, pets, NPCs and yours, live or not. Nameplates still show, with aliases while live: to see NPC names, turn on friendly NPC nameplates (in the game's options or your nameplate addon). After you switch it on or off: type /logout and log back in, or restart the game. /reload is not enough, and until then nothing changes. This is a limit of the game engine, not of OnAir."])
    P.Finish()
end

---------------------------------------------------------------------------------------------- stream chat page

local function BuildStream()
    local P = NewPage("stream")
    local Stream = OA.StreamChat
    local db = OA.db.stream

    P.Toggle({ icon = "Chat", title = L["Use stream chat while live"], help = L["Off: your normal chat stays in view (names still hidden)."],
        get = function() return db.enabled end,
        set = function(v)
            db.enabled = v
            Stream.Update()
        end })

    P.Heading(L["Show in stream chat"])
    for _, group in ipairs(Stream.GROUPS) do
        P.Toggle({ icon = group.icon, title = group.text, help = group.help,
            get = function() return db.groups[group.key] == true end,
            set = function(v)
                db.groups[group.key] = v or nil
                Stream.Update()
            end })
    end

    P.Heading(L["Look"])
    P.Slider({ label = L["Text size"], min = 10, max = 22, step = 1,
        get = function() return db.fontSize end,
        set = function(v)
            db.fontSize = v
            Stream.ApplyLook()
        end })
    P.Slider({ label = L["Background"], min = 0, max = 1, step = 0.05,
        get = function() return db.opacity end,
        set = function(v)
            db.opacity = v
            Stream.ApplyLook()
        end,
        format = function(v) return string.format("%d%%", v * 100) end })
    P.Toggle({ icon = "Trash", title = L["Fade old lines"], help = L["Lines fade out after a minute."],
        get = function() return db.fade ~= false end,
        set = function(v)
            db.fade = v
            Stream.ApplyLook()
        end })
    P.Toggle({ icon = "Live", title = L["Title bar"], help = L["The bar on top of the window (drag it to move)."],
        get = function() return db.header ~= false end,
        set = function(v)
            db.header = v
            Stream.ApplyLook()
        end })

    P.Buttons({
        { text = function() return Stream.IsPlacing() and L["Done placing"] or L["Place the window"] end, click = function()
            Stream.TogglePlacing()
            UI.Refresh()
        end },
        { text = L["Back over my chat"], click = function() Stream.ResetPosition() end },
    })
    P.Finish()
end

---------------------------------------------------------------------------------------------- moments page

local function BuildMoments()
    local P = NewPage("moments")
    local f = building
    local skin, body = P.skin, P.body
    local Moments = OA.Moments
    local db = OA.db.moments
    local shown -- the session on screen (index); nil = the latest

    P.Heading(L["Session clock"])
    local clockRow = CreateFrame("Frame", nil, body)
    clockRow:SetSize(P.width, 44)
    P.Custom(clockRow, 10)
    local clock = skin.Readout(clockRow, 32)
    clock:SetPoint("LEFT")
    local mark = skin.Button(clockRow, { text = L["Mark moment"], kind = "primary", width = 150, click = function() Moments.Mark() end })
    mark:SetPoint("LEFT", 200, 0)
    local restart = skin.Button(clockRow, { text = L["Restart clock"], width = 130, click = function() Moments.Restart() end })
    restart:SetPoint("LEFT", mark, "RIGHT", skin.colGap, 0)
    local acc = 0
    clockRow:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            clock:SetText(OA.live and Moments.Format(Moments.Elapsed(), true) or "-:--:--")
            clock:SetTextColor(unpack(OA.live and C.text or C.faint))
        end
    end)
    P.Note(L["Tip: bind the same key to OnAir > Mark a moment and to OBS's replay buffer (Save replay). One press gives you a clip and a timecode."])

    P.Heading(L["Mark automatically"])
    for _, group in ipairs(Moments.AUTO) do
        P.Toggle({ icon = group.icon, title = group.text, help = group.help,
            get = function() return db.auto[group.key] ~= false end,
            set = function(v) db.auto[group.key] = v end })
    end
    P.Toggle({ icon = "Camera", title = L["Screenshot each moment"], help = L["Saved in your Screenshots folder: thumbnails."],
        get = function() return db.screenshot == true end, set = function(v) db.screenshot = v end })
    P.Toggle({ icon = "Clapper", title = L["Slate at 00:00"], help = L["A short card when you go live, so the video shows 00:00."],
        get = function() return db.flash ~= false end, set = function(v) db.flash = v end })
    P.Toggle({ icon = "Chat", title = L["Moments in stream chat"], help = L["A line with the timecode as it happens."],
        get = function() return db.note ~= false end, set = function(v) db.note = v end })

    -- The sessions, newest first; older ones stay for exporting later.
    P.Heading(L["Sessions"])
    local picker = CreateFrame("Frame", nil, body)
    picker:SetSize(P.width, 30)
    P.Custom(picker, 10)
    local prev = Kit.IconButton(picker, "Chevron", 28, L["Older session"])
    prev.icon:SetRotation(math.rad(-90))
    prev:SetPoint("LEFT")
    local sessionText = skin.Label(picker, 13, C.text)
    sessionText:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    local nextB = Kit.IconButton(picker, "Chevron", 28, L["Newer session"])
    nextB.icon:SetRotation(math.rad(90))
    nextB:SetPoint("LEFT", 270, 0)
    local list = skin.Button(picker, { text = L["Marker list"], width = 120 })
    list:SetPoint("RIGHT")
    local chapters = skin.Button(picker, { text = L["YouTube chapters"], width = 140 })
    chapters:SetPoint("RIGHT", list, "LEFT", -skin.colGap, 0)

    local listTop = P.Y()
    local listFrame = CreateFrame("Frame", nil, body)
    listFrame:SetSize(P.width, 10)
    listFrame:SetPoint("TOPLEFT", body, "TOPLEFT", f.shell.pad, -listTop)
    local empty = skin.Label(listFrame, 13, C.faint)
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetText(L["No moments yet. Go live, and they show up here as they happen."])
    local rows = {}
    local ROW_H = 26
    local MAX_ROWS = 60

    local function Session()
        local sessions = Moments.Sessions()
        local index = shown or #sessions
        return sessions[index], index, #sessions
    end

    local function Render()
        local session, index, total = Session()
        if session then
            sessionText:SetText(string.format(L["Session %d of %d  -  %s"], index, total, date("%d %b %H:%M", session.started)))
        else
            sessionText:SetText(L["No sessions yet"])
        end
        prev:SetEnabled(index > 1)
        prev:SetAlpha(index > 1 and 1 or 0.3)
        nextB:SetEnabled(index < total)
        nextB:SetAlpha(index < total and 1 or 0.3)
        local moments = session and session.moments or {}
        local first = math.max(1, #moments - MAX_ROWS + 1)
        local n = 0
        for i = #moments, first, -1 do
            n = n + 1
            local moment = moments[i]
            local row = rows[n]
            if not row then
                row = skin.ListRow(listFrame, P.width, ROW_H - 2, n)
                row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H)
                row.time = skin.Readout(row, 13)
                row.time:SetPoint("LEFT", 10, 0)
                row.icon = Kit.Icon(row, "Flag", 14, C.text)
                row.icon:SetPoint("LEFT", 92, 0)
                row.text = skin.Label(row, 13, C.text)
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
                row.text:SetPoint("RIGHT", -10, 0)
                rows[n] = row
            end
            local kind = Moments.KINDS[moment.kind] or Moments.KINDS.mark
            row.time:SetText(Moments.Format(moment.t, true))
            row.icon:SetTexture(Utils.ICONS .. kind.icon)
            row.icon:SetVertexColor(unpack(kind.color))
            row.text:SetText(moment.text)
            row:Show()
        end
        for i = n + 1, #rows do
            rows[i]:Hide()
        end
        empty:SetShown(n == 0)
        local h = math.max(30, n * ROW_H)
        listFrame:SetHeight(h)
        f.pages.moments.scroll:SetContentHeight(listTop + h + 24)
    end
    f.renderMoments = Render

    prev:SetScript("OnClick", function()
        local _, index = Session()
        shown = math.max(1, index - 1)
        Render()
    end)
    nextB:SetScript("OnClick", function()
        local _, index, total = Session()
        shown = (index + 1 >= total) and nil or index + 1
        Render()
    end)
    chapters:SetScript("OnClick", function()
        local session = Session()
        if session then
            Moments.ShowExport(L["YouTube chapters"], Moments.Chapters(session))
        end
    end)
    list:SetScript("OnClick", function()
        local session = Session()
        if session then
            Moments.ShowExport(L["Marker list"], Moments.MarkerList(session))
        end
    end)

    P.OnRefresh(function()
        Render()
        mark.oaAlpha = (OA.live and not OA.rehearsal) and 1 or 0.4
        mark:SetAlpha(mark.oaAlpha)
    end)
end

function UI.RefreshMoments()
    if face and face.renderMoments and console and console:IsShown() and current == "moments" then
        face.renderMoments()
    end
end

---------------------------------------------------------------------------------------------- shield page

local function BuildShield()
    local P = NewPage("shield")
    local db = OA.db.shield

    local function T(icon, title, help, key, after)
        P.Toggle({ icon = icon, title = title, help = help,
            get = function() return db[key] == true end,
            set = function(v)
                db[key] = v
                if after then
                    after()
                end
            end })
    end
    local function Apply()
        OA.Shield.Apply()
    end

    P.Heading(L["Strangers"])
    T("BNet", L["Hold stranger whispers"], L["Shown in chat when the broadcast ends."], "whispers")
    T("Chat", L["Polite auto-reply"], L["Once per player per 15 minutes."], "reply")
    T("Group", L["Decline group invites"], L["From players you don't know."], "invites")
    T("Social", L["Decline duels"], L["From players you don't know."], "duels")
    T("Plus", L["Decline trades"], L["From players you don't know."], "trades")

    P.Input({ label = L["Auto-reply text"], max = 240,
        get = function() return db.replyText end,
        set = function(v) if v ~= "" then db.replyText = v end end })

    P.Heading(L["Location"])
    T("World", L["Hide zone names"], L["Your zone reads Somewhere in all text."], "zones", Apply)
    T("Overhead", L["Hide zone banners"], L["The big zone name when you enter."], "banners", Apply)
    T("Nameplate", L["Hide the minimap"], L["Its map shows where you are."], "minimap", Apply)

    local held = P.Note("")
    P.OnRefresh(function()
        local count = OA.Shield.HeldCount()
        held.text:SetText(count > 0 and string.format(L["%d whispers held so far."], count) or L["No whispers held."])
    end)
    P.Note(L["An addon can't delay your stream: set a stream delay in OBS too. Auto-replies wait outside boss encounters, when the game blocks addon chat."])
    P.Finish()
end

---------------------------------------------------------------------------------------------- camera page

local function BuildCamera()
    local P = NewPage("camera")
    local Camera = OA.Camera
    local cam = OA.db.camera

    P.Choice({ label = L["When"], hint = L["Off leaves your camera alone. Always works without going live. While live switches with the broadcast. Your own camera settings come back when it turns off."],
        options = {
            { value = "off", text = L["Off"] },
            { value = "always", text = L["Always"] },
            { value = "live", text = L["Only while live"] },
        },
        get = function() return cam.mode end,
        set = function(v)
            cam.mode = v
            Camera.Update()
            UI.Refresh()
        end })

    local presets = {}
    for _, preset in ipairs(Camera.PRESETS) do
        presets[#presets + 1] = { value = preset.key, text = preset.text }
    end
    presets[#presets + 1] = { value = "custom", text = L["Custom"] }
    P.Choice({ label = L["Preset"], options = presets,
        get = function() return cam.preset end,
        set = function(v)
            if v ~= "custom" then
                Camera.UsePreset(v)
            end
            UI.Refresh()
        end })

    P.Heading(L["Fine tune"])
    for _, setting in ipairs(Camera.SETTINGS) do
        P.Slider({ label = setting.label, min = setting.min, max = setting.max, step = setting.step, format = setting.format,
            get = function() return Camera.Get(setting.key) end,
            set = function(v) Camera.Set(setting.key, v) end,
            enabled = function() return Camera.Exists(setting.cvar) end })
    end

    P.Choice({ label = L["Follow style"], hint = L["How the camera swings behind you while you move."], options = Camera.STYLES,
        get = function() return Camera.Get("style") end,
        set = function(v)
            cam.style = v
            cam.preset = "custom"
            Camera.Update()
            UI.Refresh()
        end })
    P.Toggle({ icon = "Overhead", title = L["Target focus"], help = L["The camera turns toward the enemy you target."],
        get = function() return cam.focus == true end,
        set = function(v)
            cam.focus = v
            cam.preset = "custom"
            Camera.Update()
        end })

    P.Heading(L["Orbit"], L["A slow turn around your character for intros and outros. Stops when combat starts. On the Deck: left click orbits left, right click orbits right, the same click again or a middle click stops. Key binding: OnAir > Camera orbit."])
    P.Choice({ label = L["Direction"], options = { { value = "left", text = L["Turn left"] }, { value = "right", text = L["Turn right"] } },
        get = function() return cam.orbitDir or "left" end,
        set = function(v)
            Camera.SetOrbitDirection(v)
            UI.Refresh()
        end })
    P.Slider({ label = L["Orbit speed"], min = 0.01, max = 1, step = 0.01,
        get = function() return cam.orbitSpeed or 0.1 end,
        set = function(v) Camera.SetOrbitSpeed(v) end,
        format = function(v) return string.format("%d%%", v * 100) end })
    cam.orbitStop = cam.orbitStop or { move = true, mouse = true }
    P.Toggle({ icon = "Orbit", title = L["Stop when I move"], help = L["Walking, jumping or turning ends the orbit."],
        get = function() return cam.orbitStop.move == true end, set = function(v) cam.orbitStop.move = v end })
    P.Toggle({ icon = "Camera", title = L["Stop when I grab the camera"], help = L["Turning the camera with the mouse ends the orbit."],
        get = function() return cam.orbitStop.mouse == true end, set = function(v) cam.orbitStop.mouse = v end })
    P.Buttons({
        { text = function() return Camera.IsOrbiting() and L["Stop orbit"] or L["Start orbit"] end, click = function() Camera.ToggleOrbit() end },
        { text = L["Back to game defaults"], width = 200, click = function()
            Camera.UsePreset("default")
            UI.Refresh()
        end },
    })
    P.Note(L["The game caps the field of view at 90 (its normal value), so it can only get narrower, for a film look. Shoulder offset, tilt and head movement are the game's action camera."])
    P.Finish()
end

---------------------------------------------------------------------------------------------- custom page

local function Mask(text)
    return text:sub(1, 1) .. string.rep("*", math.max(2, math.min(6, #text - 1)))
end

local function BuildCustom()
    local P = NewPage("custom")
    local f = building
    local skin = P.skin
    local db = OA.db
    local reveal = false
    local pendingReal, pendingAlias = "", ""

    P.Heading(L["Add a fixed alias"])
    local fields = P.Fields({ items = {
        { label = L["Real name"], live = true, get = function() return pendingReal end, set = function(v) pendingReal = v end },
        { label = L["Alias"], live = true, get = function() return pendingAlias end, set = function(v) pendingAlias = v end },
    } })
    P.Button({ text = L["Add"], kind = "primary", width = 120, click = function()
        if pendingReal ~= "" and pendingAlias ~= "" then
            db.custom[pendingReal] = pendingAlias
            pendingReal, pendingAlias = "", ""
            for _, input in ipairs(fields.inputs) do
                input.box:ClearFocus()
            end
            OA.NamesChanged(false)
        end
    end })
    P.Toggle({ icon = "Hide", title = L["Reveal real names"], help = L["Shows the real names in the list below. Off the air only, ideally."],
        get = function() return reveal end,
        set = function(v)
            reveal = v
            UI.Refresh()
        end })

    local listTop = P.Y()
    local list = CreateFrame("Frame", nil, P.body)
    list:SetSize(P.width, 10)
    list:SetPoint("TOPLEFT", P.body, "TOPLEFT", f.shell.pad, -listTop)
    local rows = {}
    local ROW_H = 32
    P.OnRefresh(function()
        local keys = {}
        for real in pairs(db.custom) do
            keys[#keys + 1] = real
        end
        table.sort(keys, function(a, b) return a:lower() < b:lower() end)
        for i, real in ipairs(keys) do
            local row = rows[i]
            if not row then
                row = skin.ListRow(list, P.width, ROW_H - 2, i)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                row.real = skin.Label(row, 13, C.muted)
                OA.Hide.Exempt(row.real)
                row.real:SetPoint("LEFT", 14, 0)
                row.real:SetWidth(180)
                local arrow = Kit.Icon(row, "Chevron", 12, C.faint)
                arrow:SetRotation(math.rad(90))
                arrow:SetPoint("LEFT", 200, 0)
                row.alias = skin.Label(row, 14, C.text)
                row.alias:SetPoint("LEFT", arrow, "RIGHT", 14, 0)
                row.remove = Kit.IconButton(row, "Trash", 26, L["Remove"])
                row.remove:SetPoint("RIGHT", -6, 0)
                rows[i] = row
            end
            row.real:SetText(reveal and real or Mask(real))
            row.alias:SetText(db.custom[real])
            row.remove:SetScript("OnClick", function()
                db.custom[real] = nil
                OA.NamesChanged(false)
            end)
            row:Show()
        end
        for i = #keys + 1, #rows do
            rows[i]:Hide()
        end
        local h = math.max(10, #keys * ROW_H)
        list:SetHeight(h)
        f.pages.custom.scroll:SetContentHeight(listTop + h + 24)
    end)
end

---------------------------------------------------------------------------------------------- about page

local function BuildAbout()
    local P = NewPage("about")
    local head = CreateFrame("Frame", nil, P.body)
    head:SetSize(P.width, 72)
    P.Custom(head, 20)
    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(Utils.MEDIA .. "Logo")
    logo:SetSize(72, 72)
    logo:SetPoint("LEFT")
    local name = P.skin.Label(head, 26, C.text)
    name:SetPoint("LEFT", logo, "RIGHT", 18, 10)
    name:SetText("On|cffff3b30Air|r")
    local tag = P.skin.Label(head, 13, C.muted)
    tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    tag:SetText(L["Streamer & recording mode for World of Warcraft."])

    P.Heading(L["Commands"])
    P.Note(L["/onair  open this console\n/onair live  go live\n/onair off  end the broadcast\n/onair mark [note]  mark a moment\n/onair orbit  camera orbit on / off\n/onair camera  the camera page\n/onair preview  preview on / off\n/onair layout  edit the layout\n/onair reshuffle  everyone draws a new name\n/onair check  look for real names still on screen\nKey bindings: Esc > Options > Keybindings > OnAir"], true)
    P.Heading(L["How it works"])
    P.Note(L["OnAir learns every player your UI can show (group, targets, nameplates, chat, friends, guild, communities, group finder, mail) and swaps their names for aliases in all text, including other addons'. Names you see stay the same every session."], true)
    P.Heading(L["What the game doesn't allow"])
    P.Note(L["In combat and in instances the game hides some names from addons. OnAir can't read those, so it hides that text instead (nameplates, meters, unit frames). Blizzard's friendly nameplates inside dungeons can't be touched by any addon: use overhead names off, or EllesmereUI's friendly plates. The combat log tab is not changed."], true)
    P.Finish()
end

---------------------------------------------------------------------------------------------- deck page

local function BuildDeck()
    local P = NewPage("deck")
    local Deck = OA.Deck
    local db = OA.db.deck

    P.Choice({ label = L["Show the Deck"], options = {
            { value = "always", text = L["Always"] },
            { value = "live", text = L["Only while live"] },
            { value = "never", text = L["Never"] },
        },
        get = function() return db.show end,
        set = function(v)
            db.show = v
            Deck.Refresh()
        end })
    P.Choice({ label = L["When you're not using it"], hint = L["Tuck works when the Deck sits on an edge: it slides away and leaves a small handle."],
        options = {
            { value = "never", text = L["Stay"] },
            { value = "fade", text = L["Fade"] },
            { value = "tuck", text = L["Tuck into the edge"] },
        },
        get = function() return db.hide end,
        set = function(v)
            db.hide = v
            Deck.Refresh()
        end })
    P.Toggle({ icon = "Live", title = L["Status on the tuck handle"],
        help = L["The small handle a tucked Deck leaves shows if you're live, in preview or off."],
        get = function() return db.tabStatus ~= false end,
        set = function(v)
            db.tabStatus = v
            Deck.Refresh()
        end })
    P.Slider({ label = L["Faded to"], min = 0, max = 1, step = 0.05,
        get = function() return db.fadeTo end, set = function(v) db.fadeTo = v end,
        format = function(v) return v <= 0 and L["Invisible"] or string.format("%d%%", v * 100) end })
    P.Slider({ label = L["After"], min = 1, max = 6, step = 0.5,
        get = function() return db.delay end, set = function(v) db.delay = v end,
        format = function(v) return string.format(L["%.1f s"], v) end })
    P.Slider({ label = L["Size"], min = 0.7, max = 1.6, step = 0.05,
        get = function() return db.scale end,
        set = function(v)
            db.scale = v
            Deck.Refresh()
        end,
        format = function(v) return string.format("%d%%", v * 100) end })
    P.Toggle({ icon = "Orbit", title = L["Quick panels"], help = L["Rest the mouse on a button for a second: orbit speed, camera preset, snapping and more, right there."],
        get = function() return db.panels ~= false end, set = function(v) db.panels = v end })

    P.Heading(L["Buttons"])
    for _, spec in ipairs(Deck.BUTTONS) do
        P.Toggle({ icon = spec.icon, title = spec.text, help = spec.tip(),
            get = function() return db.buttons[spec.key] ~= false end,
            set = function(v)
                db.buttons[spec.key] = v and nil or false
                Deck.Refresh()
            end })
    end
    P.Button({ text = L["Back to the top"], click = function() Deck.ResetPosition() end })
    P.Note(L["Key binding: OnAir > Hide / show the UI. The game doesn't let addons hide the UI in combat: Alt+Z still works there."])
    P.Finish()
end

---------------------------------------------------------------------------------------------- look page

-- A tiny sketch of a skin: its colors and the shape of its console.
local function Sketch(card, t)
    local function Col(name, a)
        local c = Kit.ThemeColor(t, name)
        return { c[1], c[2], c[3], a or 1 }
    end
    local box = CreateFrame("Frame", nil, card)
    box:SetSize(120, 74)
    box:SetPoint("LEFT", 12, 0)
    local bg = Kit.Rect(box, Col("bg"), "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(box, Col("line"))
    local skin = Kit.SKINS[t.key]
    if skin and skin.Sketch then
        skin.Sketch(box, Col)
    end
    return box
end

local LOOKS = {
    viewfinder = { L["Viewfinder"], L["A camera screen: a REC readout on top, a menu of rows you step through, tick scales, corner brackets."] },
    mixer = { L["Vision mixer"], L["A broadcast desk: Program and Preview keys, a timecode display, lit keys and faders."] },
    slate = { L["Film slate"], L["A clapperboard: chalk cells for production, scene and take, clapper stripes, film-strip edges."] },
    studio = { L["Studio"], L["The plain dark console: tiles, switches and one red light."] },
}

local function BuildLook()
    local P = NewPage("look")
    P.Heading(L["Skin"], L["Switches right away. Everything you set stays the same in every skin."])
    local CARD_H = 98
    local cardW = (P.width - P.skin.colGap) / 2
    local cards = {}
    local grid = CreateFrame("Frame", nil, P.body)
    local rowsN = math.ceil(#Kit.THEMES / 2)
    grid:SetSize(P.width, rowsN * (CARD_H + P.skin.colGap))
    P.Custom(grid)
    for i, t in ipairs(Kit.THEMES) do
        local info = LOOKS[t.key]
        local card = CreateFrame("Button", nil, grid)
        card:SetSize(cardW, CARD_H)
        card:SetPoint("TOPLEFT", ((i - 1) % 2) * (cardW + P.skin.colGap), -math.floor((i - 1) / 2) * (CARD_H + P.skin.colGap))
        local bg = Kit.Rect(card, C.card, "BACKGROUND")
        bg:SetAllPoints()
        card.edges = Kit.Border(card)
        Sketch(card, t)
        local name = P.skin.Label(card, 15, C.text)
        name:SetPoint("TOPLEFT", 144, -14)
        name:SetText(info[1])
        local desc = P.skin.Label(card, 11, C.muted)
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        desc:SetWordWrap(true)
        desc:SetMaxLines(4)
        desc:SetText(info[2])
        card.badge = P.skin.Label(card, 10, C.accent)
        card.badge:SetPoint("BOTTOMRIGHT", -10, 8)
        card:SetScript("OnEnter", function() bg:SetColorTexture(unpack(C.raised)) end)
        card:SetScript("OnLeave", function() bg:SetColorTexture(unpack(C.card)) end)
        card:SetScript("OnClick", function()
            UI.SetSkin(t.key)
        end)
        card.key = t.key
        cards[#cards + 1] = card
    end
    P.Finish()

    P.OnRefresh(function()
        local active = Kit.Theme().key
        for _, card in ipairs(cards) do
            local on = card.key == active
            Kit.SetBorderColor(card.edges, on and C.accent or C.line)
            card.badge:SetText(on and L["IN USE"] or "")
        end
    end)
end

---------------------------------------------------------------------------------------------- layout page

local function BuildLayout()
    local P = NewPage("layout")
    local Layout = OA.Layout
    local o = Layout.Options()

    P.Heading(L["Edit layout"], L["A grid over the screen: drag the stream chat and the Deck where you want them. The console comes back when you're done. Also on the Deck and /onair layout."])
    P.Button({ text = function() return Layout.IsEditing() and L["Done"] or L["Edit layout"] end, kind = "primary",
        click = function() Layout.Toggle() end })

    P.Choice({ label = L["Snapping"], hint = L["Free: pieces go exactly where you drop them. Guides: any side or the middle of a piece sticks to the screen's center lines and edges and to the other pieces. Grid: the grid lines too. Hold Shift while dragging to place freely."],
        options = {
            { value = "free", text = L["Free"] },
            { value = "guides", text = L["Guides"] },
            { value = "grid", text = L["Grid"] },
        },
        get = function() return o.snap end, set = function(v) Layout.SetOption("snap", v) end })
    local sizes = {}
    for _, size in ipairs(Layout.GRID_SIZES) do
        sizes[#sizes + 1] = { value = size, text = string.format(L["%d px"], size) }
    end
    P.Choice({ label = L["Grid size"], hint = L["In UI pixels. Used by Grid snapping; the grid shows in every mode."], options = sizes,
        get = function() return o.grid end, set = function(v) Layout.SetOption("grid", v) end })

    P.Toggle({ icon = "UnitFrame", title = L["Game frames"], help = L["Line up with the game's frames too: unit frames, minimap, chat, action bars, quest tracker."],
        get = function() return o.ui == true end, set = function(v) Layout.SetOption("ui", v) end })
    P.Toggle({ icon = "Shield", title = L["Lock positions"], help = L["The stream chat and the Deck can't be dragged (edit layout still moves them)."],
        get = function() return Layout.Locked() end, set = function(v) Layout.SetOption("locked", v) end })

    P.Heading(L["Put back"])
    P.Buttons({
        { text = L["Stream chat"], click = function() OA.StreamChat.ResetPosition() end },
        { text = L["Deck"], click = function() OA.Deck.ResetPosition() end },
    })
    P.Finish()
end

---------------------------------------------------------------------------------------------- window

local function Stagger(page)
    local kids = { page.body:GetChildren() }
    for i = 1, math.min(#kids, 40) do
        local kid = kids[i]
        local target = kid.oaAlpha or 1
        kid:SetAlpha(0)
        Kit.Tween(kid, 0, target, 0.32, function(a) kid:SetAlpha(a) end, "out", 0.05 + i * 0.022)
    end
end

function UI.ShowPage(key, animate)
    if not console then
        current = key
        return
    end
    local pages = face.pages
    if not pages[key] then
        key = "broadcast"
    end
    local old = pages[current]
    current = key
    for k, page in pairs(pages) do
        if k == key then
            page:Show()
        elseif animate and page == old and old:IsShown() then
            Kit.Tween(old, old:GetAlpha(), 0, 0.1, function(a)
                old:SetAlpha(a)
                if a <= 0 and current ~= k then
                    old:Hide()
                end
            end)
        else
            page:Hide()
        end
    end
    face.shell.Select(key, animate)
    local page = pages[key]
    if animate then
        page:SetAlpha(0)
        Kit.Tween(page, 0, 1, 0.36, function(p)
            page:SetAlpha(p)
            page:SetPoint("TOPLEFT", 28 * (1 - p), 0)
        end, "quint", 0.06)
        Stagger(page)
    else
        page:SetAlpha(1)
        page:SetPoint("TOPLEFT", 0, 0)
    end
end

local PAGES = { BuildBroadcast, BuildStream, BuildMoments, BuildNames, BuildHide, BuildCustom, BuildShield,
    BuildCamera, BuildDeck, BuildLook, BuildLayout, BuildAbout }

local function BuildFace(key)
    local skin = Kit.SKINS[key] or Kit.SKINS.studio
    local frame = CreateFrame("Frame", nil, console)
    frame:SetAllPoints()
    local new = { key = key, frame = frame, skin = skin, refreshers = {}, pages = {} }
    building = new
    new.shell = skin.Shell(frame, API, function(fn) new.refreshers[#new.refreshers + 1] = fn end)
    for _, build in ipairs(PAGES) do
        build()
    end
    building = nil
    frame:Hide()
    return new
end

-- Puts the active skin's face in the window (building it the first time).
local function UseFace(animate)
    local key = Kit.Theme().key
    faces[key] = faces[key] or BuildFace(key)
    local new = faces[key]
    if face and face ~= new then
        face.frame:Hide()
    end
    face = new
    face.frame:Show()
    UI.ShowPage(current or "broadcast", false)
    UI.Refresh()
    if animate then
        face.frame:SetAlpha(0)
        Kit.Tween(face.frame, 0, 1, 0.3, function(p) face.frame:SetAlpha(p) end, "quint")
    else
        face.frame:SetAlpha(1)
    end
end

local function Build()
    console = CreateFrame("Frame", "OnAirConsole", UIParent)
    console:SetSize(W, H)
    console:SetFrameStrata("HIGH")
    console:SetToplevel(true)
    console:SetClampedToScreen(true)
    console:SetMovable(true)
    console:EnableMouse(true)
    local pos = OA.db.window
    if pos and pos.point then
        console:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        console:SetPoint("CENTER")
    end
    tinsert(UISpecialFrames, "OnAirConsole")
    console:Hide()
end

-- Another skin, right away: the console, the Deck, the stream chat and the rest follow.
function UI.SetSkin(key)
    if key == Kit.Theme().key then
        return
    end
    OA.db.look = key
    Kit.SetSkin(key)
    if console then
        UseFace(console:IsShown())
    end
    UI.Refresh()
end

-- Opens with a soft rise and a slight pop; closes with a quick fade.
function UI.ShowConsole()
    if not console then
        Build()
    end
    UseFace(false)
    console:Show()
    console:SetAlpha(0)
    Kit.Tween(console, 0, 1, 0.34, function(p)
        console:SetAlpha(math.min(1, p))
        console:SetScale(0.96 + 0.04 * p)
    end, "back")
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
end

function UI.HideConsole()
    if console and console:IsShown() then
        Kit.Tween(console, console:GetAlpha(), 0, 0.14, function(p)
            console:SetAlpha(p)
            console:SetScale(0.98 + 0.02 * p)
            if p <= 0 then
                console:Hide()
                console:SetScale(1)
            end
        end)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    end
end

function UI.ToggleConsole()
    if console and console:IsShown() and console:GetAlpha() > 0.5 then
        UI.HideConsole()
    else
        UI.ShowConsole()
    end
end

function UI.OnLiveChanged()
    UI.Refresh()
end

function UI.Init()
    if UI.InitExtras then
        UI.InitExtras()
    end
end

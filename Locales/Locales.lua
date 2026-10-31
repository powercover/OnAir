local _, OA = ...

-- Translations. The addon's text is written in English and looked up through OA.L: L["Go live"]
-- is the chosen language's text, or the English itself when there's no translation yet. The first
-- release is English only; other languages come in later versions.
local active = {}

OA.L = setmetatable({}, {
    __index = function(_, text)
        return active[text] or text
    end,
})

OA.Locale = {}

-- A language file calls this with its table of English text -> translation.
function OA.Locale.Add(code, translations)
    if code == (GetLocale and GetLocale()) then
        for english, translated in pairs(translations) do
            active[english] = translated
        end
    end
end

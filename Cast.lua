local _, OA = ...

-- The cast lists: the names OnAir hands out in "Cast" mode. Each player gets the same name every
-- session (picked by a hash of their name, then kept). Stage names are the dice suggestions for
-- your own name.
OA.Cast = {}

local Cast = OA.Cast
local L = OA.L

Cast.THEMES = {
    {
        key = "film",
        name = L["Film set"],
        stage = { L["The Star"], L["The Director"], L["Main Character"], L["The Headliner"],
            L["Leading Role"], L["The Narrator"], L["Showrunner"], L["The Legend"] },
        cast = {
            L["Boom Mic"], L["Key Grip"], L["Best Boy"], L["Stunt Double"], L["Gaffer"],
            L["Clapper Loader"], L["Dolly Grip"], L["Body Double"], L["Stand-In"], L["Craft Services"],
            L["Location Scout"], L["Foley Artist"], L["Runner"], L["Intern"], L["Camera B"],
            L["Focus Puller"], L["Makeup Artist"], L["Wardrobe"], L["Set Dresser"], L["Prop Master"],
            L["Sound Mixer"], L["Colorist"], L["Film Editor"], L["Casting Agent"], L["Talent Scout"],
            L["Understudy"], L["Background Actor"], L["Voice Double"], L["Cue Card"], L["Spotlight"],
            L["Steadicam"], L["Drone Pilot"], L["Clapperboard"], L["Floor Manager"], L["Megaphone"],
            L["Green Screen"], L["B-Roll"], L["Blooper"], L["Cameo"], L["Producer"],
            L["Critic"], L["Paparazzi"], L["Fan Club"], L["Popcorn"], L["Ticket Stub"],
            L["Red Carpet"], L["Rough Cut"], L["Plot Twist"], L["Sequel"], L["Spoiler"],
            L["End Credits"], L["Trailer"], L["Script Doctor"], L["Extra"], L["Hair & Makeup"],
            L["Catering"], L["Second Unit"], L["Night Shoot"], L["Slow Motion"], L["Director's Cut"],
        },
    },
    {
        key = "pirates",
        name = L["Pirate crew"],
        stage = { L["The Captain"], L["Dread Captain"], L["The Admiral"], L["Sea Legend"] },
        cast = {
            L["Powder Monkey"], L["Bilge Rat"], L["Deckhand"], L["First Mate"], L["Quartermaster"],
            L["Boatswain"], L["Cabin Boy"], L["Lookout"], L["Navigator"], L["Master Gunner"],
            L["Ship's Cook"], L["Swabbie"], L["Parrot"], L["Barnacle"], L["Sea Dog"],
            L["Landlubber"], L["Scallywag"], L["Buccaneer"], L["Corsair"], L["Stowaway"],
            L["Anchor"], L["Crow's Nest"], L["Rum Barrel"], L["Cannonball"], L["Plank Walker"],
            L["Old Salt"], L["Peg Leg"], L["Hook Hand"], L["Jolly Roger"], L["Kraken Bait"],
            L["Treasure Map"], L["Message in a Bottle"], L["Shipwright"], L["Sail Mender"], L["Rope Monkey"],
            L["Deck Mop"], L["Bosun's Mate"], L["Ship's Cat"], L["Grog Keeper"], L["Spyglass"],
        },
    },
    {
        key = "court",
        name = L["Royal court"],
        stage = { L["The Monarch"], L["Their Majesty"], L["The Crown"], L["High Ruler"] },
        cast = {
            L["Court Jester"], L["Squire"], L["Herald"], L["Royal Page"], L["Falconer"],
            L["Royal Taster"], L["Court Bard"], L["Stable Hand"], L["Blacksmith"], L["Archer"],
            L["Alchemist"], L["Scribe"], L["Minstrel"], L["Gatekeeper"], L["Knight Errant"],
            L["Town Crier"], L["Chamberlain"], L["Cupbearer"], L["Court Wizard"], L["Hermit"],
            L["Oracle"], L["Peasant"], L["Baron"], L["Duke of Nothing"], L["Royal Cook"],
            L["Dungeon Keeper"], L["Tax Collector"], L["Castle Guard"], L["Torch Bearer"], L["Mapmaker"],
        },
    },
    {
        key = "critters",
        name = L["Critters"],
        stage = { L["Top Dog"], L["Big Cheese"], L["Head Honk"], L["Alpha Otter"] },
        -- Built below from adjectives and animals: hundreds of names.
        adjectives = { L["Sleepy"], L["Grumpy"], L["Brave"], L["Fluffy"], L["Sneaky"], L["Tiny"],
            L["Mighty"], L["Lucky"], L["Dizzy"], L["Fancy"], L["Silly"], L["Shy"], L["Jolly"], L["Zippy"],
            L["Wobbly"], L["Crispy"], L["Cozy"], L["Spicy"], L["Bouncy"], L["Hungry"] },
        animals = { L["Otter"], L["Badger"], L["Hamster"], L["Penguin"], L["Llama"], L["Gecko"],
            L["Hedgehog"], L["Moose"], L["Panda"], L["Raccoon"], L["Ferret"], L["Goose"], L["Walrus"],
            L["Capybara"], L["Axolotl"], L["Platypus"], L["Narwhal"], L["Sloth"], L["Puffin"], L["Wombat"] },
    },
}

local byKey = {}
for _, theme in ipairs(Cast.THEMES) do
    byKey[theme.key] = theme
    if not theme.cast then
        theme.cast = {}
        for _, adjective in ipairs(theme.adjectives) do
            for _, animal in ipairs(theme.animals) do
                theme.cast[#theme.cast + 1] = adjective .. " " .. animal
            end
        end
    end
end

function Cast.Get(key)
    return byKey[key] or byKey.film
end

-- A random stage name from the theme, not the current one.
function Cast.SuggestStage(key, current)
    local list = Cast.Get(key).stage
    for _ = 1, 8 do
        local pick = list[math.random(#list)]
        if pick ~= current then
            return pick
        end
    end
    return list[1]
end

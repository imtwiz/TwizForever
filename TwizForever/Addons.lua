-- What the TwizForever menu knows about each Twiz addon: its slash command, its settings (read
-- straight from its saved settings, changed through its own slash command so it reacts at once)
-- and a few one-click actions.
local _, NS = ...

local function T(v) return v and true or false end
local function NotFalse(v) return v ~= false end
local function onoff(cmd) return function(on) return cmd .. (on and " on" or " off") end end
local function flip(cmd) return function() return cmd end end

NS.ADDONS = {
    {
        name = "TwizAH", slash = "DEPOSITWISE", cmd = "/dw", icon = "Interface\\Icons\\INV_Misc_Coin_01",
        blurb = "Auction House profit tool: what to post, for how long and at what price, when to vendor instead, deals, undercut watch, craft-or-sell and AH mail collection.",
        db = function() return DepositWiseDB and DepositWiseDB.settings end,
        settings = {
            { "Scan your bags when the AH opens", function(d) return NotFalse(d.autoScanBags) end, onoff("autoscan") },
            { "Automatic full AH scans", function(d) return NotFalse(d.autoFullScan) end, onoff("autofull") },
            { "Sell to vendors when they pay more", function(d) return NotFalse(d.autoVendor) end, onoff("autovendor") },
            { "Learn recipes in your bags", function(d) return NotFalse(d.autoLearn) end, onoff("autolearn") },
            { "Prices in item tooltips", function(d) return NotFalse(d.tooltip) end, onoff("tooltip") },
            { "Mouse wheel posts at the AH", function(d) return NotFalse(d.wheelPost) end, onoff("wheel") },
        },
        actions = { { "Open", "" }, { "Scan", "scan" }, { "Undercuts", "auctions" }, { "Collect AH mail", "mail" } },
    },
    {
        name = "TwizQuest", slash = "QUESTROUTE", cmd = "/tq", icon = "Interface\\Icons\\INV_Misc_Map_01",
        blurb = "Plans which quests to do and in what order for the most XP per hour, with waypoints, sell & repair stops, party sharing, log cleanup, keyboard dialogue (Space / 1-9) and flight times. Needs Questie.",
        db = function() return QuestRouteDB end,
        settings = {
            { "Update the plan automatically", function(d) return T(d.auto) end, flip("auto") },
            { "Set waypoints automatically", function(d) return T(d.autoWay) end, flip("way") },
            { "Accept quests automatically", function(d) return T(d.autoAccept) end, flip("accept") },
            { "Include elite quests", function(d) return T(d.elites) end, flip("elites") },
            { "Sell & repair stops", function(d) return T(d.service) end, flip("service") },
            { "Minimap button", function(d) return NotFalse(d.minimap) end, flip("minimap") },
            { "Keyboard dialogue (Space / 1-9)", function(d) return NotFalse(d.talkKeys) end, flip("talk") },
            { "Flight timer bar", function(d) return NotFalse(d.flightBar) end, flip("flights") },
            { "Minimap line to step 1", function(d) return NotFalse(d.miniLine) end, flip("line") },
            { "Class trainer stops", function(d) return NotFalse(d.trainer) end, flip("trainer") },
        },
        actions = { { "Open", "" }, { "Share missing", "share" }, { "Share this zone", "sharezone" }, { "Clean up log", "cleanup" }, { "Flight times", "flights list" }, { "Hearth info", "hearth" } },
    },
    {
        name = "TwizCraft", slash = "CRAFTROUTE", cmd = "/tc", icon = "Interface\\Icons\\Trade_BlackSmithing",
        blurb = "Cheapest path to level each profession: what to craft, how many, a shopping list and route, buying, crafting, and your party's recipes.",
        db = function() return CraftRouteDB end,
        settings = {
            { "Count AH resale of what you craft", function(d) return T(d.resellAH) end, flip("resell") },
            { "Mouse wheel = Craft All", function(d) return NotFalse(d.wheelCraft) end, flip("wheel") },
        },
        actions = { { "Open", "" }, { "Read all professions", "readall" }, { "Shopping", "buy" }, { "Party recipes", "party" } },
    },
    {
        name = "TwizChef", slash = "AUTOCHEF", cmd = "/chef", icon = "Interface\\Icons\\INV_Misc_Food_15",
        blurb = "Remembers your cooking recipes, buys missing ingredients at vendors, one-key eat/drink and cook, drink restock and a Well Fed reminder.",
        db = function() return AutoChefDB end,
        settings = {
            { "On", function(d) return NotFalse(d.enabled) end, function(on) return on and "on" or "off" end },
            { "Well Fed reminder", function(d) return NotFalse(d.remind) end, flip("remind") },
        },
        actions = { { "Open", "" }, { "Cooking plan", "plan" }, { "Buy ingredients", "buy" }, { "Stats", "stats" } },
    },
    {
        name = "TwizBuff", slash = "TWIZBUFF", cmd = "/tb", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
        blurb = "Shows who's missing your class buffs and casts the next one with one key or a mouse-wheel notch; group buffs, strangers, nearest-friend mode and debuff removal.",
        db = function() return TwizBuffDB end,
        settings = {
            { "Mouse wheel casts the next buff", function(d) return T(d.wheel) end, onoff("wheel") },
            { "Hide the window when all buffed", function(d) return T(d.hideWhenDone) end, flip("auto") },
            { "Remove curses / poisons too", function(d) return NotFalse(d.dispel) end, flip("cleanse") },
            { "Nearest-friend mode", function(d) return T(d.nearest) end, flip("nearest") },
            { "Buff nearby strangers", function(d) return T(d.strangers) end, onoff("strangers") },
            { "Skip PvP-flagged strangers", function(d) return T(d.skipPvP) end, flip("pvp") },
            { "Include Thorns", function(d) return T(d.thorns) end, flip("thorns") },
            { "Include Shadow Protection", function(d) return T(d.shadowProt) end, flip("shadow") },
        },
        actions = { { "Open", "" } },
    },
    {
        name = "TwizHeal", slash = "TWIZHEAL", cmd = "/th", icon = "Interface\\Icons\\Spell_Holy_Heal",
        blurb = "One-key smart healing: the party window as a cross, hover a bar and press your key; right-sized ranks, HoT combos, Swiftmend, pre-HoTs, decurse, Nature's Swiftness and Tranquility keys.",
        db = function() return TwizHealDB end,
        settings = {
            { "Party window", function(d) return NotFalse(d.shown) end, flip("window") },
            { "Show what's being cast", function(d) return NotFalse(d.castInfo) end, flip("castinfo") },
            { "Alt+click the game's frames", function(d) return T(d.clickCast) end, flip("clicks") },
            { "Block bars at 90%+ in combat", function(d) return NotFalse(d.combatGuard) end, flip("guard") },
            { "Chat messages", function(d) return NotFalse(d.feedback) end, flip("quiet") },
        },
        actions = { { "Pre-HoT report", "prehot" }, { "Your ranks", "ranks" }, { "Debug", "debug" } },
    },
    {
        name = "TwizHunt", slash = "TWIZHUNT", cmd = "/hunt", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        blurb = "One-key hunter: Auto Shot, pet attack, Hunter's Mark, Summon Hawk, Serpent Sting and Arcane Shot on one key; a melee key; the right aspect and pet care out of combat; ammo and pet food restock at vendors.",
        db = function() return TwizHuntDB end,
        settings = {
            { "Aspect of the Hawk automatically", function(d) return NotFalse(d.aspects) end, flip("aspects") },
            { "Aspect of the Cheetah, no target", function(d) return T(d.cheetah) end, flip("cheetah") },
            { "Pet care on the Shoot key", function(d) return NotFalse(d.petCare) end, flip("pet") },
            { "Restock ammo at vendors", function(d) return NotFalse(d.ammo) end, flip("ammo") },
            { "Restock pet food at vendors", function(d) return NotFalse(d.petFood) end, flip("food") },
        },
        actions = { { "Status", "status" } },
    },
    {
        name = "TwizOpen", slash = "AUTOOPEN", cmd = "/ao", icon = "Interface\\Icons\\INV_Box_02",
        blurb = "Opens chests, boxes, gifts, clams and other containers in your bags - never in combat, while looting, or at a vendor, bank, mailbox, trade or AH.",
        db = function() return AutoOpenDB end,
        settings = {
            { "On", function(d) return NotFalse(d.enabled) end, function(on) return on and "on" or "off" end },
            { "\"Opened\" chat messages", function(d) return NotFalse(d.announce) end, flip("quiet") },
        },
        actions = { { "Status", "status" }, { "Ignored items", "ignored" }, { "Try again", "retry" } },
    },
    {
        name = "TwizErrors", slash = "TWIZERRORS", cmd = "/terr", icon = "Interface\\Icons\\Spell_Holy_Silence",
        blurb = "Quiets the spoken errors (\"Not enough mana\", \"I can't do that yet\"...), can hide the matching red text, and catches every addon's Lua errors in a copyable window (no BugSack needed).",
        db = function() return TwizErrorsDB end,
        settings = {
            { "Silence the error voice", function(d) return NotFalse(d.enabled) end, function(on) return on and "on" or "off" end },
            { "Hide the red text for those errors", function(d) return T(d.hideText) end, flip("text") },
            { "Catch Lua errors from all addons", function(d) return NotFalse(d.catch) end, flip("catch") },
            { "Chat line when an error is caught", function(d) return not d.quietBugs end, flip("quietbugs") },
        },
        actions = { { "Caught errors", "bugs" }, { "Clear errors", "clear" }, { "Status", "status" } },
    },
}

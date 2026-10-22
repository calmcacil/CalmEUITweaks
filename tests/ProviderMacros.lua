-- Run from the EUI root: lua CalmEUITweaks/tests/ProviderMacros.lua
local passed = 0
local MAGE_ICON = "Interface\\Icons\\ClassIcon_Mage"
local AUTO_ICON = "INV_Misc_QuestionMark"
local ICON_IDS = { [MAGE_ICON] = 626000, [AUTO_ICON] = 134400 }

local function Check(value, message)
    assert(value, message)
    passed = passed + 1
end

local function Load(path, ns)
    local chunk, message = loadfile("CalmEUITweaks/" .. path)
    assert(chunk, message)
    return chunk("CalmEUITweaks", ns)
end

local function New(options)
    options = options or {}
    local state = {
        macros = {}, timers = {}, frames = {}, known = {}, names = {}, bags = {},
        writes = 0, edits = {}, combat = false, class = options.class or "DRUID",
        level = options.level or 60,
    }
    local settings = {
        druidRebirthMacro = { enabled = options.enabled ~= false, name = "Rebirth" },
        druidThornsMacro = { enabled = options.enabled ~= false, name = "Thorns" },
        generalFoodWaterMacro = { enabled = options.generalEnabled ~= false, name = "Food and Water" },
    }
    local ns = {
        ready = true, errors = {}, statuses = {},
        charDB = { version = 1, druidRebirthMacro = {}, druidThornsMacro = {} },
        db = settings,
    }
    Load("core/Bootstrap.lua", ns)
    ns.GetSettings = function(key) return settings[key] end

    UnitClass = function() return state.class, state.class end
    UnitLevel = function() return state.level end
    InCombatLockdown = function() return state.combat end
    MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS, MAX_MACRO_LENGTH = 120, 18, 255
    strlenutf8 = nil
    IsSpellKnown = function(id) return state.known[id] or false end
    IsPlayerSpell, C_SpellBook, GetSpellInfo = nil, nil, nil
    C_Spell = {
        GetSpellInfo = function(id)
            return state.names[id] and { name = state.names[id] }
        end,
    }
    C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end }
    NUM_BAG_SLOTS = 4
    C_Container = {
        GetContainerNumSlots = function() return 4 end,
        GetContainerItemInfo = function(bag, slot)
            local itemID = state.bags[bag] and state.bags[bag][slot]
            if itemID then return { itemID = itemID } end
        end,
    }
    GetContainerNumSlots, GetContainerItemID = nil, nil
    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        state.frames[#state.frames + 1] = frame
        return frame
    end

    GetMacroInfo = function(index)
        local macro = state.macros[index]
        if macro then return macro.name, macro.icon, macro.body end
    end
    GetNumMacros = function()
        local account, character = 0, 0
        for index in pairs(state.macros) do
            if index <= 120 then account = account + 1 else character = character + 1 end
        end
        return account, character
    end
    CreateMacro = function(name, icon, body, character)
        assert(not state.combat, "Creation attempted in combat")
        local index
        if character then
            index = 121
            while state.macros[index] do index = index + 1 end
            assert(index <= 138, "Creation exceeded character capacity")
        else
            index = 1
            while state.macros[index] do index = index + 1 end
            assert(index <= 120, "Creation exceeded account capacity")
        end
        assert(character == true or character == nil, "Account scope must use a nil flag")
        state.macros[index] = {
            name = name, body = body, character = character,
            icon = options.stringIcons and icon or ICON_IDS[icon] or icon,
        }
        state.writes = state.writes + 1
        state:Event("UPDATE_MACROS")
        return index
    end
    EditMacro = function(index, name, icon, body)
        assert(not state.combat, "Edit attempted in combat")
        assert(name == nil, "Owned edits must preserve macro name")
        if index > 120 then assert(icon == nil, "Other providers must preserve icons") end
        assert(index >= 1 and index <= 138, "Edit index is outside the macro slots")
        state.edits[#state.edits + 1] = { icon = icon, body = body }
        state.macros[index].body = body
        if icon and not state.ignoreIcon then
            state.macros[index].icon = options.stringIcons and icon or ICON_IDS[icon] or icon
        end
        state.writes = state.writes + 1
        if state.afterEdit then state.afterEdit(state.macros[index]) end
        state:Event("UPDATE_MACROS")
        return index
    end

    function state:Flush()
        local batches = 0
        while #self.timers > 0 do
            local timers = self.timers
            self.timers = {}
            for _, callback in ipairs(timers) do callback() end
            batches = batches + 1
            assert(batches < 30, "Unbounded event/request loop")
        end
    end
    function state:Event(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    function state:Item(bag, slot, itemID)
        self.bags[bag] = self.bags[bag] or {}
        self.bags[bag][slot] = itemID
    end

    local providers = {}
    Load("functions/Macros.lua", ns)
    local register = ns.RegisterMacroProvider
    ns.RegisterMacroProvider = function(id, provider)
        providers[id] = provider
        return register(id, provider)
    end
    Load("macros/druid.lua", ns)
    Load("macros/general.lua", ns)
    ns.RegisterMacroProvider = register
    return state, settings, ns, providers
end

local s, settings, ns, providers = New()
Check(providers.druidRebirth.settingsKey == "druidRebirthMacro"
    and providers.druidRebirth.class == "DRUID" and providers.druidRebirth.classLabel == "Druid"
    and providers.druidRebirth.defaultName == "Rebirth", "Rebirth registration metadata")
Check(providers.druidThorns.settingsKey == "druidThornsMacro"
    and providers.druidThorns.defaultName == "Thorns", "Thorns registration metadata")
Check(providers.foodWater.settingsKey == "generalFoodWaterMacro"
    and providers.foodWater.scope == "account" and providers.foodWater.class == "ALL"
    and providers.foodWater.defaultName == "Food and Water", "General food and water metadata")

s.known[20748], s.known[1237951] = true, true
s.names[20748], s.names[1237951] = "Rebirth", "Revive"
local body = providers.druidRebirth.Build()
Check(body == table.concat({
    "#showtooltip [combat] Rebirth; Revive",
    "/cast [combat] Rebirth",
    "/cast [nocombat] Revive",
}, "\n"), "Rebirth uses unranked spell names")
Check(not body:find("Rank", 1, true), "Rebirth body never names a rank")

s.known[9910], s.names[9910] = true, "Thorns"
body = providers.druidThorns.Build()
Check(body == table.concat({
    "#showtooltip Thorns",
    "/cast [@player] Thorns",
}, "\n"), "Thorns self-cast uses the unranked spell name")

s, settings, ns, providers = New({ level = 20 })
s.known[20484], s.known[437138] = true, true
s.names[20484], s.names[437138] = "Rebirth", "Revive"
body = providers.druidRebirth.Build()
Check(body == table.concat({
    "#showtooltip [combat] Rebirth; Revive",
    "/cast [combat] Rebirth",
    "/cast [nocombat] Revive",
}, "\n"), "Lowest known Rebirth and Revive tiers are eligible")

s, settings, ns, providers = New()
local message
body, message = providers.druidRebirth.Build()
Check(body == nil and message:find("Learn Rebirth and Revive", 1, true),
    "Missing druid resurrection spells wait")

s, settings, ns, providers = New()
s.known[20748], s.known[1237951] = true, true
local missing
body, message, missing = providers.druidRebirth.Build()
Check(body == nil and #missing == 2 and missing[1] == 20748 and missing[2] == 1237951,
    "Rebirth reports only selected missing localized data")

s, settings, ns, providers = New()
s.known[20748], s.known[1237951] = true, true
s.names[20748], s.names[1237951] = "Rebirth", "Revive"
local module = ns.modules.druidRebirthMacro
module:Initialize(); s:Flush()
Check(s.writes == 1 and s.macros[121].name == "Rebirth"
    and s.macros[121].body == providers.druidRebirth.Build(),
    "Rebirth creates a character macro")
Check(ns.charDB.druidRebirthMacro.ownedMacros["Rebirth"].lastGeneratedBody == s.macros[121].body,
    "Rebirth ownership is character scope")

s, settings, ns, providers = New()
s.known[9910], s.names[9910] = true, "Thorns"
module = ns.modules.druidThornsMacro
module:Initialize(); s:Flush()
Check(s.writes == 1 and s.macros[121].body == table.concat({
    "#showtooltip Thorns",
    "/cast [@player] Thorns",
}, "\n"), "Thorns creates a character macro")

s, settings, ns, providers = New({ class = "WARRIOR" })
module = ns.modules.druidRebirthMacro
module:Initialize(); s:Flush()
Check(s.writes == 0 and #s.frames == 0 and module:GetStatus():find("Druid only", 1, true),
    "Druid macros stay inert for other classes")

s, settings, ns, providers = New({ class = "WARRIOR" })
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 1 and s.macros[1] and s.macros[1].body == "#showtooltip",
    "Enabled general provider creates an account macro even with empty bags")
local record = ns.db.generalFoodWaterMacro.ownedMacros["Food and Water"]
Check(s.macros[1].character == nil and ns.charDB.generalFoodWaterMacro == nil
    and record.lastGeneratedBody == "#showtooltip", "General ownership is account scope")
Check(s.macros[1].icon == ICON_IDS[MAGE_ICON] and record.lastGeneratedIconKey == MAGE_ICON
    and record.lastGeneratedIcon == ICON_IDS[MAGE_ICON],
    "Empty creation records the requested mage texture and actual numeric readback")
Check(s.frames[1].events.BAG_UPDATE_DELAYED, "General provider subscribes to bag changes")
s:Event("BAG_UPDATE_DELAYED"); s:Event("UPDATE_MACROS"); s:Flush()
Check(s.writes == 1, "Unchanged empty bags and native macro notifications do not write")

s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and s.macros[1].body == "#showtooltip item:5349\n/use [btn:1] item:5349",
    "Empty to food-only adds only the left-click food action")
Check(s.edits[1].icon == AUTO_ICON and s.macros[1].icon == ICON_IDS[AUTO_ICON]
    and record.lastGeneratedIconKey == AUTO_ICON and record.lastGeneratedIcon == ICON_IDS[AUTO_ICON],
    "Available food switches to the native automatic icon and records its actual ID")
s:Item(0, 2, 5350)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 3 and s.macros[1].body == table.concat({
    "#showtooltip [btn:2] item:5350; item:5349",
    "/use [btn:1] item:5349",
    "/use [btn:2] item:5350",
}, "\n"), "Food-only to both preserves the existing full macro body")
Check(s.edits[2].icon == nil, "An unchanged requested icon is not rewritten")
s:Item(0, 1, nil)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 4 and s.macros[1].body == "#showtooltip item:5350\n/use [btn:2] item:5350",
    "Both to water-only removes the unavailable food action")
s:Item(0, 2, nil)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 5 and s.macros[1].body == "#showtooltip" and s.edits[4].icon == MAGE_ICON
    and s.macros[1].icon == ICON_IDS[MAGE_ICON], "Water-only to empty removes stale actions and restores mage icon")

local savedMacros, savedRecords = s.macros, settings.generalFoodWaterMacro.ownedMacros
s, settings, ns, providers = New({ class = "ROGUE", level = 1 })
s.macros, settings.generalFoodWaterMacro.ownedMacros = savedMacros, savedRecords
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 0, "Reload recognizes saved numeric icon readback without writing")
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
s:Item(4, 1, 22895); s:Item(4, 2, 8079)
s:Item(-1, 1, 8076)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 1 and s.macros[1].body:find("item:22895", 1, true)
    and s.macros[1].body:find("item:8079", 1, true) and not s.macros[1].body:find("item:5349", 1, true),
    "Strongest owned ranks win across bags independently of class, level and known spells")
Check(s.edits[1].icon == AUTO_ICON, "Reload retains icon ownership across key transitions")
s:Item(4, 1, nil)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.macros[1].body:find("item:5349", 1, true) and s.macros[1].body:find("item:8079", 1, true),
    "Food and water ranks downgrade independently and bank items are ignored")
s:Event("BAG_UPDATE_DELAYED"); s:Event("UPDATE_MACROS"); s:Flush()
Check(s.writes == 2, "Unchanged available items do not write")

record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
s.macros[1].body, s.macros[1].icon = "/say mine", "manual body icon"
s.bags = {}
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and s.macros[1].body == "/say mine" and s.macros[1].icon == "manual body icon"
    and record.lastGeneratedIconKey == AUTO_ICON and module:GetStatus():find("User-edited", 1, true),
    "Manual body edit stops all maintenance before changing icon ownership")

s, settings, ns, providers = New({ class = "WARRIOR" })
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
s.macros[1].icon = "manual icon"
s:Event("UPDATE_MACROS"); s:Flush()
Check(s.writes == 1 and record.lastGeneratedIconKey == nil and record.lastGeneratedIcon == nil,
    "Manual icon edit relinquishes icon ownership even with an unchanged body")
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
s.bags = {}
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 3 and s.macros[1].body == "#showtooltip" and s.macros[1].icon == "manual icon"
    and s.edits[1].icon == nil and s.edits[2].icon == nil,
    "Body maintenance continues without overriding a manually customized icon")

for _, existingBody in ipairs({ "/say existing", "#showtooltip" }) do
    s, settings, ns, providers = New({ class = "WARRIOR" })
    s.macros[1] = { name = "Food and Water", body = existingBody, icon = "adopted icon" }
    module = ns.modules.generalFoodWaterMacro
    module:Initialize(); s:Flush()
    record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
    Check(s.writes == (existingBody == "#showtooltip" and 0 or 1)
        and s.macros[1].body == "#showtooltip" and s.macros[1].icon == "adopted icon"
        and record.lastGeneratedBody == "#showtooltip" and record.lastGeneratedIconKey == nil,
        "Adoption preserves an untracked icon with or without a body write")
    s:Item(0, 1, 5349)
    s:Event("BAG_UPDATE_DELAYED"); s:Flush()
    s.bags = {}
    s:Event("BAG_UPDATE_DELAYED"); s:Flush()
    Check(s.macros[1].body == "#showtooltip" and s.macros[1].icon == "adopted icon"
        and record.lastGeneratedIcon == nil, "Adopted icons remain unowned across item transitions")
    for _, edit in ipairs(s.edits) do Check(edit.icon == nil, "Adoption never writes an icon") end
end

s, settings, ns, providers = New()
s.macros[1] = { name = "Food and Water", body = "#showtooltip", icon = ICON_IDS[MAGE_ICON] }
settings.generalFoodWaterMacro.ownedMacros = { ["Food and Water"] = { lastGeneratedBody = "#showtooltip" } }
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 1 and s.edits[1].icon == nil and s.macros[1].icon == ICON_IDS[MAGE_ICON],
    "Existing body-only ownership never acquires icon ownership even for a matching native icon")

for _, indices in ipairs({ { 121 }, { 1, 2 }, { 1, 121 } }) do
    s, settings, ns, providers = New()
    for _, index in ipairs(indices) do
        s.macros[index] = { name = "Food and Water", body = "/say collision", icon = "foreign" }
    end
    module = ns.modules.generalFoodWaterMacro
    module:Initialize(); s:Flush()
    Check(s.writes == 0 and not settings.generalFoodWaterMacro.ownedMacros
        and module:GetStatus():find("Name conflict", 1, true), "Empty bags retain cross-scope and duplicate-name protection")
end

s, settings, ns, providers = New({ class = "WARRIOR" })
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
s.combat = true
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 1 and s.macros[1].body == "#showtooltip" and s.frames[1].events.PLAYER_REGEN_ENABLED,
    "Food arrival and icon changes defer during combat")
s.combat = false
s:Event("PLAYER_REGEN_ENABLED"); s:Flush()
Check(s.writes == 2 and s.macros[1].icon == ICON_IDS[AUTO_ICON]
    and s.macros[1].body:find("item:5349", 1, true), "Combat end applies the deferred food and icon update")
s.combat = true; s.bags = {}
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
s.combat = false
s:Event("PLAYER_REGEN_ENABLED"); s:Flush()
Check(s.writes == 3 and s.macros[1].body == "#showtooltip" and s.macros[1].icon == ICON_IDS[MAGE_ICON],
    "Losing items in combat removes stale actions and restores icon after combat")
settings.generalFoodWaterMacro.enabled = false; module:ApplySettings()
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 3 and next(s.frames[1].events) == nil, "Disabling releases events and preserves the existing macro")

s, settings, ns, providers = New({ generalEnabled = false })
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 0 and #s.frames == 0, "Disabled general provider stays inert with empty bags")

s, settings, ns, providers = New({ class = "WARRIOR" })
s:Item(0, 1, 5350); s.combat = true
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 0 and s.frames[1].events.PLAYER_REGEN_ENABLED,
    "Initial creation also waits for combat to end")
s.combat = false; s:Event("PLAYER_REGEN_ENABLED"); s:Flush()
record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
Check(s.writes == 1 and s.macros[1].body == "#showtooltip item:5350\n/use [btn:2] item:5350"
    and s.macros[1].icon == ICON_IDS[AUTO_ICON] and record.lastGeneratedIconKey == AUTO_ICON,
    "Creation with water uses only right-click and records the automatic icon")
s.bags = {}; s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and s.macros[1].icon == ICON_IDS[MAGE_ICON],
    "A macro first created with available items can restore its empty fallback")

s, settings, ns, providers = New({ stringIcons = true })
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
s.bags = {}; s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 3 and s.macros[1].icon == MAGE_ICON
    and settings.generalFoodWaterMacro.ownedMacros["Food and Water"].lastGeneratedIcon == MAGE_ICON,
    "String icon readbacks are supported without numeric normalization")

s, settings, ns, providers = New()
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
local build = providers.foodWater.Build
providers.foodWater.Build = function() return "#showtooltip", nil, nil, AUTO_ICON end
s.ignoreIcon = true
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and record.lastGeneratedBody == "#showtooltip"
    and record.lastGeneratedIconKey == MAGE_ICON and record.lastGeneratedIcon == ICON_IDS[MAGE_ICON],
    "Failed icon-only edit readback does not advance body or icon ownership or loop on UPDATE_MACROS")
Check(module:GetStatus():find("could not be verified", 1, true), "Failed icon request reports an unverifiable write")
providers.foodWater.Build = build
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 3 and s.edits[2].icon == nil and s.macros[1].body == build()
    and record.lastGeneratedBody == s.macros[1].body and record.lastGeneratedIconKey == MAGE_ICON,
    "A failed icon request does not suppress unrelated verified body maintenance")

s, settings, ns, providers = New()
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
providers.foodWater.Build = function() return "#showtooltip", nil, nil, AUTO_ICON end
s.afterEdit = function(macro) macro.icon = nil; s.afterEdit = nil end
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and record.lastGeneratedBody == "#showtooltip"
    and record.lastGeneratedIconKey == MAGE_ICON and record.lastGeneratedIcon == ICON_IDS[MAGE_ICON],
    "Invalid icon-only readback retains ownership through its native update notification")

s, settings, ns, providers = New()
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
record = settings.generalFoodWaterMacro.ownedMacros["Food and Water"]
s.afterEdit = function(macro) macro.icon = nil; s.afterEdit = nil end
s:Item(0, 1, 5349)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and record.lastGeneratedBody == "#showtooltip"
    and record.lastGeneratedIconKey == MAGE_ICON and record.lastGeneratedIcon == ICON_IDS[MAGE_ICON],
    "Missing icon readback after a body/icon edit retains all prior ownership without rollback")

print("PASS: " .. passed .. " provider macro checks")

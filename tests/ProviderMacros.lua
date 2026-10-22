-- Run from the EUI root: lua CalmEUITweaks/tests/ProviderMacros.lua
local passed = 0

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
        writes = 0, combat = false, class = options.class or "DRUID",
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
        if macro then return macro.name, "icon", macro.body end
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
        state.macros[index] = { name = name, body = body, character = character }
        state.writes = state.writes + 1
        return index
    end
    EditMacro = function(index, name, icon, body)
        assert(not state.combat, "Edit attempted in combat")
        assert(name == nil and icon == nil, "Owned edits must preserve macro name and icon")
        assert(index >= 1 and index <= 138, "Edit index is outside the macro slots")
        state.macros[index].body = body
        state.writes = state.writes + 1
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
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
body = providers.foodWater.Build()
Check(body == table.concat({
    "#showtooltip [btn:2] item:5350; item:5349",
    "/use [btn:1] item:5349",
    "/use [btn:2] item:5350",
}, "\n"), "General food and water uses bag items")

s:Item(0, 1, 22895); s:Item(0, 2, 8079)
body = providers.foodWater.Build()
Check(body:find("item:22895", 1, true) and body:find("item:8079", 1, true)
    and not body:find("item:5349", 1, true), "Highest food and water tiers win independently")

s.bags[0][1] = nil; s.bags[0][2] = nil
body, message = providers.foodWater.Build()
Check(body == nil and message:find("conjured food and water", 1, true),
    "Missing bag items reports a useful status")

s, settings, ns, providers = New({ class = "WARRIOR" })
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 1 and not s.macros[1].character
    and s.macros[1].body:find("item:5349", 1, true),
    "General food and water creates an account macro")
Check(ns.db.generalFoodWaterMacro.ownedMacros["Food and Water"].lastGeneratedBody == s.macros[1].body,
    "General ownership is account scope")
Check(s.frames[1].events.BAG_UPDATE_DELAYED, "General provider subscribes to bag changes")

s:Item(0, 1, 22895); s:Item(0, 2, 8079)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and s.macros[1].body:find("item:22895", 1, true)
    and s.macros[1].body:find("item:8079", 1, true), "Bag changes update the account macro")

s.macros[1].body = "/say mine"
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 2 and module:GetStatus():find("User-edited", 1, true),
    "Manual general macro edits are preserved")

s, settings, ns, providers = New({ class = "WARRIOR" })
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
s.macros[1] = { name = "Food and Water", body = "/say existing" }
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 1 and not s.macros[1].character
    and s.macros[1].body == providers.foodWater.Build()
    and ns.db.generalFoodWaterMacro.ownedMacros["Food and Water"].lastGeneratedBody == s.macros[1].body
    and module:GetStatus():find("Adopted", 1, true), "Unowned general macro is adopted")

s, settings, ns, providers = New({ class = "WARRIOR" })
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
s.combat = true
s:Item(0, 1, 22895)
s:Event("BAG_UPDATE_DELAYED"); s:Flush()
Check(s.writes == 1 and module:GetStatus():find("combat", 1, true),
    "Bag updates defer during combat")
s.combat = false
s:Event("PLAYER_REGEN_ENABLED"); s:Flush()
Check(s.writes == 2 and s.macros[1].body:find("item:22895", 1, true),
    "Combat end applies the deferred bag update")

s, settings, ns, providers = New({ generalEnabled = false, class = "WARRIOR" })
s:Item(0, 1, 5349); s:Item(0, 2, 5350)
module = ns.modules.generalFoodWaterMacro
module:Initialize(); s:Flush()
Check(s.writes == 0 and #s.frames == 0, "Disabled general provider stays inert")

print("PASS: " .. passed .. " provider macro checks")

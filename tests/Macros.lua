-- Run from the EUI root: lua CalmEUITweaks/tests/Macros.lua
local passed = 0

local function Check(value, message)
    assert(value, message)
    passed = passed + 1
end

local function Load(path, ns)
    local chunk, message = loadfile(path)
    assert(chunk, message)
    return chunk("CalmEUITweaks", ns)
end

local function New(options)
    options = options or {}
    local state = {
        macros = {}, timers = {}, frames = {}, requests = {}, known = {}, names = {},
        writes = 0, combat = false, reports = {}, clears = 0,
    }
    local settings = { enabled = options.enabled ~= false, name = options.name or "Mage FoodWater" }
    local ns = { ready = true, errors = {}, charDB = { version = 1, mageMacro = {} } }
    local module

    ns.GetSettings = function(key)
        assert(key == "mageMacro", "Unexpected settings key")
        return settings
    end
    ns.RegisterModule = function(key, value)
        assert(key == "mageMacro" and not module, "Unexpected module registration")
        module = value
    end
    ns.SetStatus = function(key, message)
        assert(key == "mageMacro" and type(message) == "string", "Invalid status")
        state.status = message
    end
    local reported = {}
    ns.ReportError = function(key, err)
        assert(key == "mageMacro", "Unexpected error settings key")
        state.coreError = tostring(err)
        ns.errors[key] = "Error: " .. state.coreError
        if not reported[state.coreError] then
            reported[state.coreError] = true
            state.reports[#state.reports + 1] = state.coreError
        end
    end
    ns.ClearError = function(key)
        assert(key == "mageMacro", "Unexpected clear settings key")
        state.clears = state.clears + 1
        state.coreError = nil
        ns.errors[key] = nil
        reported = {}
    end

    UnitClass = function() return "Mage", options.class or "MAGE" end
    UnitLevel = function() return options.level or 60 end
    InCombatLockdown = function() return state.combat end
    MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS, MAX_MACRO_LENGTH = 120, 18, 255
    strlenutf8 = nil
    IsSpellKnown = function(id) return state.known[id] or false end
    IsPlayerSpell, C_SpellBook, GetSpellInfo = nil, nil, nil
    C_Spell = {
        GetSpellInfo = function(id)
            return state.names[id] and { name = state.names[id] }
        end,
        RequestLoadSpellData = function(id)
            state.requests[id] = (state.requests[id] or 0) + 1
        end,
    }
    C_Timer = {
        After = function(_, fn) state.timers[#state.timers + 1] = fn end,
    }
    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
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
        assert(character == true, "Creation must be character-only")
        state.writes = state.writes + 1
        if options.failCreate then return nil end
        local index = 121
        while state.macros[index] do index = index + 1 end
        assert(index <= 138, "Creation exceeded character capacity")
        state.macros[index] = { name = name, body = body }
        return index
    end
    EditMacro = function(index, name, icon, body)
        assert(not state.combat, "Edit attempted in combat")
        assert(index > 120 and index <= 138, "Edit must be character-only")
        state.writes = state.writes + 1
        state.macros[index].body = body
        return index
    end

    function state:Flush()
        local batches = 0
        while #self.timers > 0 do
            local timers = self.timers
            self.timers = {}
            for _, fn in ipairs(timers) do fn() end
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

    state.known[587], state.known[5504] = true, true
    state.names[587], state.names[5504] = "Conjure Food", "Conjure Water"
    Load("CalmEUITweaks/functions/Macros.lua", ns)
    assert(not module, "Shared registry registered a module before its provider")
    local register = ns.RegisterMacroProvider
    ns.RegisterMacroProvider = function(id, provider)
        assert(id == "mage", "Unexpected provider")
        state.provider = provider
        local build = provider.Build
        provider.Build = function()
            state.builds = (state.builds or 0) + 1
            if state.buildError then error(state.buildError, 0) end
            return build()
        end
        return register(id, provider)
    end
    Load("CalmEUITweaks/macros/mage.lua", ns)
    ns.RegisterMacroProvider = register
    assert(module, "Mage provider did not register its module")
    return state, settings, ns, module
end

local s, settings, ns, m = New()
m:Initialize(); s:Flush()
Check(s.writes == 1, "Initial character creation")
Check(s.macros[121].body == table.concat({
    "#showtooltip",
    "/use [btn:1] item:5349",
    "/use [btn:1] item:5350",
    "/castsequence [btn:2] reset=10 Conjure Food, Conjure Water",
}, "\n"), "Correct generated body")
Check(ns.charDB.mageMacro.ownedMacros["Mage FoodWater"].lastGeneratedBody == s.macros[121].body,
    "Confirmed ownership")
m:ApplySettings(); s:Flush()
Check(s.writes == 1, "No redundant edit")

s.known[28612], s.known[10140] = true, true
s.names[28612], s.names[10140] = "Food VII", "Water VII"
s:Event("SPELLS_CHANGED"); s:Event("PLAYER_LEVEL_UP"); s:Event("UPDATE_MACROS")
Check(#s.timers == 1, "Coalesced events")
s:Flush()
Check(s.writes == 2 and s.macros[121].body:find("item:22895", 1, true), "Highest known rank upgrade")
s.macros[121].body = "/say mine"
s:Event("UPDATE_MACROS"); s:Flush()
Check(s.writes == 2 and m:GetStatus():find("User-edited", 1, true), "User edits preserved")
settings.name = "Other"; m:ApplySettings(); s:Flush()
Check(s.macros[121].body == "/say mine" and s.macros[122], "Rename preserves earlier macro")
Check(ns.charDB.mageMacro.ownedMacros["Mage FoodWater"] and ns.charDB.mageMacro.ownedMacros.Other,
    "Earlier ownership retained")
s:Event("SPELLS_CHANGED"); settings.enabled = false; m:ApplySettings(); s:Flush()
Check(s.writes == 3 and next(s.frames[1].events) == nil, "Disable cancels queued work and events")

for _, index in ipairs({ 1, 121 }) do
    s, settings, ns, m = New()
    s.macros[index] = { name = "Mage FoodWater", body = "/say legacy" }
    m:Initialize(); s:Flush()
    Check(s.writes == 0 and not ns.charDB.mageMacro.ownedMacros
        and m:GetStatus():find("Name conflict", 1, true), "Unowned name conflict at index " .. index)
end

s, settings, ns, m = New()
s.combat = true; m:Initialize(); s:Flush()
Check(s.writes == 0, "Combat postpones writes")
s.combat = false; s:Event("PLAYER_REGEN_ENABLED"); s:Flush()
Check(s.writes == 1, "Combat exit resumes writes")
s, settings, ns, m = New({ class = "WARRIOR" }); m:Initialize(); s:Flush()
Check(#s.frames == 0 and s.writes == 0, "Non-Mage stays inert")
s, settings, ns, m = New({ enabled = false }); m:Initialize(); s:Flush()
Check(#s.frames == 0 and s.writes == 0, "Disabled module stays inert")

s, settings, ns, m = New()
s.names = {}; m:Initialize(); s:Flush()
Check(s.requests[587] == 1 and s.requests[5504] == 1, "Only selected spell IDs requested")
s:Event("SPELL_DATA_LOAD_RESULT", 999, true)
Check(#s.timers == 0, "Unrelated spell result ignored")
s:Event("SPELL_DATA_LOAD_RESULT", 587, false)
s:Event("SPELL_DATA_LOAD_RESULT", 5504, false); s:Flush()
for i = 1, 10 do s:Event("SPELLS_CHANGED"); s:Flush() end
Check(s.requests[587] == 1 and s.requests[5504] == 1 and s.writes == 0,
    "Failed spell requests never loop")
s, settings, ns, m = New()
s.names = {}; m:Initialize(); s:Flush()
s.names[587], s.names[5504] = "Food localized", "Water localized"
s:Event("SPELL_DATA_LOAD_RESULT", 587, true)
s:Event("SPELL_DATA_LOAD_RESULT", 5504, true); s:Flush()
Check(s.writes == 1 and s.macros[121].body:find("Food localized, Water localized", 1, true),
    "Localized spell data resumes creation")

s, settings, ns, m = New({ name = string.rep("x", 17) }); m:Initialize(); s:Flush()
Check(s.writes == 0 and m:GetStatus():find("16 characters", 1, true), "Macro name length validated")
s, settings, ns, m = New()
s.names[587] = string.rep("x", 240); m:Initialize(); s:Flush()
Check(s.writes == 0 and m:GetStatus():find("body length", 1, true), "Macro body length validated")
s, settings, ns, m = New()
for i = 121, 138 do s.macros[i] = { name = "Existing" .. i, body = "" } end
m:Initialize(); s:Flush()
Check(s.writes == 0 and m:GetStatus():find("slots are full", 1, true), "Character capacity validated")
s, settings, ns, m = New({ failCreate = true }); m:Initialize(); s:Flush()
Check(not ns.charDB.mageMacro.ownedMacros, "Failed creation never records ownership")

s, settings, ns, m = New()
C_SpellBook = { IsSpellKnownOrInSpellBook = function(id) return s.known[id] end }
IsSpellKnown = nil; m:Initialize(); s:Flush()
Check(s.writes == 1, "Modern known-spell API")
s, settings, ns, m = New()
C_Spell = nil; GetSpellInfo = function(id) return s.names[id] end
m:Initialize(); s:Flush()
Check(s.writes == 1, "Legacy spell-name API")
s, settings, ns, m = New(); ns.ready = false
m:Initialize(); s:Flush()
Check(#s.frames == 0 and s.writes == 0, "Login readiness respected")
ns.ready = true; m:ApplySettings(); s:Flush()
Check(s.writes == 1, "Login apply starts module")

s, settings, ns, m = New({ enabled = false }); m:Initialize(); s:Flush()
Check(not s.builds, "Disabled module never invokes provider")
s, settings, ns, m = New({ class = "WARRIOR" }); m:Initialize(); s:Flush()
Check(not s.builds, "Non-Mage never invokes provider")
s, settings, ns, m = New(); s.combat = true; m:Initialize(); s:Flush()
Check(not s.builds, "Combat never invokes provider")
s, settings, ns, m = New(); C_Timer = nil; m:Initialize()
local frame = s.frames[1]
Check(s.writes == 1 and not frame.scripts.OnUpdate, "Missing timer API uses bounded synchronous fallback")
Check(not frame.events.PLAYER_REGEN_ENABLED and not frame.events.SPELL_DATA_LOAD_RESULT,
    "Settled macro retains no combat-end or spell-data subscriptions")
s, settings, ns, m = New(); m:Initialize(); s:Flush()
Check(not pcall(ns.RegisterMacroProvider, "mage", s.provider), "Duplicate provider rejected")
s, settings, ns, m = New()
local body = s.provider.Build()
Check(s.writes == 0 and not ns.charDB.mageMacro.ownedMacros
    and body:find("/castsequence", 1, true), "Provider only generates text")

s, settings, ns, m = New()
s.buildError = "Provider exploded"
m:Initialize()
Check(s.clears == 0, "Scheduling does not clear core errors")
Check(pcall(s.Flush, s) and s.writes == 0 and not ns.charDB.mageMacro.ownedMacros,
    "Timer provider exception is contained without claiming ownership")
Check(m:GetStatus() == "Error: Provider exploded" and s.status == m:GetStatus()
    and s.coreError == "Provider exploded" and #s.reports == 1,
    "Provider failure updates status and reports through the core")
for i = 1, 3 do s:Event("SPELLS_CHANGED"); s:Flush() end
Check(#s.reports == 1 and s.clears == 0, "Identical provider failures do not spam or clear errors")
s.buildError = "Different provider failure"
s:Event("UPDATE_MACROS"); s:Flush()
Check(#s.reports == 2 and s.coreError == s.buildError, "Different provider failures can report")
s.buildError = nil
m:ApplySettings()
Check(s.coreError == "Different provider failure" and s.clears == 0,
    "ApplySettings does not clear an async failure before running")
s:Flush()
Check(s.writes == 1 and s.clears == 1 and not s.coreError
    and m:GetStatus():find("Created character macro", 1, true), "Successful run recovers and clears core error")
s.buildError = "Provider exploded"
s:Event("SPELLS_CHANGED"); s:Flush()
Check(#s.reports == 3, "A new failure after recovery reports again")
s:Event("SPELLS_CHANGED")
local builds = s.builds
settings.enabled = false; m:ApplySettings(); s:Flush()
Check(s.builds == builds and s.writes == 1 and s.clears == 1 and s.coreError
    and next(s.frames[1].events) == nil and m:GetStatus():find("Disabled", 1, true),
    "Disable after failure cancels work without clearing the core failure")

s, settings, ns, m = New()
m:Initialize()
ns.GetSettings = function() error("Run settings failed", 0) end
Check(pcall(s.Flush, s) and s.coreError == "Run settings failed" and s.writes == 0,
    "Run boundary contains exceptions outside provider Build")

s, settings, ns, m = New()
s.names = {}; m:Initialize(); s:Flush()
Check(#s.reports == 0 and not s.coreError and s.clears == 1
    and not m:GetStatus():find("Error:", 1, true), "Expected spell-data unavailability is not an exception")

s, settings, ns, m = New()
C_Timer = nil; s.buildError = "Synchronous provider failed"; m:Initialize()
frame = s.frames[1]
Check(not frame.scripts.OnUpdate
    and s.coreError == s.buildError and s.clears == 0, "Synchronous fallback failure is contained")
s:Event("SPELLS_CHANGED")
Check(#s.reports == 1, "Synchronous repeated failure is deduplicated")
s.buildError = nil; s:Event("SPELLS_CHANGED")
Check(s.writes == 1 and not s.coreError and s.clears == 1 and not frame.scripts.OnUpdate,
    "Synchronous recovery clears error only after running")

print("PASS: " .. passed .. " macro regression checks")

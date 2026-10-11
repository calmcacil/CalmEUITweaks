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

local ns = {}
local frames, timers, macros, settings = {}, {}, {}, {}
local writes, combat = 0, false
local reported = {}
geterrorhandler = function() return function(err) reported[#reported + 1] = err end end
local known, names = {}, {}
local level = 60
ns.ready, ns.charDB = true, {}
Load("core/Bootstrap.lua", ns)
ns.GetSettings = function(key) return settings[key] end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return level end
InCombatLockdown = function() return combat end
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS, MAX_MACRO_LENGTH = 120, 18, 255
strlenutf8 = nil
C_SpellBook, IsPlayerSpell, GetSpellInfo = nil, nil, nil
IsSpellKnown = function(id) return known[id] or false end
C_Spell = { GetSpellInfo = function(id) return names[id] and { name = names[id] } end }
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    frames[#frames + 1] = frame
    return frame
end
GetMacroInfo = function(index)
    local macro = macros[index]
    if macro then return macro.name, "icon", macro.body end
end
GetNumMacros = function()
    local count = 0
    for _ in pairs(macros) do count = count + 1 end
    return 0, count
end
CreateMacro = function(name, _, body, character)
    assert(character and not combat, "Protected character creation contract")
    local index = 121
    while macros[index] do index = index + 1 end
    macros[index] = { name = name, body = body }
    writes = writes + 1
    return index
end
EditMacro = function(index, name, icon, body)
    assert(not combat and name == nil and icon == nil, "Owned update contract")
    macros[index].body = body
    writes = writes + 1
    return index
end

local function Flush()
    local batches = 0
    while #timers > 0 do
        batches = batches + 1
        assert(batches < 30, "Unbounded provider work")
        local batch = timers
        timers = {}
        for _, callback in ipairs(batch) do callback() end
    end
end

local function Event(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end

Load("functions/Macros.lua", ns)
local function Provider(key, name, build)
    return {
        settingsKey = key, class = "MAGE", classLabel = "Mage", defaultName = name,
        Build = build or function() return "/say generated" end,
    }
end

for _, id in ipairs({ "", "   ", "bad\nid" }) do
    Check(not pcall(ns.RegisterMacroProvider, id, Provider("invalid", "Invalid")),
        "Invalid provider ID rejected")
end
for _, field in ipairs({ "settingsKey", "class", "classLabel", "defaultName", "Build" }) do
    local provider = Provider("invalid", "Invalid")
    provider[field] = nil
    Check(not pcall(ns.RegisterMacroProvider, "invalid", provider), "Missing field rejected: " .. field)
    if field ~= "Build" then
        for _, value in ipairs({ "", "   ", "bad\ntext" }) do
            provider[field] = value
            Check(not pcall(ns.RegisterMacroProvider, "invalid", provider),
                "Invalid metadata rejected: " .. field)
        end
    end
end
local invalid = Provider("invalid", string.rep("x", 17))
Check(not pcall(ns.RegisterMacroProvider, "invalid", invalid), "Oversized default name rejected")
Check(#ns.moduleOrder == 0 and #frames == 0, "Rejected registration has no lifecycle side effects")

local buildsA, buildsB = 0, 0
local bodyA, bodyB = "/say alpha", "/say beta"
settings.alphaMacro = { enabled = true, name = "Alpha" }
settings.betaMacro = { enabled = true, name = "Beta" }
ns.charDB.alphaMacro, ns.charDB.betaMacro = {}, {}
local alpha = ns.RegisterMacroProvider("alpha", Provider("alphaMacro", "Alpha", function(...)
    assert(select("#", ...) == 0, "Build must be called without self or arguments")
    buildsA = buildsA + 1
    return bodyA
end))
Check(alpha == ns.modules.alphaMacro and #ns.moduleOrder == 1, "Registration returns the core module")
Check(buildsA == 0 and writes == 0 and #frames == 0, "Registration does not build or activate")
Check(not pcall(ns.RegisterMacroProvider, "alpha", Provider("unused", "Unused")),
    "Duplicate ID rejected")
Check(not pcall(ns.RegisterMacroProvider, "beta", Provider("alphaMacro", "Beta")),
    "Duplicate module/settings key rejected")
local beta = ns.RegisterMacroProvider("beta", Provider("betaMacro", "Beta", function(...)
    assert(select("#", ...) == 0, "Build must be called without self or arguments")
    buildsB = buildsB + 1
    return bodyB
end))
Check(beta == ns.modules.betaMacro and #ns.moduleOrder == 2,
    "Failed module registration does not reserve provider ID")
alpha:Initialize(); beta:Initialize(); Flush()
Check(writes == 2 and buildsA == 1 and buildsB == 1, "Independent providers each build and create")
Check(ns.charDB.alphaMacro.ownedMacros.Alpha.lastGeneratedBody == bodyA
    and ns.charDB.betaMacro.ownedMacros.Beta.lastGeneratedBody == bodyB
    and not ns.charDB.alphaMacro.ownedMacros.Beta, "Provider ownership is isolated by settings key")
settings.alphaMacro.enabled = false; alpha:ApplySettings()
bodyA, bodyB = "/say alpha upgrade", "/say beta upgrade"
Event("SPELLS_CHANGED"); Event("UPDATE_MACROS"); Flush()
Check(buildsA == 1 and buildsB == 2 and writes == 3 and macros[121].body == "/say alpha",
    "Disabling one provider leaves another updating")
Check(next(frames[1].events) == nil and frames[2].events.SPELLS_CHANGED,
    "Disabled provider releases only its own events")
combat = true; Event("SPELLS_CHANGED"); Flush()
Check(buildsB == 2 and frames[2].events.PLAYER_REGEN_ENABLED, "Combat postpones active provider build")
combat = false; Event("PLAYER_REGEN_ENABLED"); Flush()
Check(buildsB == 3 and writes == 3 and not frames[2].events.PLAYER_REGEN_ENABLED,
    "Combat resumes without redundant writes")

local tiers = { { level = 50, spell = 3 }, { level = 20, spell = 2 }, { level = 1, spell = 1 } }
known[1], known[2], known[3] = true, true, true
level = 19
Check(ns.MacroSpells.HighestKnown(tiers) == tiers[3], "Level gates known ranks")
level = 60; known[3] = false
Check(ns.MacroSpells.HighestKnown(tiers) == tiers[2], "Unlearned higher rank is skipped")
IsSpellKnown = nil
IsPlayerSpell = function(id) return known[id] end
Check(ns.MacroSpells.HighestKnown(tiers) == tiers[2], "Sparse legacy API fallback reaches IsPlayerSpell")
C_SpellBook = {
    IsSpellKnownOrInSpellBook = function() error("Unavailable API") end,
    IsSpellKnown = function() return nil end,
}
Check(ns.MacroSpells.HighestKnown(tiers) == tiers[2], "Throwing and nil APIs fall through")
C_SpellBook.IsSpellKnownOrInSpellBook = function() return false end
Check(ns.MacroSpells.HighestKnown(tiers) == nil, "Authoritative false does not fall through")
C_Spell.GetSpellInfo = function() return { name = "" } end
GetSpellInfo = function(id) return id == 2 and "Localized spell" end
Check(ns.MacroSpells.Name(2) == "Localized spell", "Empty modern name uses legacy API")
C_Spell.GetSpellInfo = function() error("Unavailable API") end
Check(ns.MacroSpells.Name(2) == "Localized spell", "Throwing modern name uses legacy API")
C_Spell, GetSpellInfo, IsPlayerSpell, C_SpellBook = nil, nil, nil, nil
Check(ns.MacroSpells.Name(2) == nil and ns.MacroSpells.HighestKnown(tiers) == nil,
    "Missing spell APIs leave helpers unavailable")

local example = Load("docs/templates/MacroProvider.lua", ns)
Check(example == nil and ns.modules.exampleMacro, "Template uses the real provider registration")
ns.modules.exampleMacro:Initialize(); Flush()
Check(writes == 3 and #frames == 2, "Unconfigured template remains inactive for other classes")
local captured
local register = ns.RegisterMacroProvider
ns.RegisterMacroProvider = function(_, provider) captured = provider end
Load("docs/templates/MacroProvider.lua", ns)
ns.RegisterMacroProvider = register
local body, message, missing = captured.Build()
Check(body == nil and type(message) == "string" and missing == nil and writes == 3,
    "Unconfigured scaffold returns a readiness status without side effects")

ns.RegisterMacroProvider("failing", Provider("failingMacro", "Failing", function()
    error("Provider failed", 0)
end)):Initialize()
bodyB = "/say beta still works"
Event("SPELLS_CHANGED"); Flush()
Check(ns.errors.failingMacro == "Error: Provider failed" and #reported == 1
    and ns.errors.betaMacro == nil and macros[122].body == bodyB and writes == 4,
    "A failing provider cannot block another provider's updates")

print("PASS: " .. passed .. " macro provider contract checks")

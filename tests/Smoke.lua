-- Load the actual TOC order against minimal WoW stubs, not a second file list.
local frames, timers, errors = {}, {}, {}
local loggedIn, combat = false, false
local playerClass = "WARRIOR"
local checks = 0
local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

function CreateFrame()
    local frame = {events = {}, scripts = {}}
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    frames[#frames + 1] = frame
    return frame
end
local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end
local function Flush()
    local passes = 0
    while #timers > 0 do
        passes = passes + 1
        assert(passes < 100, "Timer loop in TOC smoke test")
        local batch = timers
        timers = {}
        for _, callback in ipairs(batch) do callback() end
    end
end

C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
SlashCmdList = {}
function IsLoggedIn() return loggedIn end
function InCombatLockdown() return combat end
function UnitClass() return playerClass, playerClass end
function geterrorhandler() return function(err) errors[#errors + 1] = err end end
function LibStub() error("Calm UI Tweaks must not register SharedMedia fonts") end

local pluginRegistration, openedPlugin, openedModule
EllesmereUI = {
    PLUGIN_API_VERSION = 1,
    RegisterPlugin = function(name, config)
        Check(name == "CalmEUITweaks", "Plugin identity mismatch")
        pluginRegistration = config
        return true
    end,
    OpenPlugin = function(name, key)
        openedPlugin, openedModule = name, key
        return true
    end,
    GetBlizzWindowStyle = function() return "eui" end,
}
local euiStore = {unchanged = true}
EllesmereUIDB = euiStore

local ns = {}
local mageProvider
local toc = assert(io.open("CalmEUITweaks/CalmEUITweaks.toc", "r"))
local loaded = 0
for line in toc:lines() do
    local file = line:match("^%s*(.-)%s*$")
    if file ~= "" and file:sub(1, 1) ~= "#" then
        file = file:gsub("\\", "/")
        local chunk, err = loadfile("CalmEUITweaks/" .. file)
        assert(chunk, err)
        if file == "macros/mage.lua" then
            local register = ns.RegisterMacroProvider
            ns.RegisterMacroProvider = function(id, provider)
                mageProvider = provider
                return register(id, provider)
            end
        end
        chunk("CalmEUITweaks", ns)
        loaded = loaded + 1
    end
end
toc:close()
Check(ns.db == nil and CalmUITweaksDB == nil, "Settings initialized before SavedVariables load")
Check(ns.optionsInstalled, "Plugin options registration failed")
Check(ns.optionsMode == "plugin", "Official plugin API was not used")
Check(pluginRegistration.modules[1].key == "Tweaks", "Plugin module missing")
Check(#pluginRegistration.modules[1].pages == 6, "Expected the six supported options pages")
Check(type(ns.RegisterMacroProvider) == "function", "Shared macro registry missing")
Check(ns.modules.chat == ns.Chat, "Chat preset module missing")

-- WoW loads this addon's saved data immediately before ADDON_LOADED.
CalmUITweaksDB = {mageMacro = {enabled = false}}
CalmUITweaksCharDB = {mageMacro = {ownedMacros = {Keep = {lastGeneratedBody = "owned"}}}}
Fire("ADDON_LOADED", "CalmEUITweaks")
Check(ns.initialized and not ns.ready, "Startup ran gameplay before login")
Check(ns.db.mageMacro.enabled == false, "Saved false preference overwritten")
loggedIn = true
Fire("PLAYER_LOGIN")
Flush()
Check(ns.ready, "Login did not start modules")
Check(#errors == 0, "Module lifecycle error: " .. tostring(errors[1]))
Check(ns.GetStatus("mageMacro"):find("Disabled"), "Disabled macro module started")
Check(ns.GetStatus("simpleItemLevel"):find("Waiting"), "Missing SIL dependency not handled")
Check(ns.GetStatus("whatsTraining"):find("Waiting"), "Missing WhatsTraining not handled")
Check(ns.SetSetting("simpleItemLevel", "enabled", false), "Compatibility switch rejected")
Check(ns.GetStatus("simpleItemLevel") == "Disabled", "Compatibility did not stop")
ns.ResetSettings()
Flush()
Check(ns.charDB.mageMacro.ownedMacros.Keep.lastGeneratedBody == "owned", "Reset lost macro ownership")
Check(EllesmereUIDB == euiStore and next(euiStore) == "unchanged", "EUI SavedVariables changed")
Check(ns.OpenOptions() and openedPlugin == "CalmEUITweaks" and openedModule == "Tweaks", "Options target lost")
combat = true
Check(ns.OpenOptions() == false, "Options opened during combat")
Check(#errors == 0, "Post-reset lifecycle errors")

-- Exercise the real deferred provider together with the core reporting boundary.
combat, playerClass = false, "MAGE"
local macros, writes = {}, 0
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
function UnitLevel() return 1 end
C_SpellBook = {IsSpellKnownOrInSpellBook = function(id) return id == 587 or id == 5504 end}
C_Spell = {GetSpellInfo = function(id) return {name = id == 587 and "Conjure Food" or "Conjure Water"} end}
function GetMacroInfo(index)
    local macro = macros[index]
    if macro then return macro.name, "icon", macro.body end
end
function GetNumMacros()
    local count = 0
    for _ in pairs(macros) do count = count + 1 end
    return 0, count
end
function CreateMacro(name, icon, body, characterOnly)
    Check(characterOnly == true, "Integration created an account macro")
    writes = writes + 1
    macros[121] = {name = name, body = body}
    return 121
end
function EditMacro(index, name, icon, body) writes = writes + 1; macros[index].body = body end
ns.SetSetting("mageMacro", "enabled", true)
Flush()
Check(writes == 1 and ns.charDB.mageMacro.ownedMacros["Mage FoodWater"] ~= nil,
    "Integrated Mage startup did not create a verified owned macro")
local build = mageProvider.Build
mageProvider.Build = function() error("injected provider failure") end
Fire("SPELLS_CHANGED")
Flush()
Check(ns.GetStatus("mageMacro"):find("Error:"), "Core masked the deferred provider error")
Check(#errors == 1, "Deferred error was not reported exactly once")
Fire("SPELLS_CHANGED")
Flush()
Check(#errors == 1, "Repeated deferred errors spammed the error handler")
mageProvider.Build = build
ns.SetSetting("mageMacro", "enabled", true)
Check(ns.GetStatus("mageMacro"):find("Error:"), "Queuing work cleared the error before actual recovery")
Flush()
Check(not ns.GetStatus("mageMacro"):find("Error:"), "Successful provider execution did not clear the error")
Check(writes == 1, "Failed or recovered execution rewrote a valid owned macro")
print("PASS: TOC smoke (" .. checks .. " assertions)")

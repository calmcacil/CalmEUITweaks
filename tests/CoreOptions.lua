-- Run from the repository root: lua CalmEUITweaks/tests/CoreOptions.lua
-- Only core and options are loaded; no macro or compatibility modules.
local addonName = "CalmEUITweaks"
local root = "CalmEUITweaks/"
local tests, passed, failed = {}, 0, 0
local fileSets = {
    ["Core.lua"] = { "core/Bootstrap.lua", "core/Settings.lua", "core/Lifecycle.lua", "core/AnchorEvents.lua", "core/Commands.lua" },
    ["Options.lua"] = { "options/Chat.lua", "options/Pages.lua", "options/EllesmereUI.lua" },
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = copy(child, seen) end
    return result
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function truth(value, message)
    if not value then error(message or "expected a truthy value", 2) end
end

local function contains(text, fragment, message)
    truth(type(text) == "string" and text:find(fragment, 1, true),
        message or ("expected text containing " .. fragment .. ", got " .. tostring(text)))
end

local function same(actual, expected, message, seen)
    equal(type(actual), type(expected), message)
    if type(expected) ~= "table" then return equal(actual, expected, message) end
    seen = seen or {}
    if seen[expected] then return equal(actual, seen[expected], message) end
    seen[expected] = actual
    for key, value in pairs(expected) do
        same(actual[key], value, (message or "table") .. "." .. tostring(key), seen)
    end
    for key in pairs(actual) do
        truth(expected[key] ~= nil, (message or "table") .. ": unexpected key " .. tostring(key))
    end
end

local function test(name, run)
    tests[#tests + 1] = { name = name, run = run }
end

local function host()
    local eui = {
        ADDON_GROUPS = {
            { key = "suite", label = "Suite", members = { "EllesmereUIBags" }, nested = { keep = true } },
            { key = "extras", label = "Extras", members = { "ExistingAddon" } },
        },
        ADDON_ROSTER = { { folder = "ExistingAddon", display = "Existing Addon" } },
        _addonInfoByFolder = { ExistingAddon = { folder = "ExistingAddon", keep = true } },
        _modules = { ExistingAddon = { title = "Existing", pages = { "Existing Page" } } },
        _syncExempt = { ExistingAddon = false },
        shown = {},
    }
    function eui:GetMainFrame() return self.mainFrame end
    function eui:ShowModule(name) self.shown[#self.shown + 1] = name end
    function eui.BlankRowCfg() return { type = "label", text = "" } end
    return eui
end

local function sandbox(options)
    options = options or {}
    local s = { ns = {}, frames = {}, labels = {}, rows = {}, sections = {}, timers = {},
        messages = {}, errors = {}, combat = false, loggedIn = false }
    local env = setmetatable({}, { __index = _G })
    s.env = env
    s.ns.Chat = { GetSummary = function() return "Default saved: Not saved\nApplied to this character: Never\nNot applied" end }
    env._G = env
    env.CalmUITweaksDB = options.db
    env.CalmUITweaksCharDB = options.charDB
    env.EUIDB = { profile = { font = "Original Font", enabled = false }, profiles = { Existing = {} } }
    env.EllesmereUIDB = { profiles = { Existing = { marker = "untouched" } } }
    s.storageAliases = { EUIDB = env.EUIDB, EllesmereUIDB = env.EllesmereUIDB }
    s.storageBefore = { EUIDB = copy(env.EUIDB), EllesmereUIDB = copy(env.EllesmereUIDB) }
    if not options.noHost then env.EllesmereUI = host() end
    env.SlashCmdList = {}
    env.MAX_MACRO_NAME_LENGTH = 16
    env.print = function(message) s.messages[#s.messages + 1] = message end
    env.geterrorhandler = function()
        return function(err) s.errors[#s.errors + 1] = err end
    end
    env.IsLoggedIn = function() return s.loggedIn end
    env.InCombatLockdown = function() return s.combat end
    env.C_Timer = { After = function(delay, callback)
        equal(delay, 0, "apply debounce delay")
        s.timers[#s.timers + 1] = callback
    end }
    env.CreateFrame = function(kind)
        equal(kind, "Frame", "unexpected frame kind")
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, handler) self.scripts[event] = handler end
        s.frames[#s.frames + 1] = frame
        return frame
    end
    -- Font selection, profile synchronization, and capture APIs are forbidden here.
    local function forbidden() error("unexpected font/profile/capture API", 2) end
    env.SetCVar, env.hooksecurefunc = forbidden, forbidden
    env.GameFontNormal = { SetFont = forbidden }
    env.GameFontHighlightSmall = { SetFont = forbidden }
    local eui = env.EllesmereUI
    if eui then
        eui.SetFont, eui.SyncProfiles, eui.RegisterModule = forbidden, forbidden, forbidden
        eui.CaptureWidget = forbidden
        eui.Widgets = {}
        function eui.Widgets:SectionHeader(parent, text, y)
            s.section = text
            s.sections[#s.sections + 1] = { parent = parent, text = text, y = y }
            return nil, 30
        end
        function eui.Widgets:DualRow(parent, y, left, right)
            s.rows[#s.rows + 1] = { parent = parent, y = y, left = left, right = right, section = s.section }
            for _, cfg in ipairs({ left, right }) do
                if cfg.type == "toggle" then
                    equal(cfg.noCapture, true, "editable widget must opt out of EUI capture")
                    equal(type(cfg.getValue()), "boolean", "toggle getter must be independent")
                end
            end
            return nil, 36
        end
        function eui.Widgets:Spacer(_, _, height) return nil, height end
        eui.CONTENT_PAD = 10
        eui.PanelPP = { Point = function(label, ...) label:SetPoint(...) end }
        eui.MakeFont = function(parent) return parent:CreateFontString(nil, "OVERLAY") end
    end
    s.parent = {}
    function s.parent:CreateFontString(_, layer, template)
        equal(layer, "OVERLAY")
        local label = { points = {}, updates = 0 }
        function label:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function label:SetJustifyH(value) equal(value, "LEFT") end
        function label:SetWordWrap(value) equal(value, true) end
        function label:SetText(text) self.text = text; self.updates = self.updates + 1 end
        function label:GetStringHeight() return 20 end
        label.SetFont = forbidden
        s.labels[#s.labels + 1] = label
        return label
    end
    env.LibStub = forbidden
    function s:load(file, name)
        for _, path in ipairs(assert(fileSets[file], "unexpected test load: " .. file)) do
            local chunk, err
            if setfenv then
                chunk, err = loadfile(root .. path)
                if chunk then setfenv(chunk, env) end
            else
                chunk, err = loadfile(root .. path, "t", env)
            end
            truth(chunk, err)
            chunk(name or addonName, self.ns)
        end
        return self
    end
    function s:event(event, ...)
        -- Snapshot delivery: listeners may unregister themselves during an event.
        local listeners = {}
        for _, frame in ipairs(self.frames) do
            if frame.events[event] then listeners[#listeners + 1] = frame end
        end
        for _, frame in ipairs(listeners) do frame.scripts.OnEvent(frame, event, ...) end
    end
    function s:initialize() self:event("ADDON_LOADED", addonName); return self end
    function s:login() self:event("PLAYER_LOGIN"); return self end
    function s:flush()
        local pending = self.timers
        self.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
    function s:storageUnchanged()
        equal(env.EUIDB, self.storageAliases.EUIDB, "EUIDB identity")
        equal(env.EllesmereUIDB, self.storageAliases.EllesmereUIDB, "EllesmereUIDB identity")
        same(env.EUIDB, self.storageBefore.EUIDB, "EUIDB")
        same(env.EllesmereUIDB, self.storageBefore.EllesmereUIDB, "EllesmereUIDB")
    end
    function s:module(key)
        local module = { initialized = 0, applied = 0, addons = {} }
        function module:Initialize() self.initialized = self.initialized + 1 end
        function module:ApplySettings() self.applied = self.applied + 1 end
        function module:OnAddonLoaded(name) self.addons[#self.addons + 1] = name end
        self.ns.RegisterModule(key, module)
        return module
    end
    function s:build(page)
        local module = self.pluginRegistration.modules[1]
        return module.buildPage(page, self.parent, -10)
    end
    function s:findLabel(fragment, exact)
        for _, label in ipairs(self.labels) do
            if (exact and label.text == fragment) or (not exact and label.text:find(fragment, 1, true)) then
                return label
            end
        end
        error("no label containing " .. fragment, 2)
    end
    return s
end

local function core(options) return sandbox(options):load("Core.lua") end

local privateRegistries = { "ADDON_GROUPS", "ADDON_ROSTER", "_addonInfoByFolder", "_modules", "_syncExempt" }

local function unchangedHost(eui)
    local before, aliases, seen = copy(eui), {}, {}
    local function capture(parent)
        if seen[parent] then return end
        seen[parent] = true
        for key, value in pairs(parent) do
            if type(value) == "table" then
                aliases[#aliases + 1] = { parent = parent, key = key, value = value }
                capture(value)
            end
        end
    end
    capture(eui)
    return function()
        same(eui, before, "native API must leave host registries untouched")
        for _, alias in ipairs(aliases) do
            equal(alias.parent[alias.key], alias.value, "native API replaced host alias " .. tostring(alias.key))
        end
    end
end

local function enablePluginAPI(s)
    local eui = s.env.EllesmereUI
    s.pluginCalls, s.openPluginCalls = 0, 0
    eui.PLUGIN_API_VERSION = 1
    eui.IsSearchPrebuild = function() return false end
    eui.RegisterPlugin = function(name, config, ...)
        equal(name, addonName, "RegisterPlugin must be a dot call")
        equal(select("#", ...), 0, "RegisterPlugin argument count")
        equal(type(config), "table")
        s.pluginCalls = s.pluginCalls + 1
        s.pluginRegistration = config
        return true
    end
    eui.OpenPlugin = function(name, key, ...)
        equal(name, addonName, "OpenPlugin must be a dot call")
        equal(key, "Tweaks")
        equal(select("#", ...), 0, "OpenPlugin argument count")
        s.openPluginCalls = s.openPluginCalls + 1
        return true
    end
    return eui
end

local function optionsFixture(options)
    local s = core(options)
    enablePluginAPI(s)
    return s:load("Options.lua")
end

local function usefulReason(s, returned)
    local reason = s.ns.optionsError or returned
    truth(type(reason) == "string" and reason:match("%S"), "failure must provide a useful reason")
    return reason
end

test("settings are not created by chunk loading or unrelated ADDON_LOADED", function()
    local s = core()
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    equal(s.ns.db, nil)
    equal(s.ns.charDB, nil)
    equal(s.ns.GetSettings("mageMacro"), s.ns.defaults.mageMacro)
    s:event("ADDON_LOADED", "UnrelatedAddon")
    equal(s.ns.initialized, nil)
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    s:storageUnchanged()
end)

test("own ADDON_LOADED creates independent saved settings and ownership storage", function()
    local s = core():initialize()
    equal(s.ns.db, s.env.CalmUITweaksDB)
    equal(s.ns.charDB, s.env.CalmUITweaksCharDB)
    same(s.ns.db, s.ns.defaults)
    same(s.ns.charDB.mageMacro, {})
    equal(type(s.ns.charDB.chat), "table")
    truth(s.ns.db ~= s.ns.defaults)
    truth(s.ns.db.mageMacro ~= s.ns.defaults.mageMacro)
    equal(s.ns.ready, nil)
    s:storageUnchanged()
end)

test("default filling preserves false, unknown fields, and ownership records", function()
    local db = { version = "bad", mageMacro = { enabled = false, name = 42, extra = "keep" },
        simpleItemLevel = { enabled = false, inventory = false, reagent = false, bank = "bad" },
        whatsTraining = { enabled = false }, unrelated = { keep = 17 } }
    local ownership = { name = "Owned", body = "/use water", marker = true }
    local charDB = { version = false, mageMacro = ownership, another = false }
    local s = core({ db = db, charDB = charDB }):initialize()
    equal(s.ns.db, db)
    equal(s.ns.charDB, charDB)
    equal(db.version, 1)
    equal(db.mageMacro.enabled, false)
    equal(db.mageMacro.name, "Mage FoodWater")
    equal(db.mageMacro.extra, "keep")
    equal(db.simpleItemLevel.enabled, false)
    equal(db.simpleItemLevel.inventory, false)
    equal(db.simpleItemLevel.reagent, false)
    equal(db.simpleItemLevel.bank, true)
    equal(db.whatsTraining.enabled, false)
    equal(db.unrelated.keep, 17)
    equal(charDB.version, 1)
    equal(charDB.mageMacro, ownership)
    equal(charDB.another, false)
    s:storageUnchanged()
end)

test("malformed saved variable containers and nested settings are repaired", function()
    for _, value in ipairs({ false, 7, "invalid" }) do
        local s = core({ db = value, charDB = value }):initialize()
        same(s.ns.db, s.ns.defaults)
        same(s.ns.charDB.mageMacro, {})
        equal(type(s.ns.charDB.chat), "table")
    end
    local s = core({ db = { mageMacro = false, simpleItemLevel = "bad", whatsTraining = 1 },
        charDB = { mageMacro = "bad" } }):initialize()
    same(s.ns.db, s.ns.defaults)
    same(s.ns.charDB.mageMacro, {})
end)

test("invalid persisted macro names revert to the default", function()
    for _, name in ipairs({ "", "   ", string.rep("x", 17), "bad|name", "bad\nname", false, {} }) do
        local s = core({ db = { mageMacro = { name = name } } }):initialize()
        equal(s.ns.db.mageMacro.name, "Mage FoodWater")
    end
end)

test("module Initialize is once-only and ApplySettings starts at PLAYER_LOGIN", function()
    local s = core()
    local module = s:module("mageMacro")
    s:initialize()
    equal(module.initialized, 1)
    equal(module.applied, 0)
    local db, charDB = s.ns.db, s.ns.charDB
    s:initialize()
    equal(module.initialized, 1)
    equal(module.applied, 0)
    equal(s.ns.db, db)
    equal(s.ns.charDB, charDB)
    s:login()
    equal(s.ns.ready, true)
    equal(module.initialized, 1)
    equal(module.applied, 1)
    s:login()
    equal(module.applied, 1)
end)

test("login applies registered modules in registration order", function()
    local s = core()
    local calls = {}
    for _, key in ipairs({ "mageMacro", "simpleItemLevel", "whatsTraining" }) do
        s.ns.RegisterModule(key, {
            Initialize = function() calls[#calls + 1] = "init:" .. key end,
            ApplySettings = function() calls[#calls + 1] = "apply:" .. key end,
        })
    end
    s:initialize():login()
    same(calls, { "init:mageMacro", "init:simpleItemLevel", "init:whatsTraining",
        "apply:mageMacro", "apply:simpleItemLevel", "apply:whatsTraining" })
end)


test("late ADDON_LOADED is forwarded only after own settings initialize", function()
    local s = core()
    local module = s:module("simpleItemLevel")
    s:event("ADDON_LOADED", "Before")
    equal(#module.addons, 0)
    s:initialize()
    s:event("ADDON_LOADED", "SimpleItemLevel")
    same(module.addons, { "SimpleItemLevel" })
    equal(module.applied, 0)
    s:storageUnchanged()
end)

test("module failures are isolated and surfaced through status and error handler", function()
    local s = core()
    s.ns.RegisterModule("mageMacro", { Initialize = function() error("initialize exploded") end,
        ApplySettings = function() error("apply exploded") end })
    local survivor = s:module("simpleItemLevel")
    s:initialize():login()
    equal(survivor.initialized, 1)
    equal(survivor.applied, 1)
    equal(#s.errors, 2)
    contains(s.ns.GetStatus("mageMacro"), "Error:")
    contains(s.ns.GetStatus("mageMacro"), "apply exploded")
end)

test("caught failures override a stale module getter and clear after synchronous recovery", function()
    local s = optionsFixture()
    local module = { GetStatus = function() return "Ready (stale)" end,
        OnAddonLoaded = function() end,
        ApplySettings = function() error("apply failed") end }
    s.ns.RegisterModule("mageMacro", module)
    local survivor = s:module("simpleItemLevel")
    s:initialize():login()
    equal(survivor.applied, 1)
    contains(s.ns.GetStatus("mageMacro"), "apply failed")
    s.ns.CallModule("mageMacro", "OnAddonLoaded", "Unrelated")
    contains(s.ns.GetStatus("mageMacro"), "apply failed")
    module.ApplySettings = function() end
    s.ns.CallModule("mageMacro", "ApplySettings")
    equal(s.ns.GetStatus("mageMacro"), "Ready (stale)")
end)

test("throwing status getters are contained and do not abort startup or UI refresh", function()
    local s = optionsFixture()
    s.ns.RegisterModule("mageMacro", { GetStatus = function() error("getter failed") end })
    local survivor = s:module("simpleItemLevel")
    s:initialize():login()
    s:build("General")
    equal(survivor.applied, 1)
    contains(s.ns.GetStatus("mageMacro"), "getter failed")
    truth(pcall(s.ns.RefreshOptions))
    equal(#s.errors, 1)
end)

test("broken error handlers and refresh callbacks cannot defeat module isolation", function()
    local s = core()
    s.env.geterrorhandler = function() return function() error("handler failed") end end
    s.ns.RefreshOptions = function() error("refresh failed") end
    s.ns.RegisterModule("mageMacro", { ApplySettings = function() error("original failure") end })
    local survivor = s:module("simpleItemLevel")
    truth(pcall(function() s:initialize():login() end))
    equal(survivor.applied, 1)
    contains(s.ns.GetStatus("mageMacro"), "original failure")
    contains(s.ns.GetStatus("options"), "refresh failed")
    truth(#s.messages >= 1)
end)

test("identical errors are deduplicated without losing their displayed status", function()
    local s = core()
    s.ns.ReportError("mageMacro", "same failure")
    s.ns.ReportError("mageMacro", "same failure")
    equal(#s.errors, 1)
    contains(s.ns.GetStatus("mageMacro"), "same failure")
    s.ns.ReportError("mageMacro", "different failure")
    equal(#s.errors, 2)
end)

test("a recurring error reports again after recovery", function()
    local s = core()
    s.ns.ReportError("mageMacro", "provider failed")
    s.ns.ReportError("mageMacro", "provider failed")
    equal(#s.errors, 1, "repeated failures in one episode must be deduplicated")
    s.ns.ClearError("mageMacro")
    equal(s.ns.errors.mageMacro, nil)
    s.ns.ReportError("mageMacro", "provider failed")
    equal(#s.errors, 2, "the same failure must report again after recovery")
    contains(s.ns.GetStatus("mageMacro"), "provider failed")
end)

test("deferred modules retain errors until their actual execution clears them", function()
    local s = core()
    s.ns.RegisterModule("mageMacro", { asyncErrors = true,
        ApplySettings = function() end, GetStatus = function() return "Ready" end })
    s.ns.ReportError("mageMacro", "deferred failure")
    s.ns.CallModule("mageMacro", "ApplySettings")
    contains(s.ns.GetStatus("mageMacro"), "deferred failure")
    s.ns.ClearError("mageMacro")
    equal(s.ns.GetStatus("mageMacro"), "Ready")
end)

test("cached macro name read and write failures are contained", function()
    local s = optionsFixture():initialize()
    s:build("Mage Macro")
    local nameLabel = s:findLabel("Macro name:")
    local getSettings = s.ns.GetSettings
    s.ns.GetSettings = function() error("cached getter failed") end
    s.ns.RefreshOptions()
    contains(s.ns.GetStatus("options"), "cached getter failed")
    s.ns.GetSettings = getSettings
    local setText = nameLabel.SetText
    nameLabel.SetText = function() error("cached setter failed") end
    s.ns.RefreshOptions()
    contains(s.ns.GetStatus("options"), "cached setter failed")
    nameLabel.SetText = setText
    s.ns.RefreshOptions()
    equal(s.ns.errors.options, nil, "healthy cached label releases its error")
end)

test("duplicate module registration rejects without replacing the first module", function()
    local s = core()
    local module = s:module("mageMacro")
    local ok = pcall(s.ns.RegisterModule, "mageMacro", {})
    equal(ok, false)
    equal(s.ns.modules.mageMacro, module)
    same(s.ns.moduleOrder, { "mageMacro" })
end)

test("setters reject calls before ADDON_LOADED without creating saved variables", function()
    local s = core()
    local defaults = copy(s.ns.defaults)
    local ok, err = s.ns.SetSetting("mageMacro", "enabled", false)
    equal(ok, false)
    contains(err, "not loaded")
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    same(s.ns.defaults, defaults)
    s.ns.ResetSettings()
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
end)

test("valid setters trim names, preserve false, and apply only after login", function()
    local s = core():initialize()
    local module = s:module("mageMacro")
    local refreshes = 0
    s.ns.RefreshOptions = function() refreshes = refreshes + 1 end
    equal(s.ns.SetSetting("mageMacro", "enabled", false), true)
    equal(s.ns.db.mageMacro.enabled, false)
    equal(module.applied, 0)
    s:login()
    equal(s.ns.SetSetting("mageMacro", "name", "  My Water  "), true)
    equal(s.ns.db.mageMacro.name, "My Water")
    equal(module.applied, 2)
    equal(refreshes, 2)
    equal(s.ns.SetSetting("mageMacro", "name", string.rep("x", 16)), true)
    s:storageUnchanged()
end)

test("invalid settings and names reject without apply or saved data mutation", function()
    local s = core():initialize()
    local module = s:module("mageMacro")
    s:login()
    local before, refreshes = copy(s.ns.db), 0
    s.ns.RefreshOptions = function() refreshes = refreshes + 1 end
    local invalid = {
        { "unknown", "enabled", true }, { "version", "enabled", true },
        { "mageMacro", "unknown", true },
        { "mageMacro", "enabled", "false" }, { "mageMacro", "name", false },
        { "mageMacro", "name", "   " }, { "mageMacro", "name", string.rep("x", 17) },
        { "mageMacro", "name", "bad|name" }, { "mageMacro", "name", "bad\nname" },
        { "mageMacro", "name", "bad\0name" },
    }
    for _, args in ipairs(invalid) do
        local ok, err = s.ns.SetSetting(args[1], args[2], args[3])
        equal(ok, false)
        truth(type(err) == "string")
        same(s.ns.db, before)
    end
    equal(module.applied, 1)
    equal(refreshes, 0)
end)


test("reset restores only preferences and preserves ownership and host storage", function()
    local ownership = { name = "Owned", body = "existing", marker = "owned" }
    local s = core({ db = { mageMacro = { enabled = false, name = "Custom" }, keep = { value = 3 } },
        charDB = { version = 1, mageMacro = ownership } }):initialize()
    local module = s:module("mageMacro")
    s:login()
    local db, charDB, beforeChar = s.ns.db, s.ns.charDB, copy(s.ns.charDB)
    s.ns.ResetSettings()
    equal(s.ns.db, db)
    equal(s.ns.charDB, charDB)
    equal(s.ns.charDB.mageMacro, ownership)
    same(s.ns.charDB, beforeChar)
    for key, value in pairs(s.ns.defaults) do same(s.ns.db[key], value) end
    equal(s.ns.db.keep.value, 3)
    truth(s.ns.db.mageMacro ~= s.ns.defaults.mageMacro)
    equal(module.applied, 2)
    s:storageUnchanged()
end)

test("reset disables chat automation while preserving the default and character receipt", function()
    local preset = { export = "stored chat setup", savedAt = 123 }
    local receipt = { appliedExport = preset.export, appliedSavedAt = 123, appliedAt = 124 }
    local s = core({ db = { chat = { autoApply = true, default = preset } },
        charDB = { chat = receipt } }):initialize():login()
    local before = copy(receipt)
    s.ns.ResetSettings()
    equal(s.ns.db.chat.autoApply, false)
    equal(s.ns.db.chat.default, preset)
    same(s.ns.charDB.chat, before)
    s:storageUnchanged()
end)

test("reset before PLAYER_LOGIN does not activate modules", function()
    local s = core():initialize()
    local module = s:module("mageMacro")
    s.ns.SetSetting("mageMacro", "enabled", false)
    s.ns.ResetSettings()
    equal(s.ns.db.mageMacro.enabled, true)
    equal(module.applied, 0, "reset must respect the same login gate as setters")
    equal(s.ns.ready, nil)
end)

test("spacer layouts migrate to account storage without replacing shared layouts", function()
    local legacy = { [1] = { width = 63, height = 18,
        position = { point = "CENTER", relPoint = "CENTER", x = 44, y = -90 } } }
    local receipt = { appliedSavedAt = 123, appliedAt = 125 }
    local baseline = { player = { base = -10, side = "LEFT" } }
    local first = core({ db = { spacers = { spacer1 = true }, spacerCorners = { player = "TOPRIGHT" } },
        charDB = { spacers = legacy, chat = receipt, spacerCorners = baseline } }):initialize()
    same(first.ns.db.spacerLayouts, legacy)
    truth(first.ns.db.spacerLayouts[1] ~= legacy[1], "migration must copy the layout")
    truth(first.ns.db.spacerLayouts[1].position ~= legacy[1].position, "migration must copy nested position")
    equal(first.ns.charDB.spacers, nil)
    equal(first.ns.charDB.chat, receipt)
    equal(first.ns.charDB.spacerCorners, baseline)
    local second = core({ db = copy(first.ns.db),
        charDB = { spacers = { [1] = { width = 99, height = 99 } } } }):initialize()
    equal(second.ns.db.spacerLayouts[1].width, 63, "later characters must not overwrite account geometry")
    equal(second.ns.db.spacerLayouts[1].position.x, 44)
    equal(second.ns.db.spacers.spacer1, true)
    equal(second.ns.db.spacerCorners.player, "TOPRIGHT")
    same(second.ns.charDB.chat, {})
    same(second.ns.charDB.spacerCorners, {})
    local layouts = second.ns.db.spacerLayouts
    second.ns.ResetSettings()
    equal(second.ns.db.spacerLayouts, layouts, "preference reset preserves shared geometry")
    equal(second.ns.db.spacers.spacer1, false)
    equal(second.ns.db.spacerCorners.player, "DEFAULT")
end)

test("session login hook runs once after readiness and before settings apply", function()
    for _, late in ipairs({ false, true }) do
        local s = core()
        s.loggedIn = late
        local calls = {}
        s.ns.RegisterModule("chat", {
            Initialize = function() calls[#calls + 1] = "init" end,
            OnLogin = function()
                truth(s.ns.ready and s.ns.db and s.ns.charDB)
                calls[#calls + 1] = "login"
            end,
            ApplySettings = function() calls[#calls + 1] = "apply" end,
        })
        s:initialize():login():login()
        same(calls, { "init", "login", "apply" })
    end
end)

test("apply requests debounce per module, wait for readiness, and honor cancellation", function()
    local s = core()
    local macro, sil = s:module("mageMacro"), s:module("simpleItemLevel")
    s.ns.RequestApply("mageMacro")
    equal(#s.timers, 0)
    s:initialize():login()
    s.ns.RequestApply("mageMacro")
    s.ns.RequestApply("mageMacro")
    s.ns.RequestApply("simpleItemLevel")
    equal(#s.timers, 2)
    equal(macro.applied, 1)
    s:flush()
    equal(macro.applied, 2)
    equal(sil.applied, 2)
    s.ns.RequestApply("mageMacro")
    s.ns.ready = false
    s:flush()
    equal(macro.applied, 2)
    s.ns.ready = true
    s.ns.RequestApply("mageMacro")
    s:flush()
    equal(macro.applied, 3)
end)

test("status refreshes are deduplicated and module status has precedence", function()
    local s = core()
    local refreshes = 0
    s.ns.RefreshOptions = function() refreshes = refreshes + 1 end
    equal(s.ns.GetStatus("mageMacro"), "Waiting for login.")
    s.ns.SetStatus("mageMacro", "Ready")
    s.ns.SetStatus("mageMacro", "Ready")
    equal(refreshes, 1)
    equal(s.ns.GetStatus("mageMacro"), "Ready")
    s.ns.RegisterModule("mageMacro", { GetStatus = function() return "Live module status" end })
    equal(s.ns.GetStatus("mageMacro"), "Live module status")
end)

test("slash status, help, and macro-name handle whitespace and validation", function()
    local s = core():initialize()
    s:module("mageMacro")
    s.ns.SetStatus("mageMacro", "Available")
    equal(s.env.SLASH_CALMUITWEAKS1, "/calmtweaks")
    local slash = s.env.SlashCmdList.CALMUITWEAKS
    slash("  STATUS  ")
    contains(s.messages[1], "Options:")
    contains(s.messages[2], "mageMacro: Available")
    slash("  MACRO-NAME    New Water   ")
    equal(s.ns.db.mageMacro.name, "New Water")
    contains(s.messages[#s.messages], "previous macros are left intact")
    slash("macro-name bad|name")
    equal(s.ns.db.mageMacro.name, "New Water")
    contains(s.messages[#s.messages], "plain text")
    slash("unknown")
    contains(s.messages[#s.messages], "Commands:")
end)

test("slash reset requires confirmation and preserves character ownership", function()
    local s = core():initialize():login()
    s.ns.db.mageMacro.enabled = false
    s.ns.charDB.mageMacro.owned = { name = "Existing", body = "existing body" }
    local before = copy(s.ns.charDB)
    local slash = s.env.SlashCmdList.CALMUITWEAKS
    slash("reset")
    equal(s.ns.db.mageMacro.enabled, false)
    contains(s.messages[#s.messages], "reset confirm")
    slash("reset confirm")
    equal(s.ns.db.mageMacro.enabled, true)
    same(s.ns.charDB, before)
    contains(s.messages[#s.messages], "ownership and existing macros are preserved")
end)

test("empty slash falls back safely when the options adapter is absent", function()
    local s = core()
    s.env.SlashCmdList.CALMUITWEAKS(nil)
    contains(s.messages[#s.messages], "unavailable")
    s.ns.optionsError = "Unsupported host"
    s.env.SlashCmdList.CALMUITWEAKS("  ")
    contains(s.messages[#s.messages], "Unsupported host")
    equal(s.env.CalmUITweaksDB, nil)
end)

test("absent host rejects cleanly while Core remains usable", function()
    local s = core()
    s.env.EllesmereUI = nil
    s:load("Options.lua")
    equal(s.ns.optionsInstalled, false)
    contains(s.ns.optionsError, "unavailable")
    s:initialize()
    equal(s.ns.SetSetting("mageMacro", "enabled", false), true)
    equal(s.ns.OpenOptions(), false)
    contains(s.messages[#s.messages], "unavailable")
end)

test("empty right slots use fresh EUI blanks and finish their section", function()
    local s = optionsFixture():initialize():login()
    local blanks = {}
    s.env.EllesmereUI.BlankRowCfg = function()
        local cfg = { type = "label", text = "" }
        blanks[cfg] = true
        return cfg
    end
    local used = {}
    for _, page in ipairs(s.pluginRegistration.modules[1].pages) do
        s.rows = {}
        truth(s:build(page) > 0)
        for index, row in ipairs(s.rows) do
            truth(row.left and row.right, "DualRow requires both slots")
            truth(row.left.type ~= "label", "rows must fill the left slot first")
            if row.right.type == "label" and row.right.text == "" then
                truth(blanks[row.right], "empty slots must use EUI's blank factory")
                truth(not used[row.right], "each empty slot needs a fresh config")
                used[row.right] = true
                local following = s.rows[index + 1]
                truth(not following or following.section ~= row.section,
                    "only a section's final row may have an empty slot: " .. page)
            end
        end
    end
    s:storageUnchanged()
end)


test("native registration and opening need none of the legacy internals", function()
    local s = core()
    local eui = enablePluginAPI(s)
    eui.PLUGIN_API_VERSION = 2
    for _, key in ipairs(privateRegistries) do eui[key] = nil end
    eui.GetMainFrame, eui.ShowModule = nil, nil
    local unchanged = unchangedHost(eui)
    s:load("Options.lua")
    equal(s.ns.optionsInstalled, true)
    equal(s.ns.optionsMode, "plugin")
    equal(s.ns.OpenOptions(), true)
    equal(s.openPluginCalls, 1)
    unchanged()
    s:storageUnchanged()
end)


test("missing RegisterPlugin disables options without mutating the host or blocking features", function()
    local s = core()
    local eui = enablePluginAPI(s)
    eui.RegisterPlugin = nil
    local unchanged = unchangedHost(eui)
    s:load("Options.lua")
    equal(s.ns.optionsInstalled, false)
    equal(s.ns.optionsMode, nil)
    contains(s.ns.optionsError, "Update EllesmereUI")
    equal(s.pluginCalls, 0)
    equal(s.ns.OpenOptions(), false)
    equal(s.openPluginCalls, 0)
    unchanged()
    s:initialize():login()
    equal(s.ns.SetSetting("mageMacro", "enabled", false), true)
    equal(s.ns.db.mageMacro.enabled, false)
end)

local function rejectedPlugin(mutate, expected)
    local s = core()
    local eui = enablePluginAPI(s)
    mutate(eui, s)
    local unchanged = unchangedHost(eui)
    truth(pcall(s.load, s, "Options.lua"), "native API rejection must not escape chunk loading")
    equal(s.ns.optionsInstalled, false)
    equal(s.ns.optionsMode, nil)
    local reason = usefulReason(s)
    if expected then contains(reason, expected) end
    equal(s.ns.OpenOptions(), false)
    equal(s.openPluginCalls, 0)
    unchanged()
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    s:storageUnchanged()
    return s
end

for _, version in ipairs({ { name = "missing" }, { name = "zero", value = 0 },
    { name = "negative", value = -1 }, { name = "string", value = "1" },
    { name = "boolean", value = false }, { name = "table", value = {} } }) do
    test("present API with " .. version.name .. " version rejects without legacy fallback", function()
        local s = rejectedPlugin(function(eui) eui.PLUGIN_API_VERSION = version.value end)
        equal(s.pluginCalls, 0, "invalid API version must be rejected before registration")
    end)
end

test("present malformed RegisterPlugin never falls back to legacy", function()
    for _, value in ipairs({ false, true, "unsupported", {} }) do
        local s = rejectedPlugin(function(eui) eui.RegisterPlugin = value end)
        equal(s.pluginCalls, 0)
    end
end)

test("native registration requires a callable OpenPlugin before any registration", function()
    for _, value in ipairs({ {}, { value = false }, { value = true }, { value = "unsupported" } }) do
        local s = rejectedPlugin(function(eui) eui.OpenPlugin = value.value end)
        equal(s.pluginCalls, 0)
    end
end)

test("API registration rejection reports a useful reason and never falls back", function()
    rejectedPlugin(function(eui)
        eui.RegisterPlugin = function(name)
            equal(name, addonName)
            return false, "registration rejected by host"
        end
    end, "reject")
end)

test("API registration exceptions are contained without legacy fallback", function()
    rejectedPlugin(function(eui)
        eui.RegisterPlugin = function() error("native registration exploded") end
    end, "native registration exploded")
end)

test("API registration accepts only literal true", function()
    for _, result in ipairs({ {}, { value = "accepted" }, { value = 1 }, { value = {} } }) do
        rejectedPlugin(function(eui) eui.RegisterPlugin = function() return result.value end end)
    end
end)


test("native opening uses OpenPlugin exclusively with dot-call arguments", function()
    local s = optionsFixture()
    local eui = s.env.EllesmereUI
    eui.ShowModule = function() error("native opening fell back to ShowModule") end
    equal(s.ns.OpenOptions(), true)
    equal(s.openPluginCalls, 1)
    s.env.SlashCmdList.CALMUITWEAKS("")
    equal(s.openPluginCalls, 2)
    same(eui.shown, {})
    equal(s.env.CalmUITweaksDB, nil)
    s:storageUnchanged()
end)

test("native opening false reports a useful reason without ShowModule fallback", function()
    local s = optionsFixture()
    s.env.EllesmereUI.OpenPlugin = function() return false, "host refused to open plugin" end
    local opened, reason = s.ns.OpenOptions()
    equal(opened, false)
    local reported = usefulReason(s, reason)
    same(s.env.EllesmereUI.shown, {})
    s.env.SlashCmdList.CALMUITWEAKS("")
    contains(s.messages[#s.messages], reported)
end)

test("native opening accepts only literal true and explains a missing host reason", function()
    for _, result in ipairs({ {}, { value = false }, { value = "opened" },
        { value = 1 }, { value = {} } }) do
        local s = optionsFixture()
        s.env.EllesmereUI.OpenPlugin = function() return result.value end
        local opened, reason = s.ns.OpenOptions()
        equal(opened, false)
        usefulReason(s, reason)
        same(s.env.EllesmereUI.shown, {})
    end
end)

test("native opening exceptions are contained with no legacy fallback", function()
    local s = optionsFixture()
    s.env.EllesmereUI.OpenPlugin = function() error("native opening exploded") end
    local called, opened, reason = pcall(s.ns.OpenOptions)
    equal(called, true)
    equal(opened, false)
    contains(usefulReason(s, reason), "native opening exploded")
    same(s.env.EllesmereUI.shown, {})
end)

test("native opening fails closed if OpenPlugin disappears after registration", function()
    local s = optionsFixture()
    s.env.EllesmereUI.OpenPlugin = nil
    equal(s.ns.OpenOptions(), false)
    usefulReason(s)
    same(s.env.EllesmereUI.shown, {})
end)

test("native opening checks combat before calling any host opening method", function()
    local s = optionsFixture()
    local eui = s.env.EllesmereUI
    s.combat = true
    equal(s.ns.OpenOptions(), false)
    equal(s.openPluginCalls, 0)
    s.env.SlashCmdList.CALMUITWEAKS("")
    contains(s.messages[#s.messages], "combat")
    s.combat = false
    s.env.InCombatLockdown = function() error("combat getter failed") end
    equal(s.ns.OpenOptions(), false)
    s.env.InCombatLockdown = nil
    equal(s.ns.OpenOptions(), false)
    s.env.InCombatLockdown = function() return nil end
    equal(s.ns.OpenOptions(), false)
    equal(s.openPluginCalls, 0)
    same(eui.shown, {})
end)

test("slash status reports plugin registration and prioritizes options errors", function()
        local s = optionsFixture()
        local expected = "registered via EUI plugin API"
        local slash = s.env.SlashCmdList.CALMUITWEAKS
        slash("status")
        contains(s.messages[#s.messages], expected)
        s.ns.optionsError = "adapter open failure"
        slash("status")
        contains(s.messages[#s.messages], "adapter open failure")
        s.ns.optionsRenderError = "render failure"
        slash("status")
        contains(s.messages[#s.messages], "render failure")
        s.ns.ReportError("options", "cached status failure")
        slash("status")
        contains(s.messages[#s.messages], "cached status failure")
end)

local function checkVisiblePages(s)
    local before = copy(s.ns.db)
    for _, page in ipairs(s.pluginRegistration.modules[1].pages) do
        truth(s:build(page) > 0, "page height must be positive")
    end
    local bindings = {
        ["Mage food / water macro"] = { "mageMacro", "enabled" },
        ["SimpleItemLevel bridge"] = { "simpleItemLevel", "enabled" },
        ["WhatsTraining spellbook theme"] = { "whatsTraining", "enabled" },
        ["Maintain character macro"] = { "mageMacro", "enabled" },
        ["Enable bag / bank bridge"] = { "simpleItemLevel", "enabled" },
        ["Inventory bags"] = { "simpleItemLevel", "inventory" },
        ["Reagent bags"] = { "simpleItemLevel", "reagent" },
        ["Bank"] = { "simpleItemLevel", "bank" },
        ["Match spellbook theme"] = { "whatsTraining", "enabled" },
        ["Auto Apply Updated Default"] = { "chat", "autoApply" },
        ["Enable Spacer 1"] = { "spacers", "spacer1" },
        ["Enable Spacer 2"] = { "spacers", "spacer2" },
        ["Enable Spacer 3"] = { "spacers", "spacer3" },
        ["Enable Spacer 4"] = { "spacers", "spacer4" },
        ["Automatic anchor gap"] = { "anchorGap", "enabled" },
    }
    for _, row in ipairs(s.rows) do
        for _, cfg in ipairs({ row.left, row.right }) do
            if cfg.type == "toggle" then
                equal(cfg.noCapture, true)
                equal(type(cfg.setValue), "function")
                local value = cfg.getValue()
                local expected, binding = copy(s.ns.db), bindings[cfg.text]
                truth(binding, "unexpected editable widget: " .. tostring(cfg.text))
                expected[binding[1]][binding[2]] = not value
                cfg.setValue(not value)
                equal(cfg.getValue(), not value)
                same(s.ns.db, expected, "widget must change only its own setting")
                cfg.setValue(value)
            elseif cfg.type == "slider" then
                equal(cfg.noCapture, true)
                local side = cfg.text:match("^(%a+) gap %(pixels%)$")
                truth(side, "unexpected slider: " .. tostring(cfg.text))
                side = side:lower()
                truth(s.ns.defaults.anchorGap[side] ~= nil, "unknown gap side")
                local value, expected = cfg.getValue(), copy(s.ns.db)
                expected.anchorGap[side] = cfg.min
                cfg.setValue(cfg.min)
                equal(cfg.getValue(), cfg.min)
                same(s.ns.db, expected, "slider must change only its gap preference")
                cfg.setValue(value)
            elseif cfg.type == "dropdown" then
                equal(cfg.noCapture, true)
                local unit = cfg.text:match("^(%a+) corner$")
                truth(unit, "unexpected dropdown")
                unit = unit:lower()
                local value, expected = cfg.getValue(), copy(s.ns.db)
                expected.spacerCorners[unit] = "TOPLEFT"
                cfg.setValue("TOPLEFT")
                equal(cfg.getValue(), "TOPLEFT")
                same(s.ns.db, expected, "corner dropdown changes only its own preference")
                cfg.setValue(value)
            elseif cfg.type == "button" then
                equal(cfg.noCapture, true)
                equal(type(cfg.onClick), "function")
            else
                equal(cfg.type, "label")
                equal(cfg.text, "")
            end
        end
    end
    same(s.ns.db, before)
    s:storageUnchanged()
end


test("native visible pages retain noCapture settings and isolated widget writes", function()
    local s = optionsFixture():initialize():login()
    local unchanged = unchangedHost(s.env.EllesmereUI)
    checkVisiblePages(s)
    unchanged()
end)

test("hidden search builders create no frames or labels and activate no modules", function()
    local s = optionsFixture():initialize()
    local modules = { s:module("mageMacro"), s:module("simpleItemLevel"), s:module("whatsTraining") }
    s.env.EllesmereUI.IsSearchPrebuild = function() return true end
    local frames, db, charDB = #s.frames, copy(s.ns.db), copy(s.ns.charDB)
    for _, page in ipairs(s.pluginRegistration.modules[1].pages) do s:build(page) end
    equal(#s.frames, frames)
    equal(#s.labels, 0)
    for _, module in ipairs(modules) do equal(module.applied, 0) end
    same(s.ns.db, db)
    same(s.ns.charDB, charDB)
    equal(#s.timers, 0)
    s.env.EllesmereUI.IsSearchPrebuild = function() return false end
    truth(s:build("Mage Macro") > 0)
    truth(#s.labels > 0)
    s:storageUnchanged()
end)

test("public search prebuild API suppresses custom frames without private prebuilding state", function()
    local s = optionsFixture()
    local eui = s.env.EllesmereUI
    equal(eui._prebuilding, nil)
    local searchCalls = 0
    eui.IsSearchPrebuild = function(...)
        equal(select("#", ...), 0, "IsSearchPrebuild must be a dot call")
        searchCalls = searchCalls + 1
        return true
    end
    local modules = { s:module("mageMacro"), s:module("simpleItemLevel"), s:module("whatsTraining") }
    local defaults, frames = copy(s.ns.defaults), #s.frames
    local function buildAll()
        for _, page in ipairs(s.pluginRegistration.modules[1].pages) do truth(s:build(page) > 0) end
    end
    buildAll()
    truth(searchCalls > 0, "pages must use the public search helper")
    equal(#s.frames, frames)
    equal(#s.labels, 0)
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    same(s.ns.defaults, defaults)
    s:initialize()
    local db, charDB = copy(s.ns.db), copy(s.ns.charDB)
    buildAll()
    equal(#s.frames, frames)
    equal(#s.labels, 0)
    same(s.ns.db, db)
    same(s.ns.charDB, charDB)
    for _, module in ipairs(modules) do equal(module.applied, 0) end
    equal(#s.timers, 0)
    s:storageUnchanged()
end)

test("public search helper takes precedence over stale private prebuilding state", function()
    local s = optionsFixture()
    local eui = s.env.EllesmereUI
    eui._prebuilding = true
    eui.IsSearchPrebuild = function() return false end
    truth(s:build("Mage Macro") > 0)
    truth(#s.labels > 0, "public false must allow visible custom text despite private true")
    equal(s.env.CalmUITweaksDB, nil)
    equal(s.env.CalmUITweaksCharDB, nil)
    s:storageUnchanged()
end)


test("cached macro name follows settings changes without rebuilding", function()
    local s = optionsFixture():initialize()
    s:build("Mage Macro")
    local macroName = s:findLabel("Macro name:")
    equal(s.ns.SetSetting("mageMacro", "name", "Changed Name"), true)
    equal(macroName.text, "Macro name: Changed Name")
    s.ns.db.mageMacro.name = "Restored Name"
    s.pluginRegistration.modules[1].onPageCacheRestore()
    equal(macroName.text, "Macro name: Restored Name")
    s:storageUnchanged()
end)

test("saving the first chat default refreshes native action buttons", function()
    local s = optionsFixture():initialize():login()
    local eui = s.env.EllesmereUI
    local disabled, saveButton = {}, nil
    local function RefreshButtons()
        for _, row in ipairs(s.rows) do
            for _, cfg in ipairs({row.left, row.right}) do
                if cfg.type == "button" then
                    disabled[cfg.text] = cfg.disabled()
                    if cfg.text == "Save Default" then saveButton = cfg end
                end
            end
        end
    end
    s:build("Chat")
    local rowCount = #s.rows
    RefreshButtons()
    equal(disabled["Apply Default"], true)
    equal(disabled["Export Default"], true)
    eui.ShowConfirmPopup = function(self, cfg)
        equal(self, eui)
        cfg.onConfirm()
    end
    eui.RefreshPage = function(self, force)
        equal(self, eui)
        equal(force, nil, "chat actions must refresh controls without rebuilding")
        RefreshButtons()
    end
    s.ns.Chat.SaveDefault = function()
        s.ns.db.chat.default = {export = "saved setup", savedAt = 1}
        return true
    end
    saveButton.onClick()
    equal(disabled["Apply Default"], false, "Apply must unlock after the first save")
    equal(disabled["Export Default"], false, "Export must unlock after the first save")
    equal(#s.rows, rowCount)
    equal(s.ns.errors.options, nil)
end)


test("pages safely decline building when host widgets are unavailable", function()
    local s = optionsFixture()
    s.env.EllesmereUI.Widgets = nil
    for _, page in ipairs(s.pluginRegistration.modules[1].pages) do equal(s:build(page), 60) end
    equal(#s.labels, 0)
    equal(#s.rows, 0)
    equal(s.env.CalmUITweaksDB, nil)
end)

for _, method in ipairs({ "SectionHeader", "DualRow" }) do
    test("partial widget interface missing " .. method .. " declines safely and can recover", function()
        local s = optionsFixture()
        local widgets = s.env.EllesmereUI.Widgets
        local original = widgets[method]
        widgets[method] = nil
        equal(s:build("General"), 60)
        contains(s.ns.optionsRenderError, "incompatible")
        equal(#s.labels, 0)
        equal(#s.rows, 0)
        widgets[method] = original
        truth(s:build("General") > 0)
        equal(s.ns.optionsRenderError, nil)
    end)
end

test("throwing widget methods do not escape into the host panel", function()
    local s = optionsFixture()
    local widgets = s.env.EllesmereUI.Widgets
    local sectionHeader = widgets.SectionHeader
    widgets.SectionHeader = function() error("widget failed") end
    equal(s:build("General"), 60)
    contains(s.ns.GetStatus("options"), "widget failed")
    contains(s.ns.optionsRenderError, "page failed")
    widgets.SectionHeader = sectionHeader
    s:build("General")
    equal(s.ns.optionsRenderError, nil)
    equal(s.ns.errors.options, nil, "successful rebuild releases its error")
end)

test("page and cached-label recovery cannot clear each other's outstanding failures", function()
    local s = optionsFixture():initialize()
    s:build("Mage Macro")
    local label = s:findLabel("Macro name:")
    local setText = label.SetText
    label.SetText = function() error("label failed", 0) end
    s.ns.RefreshOptions()
    local widgets = s.env.EllesmereUI.Widgets
    local header = widgets.SectionHeader
    widgets.SectionHeader = function() error("page failed", 0) end
    s:build("General")
    label.SetText = setText
    s.ns.RefreshOptions()
    contains(s.ns.GetStatus("options"), "page failed")
    widgets.SectionHeader = header
    s:build("General")
    equal(s.ns.errors.options, nil)
    label.SetText = function() error("label failed again", 0) end
    s.ns.RefreshOptions()
    s:build("General")
    truth(s.ns.errors.options, "a healthy page cannot release a failed cached label")
    s.ns.ReportError("options", "unrelated dialog failure", true)
    label.SetText = setText
    s.ns.RefreshOptions()
    contains(s.ns.GetStatus("options"), "unrelated dialog failure")
end)


for _, case in ipairs(tests) do
    local ok, err = xpcall(case.run, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS " .. case.name)
    else
        failed = failed + 1
        print("FAIL " .. case.name .. "\n" .. tostring(err))
    end
end

print(string.format("Core/Options: %d tests, %d passed, %d failed", #tests, passed, failed))
if failed > 0 then os.exit(1) end

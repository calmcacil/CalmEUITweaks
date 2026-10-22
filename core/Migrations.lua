local _, ns = ...
local module = { asyncErrors = true }
ns.RegisterModule("migrations", module)

ns.LEGACY_SCHEMA_VERSION = 4
-- Historical entries remain immutable for direct upgrades from pre-1.0 data.
ns.legacySchemaMigrations = {
    [1] = {
        settingsKey = "gatheringSparkles", retired = true,
        values = {
            { "SoftTargetInteract", "3" },
            { "SoftTargetInteractRange", "15" },
            { "SoftTargetInteractArc", "2" },
            { "SoftTargetInteractOnlyInRange", "0" },
            { "SoftTargetIconInteract", "1" },
            { "SoftTargetIconGameObject", "1" },
            { "SoftTargetLowPriorityIcons", "1" },
            { "SoftTargetNameplateInteract", "0", "1" },
        },
    },
    [2] = {
        migrate = function(db)
            local gaps = db.anchorGap
            if type(gaps) == "table" then
                local value = gaps.pixels
                if type(value) == "number" and value == value and value >= 0 and value <= 10
                    and value == math.floor(value) then
                    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
                        if gaps[side] == nil then gaps[side] = value end
                    end
                end
                gaps.pixels = nil
            end
            db.version, db.cvarVersion = nil, nil
            return true
        end,
    },
    [3] = {
        migrate = function(db)
            if db.cursorWashedOut == nil then db.cursorWashedOut = { enabled = false } end
            return true
        end,
    },
    -- Legacy checkpoint 4 retires these roots; the new lineage starts below.
    -- Unrecognized roots may belong to macro providers or user data.
    [4] = {
        migrate = function(db)
            for _, key in ipairs({ "gatheringSparkles", "whatsTraining", "anchorGap",
                "spacerCorners", "version", "cvarVersion" }) do
                db[key] = nil
            end
            return true
        end,
    },
}
ns.SCHEMA_VERSION = 1
ns.schemaMigrations = {
    [1] = {
        cleanup = {
            { settingsKey = "questLootSparkles", values = {
                { "outlineModeShowLootEffectWhenDisabled", "1" },
                { "graphicsOutlineMode", "0" },
                { "OutlineEngineMode", "0" },
                { "raidGraphicsOutlineMode", "0" },
                { "RAIDOutlineEngineMode", "0" },
            } },
            { settingsKey = "cursorWashedOut", values = { { "HardwareCursor", "0" } } },
        },
        migrate = function(db)
            -- Legacy checkpoint 4 can still carry recognized stale metadata.
            db.version, db.cvarVersion = nil, nil
            return ns.ResetPreferences(db)
        end,
        normalize = true,
    },
}
local events, watched = nil, {}
local origin, existing, startedMarked, notice

local function Integer(value, maximum)
    return type(value) == "number" and value == value and value >= 0
        and value <= maximum and value == math.floor(value)
end

local function Version(account, character)
    if account ~= nil and type(account) ~= "table" then return nil, "Account SavedVariables are not a table; data preserved." end
    if character ~= nil and type(character) ~= "table" then return nil, "Character SavedVariables are not a table; data preserved." end
    account, character = account or {}, character or {}
    if character.schemaVersion ~= nil or (character.version ~= nil and character.version ~= 1) then
        return nil, "Unsupported character saved-data version; data preserved."
    end
    local marker, legacy, schema = account.calm_forever, account.cvarVersion, account.schemaVersion
    if marker ~= nil then
        if marker ~= true then return nil, "Unsupported saved-data lineage; data preserved." end
        if not Integer(schema, ns.SCHEMA_VERSION) or schema < 1 then
            return nil, "Unsupported Calm Forever schema version; update the addon or restore a compatible backup."
        end
        if account.version ~= nil or legacy ~= nil then
            return nil, "Conflicting saved-data lineage metadata; data preserved."
        end
        return schema, nil, true
    end
    if account.version ~= nil and account.version ~= 1 then return nil, "Unsupported legacy account version; data preserved." end
    if legacy ~= nil and not Integer(legacy, 1) then return nil, "Unsupported legacy CVar version; data preserved." end
    if schema ~= nil then
        if not Integer(schema, ns.LEGACY_SCHEMA_VERSION) then return nil, "Unsupported legacy saved-data schema version; update the addon or restore a compatible backup." end
        if legacy and legacy > schema then return nil, "Conflicting saved-data versions; data preserved." end
        return schema
    end
    return legacy or 0
end

local function StopEvents()
    if events then events:UnregisterAllEvents() end
end

local function Subscribe(cvars)
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event, name)
            if ns.IsApplyingCVars() then return end
            if event == "CVAR_UPDATE" and (type(name) ~= "string" or not watched[string.lower(name)]) then return end
            ns.RequestApply("migrations")
        end)
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if cvars then
        events:RegisterEvent("VARIABLES_LOADED")
        events:RegisterEvent("CVAR_UPDATE")
    end
end

local function Pending(reason)
    ns.settingsPending, ns.settingsError = true, nil
    ns.SetStatus("migrations", reason)
    return false, reason
end

local function Commit(target, candidate)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(candidate) do target[key] = value end
end

local function RunStep(step, account, version, marked)
    if step.cleanup then
        for _, cleanup in ipairs(step.cleanup) do
            local done, reason = RunStep(cleanup, account)
            if done ~= true then return false, reason end
        end
    end
    if step.migrate then
        local candidate = ns.Copy(account)
        local done, reason = step.migrate(candidate)
        if done ~= true then return false, reason or "Saved-data migration did not complete." end
        local character
        if step.normalize then
            character = ns.Copy(CalmUITweaksCharDB)
            ns.NormalizeSettings(candidate, character)
        end
        candidate.schemaVersion = version
        if marked then candidate.calm_forever = true end
        -- Publish normalized preferences and lineage together, without callbacks.
        Commit(account, candidate)
        if character then Commit(CalmUITweaksCharDB, character) end
        return true
    end
    local saved = account[step.settingsKey]
    if type(saved) ~= "table" or saved.restore == nil then
        if step.retired then account[step.settingsKey] = nil end
        return true
    end
    local settings = saved
    if step.retired then settings = { restore = settings.restore } end
    ns.InitializeCVarRestore(settings, step.values)
    account[step.settingsKey] = (not step.retired or next(settings.restore)) and settings or nil
    if next(settings.restore) then
        watched = {}
        for _, entry in ipairs(step.values) do watched[string.lower(entry[1])] = true end
        Subscribe(true)
        if not ns.loggedIn then return false, "Saved-data cleanup waiting for login." end
        if InCombatLockdown() then
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return false, "Saved-data cleanup waiting for combat to end."
        end
        local done, reason = ns.ApplyOwnedCVars(settings, step.values, false)
        if not done then return false, reason end
    end
    if step.retired then account[step.settingsKey] = nil end
    return true
end

local function Advance(account, version, target, steps, marked)
    while version < target do
        local step = steps[version + 1]
        if type(step) ~= "table" then
            ns.settingsPending, ns.settingsError = false, "Missing saved-data migration " .. (version + 1) .. "."
            ns.SetStatus("migrations", ns.settingsError)
            return false, ns.settingsError
        end
        local ok, done, problem = pcall(RunStep, step, account, version + 1, marked)
        if not ok then
            Subscribe(step.cleanup or not step.migrate)
            Pending("Saved-data migration " .. (version + 1) .. " failed; waiting to retry.")
            ns.ReportError("migrations", done)
            return false, ns.errors.migrations
        end
        if done ~= true then
            Subscribe(step.cleanup or not step.migrate)
            return Pending(problem)
        end
        StopEvents()
        version = version + 1
        account.schemaVersion = version
        if marked then account.calm_forever = true end
        ns.ClearError("migrations")
    end
    return true
end

function ns.RunSchemaMigrations()
    StopEvents()
    local account, character = CalmUITweaksDB, CalmUITweaksCharDB
    local version, reason, marked = Version(account, character)
    if version == nil then
        ns.settingsPending, ns.settingsError = false, reason
        ns.SetStatus("migrations", reason)
        return false, reason
    end
    if origin == nil then
        origin, startedMarked = version, marked
        existing = type(account) == "table" and next(account) ~= nil
    end
    account, character = account or {}, character or {}
    CalmUITweaksDB, CalmUITweaksCharDB = account, character
    if not marked then
        local ok, problem = Advance(account, version, ns.LEGACY_SCHEMA_VERSION, ns.legacySchemaMigrations)
        if not ok then return false, problem end
        version = 0
    end
    local ok, problem = Advance(account, version, ns.SCHEMA_VERSION, ns.schemaMigrations, true)
    if not ok then return false, problem end
    ns.settingsPending, ns.settingsError = false, nil
    if existing then
        if not startedMarked then
            notice = 'savedvarsdb initialized for "calm_forever" schema "1"; preferences reset, all features disabled.'
        elseif ns.SCHEMA_VERSION > origin then
            notice = string.format('savedvarsdb updated from "%d" to "%d"', origin, ns.SCHEMA_VERSION)
        end
    end
    ns.ClearError("migrations")
    ns.SetStatus("migrations", "SavedVariables ready (calm_forever schema version " .. ns.SCHEMA_VERSION .. ").")
    return true
end

function module:ApplySettings()
    if ns.settingsPending then ns.ResumeStartup() end
end

function module:OnLogin()
    if notice then
        local message = notice
        notice = nil
        ns.Print(message)
    end
end

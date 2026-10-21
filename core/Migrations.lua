local _, ns = ...
local module = { asyncErrors = true }
ns.RegisterModule("migrations", module)

ns.SCHEMA_VERSION = 3
-- Append steps and raise the target together; shipped definitions are immutable.
ns.schemaMigrations = {
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
}
local events, watched = nil, {}
local origin, existing, notice

local function Integer(value, maximum)
    return type(value) == "number" and value == value and value >= 0
        and value <= maximum and value == math.floor(value)
end

local function Version(account, character)
    if account ~= nil and type(account) ~= "table" then return nil, "Account SavedVariables are not a table; data preserved." end
    if character ~= nil and type(character) ~= "table" then return nil, "Character SavedVariables are not a table; data preserved." end
    account, character = account or {}, character or {}
    if account.version ~= nil and account.version ~= 1 then return nil, "Unsupported legacy account version; data preserved." end
    if character.schemaVersion ~= nil or (character.version ~= nil and character.version ~= 1) then
        return nil, "Unsupported character saved-data version; data preserved."
    end
    local legacy, schema = account.cvarVersion, account.schemaVersion
    if legacy ~= nil and not Integer(legacy, 1) then return nil, "Unsupported legacy CVar version; data preserved." end
    if schema ~= nil then
        if not Integer(schema, ns.SCHEMA_VERSION) then return nil, "Unsupported saved-data schema version; update the addon or restore a compatible backup." end
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

local function RunStep(step, account)
    if step.migrate then
        local candidate = ns.Copy(account)
        local done, reason = step.migrate(candidate)
        if done ~= true then return false, reason or "Saved-data migration did not complete." end
        -- Feature modules have no DB reference yet; commit without changing root identity.
        for key in pairs(account) do account[key] = nil end
        for key, value in pairs(candidate) do account[key] = value end
        return true
    end
    local saved = account[step.settingsKey]
    local settings = type(saved) == "table" and saved or {}
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

function ns.RunSchemaMigrations()
    StopEvents()
    local account, character = CalmUITweaksDB, CalmUITweaksCharDB
    local version, reason = Version(account, character)
    if version == nil then
        ns.settingsPending, ns.settingsError = false, reason
        ns.SetStatus("migrations", reason)
        return false, reason
    end
    if origin == nil then
        origin = version
        existing = type(account) == "table" and next(account) ~= nil
    end
    account, character = account or {}, character or {}
    CalmUITweaksDB, CalmUITweaksCharDB = account, character
    while version < ns.SCHEMA_VERSION do
        local step = ns.schemaMigrations[version + 1]
        if type(step) ~= "table" then
            ns.settingsPending, ns.settingsError = false, "Missing saved-data migration " .. (version + 1) .. "."
            ns.SetStatus("migrations", ns.settingsError)
            return false, ns.settingsError
        end
        local ok, done, problem = pcall(RunStep, step, account)
        if not ok then
            Subscribe(not step.migrate)
            Pending("Saved-data migration " .. (version + 1) .. " failed; waiting to retry.")
            ns.ReportError("migrations", done)
            return false, ns.errors.migrations
        end
        if done ~= true then
            Subscribe(not step.migrate)
            return Pending(problem)
        end
        StopEvents()
        version = version + 1
        account.schemaVersion = version
        ns.ClearError("migrations")
    end
    ns.settingsPending, ns.settingsError = false, nil
    if existing and version > origin then notice = version end
    ns.ClearError("migrations")
    ns.SetStatus("migrations", "SavedVariables ready (schema version " .. version .. ").")
    return true
end

function module:ApplySettings()
    if ns.settingsPending then ns.ResumeStartup() end
end

function module:OnLogin()
    if notice then
        local target = notice
        notice = nil
        ns.Print(string.format('savedvarsdb updated from "%d" to "%d"', origin, target))
    end
end

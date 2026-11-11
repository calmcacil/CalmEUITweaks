local _, ns = ...
local module = { asyncErrors = true }
ns.RegisterModule("migrations", module)

ns.SCHEMA_VERSION = 1
ns.schemaMigrations = {}
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
    if character.schemaVersion ~= nil or (character.version ~= nil and character.version ~= 1) then
        return nil, "Unsupported character saved-data version; data preserved."
    end
    if next(account) == nil then return 1 end
    if account.calm_forever ~= true then
        return nil, "Unsupported pre-beta or invalid saved data; data preserved. Use Reset Saved Data to start fresh."
    end
    local schema = account.schemaVersion
    if not Integer(schema, ns.SCHEMA_VERSION) or schema < 1 then
        return nil, "Unsupported Calm Forever schema version; update the addon or restore a compatible backup."
    end
    if account.version ~= nil or account.cvarVersion ~= nil then
        return nil, "Conflicting saved-data lineage metadata; data preserved."
    end
    return schema
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

local function RunStep(step, account, version)
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
        candidate.calm_forever = true
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

local function Advance(account, version)
    while version < ns.SCHEMA_VERSION do
        local step = ns.schemaMigrations[version + 1]
        if type(step) ~= "table" then
            ns.settingsPending, ns.settingsError = false, "Missing saved-data migration " .. (version + 1) .. "."
            ns.SetStatus("migrations", ns.settingsError)
            return false, ns.settingsError
        end
        local ok, done, problem = pcall(RunStep, step, account, version + 1)
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
        account.calm_forever = true
        ns.ClearError("migrations")
    end
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
    if next(account) == nil then
        local candidate, characterCandidate = {}, ns.Copy(character)
        ns.NormalizeSettings(candidate, characterCandidate)
        candidate.calm_forever, candidate.schemaVersion = true, 1
        Commit(account, candidate)
        Commit(character, characterCandidate)
    end
    CalmUITweaksDB, CalmUITweaksCharDB = account, character
    local ok, problem = Advance(account, version)
    if not ok then return false, problem end
    ns.settingsPending, ns.settingsError = false, nil
    if existing and ns.SCHEMA_VERSION > origin then
        notice = string.format('savedvarsdb updated from "%d" to "%d"', origin, ns.SCHEMA_VERSION)
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

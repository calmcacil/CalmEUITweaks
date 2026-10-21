local _, ns = ...
local module = {}
ns.RegisterModule("legacyCVars", module)

-- Append steps; shipped historical definitions must not change or be renumbered.
ns.cvarMigrations = {
    [1] = {
        settingsKey = "gatheringSparkles",
        retired = true,
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
}
local events, watched

local function Version()
    local version = ns.db.cvarVersion
    if version == nil then return 0 end
    if type(version) ~= "number" or version ~= version or version < 0
        or version == math.huge or version ~= math.floor(version) then
        return nil, "Saved CVar migration version is invalid; no console settings were changed."
    end
    if version > #ns.cvarMigrations then
        return nil, "Saved CVar version is newer than this addon; update before changing console settings."
    end
    return version
end

function ns.CVarMigrationsReady()
    local version, reason = Version()
    if not version then return false, reason end
    if version < #ns.cvarMigrations then
        return false, "Waiting for CVar migration " .. (version + 1) .. " of " .. #ns.cvarMigrations .. "."
    end
    return true
end

local function Prepare(version)
    local step = ns.cvarMigrations[version + 1]
    local saved = ns.db[step.settingsKey]
    local settings = type(saved) == "table" and saved or {}
    if step.retired then settings = { restore = settings.restore } end
    ns.InitializeCVarRestore(settings, step.values)
    ns.db[step.settingsKey] = (not step.retired or next(settings.restore)) and settings or nil
    watched = {}
    for _, entry in ipairs(step.values) do watched[string.lower(entry[1])] = true end
    return step, settings
end

local function CreateDriver()
    if events then return end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, name)
        if ns.IsApplyingCVars() then return end
        if event == "CVAR_UPDATE" and (type(name) ~= "string" or not watched[string.lower(name)]) then return end
        ns.RequestApply("legacyCVars")
    end)
end

function module:Initialize()
    local version, reason = Version()
    if not version then ns.SetStatus("legacyCVars", reason); return end
    if version < #ns.cvarMigrations then
        local _, settings = Prepare(version)
        if next(settings.restore) then CreateDriver() end
    end
end

function module:ApplySettings()
    if events then events:UnregisterAllEvents() end
    local version, reason = Version()
    if not version then ns.SetStatus("legacyCVars", reason); return end
    local advanced = false
    while version < #ns.cvarMigrations do
        -- Reset replaces active settings tables; always use the latest preferences.
        local step, settings = Prepare(version)
        if next(settings.restore) then
            CreateDriver()
            events:RegisterEvent("VARIABLES_LOADED")
            events:RegisterEvent("PLAYER_ENTERING_WORLD")
            events:RegisterEvent("CVAR_UPDATE")
            if InCombatLockdown() then
                events:RegisterEvent("PLAYER_REGEN_ENABLED")
                ns.SetStatus("legacyCVars", "CVar migration " .. (version + 1) .. " waiting for combat to end.")
                return
            end
            local ok, problem = ns.ApplyOwnedCVars(settings, step.values, false)
            if not ok then ns.SetStatus("legacyCVars", problem); return end
            events:UnregisterAllEvents()
        end
        if step.retired then ns.db[step.settingsKey] = nil end
        version = version + 1
        ns.db.cvarVersion = version
        advanced = true
    end
    ns.SetStatus("legacyCVars", "CVar migrations complete (version " .. version .. ").")
    if advanced then ns.RequestApply("questLootSparkles") end
end

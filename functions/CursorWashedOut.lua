local _, ns = ...
local module = {}
ns.RegisterModule("cursorWashedOut", module)

local values = { { "HardwareCursor", "0" } }
local events = CreateFrame("Frame")
local restoreInitialized = false

function module:ApplySettings()
    events:UnregisterAllEvents()
    local ready, reason = ns.SavedVariablesReady()
    if not ready then ns.SetStatus("cursorWashedOut", reason); return end
    local settings = ns.GetSettings("cursorWashedOut")
    if not restoreInitialized then
        ns.InitializeCVarRestore(settings, values)
        restoreInitialized = true
    end
    local enabled = settings.enabled
    if enabled then
        events:RegisterEvent("CVAR_UPDATE")
    elseif not next(settings.restore) then
        ns.SetStatus("cursorWashedOut", "Disabled")
        return
    end
    events:RegisterEvent("VARIABLES_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("cursorWashedOut", "Waiting for combat to end.")
        return
    end
    local ok, reason = ns.ApplyOwnedCVars(settings, values, enabled)
    if not ok then ns.SetStatus("cursorWashedOut", reason); return end
    if not enabled then events:UnregisterAllEvents() end
    ns.SetStatus("cursorWashedOut", enabled and "Enabled; hardware cursor disabled." or "Disabled")
end

events:SetScript("OnEvent", function(_, event, name)
    if ns.IsApplyingCVars() then return end
    if event ~= "CVAR_UPDATE" or (type(name) == "string" and string.lower(name) == "hardwarecursor") then
        ns.RequestApply("cursorWashedOut")
    end
end)

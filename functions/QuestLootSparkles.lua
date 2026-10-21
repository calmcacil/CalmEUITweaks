local _, ns = ...
local module = {}
ns.RegisterModule("questLootSparkles", module)

local values = {
    { "outlineModeShowLootEffectWhenDisabled", "1" },
    { "graphicsOutlineMode", "0" },
    { "OutlineEngineMode", "0" },
    { "raidGraphicsOutlineMode", "0" },
    { "RAIDOutlineEngineMode", "0" },
}
local watched = { graphicsquality = true, raidgraphicsquality = true }
for _, entry in ipairs(values) do watched[string.lower(entry[1])] = true end
local events = CreateFrame("Frame")
local restoreInitialized = false

function module:ApplySettings()
    events:UnregisterAllEvents()
    local ready, reason = ns.CVarMigrationsReady()
    if not ready then ns.SetStatus("questLootSparkles", reason); return end
    local settings = ns.GetSettings("questLootSparkles")
    if not restoreInitialized then
        ns.InitializeCVarRestore(settings, values)
        restoreInitialized = true
    end
    local enabled = settings.enabled
    if enabled then
        events:RegisterEvent("CVAR_UPDATE")
    elseif not next(settings.restore) then
        ns.SetStatus("questLootSparkles", "Disabled")
        return
    end
    events:RegisterEvent("VARIABLES_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("questLootSparkles", "Waiting for combat to end.")
        return
    end
    local ok, reason = ns.ApplyOwnedCVars(settings, values, enabled)
    if not ok then ns.SetStatus("questLootSparkles", reason); return end
    if not enabled then events:UnregisterAllEvents() end
    ns.SetStatus("questLootSparkles", enabled and "Enabled; normal and raid outlines disabled."
        or "Disabled; restart the game if sparkles remain.")
end

events:SetScript("OnEvent", function(_, event, name)
    if ns.IsApplyingCVars() then return end
    if event ~= "CVAR_UPDATE" or (type(name) == "string" and watched[string.lower(name)]) then
        ns.RequestApply("questLootSparkles")
    end
end)

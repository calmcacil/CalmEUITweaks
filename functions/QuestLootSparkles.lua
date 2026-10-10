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
local applying = false

function module:Initialize()
    local settings = ns.GetSettings("questLootSparkles")
    local saved = settings.restore
    local restore = {}
    if type(saved) == "table" then
        for _, entry in ipairs(values) do
            local record = saved[entry[1]]
            if type(record) == "table" and type(record.before) == "string"
                and record.applied == entry[2] then
                restore[entry[1]] = record
            end
        end
    end
    settings.restore = restore
end

local function Write(plan, restore, enabled)
    for _, entry in ipairs(plan) do
        local name, value = entry[1], entry[2]
        if C_CVar.SetCVar(name, value) ~= true then
            error("Could not set graphics variable: " .. name)
        end
    end
    for _, entry in ipairs(enabled and values or plan) do
        if C_CVar.GetCVar(entry[1]) ~= entry[2] then
            error("Graphics variable did not retain its value: " .. entry[1])
        end
        if not enabled then restore[entry[1]] = nil end
    end
end

function module:ApplySettings()
    local settings = ns.GetSettings("questLootSparkles")
    local enabled, restore = settings.enabled, settings.restore
    events:UnregisterAllEvents()
    if enabled then
        events:RegisterEvent("CVAR_UPDATE")
    elseif not next(restore) then
        ns.SetStatus("questLootSparkles", "Disabled")
        return
    end
    events:RegisterEvent("VARIABLES_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function"
        or type(C_CVar.SetCVar) ~= "function" then
        ns.SetStatus("questLootSparkles", "Waiting for native graphics settings.")
        return
    end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("questLootSparkles", "Waiting for combat to end.")
        return
    end

    local current, plan = {}, {}
    -- Snapshot before writes because graphics variables can affect each other.
    for _, entry in ipairs(values) do
        current[entry[1]] = C_CVar.GetCVar(entry[1])
        if (enabled or restore[entry[1]]) and current[entry[1]] == nil then
            ns.SetStatus("questLootSparkles", "Waiting for graphics variable: " .. entry[1])
            return
        end
    end
    for _, entry in ipairs(values) do
        local name, value = entry[1], entry[2]
        local record = restore[name]
        if enabled then
            if current[name] ~= value then
                restore[name] = { before = current[name], applied = value }
                plan[#plan + 1] = { name, value }
            end
        elseif record then
            if current[name] == record.applied then
                plan[#plan + 1] = { name, record.before }
            else
                restore[name] = nil
            end
        end
    end
    applying = true
    local ok, err = pcall(Write, plan, restore, enabled)
    applying = false
    if not ok then error(err) end
    if not enabled then events:UnregisterAllEvents() end
    ns.SetStatus("questLootSparkles", enabled and "Enabled; normal and raid outlines disabled."
        or "Disabled; restart the game if sparkles remain.")
end

events:SetScript("OnEvent", function(_, event, name)
    if applying then return end
    if event ~= "CVAR_UPDATE" or (type(name) == "string" and watched[string.lower(name)]) then
        ns.RequestApply("questLootSparkles")
    end
end)

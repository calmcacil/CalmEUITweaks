local _, ns = ...
local applying = false

function ns.IsApplyingCVars()
    return applying
end

function ns.InitializeCVarRestore(settings, values)
    local saved, restore = settings.restore, {}
    if type(saved) == "table" then
        for _, entry in ipairs(values) do
            local record = saved[entry[1]]
            if type(record) == "table" and type(record.before) == "string"
                and (record.applied == entry[2] or (entry[3] and record.applied == entry[3])) then
                restore[entry[1]] = record
            end
        end
    end
    settings.restore = restore
end

local function Write(plan, restore, enabled, values)
    for _, entry in ipairs(plan) do
        if C_CVar.SetCVar(entry[1], entry[2]) ~= true then
            error("Could not set console variable: " .. entry[1])
        end
    end
    for _, entry in ipairs(enabled and values or plan) do
        if C_CVar.GetCVar(entry[1]) ~= entry[2] then
            error("Console variable did not retain its value: " .. entry[1])
        end
        if not enabled then restore[entry[1]] = nil end
    end
end

function ns.ApplyOwnedCVars(settings, values, enabled)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function"
        or type(C_CVar.SetCVar) ~= "function" then
        return false, "Waiting for native console settings."
    end
    local restore, current, plan = settings.restore, {}, {}
    -- Snapshot before writes because console variables can affect each other.
    for _, entry in ipairs(values) do
        current[entry[1]] = C_CVar.GetCVar(entry[1])
        if (enabled or restore[entry[1]]) and current[entry[1]] == nil then
            return false, "Waiting for console variable: " .. entry[1]
        end
    end
    for _, entry in ipairs(values) do
        local name, value = entry[1], entry[2]
        local record = restore[name]
        if enabled then
            if current[name] ~= value then
                -- A change from one of our modes retains the original baseline.
                if not record or current[name] ~= record.applied then
                    record = { before = current[name] }
                    restore[name] = record
                end
                record.applied = value
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
    local ok, err = pcall(Write, plan, restore, enabled, values)
    applying = false
    if not ok then error(err) end
    return true
end

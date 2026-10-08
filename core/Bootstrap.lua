local addonName, ns = ...

ns.name = addonName
ns.title = "Calm UI Tweaks"
ns.modules = {}
ns.moduleOrder = {}
ns.statuses = {}
ns.errors = {}
local reportedErrors = {}
local failedMethods = {}
local refreshing = false

function ns.Print(message)
    print("|cffdca77fCalm UI Tweaks:|r " .. tostring(message))
end

function ns.RegisterModule(key, module)
    assert(not ns.modules[key], "Duplicate Calm UI Tweaks module: " .. key)
    ns.modules[key] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = key
end

local function RefreshStatus()
    if refreshing or type(ns.RefreshOptions) ~= "function" then return end
    refreshing = true
    local ok, err = pcall(ns.RefreshOptions)
    refreshing = false
    if not ok then ns.ReportError("options", err, true) end
end

function ns.ReportError(key, err, skipRefresh)
    local ok, message = pcall(tostring, err)
    if not ok then message = "Unknown error" end
    ns.errors[key] = "Error: " .. message
    -- Mark before reporting: even an error handler that re-enters us cannot spam.
    if reportedErrors[key] ~= message then
        reportedErrors[key] = message
        local obtained, handler = false, nil
        if type(geterrorhandler) == "function" then obtained, handler = pcall(geterrorhandler) end
        local handled = obtained and type(handler) == "function" and pcall(handler, err)
        if not handled then pcall(ns.Print, key .. ": " .. ns.errors[key]) end
    end
    if not skipRefresh then RefreshStatus() end
end

function ns.ClearError(key)
    if not ns.errors[key] then return end
    ns.errors[key] = nil
    reportedErrors[key] = nil
    failedMethods[key] = nil
    RefreshStatus()
end

function ns.SetStatus(key, message)
    if ns.statuses[key] == message then return end
    ns.statuses[key] = message
    RefreshStatus()
end

function ns.GetStatus(key)
    if ns.errors[key] then return ns.errors[key] end
    local module = ns.modules[key]
    if module and type(module.GetStatus) == "function" then
        local ok, status = pcall(module.GetStatus, module)
        if ok then return status end
        ns.ReportError(key, status)
        return ns.errors[key]
    end
    return ns.statuses[key] or "Waiting for login."
end

function ns.CallModule(key, method, ...)
    local module = ns.modules[key]
    if module and type(module[method]) == "function" then
        local ok, err = pcall(module[method], module, ...)
        if not ok then
            failedMethods[key] = method
            ns.ReportError(key, err)
        -- Deferred modules clear errors after actual work, not after queuing a timer.
        elseif not module.asyncErrors and (not failedMethods[key] or failedMethods[key] == method) then
            ns.ClearError(key)
        end
    end
end

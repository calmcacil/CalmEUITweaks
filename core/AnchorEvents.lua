local _, ns = ...
local observers = {}
local hooks = setmetatable({}, { __mode = "k" })
local frameKeys = setmetatable({}, { __mode = "k" })
local host

function ns.IsEUIAddon(name)
    return type(name) == "string" and name:match("^EllesmereUI") ~= nil
end

local function Notify(key, reason)
    if host ~= _G.EllesmereUI or not next(observers) then return end
    for owner, callback in pairs(observers) do
        local ok, err = pcall(callback, key, reason)
        if not ok then ns.ReportError(owner, err) end
    end
end

local function MapFrames()
    frameKeys = setmetatable({}, { __mode = "k" })
    for key, element in pairs(host._unlockRegisteredElements or {}) do
        if type(element.getFrame) == "function" then
            local ok, frame = pcall(element.getFrame, key)
            if ok and frame then
                local keys = frameKeys[frame]
                if not keys then keys = {}; frameKeys[frame] = keys end
                keys[#keys + 1] = key
            end
        end
    end
end

local function Hook(method, callback)
    if type(host[method]) ~= "function" then return end
    local record = hooks[host]
    if not record then record = {}; hooks[host] = record end
    if record[method] == host[method] then return end
    local installedHost = host
    hooksecurefunc(host, method, function(...)
        if host == installedHost and host == _G.EllesmereUI then callback(...) end
    end)
    record[method] = host[method]
end

function ns.ObserveAnchors(owner, callback)
    local added = callback and not observers[owner]
    observers[owner] = callback
    if not next(observers) then return true end
    local eui = _G.EllesmereUI
    if type(eui) ~= "table" or type(hooksecurefunc) ~= "function"
        or type(eui.SetFramePoint) ~= "function" then return false end
    local changedHost = host ~= eui
    if changedHost then host = eui end
    if changedHost or added then MapFrames() end
    -- Native side/corner picks call SetFramePoint after replacing their link record.
    Hook("SetFramePoint", function(frame)
        if not next(observers) then return end
        local keys = frameKeys[frame]
        if keys then for _, key in ipairs(keys) do Notify(key, "placement") end end
    end)
    for _, method in ipairs({ "ReapplyOwnAnchor", "ReapplyUnlockAnchor" }) do
        Hook(method, function(key) Notify(key, "placement") end)
    end
    Hook("RegisterUnlockElements", function()
        if not next(observers) then return end
        MapFrames()
        Notify(nil, "registry")
    end)
    Hook("UnregisterUnlockElement", function(_, key)
        if not next(observers) then return end
        MapFrames()
        Notify(key, "registry")
    end)
    for _, method in ipairs({ "RepointAllDBs", "ReapplyAllUnlockAnchors" }) do
        Hook(method, function() Notify(nil, "layout") end)
    end
    return true
end

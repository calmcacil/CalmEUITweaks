local _, ns = ...
local Chat = { asyncErrors = true }
ns.Chat = Chat
ns.RegisterModule("chat", Chat)

local MAX_EXPORT, MAX_WINDOWS = 65536, 20
local frame, pending, queued, status
local loginChecked, loginDefault = false, nil
local generation = 0
local UpdateEvents
local eventMask = {}
local function Refresh()
    if type(ns.RefreshOptions) == "function" then
        local ok, err = pcall(ns.RefreshOptions)
        if not ok and ns.ReportError then pcall(ns.ReportError, "options", err, true) end
    end
end
local function Status(text)
    if status ~= text then status = text; Refresh() end
end
local function Exception(err)
    if pending and not pending.restored then pending = nil end
    Status("Chat preset failed; it has not been marked applied.")
    if ns.ReportError then pcall(ns.ReportError, "chat", err) end
    return false, status
end
local function Boundary(fn, ...)
    local result = { pcall(fn, ...) }
    if not result[1] then
        local ok, reason = Exception(result[2])
        if UpdateEvents then UpdateEvents() end
        return ok, reason
    end
    if UpdateEvents then UpdateEvents() end
    return unpack(result, 2)
end
local function Stores()
    if not ns.db or type(ns.db.chat) ~= "table" or not ns.charDB or type(ns.charDB.chat) ~= "table" then
        return nil, nil, "Chat settings are not loaded yet."
    end
    return ns.db.chat, ns.charDB.chat
end
local function Boolean(value) return value == true or value == 1 end
local function Number(value, low, high, integer)
    return type(value) == "number" and value == value and value >= low and value <= high
        and (not integer or value == math.floor(value))
end
local function Text(value, max)
    return type(value) == "string" and #value > 0 and #value <= max and not value:find("%c")
end
local function Validate(layout)
    if type(layout) ~= "table" or not Number(#layout.windows, 2, MAX_WINDOWS, true) then return false end
    local ids, dock, main, combat = {}, {}, false, false
    for ordinal, w in ipairs(layout.windows) do
        if w.id ~= ordinal or not Number(w.id, 1, MAX_WINDOWS, true) or ids[w.id]
            or type(w.name) ~= "string" or #w.name > 256 or w.name:find("%c") or (w.shown and not Text(w.name, 256))
            or type(w.shown) ~= "boolean"
            or not Number(w.dock, 0, MAX_WINDOWS, true) or (w.dock > 0 and dock[w.dock])
            or #w.groups > 128 or #w.channels > 64 or (w.dock > 0 and not w.shown)
            or (w.id > 2 and not w.shown) then return false end
        ids[w.id] = true
        if w.dock > 0 then dock[w.dock] = w.id end
        if w.id == 1 then main = w.shown and w.dock == 1 end
        if w.id == 2 then combat = true end
        for _, list in ipairs({ w.groups, w.channels }) do
            local seen = {}
            for _, value in ipairs(list) do
                if not Text(value, 256) or seen[value] then return false end
                seen[value] = true
            end
        end
    end
    local count = 0
    for _ in pairs(dock) do count = count + 1 end
    for i = 1, count do if not dock[i] then return false end end
    return main and combat and Number(layout.selected, 1, MAX_WINDOWS, true) and ids[layout.selected]
        and (function() for _, w in ipairs(layout.windows) do if w.id == layout.selected then return w.dock > 0 end end end)()
end

-- Fixed fields and hex strings keep the decoder bounded and non-executable.
local fields = { "id", "name", "shown", "dock" }
local function Encode(layout)
    local tokens = { "CUTCHAT2", tostring(layout.selected), tostring(#layout.windows) }
    local function Add(value)
        if value == nil then tokens[#tokens + 1] = "-"
        elseif type(value) == "boolean" then tokens[#tokens + 1] = value and "T" or "F"
        elseif type(value) == "string" then
            tokens[#tokens + 1] = "S" .. value:gsub(".", function(c) return string.format("%02X", c:byte()) end)
        else tokens[#tokens + 1] = string.format("%.17g", value) end
    end
    for _, w in ipairs(layout.windows) do
        for _, key in ipairs(fields) do Add(w[key]) end
        for _, list in ipairs({ w.groups, w.channels }) do
            Add(#list)
            for _, value in ipairs(list) do Add(value) end
        end
    end
    return table.concat(tokens, ":")
end
local function Decode(text)
    if type(text) ~= "string" or #text > MAX_EXPORT or #text < 10 or text:find("[^%w:%.%+%-]") then
        return nil, "Invalid or oversized chat export."
    end
    local tokens = {}
    for token in (text .. ":"):gmatch("([^:]*):") do
        if token == "" then return nil, "Truncated chat export." end
        tokens[#tokens + 1] = token
    end
    if tokens[1] ~= "CUTCHAT2" then return nil, "Unsupported chat export version; save a new tabs-only default or import CUTCHAT2." end
    local pos = 2
    local function Take()
        local token = tokens[pos]; pos = pos + 1
        if not token then error("Truncated chat export") end
        if token == "-" then return nil end
        if token == "T" then return true end
        if token == "F" then return false end
        if token:sub(1, 1) == "S" then
            local hex = token:sub(2)
            if #hex > 512 or #hex % 2 ~= 0 or hex:find("[^0-9A-F]") then error("Invalid string") end
            return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
        end
        return tonumber(token)
    end
    local ok, layout = pcall(function()
        local value = { selected = Take(), windows = {} }
        local count = Take()
        if not Number(count, 2, MAX_WINDOWS, true) then error("Invalid window count") end
        for i = 1, count do
            local w = { groups = {}, channels = {} }
            for _, key in ipairs(fields) do w[key] = Take() end
            for _, list in ipairs({ w.groups, w.channels }) do
                local length = Take()
                if not Number(length, 0, 128, true) then error("Invalid list length") end
                for j = 1, length do list[j] = Take(); if list[j] == nil then error("Invalid list entry") end end
            end
            value.windows[i] = w
        end
        if pos ~= #tokens + 1 or not Validate(value) then error("Invalid layout") end
        table.sort(value.windows, function(a, b) return a.id < b.id end)
        for _, w in ipairs(value.windows) do table.sort(w.groups); table.sort(w.channels) end
        return value
    end)
    if not ok then return nil, "Malformed chat export." end
    return layout
end

local required = { "FCF_GetChatWindowInfo", "GetChatWindowMessages", "GetChatWindowChannels", "FCFDock_GetChatFrames", "FCFDock_GetSelectedWindow" }
local subscriptions = { "AddMessageGroup", "RemoveAllMessageGroups", "AddChannel", "RemoveAllChannels" }
local function Subscribe(f, method, ...)
    if type(_G["ChatFrame_" .. method]) == "function" then return _G["ChatFrame_" .. method](f, ...) end
    return f[method](f, ...)
end
local restore = { "FCF_OpenNewWindow", "FCF_SetWindowName", "FCF_SetLocked", "FCF_SetUninteractable", "FCF_DockFrame", "FCF_UnDockFrame", "FCFDock_SelectWindow", "FCF_Close", "SetChatWindowShown", "GetChannelName", "JoinPermanentChannel" }
local function WindowLimit()
    return Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS
end
local function GetFrame(id)
    if type(FCF_GetChatFrameByID) == "function" then return FCF_GetChatFrameByID(id) end
    return _G["ChatFrame" .. id]
end
local function Reserved(id)
    if id <= 2 then return true end
    if type(FCF_IsChatWindowIndexReserved) == "function" then return FCF_IsChatWindowIndexReserved(id) end
    return IsBuiltinChatWindow(GetFrame(id))
end
local function CompatibleGroups(layout)
    if type(ChatTypeGroup) ~= "table" or not next(ChatTypeGroup) then
        return false, "Chat message groups are not ready."
    end
    for _, w in ipairs(layout.windows) do
        local groups = {}
        for _, group in ipairs(w.groups) do
            if ChatTypeGroup[group] then
                groups[#groups + 1] = group
            end
        end
        -- Native saved subscriptions can include groups absent on the destination client.
        w.groups = groups
    end
    return true
end
local function Preflight(layout)
    local limit = WindowLimit()
    if not Number(limit, 2, MAX_WINDOWS, true) or not GENERAL_CHAT_DOCK
        or (type(FCF_IsChatWindowIndexReserved) ~= "function" and type(IsBuiltinChatWindow) ~= "function") then
        return false, "Modern chat frames are not ready."
    end
    for _, list in ipairs(layout and { required, restore } or { required }) do
        for _, name in ipairs(list) do if type(_G[name]) ~= "function" then return false, "Chat API unavailable: " .. name .. "." end end
    end
    local available = 0
    for id = 1, limit do
        local f = GetFrame(id)
        if not f or f.isTemporary or type(f.GetID) ~= "function" then return false, "Permanent chat frames are not ready." end
        if not Reserved(id) then available = available + 1 end
        if layout and (id <= 2 or not Reserved(id)) then
            local tab = _G["ChatFrame" .. id .. "Tab"]
            if not tab or type(tab.Show) ~= "function" or type(tab.Hide) ~= "function"
                or type(f.Show) ~= "function" or type(f.Hide) ~= "function" then return false, "Chat tabs are not ready." end
            for _, method in ipairs(subscriptions) do
                if type(_G["ChatFrame_" .. method]) ~= "function" and type(f[method]) ~= "function" then
                    return false, "Chat subscription API unavailable: " .. method .. "."
                end
            end
        end
    end
    if layout then
        if #layout.windows - 2 > available then return false, "This client supports fewer normal chat tabs." end
        return CompatibleGroups(layout)
    end
    return true
end
local function Capture()
    local ok, reason = Preflight()
    if not ok then return nil, reason end
    local layout, logical = { windows = {} }, {}
    for id = 1, WindowLimit() do
        local f = GetFrame(id)
        local name, _, _, _, _, _, shown = FCF_GetChatWindowInfo(id)
        if id <= 2 or (not Reserved(id) and (Boolean(shown) or f.isDocked)) then
            local w = { id = #layout.windows + 1, name = name, shown = Boolean(shown) or not not f.isDocked,
                dock = 0, groups = id ~= 2 and { GetChatWindowMessages(id) } or {}, channels = {} }
            if id ~= 2 then
                local channels = { GetChatWindowChannels(id) }
                for index = 1, #channels, 2 do w.channels[#w.channels + 1] = channels[index] end
            end
            logical[id] = w
            layout.windows[#layout.windows + 1] = w
        end
    end
    local count = 0
    for _, f in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
        local w = logical[f:GetID()]
        if w then count = count + 1; w.dock = count end
    end
    local selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    layout.selected = selected and logical[selected:GetID()] and logical[selected:GetID()].id or 1
    if not Validate(layout) then return nil, "Current chat tabs cannot be saved safely." end
    local compatible, problem = CompatibleGroups(layout)
    if not compatible then return nil, problem end
    for _, w in ipairs(layout.windows) do table.sort(w.groups); table.sort(w.channels) end
    return layout
end
local function Receipt(work)
    local _, character = Stores()
    character.appliedExport, character.appliedSavedAt, character.appliedAt = work.export, work.savedAt, time()
    pending = nil
    loginDefault = nil
    if ns.ClearError then pcall(ns.ClearError, "chat") end
    Status("Chat default applied."); Refresh()
end
local function Subscribed(id, name)
    local channels = { GetChatWindowChannels(id) }
    for index = 1, #channels, 2 do if channels[index] == name then return true end end
    return false
end
local function Channels(work)
    local waiting = false
    for _, w in ipairs(work.layout.windows) do
        if w.id ~= 2 then
            local f = work.frames[w.id]
            for _, name in ipairs(w.channels) do
                if (GetChannelName(name) or 0) <= 0 then JoinPermanentChannel(name, nil, f:GetID(), 1) end
                if (GetChannelName(name) or 0) > 0 then
                    if not Subscribed(f:GetID(), name) then Subscribe(f, "AddChannel", name) end
                    if not Subscribed(f:GetID(), name) then waiting = true end
                else waiting = true end
            end
        end
    end
    if waiting then Status("Waiting for required chat channels; default not yet applied."); return false, status end
    Receipt(work)
    return true, "Chat default applied."
end
local function Restore(work)
    local ok, reason = Preflight(work.layout)
    if not ok then Status(reason); return false, reason end
    -- Preset IDs identify tabs, not native slots: modern clients reserve slot 3 for voice.
    local frames, used, active, live = { GetFrame(1), GetFrame(2) }, {}, {}, {}
    for id = 1, WindowLimit() do
        if id <= 2 or not Reserved(id) then
            local f = GetFrame(id)
            local name, _, _, _, _, _, shown, locked, _, uninteractable = FCF_GetChatWindowInfo(id)
            if Boolean(shown) or f.isDocked then
                live[f] = { locked = Boolean(locked), uninteractable = Boolean(uninteractable) }
                if id > 2 then active[#active + 1] = { frame = f, name = name } end
            end
        end
    end
    -- Match names before reusing unmatched active windows, preserving their history and styling.
    for _, w in ipairs(work.layout.windows) do
        if w.id > 2 then
            for _, candidate in ipairs(active) do
                if not used[candidate.frame] and candidate.name == w.name then
                    frames[w.id] = candidate.frame; used[candidate.frame] = true; break
                end
            end
        end
    end
    for _, w in ipairs(work.layout.windows) do
        if w.id > 2 and not frames[w.id] then
            for _, candidate in ipairs(active) do
                if not used[candidate.frame] then
                    frames[w.id] = candidate.frame; used[candidate.frame] = true; break
                end
            end
        end
    end
    for _, candidate in ipairs(active) do
        if not used[candidate.frame] then
            FCF_Close(candidate.frame); SetChatWindowShown(candidate.frame:GetID(), false)
        end
    end
    for _, w in ipairs(work.layout.windows) do
        if not frames[w.id] then
            local f = FCF_OpenNewWindow(w.name, true)
            if not f or Reserved(f:GetID()) or used[f] then error("Native chat window allocation failed") end
            frames[w.id] = f; used[f] = true
        end
    end
    work.frames = frames
    local dock = {}
    for _, w in ipairs(work.layout.windows) do
        local f = frames[w.id]
        FCF_SetWindowName(f, w.name)
        SetChatWindowShown(f:GetID(), w.shown)
        if w.shown then f:Show() else f:Hide() end
        local tab = _G["ChatFrame" .. f:GetID() .. "Tab"]
        if w.shown then tab:Show() else tab:Hide() end
        if w.dock > 0 then dock[w.dock] = f end
        if w.id ~= 2 then
            Subscribe(f, "RemoveAllMessageGroups"); Subscribe(f, "RemoveAllChannels")
            for _, group in ipairs(w.groups) do Subscribe(f, "AddMessageGroup", group) end
        end
    end
    -- Keep reserved tabs in their live dock positions; never rename, close or configure voice.
    local current = {}
    for index, f in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do current[index] = f end
    for index, f in ipairs(current) do
        if f:GetID() > 2 and Reserved(f:GetID()) then table.insert(dock, math.min(index, #dock + 1), f) end
    end
    local changed = #current ~= #dock
    for index, f in ipairs(dock) do if current[index] ~= f then changed = true end end
    if changed then
        for _, f in ipairs(current) do
            if f:GetID() == 2 or not Reserved(f:GetID()) then FCF_UnDockFrame(f) end
        end
        for index, f in ipairs(dock) do if not f.isDocked then FCF_DockFrame(f, index, false) end end
    end
    FCFDock_SelectWindow(GENERAL_CHAT_DOCK, frames[work.layout.selected])
    -- Docking locks frames natively; retain each existing window's local interaction settings.
    for f, values in pairs(live) do
        if f:GetID() <= 2 or used[f] then
            local _, _, _, _, _, _, _, locked, _, uninteractable = FCF_GetChatWindowInfo(f:GetID())
            if Boolean(locked) ~= values.locked then FCF_SetLocked(f, values.locked) end
            if Boolean(uninteractable) ~= values.uninteractable then FCF_SetUninteractable(f, values.uninteractable) end
        end
    end
    work.restored = true
    return Channels(work)
end
local function Run()
    if not pending then return false, "No chat apply is pending." end
    if InCombatLockdown and InCombatLockdown() then Status("Waiting for combat to end."); return false, status end
    if pending.restored then return Channels(pending) end
    return Restore(pending)
end
local function Apply(automatic)
    local account, character, reason = Stores()
    if not account then return false, reason end
    local default = automatic and loginDefault or account.default
    if type(default) ~= "table" then return false, "No chat default has been saved." end
    local layout, problem = Decode(default.export)
    if not layout then
        if automatic then loginDefault = nil end
        Status(problem); return false, problem
    end
    if not Number(default.savedAt, 0, 99999999999, true) then
        if automatic then loginDefault = nil end
        return false, "Invalid saved chat date."
    end
    local ok, message = Preflight(layout)
    if not ok then Status(message); return false, message end
    if pending and pending.export == default.export and pending.savedAt == default.savedAt then
        if not automatic then pending.automatic = false end
    else pending = { layout = layout, export = default.export, savedAt = default.savedAt, automatic = automatic } end
    return Run()
end
function Chat.NeedsApply()
    local account, character = Stores()
    if not account or type(account.default) ~= "table"
        or not Number(account.default.savedAt, 0, 99999999999, true) then return false end
    return not Number(character.appliedSavedAt, 0, 99999999999, true)
        or account.default.savedAt > character.appliedSavedAt
end
local function SavedTime(account)
    local previous = type(account.default) == "table" and account.default.savedAt
    -- Saves/imports in the same second still produce a strictly newer default.
    return Number(previous, 0, 99999999998, true) and math.max(time(), previous + 1) or time()
end
function Chat.SaveDefault()
    return Boundary(function()
        local account, _, reason = Stores(); if not account then return false, reason end
        local layout, problem = Capture(); if not layout then return false, problem end
        local export = Encode(layout)
        if #export > MAX_EXPORT then return false, "Chat layout is too large to export." end
        local savedAt = SavedTime(account)
        account.default = { export = export, savedAt = savedAt }
        generation = generation + 1; queued = false
        Receipt({ export = export, savedAt = savedAt })
        Status("Current chat saved as the account default.")
        return true, status
    end)
end
function Chat.ApplyDefault()
    generation = generation + 1; queued = false; loginDefault = nil
    return Boundary(Apply, false)
end
function Chat.ExportDefault()
    local account, _, reason = Stores(); if not account then return nil, reason end
    if type(account.default) ~= "table" then return nil, "No chat default has been saved." end
    local layout, problem = Decode(account.default.export)
    if not layout then return nil, problem end
    return Encode(layout)
end
function Chat.ImportDefault(text)
    return Boundary(function()
        local account, _, reason = Stores(); if not account then return false, reason end
        local layout, problem = Decode(text); if not layout then return false, problem end
        local ok, message = Preflight(layout); if not ok then return false, message end
        account.default = { export = Encode(layout), savedAt = SavedTime(account) }
        pending = nil; loginDefault = nil; generation = generation + 1; queued = false
        Status("Chat default imported; current chat is unchanged."); Refresh()
        return true, status
    end)
end
local function Date(value)
    if type(value) ~= "number" then return "never" end
    if type(date) == "function" then return date("%Y-%m-%d %H:%M:%S", value) end
    return os.date("%Y-%m-%d %H:%M:%S", value)
end
function Chat.GetSummary()
    local account, character = Stores()
    if not account or type(account.default) ~= "table" then
        return "Default saved: Not saved\nApplied to this character: Never\nNot applied"
    end
    local state = not character.appliedExport and "Not applied" or Chat.NeedsApply() and "Updated default available" or "Up to date"
    if pending then state = pending.restored and "Waiting for channels" or "Waiting for combat" end
    return "Default saved: " .. Date(account.default.savedAt) .. "\nApplied to this character: "
        .. (character.appliedAt and Date(character.appliedAt) or "Never") .. "\n" .. state
end
local function QueueAuto()
    if queued or not loginDefault then return end
    local account = Stores()
    if not account or not account.autoApply or not Chat.NeedsApply() or pending then return end
    queued = true
    local ticket = generation
    local function Flush()
        if ticket ~= generation then return end
        queued = false
        local current = Stores()
        if current and current.autoApply and Chat.NeedsApply() and not pending then Boundary(Apply, true) end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Flush)
    else Flush() end
end

UpdateEvents = function()
    if not frame then return end
    local desired = {}
    local account = Stores()
    local automatic = loginDefault and account and account.autoApply and Chat.NeedsApply()
    if pending or automatic then
        desired.PLAYER_ENTERING_WORLD = true
        if InCombatLockdown and InCombatLockdown() then desired.PLAYER_REGEN_ENABLED = true
        else
            desired.CHANNEL_UI_UPDATE = true
            desired.CHAT_MSG_CHANNEL_NOTICE = pending and pending.restored or nil
        end
    end
    for event in pairs(eventMask) do
        if not desired[event] then frame:UnregisterEvent(event); eventMask[event] = nil end
    end
    for event in pairs(desired) do
        if not eventMask[event] then frame:RegisterEvent(event); eventMask[event] = true end
    end
end

function Chat:Initialize()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_CHANNEL_NOTICE" then
            if not pending or not pending.restored or select(1, ...) ~= "YOU_JOINED" then return end
            local channel = select(9, ...) or select(2, ...)
            if type(channel) ~= "string" then return end
            local requiredChannel = false
            for _, window in ipairs(pending.layout.windows) do
                for _, name in ipairs(window.channels) do
                    if channel == name or channel:find(name .. " -", 1, true) then requiredChannel = true end
                end
            end
            if not requiredChannel then return end
        end
        Boundary(function()
            if pending then Run() else QueueAuto() end
        end)
    end)
    UpdateEvents()
    Status("Chat presets ready.")
end
function Chat:OnLogin()
    if loginChecked then return end
    loginChecked = true
    local account = Stores()
    if account and account.autoApply and Chat.NeedsApply() then
        loginDefault = { export = account.default.export, savedAt = account.default.savedAt }
        QueueAuto()
    end
    UpdateEvents()
end
function Chat:ApplySettings()
    local account = Stores()
    if not account or not account.autoApply then
        generation = generation + 1; queued = false; loginDefault = nil
        if pending and pending.automatic then pending = nil; Status("Automatic chat apply disabled.") end
    else QueueAuto() end
    UpdateEvents()
end
function Chat:GetStatus() return status or "Chat presets not initialized." end

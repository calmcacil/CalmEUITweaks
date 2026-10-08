-- Run from the EUI root: lua CalmEUITweaks/tests/Chat.lua
local passed = 0
local unpack = unpack or table.unpack
local function Check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = Copy(v) end; return result
end
local function New(account, character, loggedIn)
    local s = { writes = 0, closes = 0, joins = {}, joined = { General = 7, Trade = 12 }, timers = {}, reports = {}, clears = 0,
        now = 1700000000, combat = false, windows = {}, dock = {}, selected = nil, blocked = {}, events = {}, loggedIn = loggedIn }
    local ns = { db = { chat = account or { autoApply = false } }, charDB = { chat = character or {} } }
    ns.RegisterModule = function(key, module) assert(key == "chat"); ns.module = module end
    ns.RefreshOptions = function() s.refreshes = (s.refreshes or 0) + 1 end
    ns.ReportError = function(key, err) assert(key == "chat"); s.reports[#s.reports + 1] = tostring(err); s.error = tostring(err) end
    ns.ClearError = function() s.clears = s.clears + 1; s.error = nil end
    time = function() return s.now end
    date = function(_, timestamp) return "date-" .. tostring(timestamp) end
    InCombatLockdown = function() return s.combat end
    IsLoggedIn = function() return s.loggedIn or false end
    C_Timer = { After = function(_, fn) s.timers[#s.timers + 1] = fn end }
    CreateFrame = function()
        local f = { scripts = {}, events = {} }
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
    function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(key, fn) self.scripts[key] = fn end
        s.events[#s.events + 1] = f
        return f
    end
    UIParent = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end }
    GENERAL_CHAT_DOCK = {}
    NUM_CHAT_WINDOWS = 7
    Constants = { ChatFrameConstants = { MaxChatWindows = NUM_CHAT_WINDOWS } }
    FCF_IsChatWindowIndexReserved = function(id) return id <= 3 end
    ChatTypeGroup = { SAY = {}, CHANNEL = {}, LOOT = {}, SYSTEM = {}, COMBAT_MISC_INFO = {} }
    local function Write()
        assert(not s.combat, "Native mutation in combat")
        s.writes = s.writes + 1
        if s.failAt == s.writes then error("native write failed") end
    end
    for id = 1, NUM_CHAT_WINDOWS do
        local f = { id = id, name = id == 1 and "General" or id == 2 and "Combat Log" or id == 3 and "Voice" or id == 4 and "Loot: | café" or "",
            width = 400 + id, height = 180 + id, left = 10 * id, bottom = 20 * id,
            shown = id <= 2 or id == 4, locked = id <= 4, uninteractable = false, font = 12 + id,
            r = 0.1, g = 0.2, b = 0.3, a = 0.4, fading = true, visible = 120,
            groups = id == 2 and { "COMBAT_MISC_INFO" } or id == 4 and { "LOOT", "CHANNEL" } or { "SAY" },
            channels = id == 1 and { "General" } or id == 4 and { "Trade" } or {}, history = { "untouched" } }
        function f:GetID() return self.id end
        function f:GetWidth() return self.width end
        function f:GetHeight() return self.height end
        function f:GetLeft() return self.left end
        function f:GetBottom() return self.bottom end
        function f:GetFading() return self.fading end
        function f:GetTimeVisible() return self.visible end
        function f:SetFading() error("Chat fading changed") end
        function f:SetTimeVisible() error("Chat fading changed") end
        function f:Show() assert(self.id ~= 3, "Voice visibility changed"); Write(); self.visibleNow = true end
        function f:Hide() assert(self.id ~= 3, "Voice visibility changed"); Write(); self.visibleNow = false end
        function f:ClearAllPoints() error("Chat anchors changed") end
        function f:SetPoint() error("Chat position changed") end
        function f:SetSize() error("Chat dimensions changed") end
        function f:SetUserPlaced() error("Chat placement ownership changed") end
        _G["ChatFrame" .. id] = f
        _G["ChatFrame" .. id .. "Tab"] = { Show = function() Write() end, Hide = function() Write() end }
        s.windows[id] = f
        if id <= 2 or id == 4 then s.dock[#s.dock + 1] = f; f.isDocked = true end
    end
    s.selected = s.windows[4]
    DEFAULT_CHAT_FRAME, COMBATLOG = s.windows[1], s.windows[2]
    FCF_GetChatFrameByID = function(id) return s.windows[id] end
    FCF_GetChatWindowInfo = function(id)
        local f = s.windows[id]; return f.name, f.font, f.r, f.g, f.b, f.a, f.shown, f.locked, f.isDocked, f.uninteractable
    end
    GetChatWindowInfo = FCF_GetChatWindowInfo
    GetChatWindowMessages = function(id) return unpack(s.windows[id].groups) end
    GetChatWindowChannels = function(id)
        local result = {}
        for _, name in ipairs(s.windows[id].channels) do result[#result + 1] = name; result[#result + 1] = name == "General" and 1 or 2 end
        return unpack(result)
    end
    FCFDock_GetChatFrames = function() return s.dock end
    FCFDock_GetSelectedWindow = function() return s.selected end
    FCFDock_SelectWindow = function(_, f) Write(); s.selected = f end
    FCF_UnDockFrame = function(f)
        Write(); if f.id == 1 then return end
        for i = #s.dock, 1, -1 do if s.dock[i] == f then table.remove(s.dock, i) end end
        f.isDocked = false
    end
    FCF_DockFrame = function(f, index)
        Write(); assert(not f.isDocked, "Duplicate dock"); table.insert(s.dock, index, f); f.isDocked = true; f.locked = true
    end
    FCF_Close = function(f)
        Write(); assert(not FCF_IsChatWindowIndexReserved(f.id), "Closed reserved tab"); s.closes = s.closes + 1
        FCF_UnDockFrame(f); f.groups, f.channels = {}, {}; f.visibleNow = false; f.shown = false
    end
    SetChatWindowShown = function(id, v) assert(id ~= 3, "Voice visibility persisted"); Write(); s.windows[id].shown = v end
    FCF_SetWindowName = function(f, v) assert(f.id ~= 3, "Voice renamed"); Write(); f.name = v end
    FCF_SetWindowColor = function() error("Chat background changed") end
    FCF_SetWindowAlpha = function() error("Chat opacity changed") end
    FCF_SetLocked = function(f, v) Write(); f.locked = v end
    FCF_SetUninteractable = function(f, v) Write(); f.uninteractable = v end
    FCF_SetChatWindowFontSize = function() error("Chat font changed") end
    FCF_SavePositionAndDimensions = function() error("Chat position saved") end
    FCF_OpenNewWindow = function(name)
        for id = 4, NUM_CHAT_WINDOWS do
            local f = s.windows[id]
            if not f.shown and not f.isDocked then
                Write()
                f.name, f.shown = name, true
                f.groups, f.channels, f.history = {}, {}, {}
                FCF_DockFrame(f, #s.dock + 1)
                return f, id
            end
        end
    end
    ChatFrame_RemoveAllMessageGroups = function(f) Write(); f.groups = {} end
    ChatFrame_AddMessageGroup = function(f, v)
        assert(ChatTypeGroup and ChatTypeGroup[v], "Unsupported group passed to native chat: " .. v)
        Write(); f.groups[#f.groups + 1] = v
    end
    ChatFrame_RemoveAllChannels = function(f) Write(); f.channels = {} end
    ChatFrame_AddChannel = function(f, v)
        Write(); if s.failChannel then error("channel failure") end
        assert(type(v) == "string", "Character-specific channel number used")
        for _, old in ipairs(f.channels) do assert(old ~= v, "Duplicate channel subscription") end
        f.channels[#f.channels + 1] = v
    end
    GetChannelName = function(name) assert(type(name) == "string"); return s.joined[name] or 0, name end
    JoinPermanentChannel = function(name, password, id, permanent)
        Write(); assert(password == nil and type(name) == "string" and permanent == 1)
        s.joins[#s.joins + 1] = { name = name, id = id }
        if not s.blocked[name] then s.joined[name] = 32 end
    end
    LeaveChannel = function() error("Unrelated joined channel left") end
    FCF_ResetChatWindows = function() error("Destructive chat reset") end
    SetCVar = function() error("Unrelated CVar changed") end
    local chunk = assert(loadfile("CalmEUITweaks/functions/Chat.lua")); chunk("CalmEUITweaks", ns)
    local chat = ns.Chat
    chat:Initialize()
    function s:Login()
        self.loggedIn = true
        chat:OnLogin()
    end
    if loggedIn then s:Login() end
    function s:Flush()
        local timers = self.timers; self.timers = {}
        for _, fn in ipairs(timers) do fn() end
        assert(#self.timers == 0, "Automatic apply polls or reschedules itself")
    end
    function s:Event(event, ...)
        if event == "PLAYER_ENTERING_WORLD" then self:Login() end
        for _, f in ipairs(self.events) do if f.events[event] then f.scripts.OnEvent(f, event, ...) end end
    end
    return s, ns, chat
end

local source, owner, chat = New()
Check(chat.SaveDefault(), "Capture saved")
local exported = assert(chat.ExportDefault())
Check(not chat.NeedsApply(), "Saving character already applied")
Check(exported:match("^CUTCHAT2:") and not exported:find("café", 1, true), "Printable versioned Unicode-safe export")
Check(source.writes == 0, "Saving never mutates native chat")
local account = Copy(owner.db.chat)
local target, other, migrated = New(account)
Check(migrated.NeedsApply(), "New character is stale")
Check(migrated.ImportDefault(exported), "Roundtrip import")
Check(other.charDB.chat.appliedExport == nil and target.writes == 0 and not account.autoApply, "Import neither applies nor opts in")
Check(migrated.ExportDefault() == exported, "Canonical export roundtrip")
-- Replace existing tab and add an extra tab before applying.
target.windows[4].name = "Wrong tab"
target.windows[5].name, target.windows[5].shown = "Extra", true
target.dock = { target.windows[1], target.windows[5], target.windows[2], target.windows[4] }
target.windows[5].isDocked = true
target.windows[2].groups = { "SYSTEM" }
target.windows[1].left, target.windows[1].font = 345, 22
target.windows[4].locked, target.windows[4].uninteractable = false, true
local voiceBefore = Copy(target.windows[3])
target.joined.General, target.joined.Trade = 95, 64
Check(migrated.ApplyDefault(), "Native restore succeeds")
Check(target.windows[4].name == "Loot: | café" and not target.windows[5].shown, "Saved tab replaces existing and closes extra")
Check(#target.dock == 3 and target.dock[2].id == 2 and target.dock[3].id == 4 and target.selected.id == 4, "Dock order and selected tab restored")
Check(target.windows[2].groups[1] == "SYSTEM" and target.windows[2].history[1] == "untouched", "Combat filters and history preserved")
Check(target.windows[1].channels[1] == "General" and target.windows[4].channels[1] == "Trade", "Channels persisted by name despite different numbers")
Check(target.windows[1].left == 345 and target.windows[1].font == 22 and target.windows[1].width == 401
    and target.windows[1].a == 0.4 and target.windows[1].fading and target.windows[1].visible == 120,
    "Existing position, dimensions, font, background and fading remain local")
Check(not target.windows[4].locked and target.windows[4].uninteractable, "Docking preserves local interaction state")
Check(target.windows[3].name == voiceBefore.name and target.windows[3].shown == voiceBefore.shown
    and target.windows[3].groups[1] == voiceBefore.groups[1] and target.windows[3].history[1] == voiceBefore.history[1],
    "Modern reserved voice frame is untouched")
Check(other.charDB.chat.appliedExport == exported and not migrated.NeedsApply(), "Successful character receipt")
Check(migrated.ApplyDefault() and #target.dock == 3, "Repeated manual apply does not duplicate tabs")
Check(migrated.GetSummary():find("Up to date", 1, true), "Summary reports up to date")

local same, sameNS, sameChat = New(Copy(account), Copy(other.charDB.chat))
same.windows[1].groups = { "SAY", "SYSTEM" }
Check(sameChat.SaveDefault(), "Same-second changed save")
Check(sameNS.db.chat.default.savedAt > account.default.savedAt and sameNS.db.chat.default.export ~= exported,
    "Same-second save advances the default date and retains changed content")
local stale, staleNS, staleChat = New(Copy(sameNS.db.chat), Copy(other.charDB.chat))
Check(staleChat.NeedsApply(), "Same-second save produces a newer default")
staleNS.db.chat.autoApply = true
staleChat:ApplySettings(); stale:Flush()
Check(stale.writes == 0, "Auto waits for entering world")
stale:Event("PLAYER_ENTERING_WORLD")
Check(stale.writes == 0, "Auto waits until next frame")
stale:Flush()
Check(stale.writes > 0 and not staleChat.NeedsApply(), "Opt-in stale character automatically applies")
local writes = stale.writes
stale:Event("PLAYER_ENTERING_WORLD"); staleChat:ApplySettings(); stale:Flush()
Check(stale.writes == writes, "Up-to-date character skips automatic apply")
local fresh, freshNS, freshChat = New(Copy(account))
freshNS.db.chat.autoApply = true; fresh:Event("PLAYER_ENTERING_WORLD")
freshNS.db.chat.autoApply = false; freshChat:ApplySettings(); fresh:Flush()
Check(fresh.writes == 0, "Disable cancels next-frame automatic apply")

local combat, combatNS, combatChat = New(Copy(account))
combat.combat = true
Check(not combatChat.ApplyDefault() and combat.writes == 0 and not combatNS.charDB.chat.appliedExport, "Combat queues manual apply without receipt")
combatChat:ApplySettings() -- Auto is disabled, but manual work survives.
combat.combat = false; combat:Event("PLAYER_REGEN_ENABLED")
Check(not combatChat.NeedsApply(), "Manual combat apply survives disabling auto")
local autoCombat, acNS, acChat = New(Copy(account))
acNS.db.chat.autoApply = true; autoCombat.combat = true
autoCombat:Event("PLAYER_ENTERING_WORLD"); autoCombat:Flush()
acNS.db.chat.autoApply = false; acChat:ApplySettings()
autoCombat.combat = false; autoCombat:Event("PLAYER_REGEN_ENABLED")
Check(autoCombat.writes == 0 and acChat.NeedsApply(), "Disabling auto cancels combat automatic work")

local channels, channelsNS, channelsChat = New(Copy(account))
channels.joined.Trade = nil; channels.blocked.Trade = true
Check(not channelsChat.ApplyDefault() and channelsNS.charDB.chat.appliedExport == nil, "Unavailable channel keeps receipt pending")
channels.windows[1].left = 333
channels.windows[1].channels = {}
channels:Event("CHANNEL_UI_UPDATE")
Check(channels.windows[1].left == 333 and channels.windows[1].channels[1] == "General",
    "Channel reconciliation preserves layout and restores subscriptions lost while pending")
channels.blocked.Trade = false; channels.joined.Trade = 81
channels:Event("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "Trade")
Check(not channelsChat.NeedsApply() and channelsNS.charDB.chat.appliedAt == channels.now
    and channels.windows[1].channels[1] == "General", "Async completion records receipt only with all channel subscriptions")
local failure, failNS, failChat = New(Copy(account))
failure.failChannel = true
Check(not failChat.ApplyDefault() and #failure.reports == 1 and failNS.charDB.chat.appliedExport == nil, "Runtime channel exception reported without receipt")
failure.failChannel = false; failure:Event("CHANNEL_UI_UPDATE")
Check(not failChat.NeedsApply() and failure.windows[4].channels[1] == "Trade" and not failure.error,
    "Deferred failure clears only after successful channel reconciliation")
local partial, partialNS, partialChat = New(Copy(account))
partial.failAt = 15
Check(not partialChat.ApplyDefault() and partialNS.charDB.chat.appliedExport == nil and #partial.reports == 1, "Partial native failure never marks applied")
partial.failAt = nil
Check(partialChat.ApplyDefault() and partial.error == nil, "Explicit retry completes partial failure")

local invalid, invalidNS, invalidChat = New(Copy(account))
local original = invalidNS.db.chat.default
for _, bad in ipairs({ "", exported:sub(1, -2), exported .. ":garbage", exported:gsub("CUTCHAT2", "CUTCHAT1"), string.rep("A", 65537), "return os.execute('bad')" }) do
    Check(not invalidChat.ImportDefault(bad) and invalidNS.db.chat.default == original and invalid.writes == 0, "Invalid import is refused before any mutation")
end
local function ChangeToken(text, index, value)
    local tokens = {}; for token in text:gmatch("[^:]+") do tokens[#tokens + 1] = token end
    tokens[index] = value; return table.concat(tokens, ":")
end
-- First tab starts at token 4: logical ID, name, shown, dock; lists follow.
for _, edit in ipairs({ { 4, "0" }, { 7, "2" }, { 6, "1" }, { 8, "-1" }, { 12, "1" }, { 15, "1" }, { 9, "T" }, { 2, "5" } }) do
    Check(not invalidChat.ImportDefault(ChangeToken(exported, edit[1], edit[2])) and invalid.writes == 0
        and invalidNS.db.chat.default == original, "Invalid tab IDs, visibility, dock order, lists and selection refused")
end
local unsupported = exported:gsub("S534159", "S554E535550504F52544544")
local filtered, filteredNS, filteredChat = New(Copy(account))
Check(filteredChat.ImportDefault(unsupported) and filtered.writes == 0 and #filtered.reports == 0,
    "Unavailable message groups are filtered without native writes or exception reports")
Check(filteredChat.ApplyDefault() and #filtered.windows[1].groups == 0 and not filteredChat.NeedsApply(),
    "Unavailable imported groups never reach native chat subscriptions")
-- Restore globals to the fixture used by the remaining preflight tests.
invalid, invalidNS, invalidChat = New(Copy(account))
local savedAPI = FCF_SetWindowName
FCF_SetWindowName = nil
Check(not invalidChat.ApplyDefault() and invalid.writes == 0, "Missing native API refused before mutations")
FCF_SetWindowName = savedAPI
local methodState, methodNS, methodChat = New(Copy(account))
for _, method in ipairs({ "AddMessageGroup", "RemoveAllMessageGroups", "AddChannel", "RemoveAllChannels" }) do
    local fn = _G["ChatFrame_" .. method]
    for _, f in ipairs(methodState.windows) do f[method] = fn end
    _G["ChatFrame_" .. method] = nil
end
Check(methodChat.ApplyDefault() and not methodChat.NeedsApply(), "Native frame-method API alternative supported")
local lateAccount = Copy(account); lateAccount.autoApply = true
local late, lateNS, lateChat = New(lateAccount, nil, true)
lateChat:ApplySettings(); late:Flush()
Check(not lateChat.NeedsApply(), "Addon loaded after login automatically applies next frame")
local timestamp, tsNS, tsChat = New(Copy(account), Copy(other.charDB.chat))
tsNS.db.chat.default.savedAt = tsNS.db.chat.default.savedAt + 1
Check(tsChat.NeedsApply(), "Changed saved timestamp is stale even with identical content")
local cancel, cancelNS, cancelChat = New(Copy(account))
cancelNS.db.chat.autoApply = true; cancel.joined.Trade = nil; cancel.blocked.Trade = true
cancel:Event("PLAYER_ENTERING_WORLD"); cancel:Flush()
local beforeCancel = cancel.writes
cancelNS.db.chat.autoApply = false; cancelChat:ApplySettings()
cancel.joined.Trade = 99; cancel:Event("CHANNEL_UI_UPDATE")
Check(cancel.writes == beforeCancel and cancelChat.NeedsApply(), "Disabling auto cancels pending channel receipt")
local manual, manualNS, manualChat = New(Copy(account))
manual.joined.Trade = nil; manual.blocked.Trade = true
Check(not manualChat.ApplyDefault(), "Manual apply awaits blocked trade channel")
manualChat:ApplySettings(); manual.joined.Trade = 18; manual:Event("PLAYER_ENTERING_WORLD")
Check(not manualChat.NeedsApply(), "Manual pending channel receipt survives auto disabled")
local baseline, baselineNS, baselineChat = New()
baseline.windows[4].name = "Loot/Trade"
baseline.windows[5].name, baseline.windows[5].shown, baseline.windows[5].isDocked = "LFG", true, true
baseline.windows[5].groups, baseline.windows[5].channels = { "CHANNEL" }, { "LookingForGroup", "Layer" }
baseline.dock[#baseline.dock + 1] = baseline.windows[5]
Check(baselineChat.SaveDefault(), "Four-tab preset captured without using reserved native IDs")
local savedTabs = assert(baselineChat.ExportDefault())
baseline.windows[1].font, baseline.windows[1].left = 27, 700
baseline.windows[6].name = "Closed tab"
Check(baselineChat.SaveDefault() and baselineChat.ExportDefault() == savedTabs,
    "Local appearance changes and inactive named windows are not part of the preset")
local created, createdNS, createdChat = New(Copy(baselineNS.db.chat))
created.windows[4].shown, created.windows[4].isDocked, created.windows[4].name = false, false, ""
created.windows[3].shown, created.windows[3].isDocked = true, true
created.dock = { created.windows[1], created.windows[2], created.windows[3] }
created.selected = created.windows[3]
created.windows[1].left, created.windows[1].bottom, created.windows[1].font = 880, 75, 24
Check(createdChat.ApplyDefault(), "Missing user tabs restored")
local settingsNames = {}
for id = 4, NUM_CHAT_WINDOWS do
    local f = created.windows[id]
    if f.shown or f.isDocked then settingsNames[#settingsNames + 1] = f.name end
end
Check(settingsNames[1] == "Loot/Trade" and settingsNames[2] == "LFG" and #settingsNames == 2,
    "Loot/Trade and LFG are ordinary windows eligible for native chat settings")
Check(created.windows[3].name == "Voice" and created.windows[3].shown and created.windows[3].isDocked
    and created.dock[3] == created.windows[3], "Active voice tab remains reserved and in its live dock position")
Check(created.windows[4].channels[1] == "Trade" and created.windows[5].channels[1] == "Layer"
    and created.windows[5].channels[2] == "LookingForGroup", "Logical tab subscriptions use allocated native frame IDs")
Check(created.windows[1].left == 880 and created.windows[1].bottom == 75 and created.windows[1].font == 24,
    "Creating native tabs never moves or restyles the primary window")
local old, oldNS, oldChat = New(Copy(account))
oldNS.db.chat.default.export = exported:gsub("CUTCHAT2", "CUTCHAT1")
Check(not oldChat.ApplyDefault() and old.writes == 0 and not oldNS.charDB.chat.appliedExport,
    "Persisted layout-format defaults cannot be applied after the tabs-only cutover")
local legacySave, legacySaveNS, legacySaveChat = New()
legacySave.windows[1].groups = {"SAY", "BN_CONVERSATION"}
Check(legacySaveChat.SaveDefault() and not legacySaveChat.ExportDefault():find("S424E5F434F4E564552534154494F4E", 1, true),
    "Saving cleans unavailable legacy subscriptions returned by the native client")
Check(legacySave.windows[1].groups[2] == "BN_CONVERSATION" and legacySave.writes == 0,
    "Saving a legacy subscription never mutates live chat")

local supportedBN, supportedBNNS, supportedBNChat = New()
ChatTypeGroup.BN_CONVERSATION = {}
supportedBN.windows[1].groups = {"SAY", "BN_CONVERSATION"}
Check(supportedBNChat.SaveDefault() and supportedBNChat.ExportDefault():find("S424E5F434F4E564552534154494F4E", 1, true),
    "Clients supporting BN_CONVERSATION retain it in exports")
Check(supportedBNChat.ApplyDefault() and supportedBN.windows[1].groups[1] == "BN_CONVERSATION",
    "Supported Battle.net conversation subscriptions are restored")

local notReady, notReadyNS, notReadyChat = New({autoApply = true, default = Copy(account.default)})
local groups = ChatTypeGroup
ChatTypeGroup = nil
notReady:Event("PLAYER_ENTERING_WORLD"); notReady:Flush()
Check(notReady.writes == 0 and notReadyChat.NeedsApply() and notReadyChat:GetStatus():find("not ready", 1, true),
    "Auto apply waits without writes or receipt when group definitions are not ready")
ChatTypeGroup = groups
notReady:Event("CHANNEL_UI_UPDATE"); notReady:Flush()
Check(not notReadyChat.NeedsApply() and notReady.writes > 0,
    "Later chat readiness event retries automatic apply after preflight failure")

local lateAPI, lateAPINS, lateAPIChat = New({autoApply = true, default = Copy(account.default)})
local rename = FCF_SetWindowName
FCF_SetWindowName = nil
lateAPI:Event("PLAYER_ENTERING_WORLD"); lateAPI:Flush()
Check(lateAPI.writes == 0 and lateAPIChat.NeedsApply(), "Late native API prevents premature auto apply")
FCF_SetWindowName = rename
lateAPI:Event("CHANNEL_UI_UPDATE"); lateAPI:Flush()
Check(not lateAPIChat.NeedsApply(), "Combat-end event retries auto apply once native API is available")
local stableWrites = lateAPI.writes
lateAPI:Event("CHANNEL_UI_UPDATE"); lateAPI:Flush()
Check(lateAPI.writes == stableWrites, "Readiness retry never reapplies an up-to-date character")
-- Runtime inventory reported by the user's Forever client, rather than retail assumptions.
local foreverGroups = [[
ACHIEVEMENT AFK BG_ALLIANCE BG_HORDE BG_NEUTRAL BN_INLINE_TOAST_ALERT BN_WHISPER CHANNEL
COLLECTED_APPEARANCE COMBAT_FACTION_CHANGE COMBAT_HONOR_GAIN COMBAT_MISC_INFO COMBAT_XP_GAIN
COMMUNITIES_CHANNEL CURRENCY DND EMOTE ERRORS GUILD GUILD_ACHIEVEMENT GUILD_DISCORD IGNORED
INSTANCE_CHAT INSTANCE_CHAT_LEADER LOOT MONEY MONSTER_BOSS_EMOTE MONSTER_BOSS_WHISPER
MONSTER_EMOTE MONSTER_SAY MONSTER_WHISPER MONSTER_YELL OFFICER OPENING PARTY PARTY_LEADER
PET_BATTLE_COMBAT_LOG PET_BATTLE_INFO PET_INFO PING RAID RAID_LEADER RAID_WARNING SAY SKILL
SYSTEM TARGETICONS TRADESKILLS VOICE_TEXT WHISPER YELL
]]
local unavailableForever = {"GUILD_ITEM_LOOTED", "SYSTEM_NOMENU", "BN_WHISPER_INFORM",
    "BN_WHISPER_PLAYER_OFFLINE", "ENCOUNTER_EVENT", "BN_CONVERSATION"}
local function ForeverTypes()
    ChatTypeGroup = {}
    for group in foreverGroups:gmatch("%S+") do ChatTypeGroup[group] = {} end
end
local crossSource, crossNS, crossChat = New()
ForeverTypes()
local expected = {}
for group in foreverGroups:gmatch("%S+") do expected[#expected + 1] = group end
table.sort(expected)
crossSource.windows[1].groups = Copy(expected)
for _, group in ipairs(unavailableForever) do
    ChatTypeGroup[group] = {}
    crossSource.windows[1].groups[#crossSource.windows[1].groups + 1] = group
end
Check(crossChat.SaveDefault(), "Cross-client source includes all six unavailable Forever groups")
local crossExport = assert(crossChat.ExportDefault())
local forever, foreverNS, foreverChat = New(Copy(crossNS.db.chat))
ForeverTypes()
Check(foreverChat.ApplyDefault() and table.concat(forever.windows[1].groups, ",") == table.concat(expected, ","),
    "Manual apply retains every supported Forever group and filters all six unavailable groups together")
Check(foreverNS.charDB.chat.appliedExport == crossExport and not foreverChat.NeedsApply(),
    "Filtering existing saved presets preserves receipt identity and prevents repeated auto application")
Check(foreverChat.ImportDefault(crossExport) and foreverChat.ApplyDefault()
    and table.concat(forever.windows[1].groups, ",") == table.concat(expected, ","),
    "Import normalizes a cross-client preset against the full reported Forever inventory")
local foreverAuto, foreverAutoNS, foreverAutoChat = New({autoApply = true, default = Copy(crossNS.db.chat.default)})
ForeverTypes()
foreverAuto:Event("PLAYER_ENTERING_WORLD"); foreverAuto:Flush()
Check(not foreverAutoChat.NeedsApply()
    and table.concat(foreverAuto.windows[1].groups, ",") == table.concat(expected, ","),
    "Auto apply handles the complete Forever inventory with all unavailable groups present")
local emptyTypes, emptyTypesNS, emptyTypesChat = New({autoApply = true, default = Copy(account.default)})
ChatTypeGroup = {}
emptyTypes:Event("PLAYER_ENTERING_WORLD"); emptyTypes:Flush()
Check(emptyTypes.writes == 0 and emptyTypesChat.NeedsApply(),
    "An empty group registry is treated as not ready instead of stripping all subscriptions")
ChatTypeGroup = {SAY = {}, CHANNEL = {}, LOOT = {}}
emptyTypes:Event("CHANNEL_UI_UPDATE"); emptyTypes:Flush()
Check(not emptyTypesChat.NeedsApply(), "Auto apply retries once the empty runtime registry becomes ready")
local idle, idleNS, idleChat = New()
Check(next(idle.events[1].events) == nil, "Manual chat has no idle readiness subscriptions")
idle:Login()
idleNS.db.chat.default = Copy(account.default)
idleNS.db.chat.autoApply = true
idleChat:ApplySettings(); idle:Flush()
Check(idleChat.NeedsApply() and idle.writes == 0 and next(idle.events[1].events) == nil,
    "Enabling chat after a defaultless login waits for the next login")
local deferredChat, deferredNS, manualChat = New(Copy(account))
deferredChat.combat = true
manualChat.ApplyDefault()
Check(deferredChat.events[1].events.PLAYER_REGEN_ENABLED
    and not deferredChat.events[1].events.CHANNEL_UI_UPDATE,
    "Manual combat deferral subscribes only to relevant readiness")
deferredChat.combat = false; deferredChat:Event("PLAYER_REGEN_ENABLED")
Check(not manualChat.NeedsApply() and next(deferredChat.events[1].events) == nil,
    "Manual completion releases combat and channel listeners")

for _, dateOffset in ipairs({ 0, -1 }) do
    local datedAccount = Copy(account); datedAccount.autoApply = true
    local applied = { appliedExport = "different serialized default", appliedSavedAt = datedAccount.default.savedAt - dateOffset }
    local dated, datedNS, datedChat = New(datedAccount, applied)
    dated:Login(); dated:Flush(); dated:Event("PLAYER_ENTERING_WORLD"); dated:Flush()
    Check(not datedChat.NeedsApply() and dated.writes == 0 and next(dated.events[1].events) == nil,
        "Equal or older default does not apply even when serialized content differs")
    Check(datedNS.charDB.chat.appliedSavedAt == applied.appliedSavedAt, "Skipped login preserves character receipt")
end

local importedAccount = Copy(account); importedAccount.autoApply = true
local imported, importedNS, importedChat = New(importedAccount, Copy(other.charDB.chat))
imported:Login(); imported:Flush()
Check(imported.writes == 0, "Up-to-date login preserves local chat")
Check(importedChat.ImportDefault(exported), "Mid-session import succeeds")
local importedDate = importedNS.db.chat.default.savedAt
Check(importedDate > account.default.savedAt, "Same-second import advances the saved default date")
importedChat:ApplySettings(); imported:Event("CHANNEL_UI_UPDATE"); imported:Event("PLAYER_ENTERING_WORLD"); imported:Flush()
Check(imported.writes == 0 and importedChat.NeedsApply() and next(imported.events[1].events) == nil,
    "Import after login never automatically applies on settings or readiness/world events")
local nextLogin, nextLoginNS, nextLoginChat = New(Copy(importedNS.db.chat), Copy(importedNS.charDB.chat))
nextLogin:Login(); nextLogin:Flush()
Check(nextLogin.writes > 0 and nextLoginNS.charDB.chat.appliedSavedAt == importedDate,
    "Next login applies the imported default and records its saved date on that character")

local disabledAccount = Copy(account)
local enabledLater, enabledNS, enabledChat = New(disabledAccount)
enabledLater:Login()
enabledNS.db.chat.autoApply = true; enabledChat:ApplySettings()
enabledLater:Event("PLAYER_ENTERING_WORLD"); enabledLater:Event("CHANNEL_UI_UPDATE"); enabledLater:Flush()
Check(enabledLater.writes == 0 and enabledChat.NeedsApply(), "Enabling automatic apply after login waits for next login")
Check(enabledChat.ApplyDefault() and not enabledChat.NeedsApply(), "Manual apply remains available during the session")

local replacementAccount = Copy(account); replacementAccount.autoApply = true
local replaced, replacedNS, replacedChat = New(replacementAccount)
replaced:Login()
Check(replacedChat.ImportDefault(exported), "Import replaces a queued login default")
replaced:Flush(); replaced:Event("PLAYER_ENTERING_WORLD"); replaced:Flush()
Check(replaced.writes == 0 and replacedChat.NeedsApply(), "Import cancels queued login work without selecting new session work")

local invalidAuto, invalidAutoNS, invalidAutoChat = New({ autoApply = true,
    default = { export = "invalid preset", savedAt = 1700000000 } })
invalidAuto:Login(); invalidAuto:Flush()
Check(invalidAuto.writes == 0 and next(invalidAuto.events[1].events) == nil,
    "An invalid saved default releases automatic readiness subscriptions")
print("Chat tests passed: " .. passed)

local root = "CalmEUITweaks/"
local ns = {}
assert(loadfile(root .. "core/Bootstrap.lua"))("CalmEUITweaks", ns)
assert(loadfile(root .. "core/Settings.lua"))("CalmEUITweaks", ns)
ns.db = ns.Copy(ns.defaults)
local calls, registered, queued = {}, {}, {}
local function Paint(frame) calls[frame] = true end
local api = {Button = Paint, EditBox = Paint, Checkbox = Paint, Shell = Paint, IsEnabled = function() return true end}
EllesmereUI = {RegisterSkin = function(label, callback)
    registered[label] = true
    callback(api)
end}
local loaded = {Auctionator = true, LiteMount = true, Journalator = true}
C_AddOns = {IsAddOnLoaded = function(name) return loaded[name] end}
local combat, events = true, {}
InCombatLockdown = function() return combat end
CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function(_, event) events[event] = true end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        UnregisterAllEvents = function() events = {} end,
    }
end
ns.RequestApply = function(key) queued[key] = true end
local function Frame(kind, ...)
    local children = {...}
    return {
        GetChildren = function() return unpack(children) end,
        IsObjectType = function(_, expected) return kind == expected end,
        HookScript = function(self, event, callback) self[event] = callback end,
    }
end
local search, unrelated = Frame("EditBox"), Frame("EditBox")
AuctionatorShoppingFrame = Frame("Frame", search)
AuctionFrame = Frame("Frame", AuctionatorShoppingFrame, unrelated)
LiteMountBasePanel = Frame("Frame", Frame("EditBox"))
for _, name in ipairs({"Controls", "Auctionator", "LiteMount", "Journalator"}) do
    assert(loadfile(root .. "skins/" .. name .. ".lua"))("CalmEUITweaks", ns)
end
ns.db.auctionatorSkin.enabled = true
local auction, mount = ns.modules.auctionatorSkin, ns.modules.liteMountSkin
auction:OnLogin()
mount:OnLogin()
mount:ApplySettings()
assert(not next(registered) and not next(calls))
loaded.Auctionator = nil
auction:ApplySettings()
auction:OnAddonLoaded("Blizzard_Settings")
assert(ns.GetStatus("auctionatorSkin") == "Disabled." and ns.db.auctionatorSkin.enabled)
assert(not next(registered) and not next(queued) and not next(events))
loaded.Auctionator = true
auction:OnAddonLoaded("Auctionator")
assert(queued.auctionatorSkin)
loaded.EUIAddonSkins = true
auction:ApplySettings()
assert(not next(registered))
loaded.EUIAddonSkins = nil
auction:ApplySettings()
assert(registered["Calm UI Tweaks - Auctionator"] and events.PLAYER_REGEN_ENABLED and not next(calls))
combat = false
auction:ApplySettings()
assert(calls[search] and not calls[unrelated] and not events.PLAYER_REGEN_ENABLED)
assert(not registered["Calm UI Tweaks - LiteMount"])
queued = {}
AuctionatorShoppingFrame.OnShow()
assert(queued.auctionatorSkin)
ns.db.auctionatorSkin.enabled = false
auction:ApplySettings()
queued = {}
AuctionatorShoppingFrame.OnShow()
assert(not next(queued) and not next(events))

ns.db.journalatorSkin.enabled = true
local journal = ns.modules.journalatorSkin
journal:OnLogin()
journal:ApplySettings()
assert(not JNRView)
Journalator = {ToggleView = function() JNRView = Frame("Frame") end}
hooksecurefunc = function(owner, method, callback)
    local original = owner[method]
    owner[method] = function() original(); callback() end
end
queued = {}
journal:OnAddonLoaded("Journalator_Display")
assert(queued.journalatorSkin)
journal:ApplySettings()
queued = {}
Journalator.ToggleView()
assert(queued.journalatorSkin and not calls[JNRView])
journal:ApplySettings()
assert(calls[JNRView])
print("Control skin tests passed")

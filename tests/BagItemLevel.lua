-- Run from the EUI root: lua CalmEUITweaks/tests/BagItemLevel.lua
local unpack = table.unpack or unpack
local production = "CalmEUITweaks/functions/BagItemLevel.lua"
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end

local function Harness()
    local h = {
        combat = false, combatViolations = 0, ownCombatMutations = 0, timers = {}, loads = {},
        frames = {}, slots = {}, items = {}, hookCounts = {}, equipped = {}, levelQueries = 0, containerQueries = 0, requests = {},
        settings = {enabled = true, inventory = true, reagent = true, bank = true},
        bankAccess = {[0] = true, [2] = true},
    }
    local env = setmetatable({}, {__index = _G})
    env._G = env
    h.env = env
    local methods = {}
    local function Visual(object)
        if h.combat and (not object or object.protected) then
            h.combatViolations = h.combatViolations + 1
            error("Bag display attempted protected mutation or creation in combat")
        end
        if h.combat then h.ownCombatMutations = h.ownCombatMutations + 1 end
    end
    local function Object(parent, isFrame)
        local object = setmetatable({
            parent = parent, children = {}, scripts = {}, events = {}, shown = true,
            calls = {}, isFrame = isFrame,
        }, {__index = methods})
        if parent and isFrame then table.insert(parent.children, object) end
        return object
    end
    function methods:GetParent() return self.parent end
    function methods:GetID() return self.id or 0 end
    -- Test-driven recycling represents native/secure pool updates, not addon actions.
    function methods:SetID(id) self.id = id end
    function methods:GetChildren() return unpack(self.children) end
    function methods:GetFrameLevel() return self.frameLevel or 1 end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:IsProtected()
        if self.protectionError then error("Protection query unavailable") end
        return not not self.protected
    end
    function methods:CanChangeProtectedState()
        if self.changeError then error("Protected-state query unavailable") end
        if self.cannotChange then return false end
        return not h.combat or not self.protected
    end
    function methods:SetParent(parent)
        Visual(self)
        if self.parent and self.isFrame then
            for i, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, i); break end
            end
        end
        self.parent = parent
        if parent and self.isFrame then table.insert(parent.children, self) end
    end
    function methods:RunScript(name, ...)
        for _, fn in ipairs(self.scripts[name] or {}) do fn(self, ...) end
    end
    function methods:HookScript(name, fn)
        self.scripts[name] = self.scripts[name] or {}
        table.insert(self.scripts[name], fn)
    end
    function methods:SetScript(name, fn) self.scripts[name] = {fn} end
    function methods:Show()
        Visual(self)
        local old = self.shown
        self.shown = true
        if not old then self:RunScript("OnShow") end
    end
    function methods:Hide()
        Visual(self)
        local old = self.shown
        self.shown = false
        if old then self:RunScript("OnHide") end
    end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:Fire(event, ...)
        if self.events[event] then self:RunScript("OnEvent", event, ...) end
    end
    function methods:SetItemButtonTexture(texture) self.texture = texture end
    function methods:SetItemButtonQuality() end
    function methods:CreateFontString()
        Visual(self)
        local region = Object(self, false)
        self.font = region
        return region
    end
    function methods:CreateTexture()
        Visual(self)
        local region = Object(self, false)
        self.textureRegion = region
        return region
    end
    for _, method in ipairs({
        "SetFrameLevel", "SetAllPoints", "SetSize", "SetAtlas", "ClearAllPoints", "SetPoint",
        "SetFontObject", "SetText", "SetTextColor", "SetScale", "SetVertexColor",
    }) do
        methods[method] = function(self, ...)
            Visual(self)
            self.calls[method] = {...}
        end
    end
    env.CreateFrame = function(_, name, parent)
        Visual()
        local frame = Object(parent, true)
        table.insert(h.frames, frame)
        if name then env[name] = frame end
        return frame
    end
    env.hooksecurefunc = function(object, method, callback)
        if type(object) == "string" then callback = method; method = object; object = env end
        local old = assert(object[method], "Missing mock hook target: " .. method)
        local counts = h.hookCounts[object] or {}
        h.hookCounts[object] = counts
        counts[method] = (counts[method] or 0) + 1
        object[method] = function(...)
            local result = {old(...)}
            callback(...)
            return unpack(result)
        end
    end
    env.SetItemButtonQuality = function() end
    env.InCombatLockdown = function() return h.combat end
    env.C_Timer = {After = function(_, fn) table.insert(h.timers, fn) end}
    env.Enum = {
        ItemClass = {Weapon = 2, Armor = 4, Profession = 19, Gem = 3},
        ItemGemSubclass = {Artifactrelic = 11}, BankType = {Character = 0, Account = 2},
        BagIndex = {AccountBankTab_1 = 13, AccountBankTab_5 = 17},
    }
    env.NumberFontNormal, env.GameFontNormalLargeOutline = {}, {}
    env.UnitLevel = function() return 80 end
    env.C_Bank = {CanUseBank = function(bankType) return h.bankAccess[bankType] end}
    local function Key(bag, slot) return bag .. ":" .. slot end
    env.C_Container = {
        GetContainerItemInfo = function(bag, slot)
            h.containerQueries = h.containerQueries + 1
            if h.failContainer then error("Simulated container failure") end
            return h.slots[Key(bag, slot)]
        end,
        GetContainerItemLink = function(bag, slot)
            local item = h.slots[Key(bag, slot)]
            return item and item.link
        end,
    }
    env.GetInventoryItemLink = function(_, slot) return h.equipped[slot] end
    env.C_Item = {
        GetDetailedItemLevelInfo = function(link)
            h.levelQueries = h.levelQueries + 1
            local item = h.items[tonumber(link:match("item:(%d+)"))]
            if h.failLevel then error("Item level unavailable") end
            return item and not item.missing and item.level or nil
        end,
        RequestLoadItemDataByID = function(id) h.requests[id] = (h.requests[id] or 0) + 1 end,
        GetItemInfoInstant = function(id)
            local itemID = tonumber(tostring(id):match("item:(%d+)")) or id
            local item = h.items[itemID] or {}
            return itemID, nil, nil, item.equipLoc or "INVTYPE_HEAD", nil, item.class or 4, item.subclass or 0
        end,
        GetItemInfo = function(id)
            local item = h.items[id] or h.items[tonumber(tostring(id):match("item:(%d+)"))]
            if not item or item.missing then return end
            return "Item", nil, nil, nil, item.minimum or 1, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, item.reagent
        end,
        GetItemQualityColor = function(quality)
            h.lastColorQuality = quality
            return 1, 0.5, 0.2
        end,
    }
    env.Item = {CreateFromBagAndSlot = function(_, bag, slot)
        return {
            bag = bag, slot = slot,
            IsItemEmpty = function() return not h.slots[Key(bag, slot)] end,
            GetItemID = function() return h.slots[Key(bag, slot)].itemID end,
            GetItemQuality = function() return h.slots[Key(bag, slot)].quality end,
            ContinueOnItemLoad = function(_, fn)
                if h.immediateLoads then fn() else table.insert(h.loads, fn) end
            end,
        }
    end}
    h.ns = {
        ready = false,
        RegisterModule = function(key, module)
            assert(key == "simpleItemLevel", "Incorrect feature key")
            h.module = module
        end,
        GetSettings = function(key) assert(key == "simpleItemLevel"); return h.settings end,
        SetStatus = function(key, message) assert(key == "simpleItemLevel"); h.status = message end,
        Print = function() end,
    }
    local chunk
    if setfenv then chunk = assert(loadfile(production)); setfenv(chunk, env)
    else chunk = assert(loadfile(production, "t", env)) end
    chunk("CalmEUITweaks", h.ns)
    function h:Flush()
        local turns = 0
        while #self.timers > 0 do
            turns = turns + 1
            assert(turns < 100, "Timer loop did not settle")
            local batch = self.timers
            self.timers = {}
            for _, fn in ipairs(batch) do fn() end
        end
    end
    function h:LoadItems()
        local batch = self.loads
        self.loads = {}
        for _, fn in ipairs(batch) do fn() end
    end
    function h:Draw(event)
        if event then self.event:Fire(event) end
        self:Flush()
        self:LoadItems()
    end
    function h:Apply() self.module:ApplySettings(); self:Draw() end
    function h:Root(name, method)
        local root = env.CreateFrame("Frame", name)
        root.protected = true
        if method then root[method] = function() end end
        return root
    end
    function h:Put(bag, slot, id)
        self.slots[Key(bag, slot)] = {itemID = id, link = "item:" .. id .. ":a", quality = 4}
        self.items[id] = self.items[id] or {level = 600, class = 4, minimum = 1}
        return self.slots[Key(bag, slot)]
    end
    function h:Button(root, bag, slot, id)
        local parent = env.CreateFrame("Frame", nil, root)
        parent.protected = true
        parent:SetID(bag)
        local button = env.CreateFrame("Button", nil, parent)
        button.protected = true
        button:SetID(slot)
        button.ItemLevelText = button:CreateFontString()
        button.ItemLevelText.protected = true
        button.ItemLevelText:SetText("native")
        self:Put(bag, slot, id)
        return button
    end
    function h:Overlay(button) return button.children[#button.children] end
    function h:Start()
        local previousFrames = #self.frames
        self.module:Initialize()
        self.event = self.frames[previousFrames + 1]
        self.ns.ready = true
        self:Apply()
    end
    return h
end

local function Equipped(h, slot, id, level, equipLoc)
    h.equipped[slot] = "item:" .. id .. ":a"
    h.items[id] = {level = level, equipLoc = equipLoc}
end

local function NativeComparison()
    local h = Harness()
    local root = h:Root("EUI_MainBagFrame")
    local head = h:Button(root, 0, 1, 100)
    local ring = h:Button(root, 0, 2, 101)
    local junk = h:Button(root, 0, 3, 102)
    h.items[101].equipLoc = "INVTYPE_FINGER"
    h.items[102].equipLoc = ""
    Equipped(h, 1, 200, 600, "INVTYPE_HEAD")
    Equipped(h, 11, 201, 620, "INVTYPE_FINGER")
    Equipped(h, 12, 202, 590, "INVTYPE_FINGER")
    h:Start()
    check(not head.ItemLevelText:IsShown(), "Native level replaces EUI label without SIL")
    check(h:Overlay(head).font.calls.SetText[1] == 600, "Native item level rendered")
    check(not h:Overlay(head).textureRegion:IsShown(), "Equal level is not an upgrade")
    check(h:Overlay(ring).textureRegion:IsShown(), "Ring compares against lower equipped ring")
    check(junk.ItemLevelText:IsShown() and #junk.children == 0, "Non-equipment keeps EUI display")
    h.items[100].level = 610
    h.items[100].minimum = 90
    h.slots["0:1"].link = "item:100:b"
    h:Draw("BAG_UPDATE_DELAYED")
    check(h:Overlay(head).textureRegion:IsShown(), "New gear updates on bag event")
    check(h:Overlay(head).textureRegion.calls.SetVertexColor[2] == 0, "Above-level upgrade is red")
    Equipped(h, 1, 203, 650, "INVTYPE_HEAD")
    h:Draw("PLAYER_EQUIPMENT_CHANGED")
    check(not h:Overlay(head).textureRegion:IsShown(), "Equipment change refreshes comparison")
    h.settings.enabled = false
    h:Apply()
    check(head.ItemLevelText:IsShown() and not h:Overlay(head):IsShown(), "Disable restores owned native visibility")
    check(next(h.event.events) == nil, "Disable releases subscriptions")
end

local function LowQualitySuggestions()
    for _, quality in ipairs({0, 1}) do
        local h = Harness()
        local root = h:Root("EUI_MainBagFrame")
        local head = h:Button(root, 0, 1, 800)
        local ring = h:Button(root, 0, 2, 801)
        local trinket = h:Button(root, 0, 3, 802)
        local two = h:Button(root, 0, 4, 803)
        local off = h:Button(root, 0, 5, 804)
        h.items[801].equipLoc = "INVTYPE_FINGER"
        h.items[802].equipLoc = "INVTYPE_TRINKET"
        h.items[803].equipLoc = "INVTYPE_2HWEAPON"
        h.items[804].equipLoc = "INVTYPE_SHIELD"
        for slot = 1, 5 do h.slots["0:" .. slot].quality = quality end
        Equipped(h, 1, 900, 100, "INVTYPE_HEAD")
        Equipped(h, 11, 901, 100, "INVTYPE_FINGER")
        Equipped(h, 12, 902, 200, "INVTYPE_FINGER")
        Equipped(h, 13, 903, 100, "INVTYPE_TRINKET")
        Equipped(h, 14, 904, 200, "INVTYPE_TRINKET")
        Equipped(h, 16, 905, 100, "INVTYPE_WEAPONMAINHAND")
        h:Start()
        for _, button in ipairs({head, ring, trinket, two}) do
            check(not h:Overlay(button).textureRegion:IsShown(), "Grey/white gear cannot replace occupied slots")
            check(h:Overlay(button).font:IsShown(), "Quality gate does not hide item levels")
        end
        check(h:Overlay(off).textureRegion:IsShown(), "Grey/white offhand can fill a free slot")
        h.equipped[1], h.equipped[12], h.equipped[14], h.equipped[16] = nil, nil, nil, nil
        h:Draw("PLAYER_EQUIPMENT_CHANGED")
        for _, button in ipairs({head, ring, trinket, two}) do
            check(h:Overlay(button).textureRegion:IsShown(), "Grey/white gear can fill empty matching slots")
        end
        Equipped(h, 16, 906, 100, "INVTYPE_2HWEAPON")
        h:Draw("PLAYER_EQUIPMENT_CHANGED")
        check(not h:Overlay(off).textureRegion:IsShown(), "Two-hander still blocks an apparently empty offhand")
        Equipped(h, 1, 900, 100, "INVTYPE_HEAD")
        h.items[900].missing = true
        h:Draw("PLAYER_EQUIPMENT_CHANGED")
        check(not h:Overlay(head).textureRegion:IsShown(), "Unloaded equipped gear is not an empty slot")
        h.items[900].missing = false
        h.slots["0:1"].quality = 2
        h:Draw("BAG_UPDATE_DELAYED")
        check(h:Overlay(head).textureRegion:IsShown(), "Green gear still compares item level against equipped gear")
    end
end

local function RefreshBudget()
    local h = Harness()
    local root = h:Root("EUI_MainBagFrame", "RefreshInventory")
    local button = h:Button(root, 0, 1, 300)
    h:Start()
    local levels, containers = h.levelQueries, h.containerQueries
    for _ = 1, 100 do
        button:SetID(button:GetID())
        button:SetParent(button:GetParent())
        button:GetParent():SetID(0)
        button:SetItemButtonTexture("same")
        button:SetItemButtonQuality()
        h.env.SetItemButtonQuality(button)
        button.ItemLevelText:Show()
        root:RefreshInventory()
    end
    check(#h.timers == 0 and h.levelQueries == levels and h.containerQueries == containers,
        "Repeated native setters and refreshes perform no item queries or scheduled work")
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.levelQueries == levels and #h.loads == 0, "Unchanged bag event reuses comparison")
    check(not h.event.events.GET_ITEM_INFO_RECEIVED and not h.event.events.ITEM_DATA_LOAD_RESULT,
        "Loaded display has no item-data subscriptions")
    h.event:Fire("GET_ITEM_INFO_RECEIVED", 300, true)
    check(#h.timers == 0, "Our own loaded-item notifications cannot restart comparisons")
    h.items[301] = {level = 620}
    h.slots["0:1"] = {itemID = 301, quality = 4, link = "item:301:a"}
    h:Draw("BAG_UPDATE_DELAYED")
    check(h:Overlay(button).font.calls.SetText[1] == 620, "Loot replacing a slot updates")
    root:Hide(); h:Draw()
    check(not h.event.events.PLAYER_EQUIPMENT_CHANGED, "Hidden bags release equipment listener")
    root:Show(); h:Draw()
    check(h:Overlay(button):IsShown(), "Opening bags refreshes display")
end

local function PendingAndRecycling()
    local h = Harness()
    local root = h:Root("EUI_MainBagFrame")
    local button = h:Button(root, 0, 1, 400)
    Equipped(h, 1, 401, 590, "INVTYPE_HEAD")
    h.items[401].missing = true
    h:Start()
    check(not h:Overlay(button).textureRegion:IsShown(), "Unknown equipped gear is not an empty slot")
    check(h.requests[401] == 1 and h.event.events.ITEM_DATA_LOAD_RESULT, "Missing equipped data requests one load")
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.requests[401] == 1, "Pending equipped lookup does not request repeatedly")
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 401, true); h:Draw()
    check(h.requests[401] == 1 and #h.timers == 0 and not h.event.events.ITEM_DATA_LOAD_RESULT,
        "Successful notification without usable data cannot start a load/refresh loop")
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.requests[401] == 2, "Later content event can retry unavailable equipped data")
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 401, false)
    check(#h.timers == 0 and not h.event.events.ITEM_DATA_LOAD_RESULT, "Failed equipped load stops until normal refresh")
    h:Draw("BAG_UPDATE_DELAYED")
    h.items[401].missing = false
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 401, true); h:Draw()
    check(h:Overlay(button).textureRegion:IsShown(), "Equipped data completion finishes comparison")
    check(not h.event.events.ITEM_DATA_LOAD_RESULT, "Resolved equipped lookup releases listener")
    h:Apply()
    h.module:ApplySettings(); h:Flush()
    local stale = assert(table.remove(h.loads, 1))
    button:SetID(2); h:Put(0, 2, 402); h.items[402].level = 650
    h:Draw(); stale()
    check(h:Overlay(button).font.calls.SetText[1] == 650 and h:Overlay(button):IsShown(), "Old load cannot clear recycled occupant")
    h.combat = true
    h.event:Fire("PLAYER_REGEN_DISABLED")
    button:SetID(3); h:Put(0, 3, 403)
    h:Draw()
    check(not h:Overlay(button):IsShown() and h.combatViolations == 0, "Combat hides owned overlays without protected changes")
    h.combat = false; h:Draw("PLAYER_REGEN_ENABLED")
    check(h:Overlay(button):IsShown(), "Deferred new occupant renders after combat")
    h.combat = true; h.settings.enabled = false; h.module:ApplySettings()
    h.combat = false; h.event:Fire("PLAYER_REGEN_ENABLED")
    check(button.ItemLevelText:IsShown() and next(h.event.events) == nil, "Combat disable restores native and releases listeners")
end

local function HiddenEquippedFailure()
    local h = Harness()
    local root = h:Root("EUI_MainBagFrame")
    local button = h:Button(root, 0, 1, 410)
    Equipped(h, 1, 411, 590, "INVTYPE_HEAD")
    h.items[411].missing = true
    h:Start()
    check(h.requests[411] == 1, "Equipped lookup starts once")
    root:Hide()
    check(not h.event.events.ITEM_DATA_LOAD_RESULT and not h.event.events.GET_ITEM_INFO_RECEIVED,
        "Hidden bags release item-data listeners")
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 411, false)
    root:Show(); h:Draw()
    check(h.requests[411] == 2, "Reopening retries equipped requests whose completion could be missed")
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.requests[411] == 2, "Visible pending requests remain deduplicated")
    h.items[411].missing = false
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 411, true); h:Draw()
    check(h:Overlay(button).textureRegion:IsShown(), "Retried equipped data restores upgrade comparison")
    local queries = h.levelQueries
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 411, true); h:Draw()
    check(h.levelQueries == queries and #h.timers == 0, "Duplicate completion cannot restart resolved comparisons")
    root:Hide()
    Equipped(h, 1, 412, 650, "INVTYPE_HEAD")
    h.items[412].missing = true
    root:Show(); h:Draw()
    queries = h.levelQueries
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 411, true); h:Draw()
    check(h.levelQueries == queries and not h:Overlay(button).textureRegion:IsShown(),
        "Late completion for old equipment cannot repaint a newer comparison")
    h.items[412].missing = false
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 412, true); h:Draw()
    check(not h:Overlay(button).textureRegion:IsShown(), "Current equipped result remains authoritative")

    local visible = Harness()
    local bags = visible:Root("EUI_MainBagFrame")
    local bank = visible:Root("EUI_BankFrame")
    visible:Button(bags, 0, 1, 413)
    visible:Button(bank, -1, 1, 414)
    Equipped(visible, 1, 415, 590, "INVTYPE_HEAD")
    visible.items[415].missing = true
    visible:Start()
    bags:Hide(); bags:Show(); visible:Draw()
    check(visible.requests[415] == 1 and visible.event.events.ITEM_DATA_LOAD_RESULT,
        "Another visible scope keeps its pending request and completion listener")
end

local function PlayerLevelChanges()
    local h = Harness()
    h.settings.reagent, h.settings.bank = false, false
    local root = h:Root("EUI_MainBagFrame")
    local button = h:Button(root, 0, 1, 420)
    h.items[420].minimum = 81
    h:Start()
    local arrow = h:Overlay(button).textureRegion
    check(arrow.calls.SetVertexColor[2] == 0, "Unavailable upgrade starts red")
    h.env.UnitLevel = function() return 81 end
    h:Draw("PLAYER_LEVEL_UP")
    check(arrow.calls.SetVertexColor[2] == 1, "Reaching the required level recolors cached upgrades")
    local queries = h.levelQueries
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.levelQueries == queries, "Level-up refresh preserves subsequent cached deduplication")
    h.items[420].minimum = 82
    h:Apply()
    h.combat = true
    h.env.UnitLevel = function() return 82 end
    h:Draw("PLAYER_LEVEL_UP")
    check(h.combatViolations == 0 and not arrow:IsShown(), "Combat level-up defers protected work and hides stale color")
    h.combat = false; h:Draw("PLAYER_REGEN_ENABLED")
    check(arrow:IsShown() and arrow.calls.SetVertexColor[2] == 1, "Combat-end renders the usable upgrade")
    root:Hide(); h:Draw()
    check(not h.event.events.PLAYER_LEVEL_UP, "Hidden scopes release the level-up listener")
    root:Show(); h:Draw()
    check(h.event.events.PLAYER_LEVEL_UP, "Visible scope restores the level-up listener")
    h.settings.enabled = false; h:Apply()
    check(next(h.event.events) == nil, "Disabled feature releases all subscriptions")
end

local function WeaponsAndScopes()
    local h = Harness()
    local root = h:Root("EUI_MainBagFrame")
    local two = h:Button(root, 0, 1, 500)
    local off = h:Button(root, 0, 2, 501)
    h.items[500].equipLoc = "INVTYPE_2HWEAPON"
    h.items[501].equipLoc = "INVTYPE_SHIELD"
    Equipped(h, 16, 502, 590, "INVTYPE_WEAPONMAINHAND")
    Equipped(h, 17, 503, 620, "INVTYPE_SHIELD")
    h:Start()
    check(not h:Overlay(two).textureRegion:IsShown(), "Two-handed comparison must beat both weapon slots")
    Equipped(h, 16, 504, 580, "INVTYPE_2HWEAPON"); h.equipped[17] = nil
    h:Draw("PLAYER_EQUIPMENT_CHANGED")
    check(h:Overlay(two).textureRegion:IsShown(), "Two-handed upgrade beats equipped two-hander")
    check(not h:Overlay(off).textureRegion:IsShown(), "Shield is not upgrade over blocked offhand")
    local bank = h:Root("EUI_BankFrame")
    local item = h:Button(bank, 17, 1, 505)
    h:Draw("BANKFRAME_OPENED")
    check(not item.ItemLevelText:IsShown(), "Accessible bank items display native levels")
    h.settings.bank = false; h:Apply()
    check(item.ItemLevelText:IsShown(), "Disabled scope restores native")
    h.settings.bank = true; h.bankAccess[2] = false; h:Apply()
    check(item.ItemLevelText:IsShown(), "Inaccessible bank is left alone")
end

local function CombatSuppression()
    local h = Harness()
    h:Start()
    local root = h:Root("EUI_MainBagFrame", "RefreshInventory")
    local a = h:Button(root, 0, 1, 300)
    h:Draw("BAG_UPDATE_DELAYED")
    local overlay = h:Overlay(a)
    check(overlay.font:IsShown() and overlay.textureRegion:IsShown(), "Both old visuals must be present before recycling")
    h.combat = true
    a:SetID(2)
    h:Put(0, 2, 301)
    h.items[301].level = 620
    check(not overlay:IsShown() and not overlay.font:IsShown() and not overlay.textureRegion:IsShown(),
        "Combat recycle must immediately suppress addon-owned level and upgrade")
    check(not a.ItemLevelText:IsShown(), "Protected native restoration must remain deferred")
    h:Draw()
    check(not overlay:IsShown(), "Stale callbacks must not repaint after combat invalidation")
    check(h.ownCombatMutations > 0 and h.combatViolations == 0, "Only nonprotected own visuals may mutate in combat")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(overlay:IsShown() and overlay.font.calls.SetText[1] == 620, "Regen must render only the new occupant")
    overlay.protected = true
    h.combat = true
    h.slots["0:2"].link = "item:301:b"
    h.event:Fire("BAG_UPDATE_DELAYED"); h:Flush()
    check(overlay:IsShown() and not overlay.font:IsShown() and not overlay.textureRegion:IsShown(),
        "Protected own frame must fall back to independently mutable owned regions")
    check(h.combatViolations == 0, "Protected own frame Hide must not be attempted")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    overlay.font.protected, overlay.textureRegion.protected = true, true
    h.combat = true
    h.settings.enabled = false
    h.module:ApplySettings()
    check(overlay:IsShown() and overlay.font:IsShown() and overlay.textureRegion:IsShown(),
        "Actually protected owned visuals must wait for regen, not attempt forbidden suppression")
    check(h.combatViolations == 0 and h.module:GetStatus():find("pending combat"), "Protected fallback must keep cleanup registered")
    h.combat = false
    h.event:Fire("PLAYER_REGEN_ENABLED")
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Protected fallback must complete at regen even while disabled")

    for _, failure in ipairs({"protectionError", "changeError", "cannotChange", "missing"}) do
        local guarded = Harness()
        guarded:Start()
        local main = guarded:Root("EUI_MainBagFrame")
        local button = guarded:Button(main, 0, 1, 302)
        guarded:Draw("BAG_UPDATE_DELAYED")
        local own = guarded:Overlay(button)
        for _, region in ipairs({own, own.font, own.textureRegion}) do
            if failure == "missing" then region.IsProtected, region.CanChangeProtectedState = false, false
            else region[failure] = true end
        end
        guarded.combat = true
        button:SetID(2)
        check(own:IsShown() and own.font:IsShown() and own.textureRegion:IsShown(),
            "Unknown or denied protection state must defer: " .. failure)
        check(guarded.combatViolations == 0 and guarded.ownCombatMutations == 0,
            "Failed protection guards must not attempt visual operations: " .. failure)
        guarded.combat = false
        guarded.settings.enabled = false
        guarded.module:ApplySettings()
        check(not own:IsShown() and button.ItemLevelText:IsShown(), "Guard fallback must clean up outside combat: " .. failure)
    end
    for _, missing in ipairs({"IsProtected", "CanChangeProtectedState"}) do
        local guarded = Harness()
        guarded:Start()
        local main = guarded:Root("EUI_MainBagFrame")
        local button = guarded:Button(main, 0, 1, 303)
        guarded:Draw("BAG_UPDATE_DELAYED")
        local own = guarded:Overlay(button)
        for _, region in ipairs({own, own.font, own.textureRegion}) do region[missing] = false end
        guarded.combat = true
        button:SetID(2)
        check(not own:IsShown() and not own.font:IsShown() and not own.textureRegion:IsShown(),
            "One available affirmative safety query must allow owned suppression: missing " .. missing)
        check(guarded.combatViolations == 0 and not button.ItemLevelText:IsShown(),
            "Single-query support must still leave native restoration deferred: missing " .. missing)
    end
end

for _, suite in ipairs({NativeComparison, LowQualitySuggestions, RefreshBudget, PendingAndRecycling, HiddenEquippedFailure, PlayerLevelChanges, WeaponsAndScopes, CombatSuppression}) do suite() end
print("PASS: Bag item levels (" .. assertions .. " assertions)")

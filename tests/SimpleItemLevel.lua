-- Run from the EUI root: lua CalmEUITweaks/tests/SimpleItemLevel.lua
local unpack = table.unpack or unpack
local production = "CalmEUITweaks/compatability/SimpleItemLevel.lua"
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end

local function Harness()
    local h = {
        combat = false, combatViolations = 0, ownCombatMutations = 0, timers = {}, loads = {}, upgrades = {},
        frames = {}, slots = {}, items = {}, hookCounts = {},
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
            error("Bridge attempted protected mutation or creation in combat")
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
    -- Test-driven recycling represents native/secure pool updates, not bridge actions.
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
            if h.failContainer then error("Simulated container failure") end
            return h.slots[Key(bag, slot)]
        end,
        GetContainerItemLink = function(bag, slot)
            local item = h.slots[Key(bag, slot)]
            return item and item.link
        end,
    }
    env.C_Item = {
        GetItemInfoInstant = function(id)
            local item = h.items[id] or {}
            return id, nil, nil, nil, nil, item.class or 4, item.subclass or 0
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
    h.db = {bags = true, position = "BOTTOMRIGHT", positionup = "TOPLEFT", font = "Large", scaleup = 1.4}
    env.SimpleItemLevelDB = h.db
    h.api = {
        ItemLevel = function(item)
            if h.failLevel then error("Simulated SIL failure") end
            return h.items[item:GetItemID()].level
        end,
        ItemIsUpgradeAsync = function(_, fn) table.insert(h.upgrades, fn) end,
    }
    env.SimpleItemLevel = {API = h.api}
    env.UIDropDownMenu_SetSelectedValue = function(dropdown, value) dropdown.selectedValue = value end
    env.SlashCmdList = {SIMPLEITEMLEVEL = function(key)
        if key == "quality 5" then h.db.quality = 5
        elseif type(h.db[key]) == "boolean" then h.db[key] = not h.db[key] end
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
    function h:Upgrade(value)
        local batch = self.upgrades
        self.upgrades = {}
        for _, fn in ipairs(batch) do fn(value) end
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
    function h:Config()
        -- Mirror only upstream config.lua's exposed hierarchy/application methods.
        local general, appearance = env.CreateFrame("Frame"), env.CreateFrame("Frame")
        self.checks, self.dropdowns = {}, {}
        for _, key in ipairs({"bags", "equipment", "itemlevel", "upgrades", "color"}) do
            local control = env.CreateFrame("Frame", nil, general)
            control.Check = env.CreateFrame("CheckButton", nil, control)
            control.Check.key = key
            control.Check.SetValue = function(_, value) self.db[key] = value end
            self.checks[key] = control.Check
        end
        for _, key in ipairs({"quality", "font", "position", "positionup"}) do
            local control = env.CreateFrame("Frame", nil, key == "quality" and general or appearance)
            local dropdown = env.CreateFrame("Frame", "SimpleItemLevelOptions" .. key .. "Dropdown", control)
            self.dropdowns[key] = dropdown
        end
        local scale = env.CreateFrame("Frame", nil, appearance)
        scale.Slider = env.CreateFrame("Slider", nil, scale)
        scale.Slider:SetScript("OnValueChanged", function(_, value) self.db.scaleup = value end)
        self.slider = scale.Slider
    end
    function h:Select(key, value)
        self.db[key] = value
        env.UIDropDownMenu_SetSelectedValue(self.dropdowns[key], value)
    end
    function h:Start()
        self.module:Initialize()
        self.event = self.frames[1]
        self.ns.ready = true
        self:Apply()
    end
    return h
end

local function LifecycleAndDisplay()
    local h = Harness()
    h.module:Initialize()
    h.event = h.frames[1]
    h.module:Initialize()
    check(#h.frames == 1, "Initialize must be idempotent")
    h.module:ApplySettings()
    check(h.module:GetStatus() == "Waiting for settings", "ApplySettings must wait for ns.ready")
    h.ns.ready = true
    h:Apply()
    check(h.module:GetStatus():find("Waiting for EllesmereUI"), "Missing lazy frames must remain retryable")
    local main = h:Root("EUI_MainBagFrame")
    local a = h:Button(main, 0, 1, 100)
    h.module:OnAddonLoaded("EllesmereUIBags")
    h:Flush()
    check(a.ItemLevelText:IsShown(), "Native text must remain while data loads")
    h:LoadItems()
    local overlay = h:Overlay(a)
    check(overlay and overlay:IsShown() and not a.ItemLevelText:IsShown(), "Valid level must own replacement")
    check(overlay.font.calls.SetText[1] == 600, "SIL level must render")
    check(overlay.font.calls.SetPoint[1] == "BOTTOMRIGHT", "SIL text position must apply")
    check(overlay.font.calls.SetFontObject[1] == h.env.GameFontNormalLargeOutline, "SIL font must apply")
    h:Upgrade(true)
    check(overlay.textureRegion:IsShown() and overlay.textureRegion.calls.SetScale[1] == 1.4, "Async upgrade and scale must apply")
    a.ItemLevelText:Show()
    check(not a.ItemLevelText:IsShown(), "Active ownership must suppress native Show")
    h.settings.enabled = false
    h:Apply()
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Disable must restore captured native visibility")
    a.ItemLevelText:Hide()
    h.settings.enabled = true
    h:Apply()
    h.settings.enabled = false
    h:Apply()
    check(not a.ItemLevelText:IsShown(), "Originally hidden native text must not be blindly shown")
    a.ItemLevelText:Show()
    h.settings.enabled = true
    h.module:ApplySettings()
    h:Flush()
    local obsolete = assert(h.loads[1])
    h.loads = {}
    a:SetID(2)
    h:Put(0, 2, 101)
    h.items[101].level = 610
    h:Draw()
    obsolete()
    check(overlay.font.calls.SetText[1] == 610 and overlay:IsShown(), "Old load must not clear a recycled occupant")
    h.slots["0:2"].link = "item:101:b"
    h:Upgrade(true)
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Changed link must invalidate async upgrades")
    h:Draw()
    h.db.equipment = false
    h:Upgrade(true)
    h:Draw()
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Current equipment filter must reject stale callbacks")
    h.db.equipment = true
    h.db.quality = 5
    h:Draw("BAG_UPDATE_DELAYED")
    check(a.ItemLevelText:IsShown(), "Quality filter must retain native fallback")
    h.db.quality = nil
    h.items[101].level = 0
    h:Draw("BAG_UPDATE_DELAYED")
    check(a.ItemLevelText:IsShown(), "Missing level must retain native fallback")
    h.items[101].level = 610
    h.failLevel = true
    h:Draw("BAG_UPDATE_DELAYED")
    check(a.ItemLevelText:IsShown(), "Failed SIL API must retain native fallback")
    h.failLevel = false
    h:Draw("BAG_UPDATE_DELAYED")
    check(not a.ItemLevelText:IsShown(), "SIL recovery must reclaim replacement")
    h.db.bags = false
    a.ItemLevelText:Show()
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Ownership must revalidate SIL settings on native Show")
    h:Draw()
    check(h.module:GetStatus():find("SIL bag display is disabled"), "Disabled SIL bags must report native fallback")
    h.db.bags = true
    h:Apply()
    h:Draw("BAG_UPDATE_DELAYED")
    main.RefreshInventory = function() end
    h:Draw("BAG_UPDATE_DELAYED")
    local hookCount = h.hookCounts[main].RefreshInventory
    h:Apply()
    check(h.hookCounts[main].RefreshInventory == hookCount, "Unchanged refresh method must not be hooked twice")
    main.RefreshInventory = function() end
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.hookCounts[main].RefreshInventory == hookCount + 1, "Replaced refresh method must be rediscovered")
    local late = h:Button(main, 0, 3, 104)
    main:RefreshInventory()
    h:Draw()
    check(not late.ItemLevelText:IsShown(), "Refresh posthook must discover new pooled buttons")
    a:Hide()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Hidden buttons must clear owned display")
    a:Show()
    h:Draw()
    check(overlay:IsShown(), "Button OnShow must recover display")
    local api = h.env.SimpleItemLevel
    h.env.SimpleItemLevel = nil
    h:Draw("BAG_UPDATE_DELAYED")
    check(a.ItemLevelText:IsShown() and h.module:GetStatus():find("Waiting for SimpleItemLevel"), "Missing SIL dependency must restore native")
    h.env.SimpleItemLevel = api
    h.module:OnAddonLoaded("SimpleItemLevel")
    h:Draw()
    check(not a.ItemLevelText:IsShown(), "Late SIL dependency must recover")
    check(a.ItemLevelText.calls.SetText[1] == "native", "Bridge must never rewrite native text")
    check(h.db.position == "BOTTOMRIGHT" and h.db.scaleup == 1.4 and h.db.itemlevel == nil,
        "Bridge must not inject or force SIL settings")
    check(h.combatViolations == 0, "Lifecycle suite must not attempt combat mutations")
end

local function ScopesBankAndCombat()
    local h = Harness()
    h:Start()
    local main = h:Root("EUI_MainBagFrame", "RefreshInventory")
    local a = h:Button(main, 0, 1, 200)
    h:Draw("BAG_UPDATE_DELAYED")
    local overlay = h:Overlay(a)
    local reagent = h:Root("EUI_ReagentBagFrame", "RefreshInventory")
    local r = h:Button(reagent, 5, 1, 201)
    local bank = h:Root("EUI_BankFrame", "RefreshBank")
    local b = h:Button(bank, 17, 1, 202)
    local character = h:Button(bank, 6, 1, 203)
    h.bankAccess[0] = false
    h:Draw("BANKFRAME_OPENED")
    check(not r.ItemLevelText:IsShown(), "Late reagent frame must be discovered independently")
    check(not b.ItemLevelText:IsShown(), "Five-tab warband bank must use Account access, not nonexistent tab six")
    check(character.ItemLevelText:IsShown(), "Inaccessible character bank must retain native display")
    h.bankAccess[0], h.bankAccess[2] = true, false
    h:Draw("BAG_UPDATE_DELAYED")
    check(b.ItemLevelText:IsShown() and not character.ItemLevelText:IsShown(), "Bank usability must distinguish character and warband")
    h.bankAccess[2] = true
    h:Draw("BAG_UPDATE_DELAYED")
    h.settings.reagent = false
    h:Apply()
    check(r.ItemLevelText:IsShown() and not a.ItemLevelText:IsShown() and not b.ItemLevelText:IsShown(), "Reagent scope must not affect main or bank")
    h.settings.inventory = false
    h:Apply()
    check(a.ItemLevelText:IsShown() and not b.ItemLevelText:IsShown(), "Inventory scope must not affect bank")
    h.settings.bank = false
    h:Apply()
    check(b.ItemLevelText:IsShown() and character.ItemLevelText:IsShown(), "Bank scope must clear both bank categories")
    h.settings.inventory, h.settings.reagent, h.settings.bank = true, true, true
    h:Apply()
    h.event:Fire("BANKFRAME_CLOSED")
    h:Draw()
    check(b.ItemLevelText:IsShown() and character.ItemLevelText:IsShown(), "Closed bank must not receive async display")
    h:Draw("BANKFRAME_OPENED")
    bank:Hide()
    check(b.ItemLevelText:IsShown(), "Hidden bank must restore native visibility")
    bank:Show()
    h:Draw()
    check(not b.ItemLevelText:IsShown(), "Bank OnShow must recover bridge")
    h.env.SimpleItemLevelDB = nil
    h:Upgrade(true)
    check(a.ItemLevelText:IsShown(), "Removed SIL database must invalidate pending upgrade")
    h.env.SimpleItemLevelDB = h.db
    h:Draw()
    local lazy = h:Button(main, 0, 4, 204)
    h.combat = true
    local frameCount = #h.frames
    h.event:Fire("PLAYER_REGEN_DISABLED")
    h:Draw("BAG_UPDATE_DELAYED")
    h:Upgrade(true)
    check(#h.frames == frameCount and #lazy.children == 0, "Combat must defer lazy overlay creation")
    check(h.module:GetStatus():find("Deferred"), "Combat deferral must report status")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(not lazy.ItemLevelText:IsShown(), "Combat end must retry lazy creation")
    -- The mock records forbidden attempts even when production's pcall catches them.
    h.module:ApplySettings()
    h:Flush()
    h.combat = true
    h:LoadItems()
    check(a.ItemLevelText:IsShown(), "Item completion in combat must defer painting")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(not a.ItemLevelText:IsShown(), "Deferred item result must recover after combat")
    h.combat = true
    a:SetID(2)
    h:Put(0, 2, 205)
    h:Upgrade(true)
    h:Draw()
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(overlay.font.calls.SetText[1] == 600 and not a.ItemLevelText:IsShown(), "Combat recycling must retry current occupant")
    h.module:ApplySettings()
    h:Flush()
    local staleLoad = assert(table.remove(h.loads, 1))
    h:LoadItems()
    h.combat = true
    h.settings.enabled = false
    h.module:ApplySettings()
    check(h.module:GetStatus():find("pending combat"), "Combat disable must retain deferred cleanup lifecycle")
    staleLoad()
    h:Upgrade(true)
    h.combat = false
    h.event:Fire("PLAYER_REGEN_ENABLED")
    check(a.ItemLevelText:IsShown() and lazy.ItemLevelText:IsShown() and not overlay:IsShown(),
        "Combat disable cleanup must restore native display")
    check(h.module:GetStatus() == "Disabled" and next(h.event.events) == nil, "Disabled cleanup must unregister module events")
    h:LoadItems()
    h:Upgrade(true)
    h:Flush()
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Disabled-generation callbacks must not reclaim display")
    h.settings.enabled = true
    h:Apply()
    h.db.bags = false
    h:Draw("BAG_UPDATE_DELAYED")
    check(a.ItemLevelText:IsShown() and r.ItemLevelText:IsShown() and b.ItemLevelText:IsShown(), "Disabled SIL bags must restore every scope")
    check(h.combatViolations == 0, "No creation or protected visual mutation may occur in combat")
end

local function CombatSuppression()
    local h = Harness()
    h:Start()
    local root = h:Root("EUI_MainBagFrame", "RefreshInventory")
    local a = h:Button(root, 0, 1, 300)
    h:Draw("BAG_UPDATE_DELAYED")
    h:Upgrade(true)
    local overlay = h:Overlay(a)
    check(overlay.font:IsShown() and overlay.textureRegion:IsShown(), "Both old visuals must be present before recycling")
    h.combat = true
    a:SetID(2)
    h:Put(0, 2, 301)
    h.items[301].level = 620
    check(not overlay:IsShown() and not overlay.font:IsShown() and not overlay.textureRegion:IsShown(),
        "Combat recycle must immediately suppress addon-owned level and upgrade")
    check(not a.ItemLevelText:IsShown(), "Protected native restoration must remain deferred")
    h:Upgrade(true)
    h:Draw()
    check(not overlay:IsShown(), "Stale callbacks must not repaint after combat invalidation")
    check(h.ownCombatMutations > 0 and h.combatViolations == 0, "Only nonprotected own visuals may mutate in combat")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(overlay:IsShown() and overlay.font.calls.SetText[1] == 620, "Regen must render only the new occupant")
    h:Upgrade(true)
    overlay.protected = true
    h.combat = true
    a:SetItemButtonTexture("new occupant")
    check(overlay:IsShown() and not overlay.font:IsShown() and not overlay.textureRegion:IsShown(),
        "Protected own frame must fall back to independently mutable owned regions")
    check(h.combatViolations == 0, "Protected own frame Hide must not be attempted")
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    h:Upgrade(true)
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
        guarded:Upgrade(true)
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
        guarded:Upgrade(true)
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

local function IdleSettings()
    local h = Harness()
    h:Start()
    local root = h:Root("EUI_MainBagFrame")
    local a = h:Button(root, 0, 1, 400)
    h:Config()
    h.module:OnAddonLoaded("SimpleItemLevel")
    h:Draw()
    h:Upgrade(true)
    local overlay = h:Overlay(a)
    check(overlay:IsShown(), "Late SIL settings controls must be discovered")
    local hooks = h.hookCounts[h.checks.bags].SetValue
    h:Apply()
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.hookCounts[h.checks.bags].SetValue == hooks and #h.slider.scripts.OnValueChanged == 2,
        "Checkbox and slider application hooks must be installed once")
    h.checks.bags:SetValue(false)
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Idle bags-off must immediately release ownership")
    h:Draw()
    h:Upgrade(true)
    check(not overlay:IsShown() and h.module:GetStatus():find("SIL bag display is disabled"),
        "Idle bags-off must invalidate old callbacks without a native Show or bag event")
    h.checks.bags:SetValue(true)
    h:Draw()
    check(overlay:IsShown() and not a.ItemLevelText:IsShown(), "Idle bags-on must directly refresh")
    h.checks.equipment:SetValue(false)
    h:Draw()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Idle equipment filter must restore native display")
    h.checks.equipment:SetValue(true)
    h:Draw()
    h:Select("quality", 5)
    h:Draw()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Idle quality dropdown must apply filter")
    h:Select("quality", 1)
    h:Select("font", "NumberNormal")
    h:Select("position", "CENTER")
    h:Select("positionup", "BOTTOMLEFT")
    h.slider:RunScript("OnValueChanged", 2.2)
    h.checks.color:SetValue(false)
    check(#h.timers == 1, "Several idle settings edits must coalesce into one refresh")
    h:Draw()
    h:Upgrade(true)
    check(overlay.font.calls.SetFontObject[1] == h.env.NumberFontNormal
        and overlay.font.calls.SetPoint[1] == "CENTER", "Idle appearance dropdowns must restyle level")
    check(overlay.textureRegion.calls.SetPoint[1] == "BOTTOMLEFT" and overlay.textureRegion.calls.SetScale[1] == 2.2,
        "Idle upgrade position and slider must restyle arrow")
    check(h.lastColorQuality == 1, "Idle color checkbox must refresh text color")
    h.checks.itemlevel:SetValue(false)
    h:Draw()
    h:Upgrade(true)
    check(a.ItemLevelText:IsShown() and not overlay.font:IsShown() and overlay.textureRegion:IsShown(),
        "Idle level-off must release native text while keeping enabled upgrade arrow")
    h.checks.upgrades:SetValue(false)
    h:Draw()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "Idle level-and-upgrade-off must hide all own display")
    h.checks.itemlevel:SetValue(true)
    h:Draw()
    h.env.SlashCmdList.SIMPLEITEMLEVEL("bags")
    h:Draw()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "SIL slash changes must refresh without UI callback")
    h.env.SlashCmdList.SIMPLEITEMLEVEL("bags")
    h:Draw()
    check(overlay:IsShown(), "SIL slash reenable must refresh idle bridge")
    h.env.SlashCmdList.SIMPLEITEMLEVEL("quality 5")
    h:Draw()
    check(not overlay:IsShown() and a.ItemLevelText:IsShown(), "SIL slash quality must apply idle filter")
    local unrelated = h.env.CreateFrame("Frame")
    h.env.UIDropDownMenu_SetSelectedValue(unrelated, 2)
    h.env.UIDropDownMenu_SetSelectedValue(h.dropdowns.quality, 5)
    check(#h.timers == 0, "Unrelated dropdowns and unchanged settings must not schedule polling")
    h:Select("quality", 1)
    h:Draw()
    h.combat = true
    h.checks.bags:SetValue(false)
    check(not overlay:IsShown() and not a.ItemLevelText:IsShown(), "Combat settings change must suppress own display but defer native restore")
    h:Draw()
    h.combat = false
    h:Draw("PLAYER_REGEN_ENABLED")
    check(a.ItemLevelText:IsShown() and not overlay:IsShown(), "Combat settings restoration must finish at regen")
    h.settings.enabled = false
    h:Apply()
    h.checks.bags:SetValue(true)
    check(#h.timers == 0, "Installed SIL hooks must remain inert when bridge is disabled")
    check(h.combatViolations == 0, "Settings hooks must never mutate protected objects in combat")
end

local function ErrorStatus()
    local h = Harness()
    h:Start()
    local root = h:Root("EUI_MainBagFrame")
    local a = h:Button(root, 0, 1, 500)
    h:Draw("BAG_UPDATE_DELAYED")
    h.failContainer = true
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.module:GetStatus():find("bridge error") and a.ItemLevelText:IsShown(),
        "Synchronous scan error must not be masked by Active status")
    h.failContainer = false
    h.immediateLoads, h.failLevel = true, true
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.module:GetStatus():find("result unavailable") and a.ItemLevelText:IsShown(),
        "Immediate item completion error must not be masked by Active status")
    h.failLevel = false
    h:Draw("BAG_UPDATE_DELAYED")
    check(h.module:GetStatus():find("Active") and not a.ItemLevelText:IsShown(), "A healthy refresh must recover error status")
end

local function RefreshBudget()
    local h = Harness()
    h:Start()
    local main = h:Root("EUI_MainBagFrame", "RefreshInventory")
    local button = h:Button(main, 0, 1, 700)
    h.module:OnAddonLoaded("EllesmereUIBags"); h:Draw(); h:Upgrade(false)
    main:RefreshInventory(); h:Flush()
    check(#h.loads == 0 and #h.upgrades == 0, "Unchanged bag refresh must not reload items or repeat upgrade queries")
    h:Draw("BAG_UPDATE_DELAYED")
    check(#h.upgrades == 0, "Delayed bag events reuse unchanged loaded item state")
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 999999, true)
    check(#h.timers == 0, "Unrelated item-data completion queues no refresh")
    h.items[700].level = 620
    h.event:Fire("ITEM_DATA_LOAD_RESULT", 700, true); h:Draw()
    check(h:Overlay(button).font.calls.SetText[1] == 620, "Tracked item-data completion refreshes its changed result")
    local reagent = h:Root("EUI_ReagentBagFrame", "RefreshInventory")
    local bank = h:Root("EUI_BankFrame", "RefreshBank")
    reagent.shown, bank.shown = false, false
    main:Hide(); h:Draw()
    local scans = 0
    for _, root in ipairs({main, reagent, bank}) do
        local original = root.GetChildren
        root.GetChildren = function(self) scans = scans + 1; return original(self) end
    end
    h:Draw("BANKFRAME_OPENED")
    check(scans == 0, "Hidden inventory, reagent and bank roots are never traversed")
    h.settings.inventory, h.settings.reagent, h.settings.bank = false, false, false
    h:Apply()
    check(next(h.event.events) == nil, "Disabling all scopes releases every bridge subscription")
    h.settings.inventory = true
    h.env.SimpleItemLevel = nil
    h:Apply()
    check(next(h.event.events) == nil, "Missing optional dependency has no bag, bank or item subscriptions")
    main:Show(); h:Draw()
    check(button.ItemLevelText:IsShown(), "Missing dependency retains native labels")
end

local suites = {
    {name = "Refresh budget and subscriptions", run = RefreshBudget},
    {name = "Lifecycle and display", run = LifecycleAndDisplay},
    {name = "Scopes, bank and combat", run = ScopesBankAndCombat},
    {name = "Combat overlay suppression", run = CombatSuppression},
    {name = "Idle SIL settings", run = IdleSettings},
    {name = "Synchronous error status", run = ErrorStatus},
}
for _, suite in ipairs(suites) do
    local before = assertions
    suite.run()
    print("PASS: " .. suite.name .. " (" .. (assertions - before) .. " assertions)")
end
print("PASS: SimpleItemLevel (" .. #suites .. " suites, " .. assertions .. " assertions)")

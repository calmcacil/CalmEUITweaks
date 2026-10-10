local _, ns = ...
local Module = {}
ns.RegisterModule("simpleItemLevel", Module)

local KEY = "simpleItemLevel"
local roots = {
    {name = "EUI_MainBagFrame", scope = "inventory"},
    {name = "EUI_ReagentBagFrame", scope = "reagent"},
    {name = "EUI_BankFrame", scope = "bank"},
}
local function WeakKeys() return setmetatable({}, {__mode = "k"}) end
local buttons, frames, parents, nativeHooks, ownedOverlays = WeakKeys(), WeakKeys(), WeakKeys(), WeakKeys(), WeakKeys()
local events = { "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_EQUIPMENT_CHANGED" }
local bankEvents = { "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
    "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }
local generation, enabled, scheduled, deferred = 0, false, false, false
local eventFrame, initialized, bankOpen
local status = "Not initialized"
local failureSerial = 0
local Schedule, Refresh, UpdateButton, UpdateEvents
local dirtyButtons, dirtyScopes, allDirty = WeakKeys(), {}, false
local pendingItems, requestedItems, equipped = {}, {}, {}
local eventMask = {}
local function RegisterEvent(event)
    if eventMask[event] then return end
    if pcall(eventFrame.RegisterEvent, eventFrame, event) then eventMask[event] = true end
end
local function ClearEvents()
    eventFrame:UnregisterAllEvents()
    eventMask = {}
end

local function SetStatus(message)
    status = message
    ns.SetStatus(KEY, message)
end

local function Failure(message)
    failureSerial = failureSerial + 1
    SetStatus(message)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Settings()
    return ns.GetSettings(KEY) or {}
end

local function API()
    return C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" and C_Item or nil
end

local function Scope(button)
    local current = button
    for _ = 1, 24 do
        for _, spec in ipairs(roots) do
            if current and current == _G[spec.name] then return spec.scope, current end
        end
        current = current and current.GetParent and current:GetParent()
        if not current then break end
    end
end

local function Location(button)
    local parent = button:GetParent()
    local bag = button.GetBankTabID and button:GetBankTabID()
    if bag == nil and button.GetBagID then bag = button:GetBagID() end
    if bag == nil and parent and parent.GetID then bag = parent:GetID() end
    local slot = button.GetContainerSlotID and button:GetContainerSlotID() or button:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" or slot < 1 then return end
    return bag, slot
end

local function Usable(button, scope, root, bag)
    local settings = Settings()
    if not (enabled and ns.ready and settings.enabled ~= false and settings[scope] ~= false) then return false end
    if not (root and root.IsVisible and root:IsVisible() and button:IsVisible()) then return false end
    if scope == "bank" then
        if bankOpen == false then return false end
        if C_Bank and C_Bank.CanUseBank and Enum and Enum.BankType then
            local indices = Enum.BagIndex or {}
            local account = false
            for name, id in pairs(indices) do
                if type(name) == "string" and name:match("^AccountBankTab_%d+$") and id == bag then
                    account = true
                    break
                end
            end
            if not indices.AccountBankTab_1 and root.IsWarbandView then account = root:IsWarbandView() end
            local bankType = account and Enum.BankType.Account or Enum.BankType.Character
            if bankType ~= nil and not C_Bank.CanUseBank(bankType) then return false end
        end
    end
    return true
end

-- Visibility belongs to EUI except while our item level replaces it.
-- Posthooks record subsequent native Show/Hide requests without changing native text.
local function RestoreNative(state)
    if not state.native then return end
    state.nativeMutation = true
    state.native:SetShown(state.nativeShown)
    state.nativeMutation = false
    state.native, state.nativeShown = nil, nil
end

local function CanSuppress(region)
    if not InCombat() then return true end
    local known = false
    for _, method in ipairs({"IsProtected", "CanChangeProtectedState"}) do
        if type(region[method]) == "function" then
            local ok, result = pcall(region[method], region)
            if not ok or type(result) ~= "boolean" then return false end
            if (method == "IsProtected" and result) or (method == "CanChangeProtectedState" and not result) then
                return false
            end
            known = true
        end
    end
    return known
end

local function SuppressOverlay(state)
    local hidden = {}
    for _, key in ipairs({"overlay", "level", "upgrade"}) do
        local region = state[key]
        if not region then hidden[key] = true
        elseif CanSuppress(region) then hidden[key] = pcall(region.Hide, region) end
    end
    -- A protected overlay can still have independently mutable regions. If neither
    -- can be hidden safely, token invalidation is immediate but visuals wait for regen.
    return hidden.overlay or (hidden.level and hidden.upgrade)
end

local function Clear(button)
    local state = buttons[button]
    if not state then return end
    state.token = state.token + 1
    state.valid = nil
    state.current = nil
    local suppressed = SuppressOverlay(state)
    if InCombat() then
        if not state.native and suppressed then return end
        deferred = true
        state.needsClear = true
        if eventFrame then RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    state.needsClear = nil
    RestoreNative(state)
end

local function OwnNative(button, state)
    local native = button.ItemLevelText
    if not native then return end
    if state.native ~= native then
        RestoreNative(state)
        state.native, state.nativeShown = native, native:IsShown()
    end
    if not nativeHooks[native] then
        nativeHooks[native] = true
        local function OnVisibility(region, shown)
            local current = buttons[button]
            if not current or current.native ~= region or current.nativeMutation then return end
            current.nativeShown = shown
            if not enabled or not current.valid then return end
            if InCombat() then
                deferred = true
                RegisterEvent("PLAYER_REGEN_ENABLED")
                return
            end
            if shown then
                current.nativeMutation = true
                region:Hide()
                current.nativeMutation = false
            end
        end
        hooksecurefunc(native, "Show", function(self) OnVisibility(self, true) end)
        hooksecurefunc(native, "Hide", function(self) OnVisibility(self, false) end)
        if native.SetShown then
            hooksecurefunc(native, "SetShown", function(self, shown) OnVisibility(self, not not shown) end)
        end
    end
    state.nativeMutation = true
    native:Hide()
    state.nativeMutation = false
end

local function SafeUpdate(button)
    local ok = pcall(UpdateButton, button)
    if not ok then
        Clear(button)
        Failure("Bag display error; using native item levels")
    end
end

local function Invalidate(button)
    if not enabled then return end
    Clear(button)
    local scope, root = Scope(button)
    local bag = Location(button)
    if scope and Usable(button, scope, root, bag) then Schedule(button) end
end

local function ButtonChanged(button)
    if not enabled then return end
    local state = buttons[button]
    if state and state.parent == button:GetParent() and state.slot == button:GetID() then return end
    Invalidate(button)
end

local function HookMethod(object, record, method, callback)
    if type(object[method]) ~= "function" or record[method] == object[method] then return end
    hooksecurefunc(object, method, callback)
    record[method] = object[method]
end

local function HookButton(button)
    local state = buttons[button]
    if not state then
        state = {token = 0, hooks = {}}
        buttons[button] = state
        button:HookScript("OnHide", Invalidate)
        button:HookScript("OnShow", function() if enabled then Schedule(button) end end)
    end
    for _, method in ipairs({"SetID", "SetParent"}) do
        HookMethod(button, state.hooks, method, ButtonChanged)
    end
    local parent = button:GetParent()
    if parent then
        local record = parents[parent]
        if not record then
            record = {buttons = WeakKeys()}
            parents[parent] = record
        end
        record.buttons[button] = true
        HookMethod(parent, record, "SetID", function(self)
            for child in pairs(record.buttons) do
                if child:GetParent() == self then
                    local bag = Location(child)
                    if buttons[child].bag ~= bag then Invalidate(child) end
                end
            end
        end)
    end
    return state
end

local function Prepare(button, state)
    if InCombat() then deferred = true; return end
    local parent = button._textOverlay or button
    if not state.overlay then
        local overlay = CreateFrame("Frame", nil, parent)
        state.overlay = overlay
        ownedOverlays[overlay] = true
        overlay:SetAllPoints(button)
        state.level = overlay:CreateFontString(nil, "OVERLAY")
        state.upgrade = overlay:CreateTexture(nil, "OVERLAY")
        state.upgrade:SetSize(10, 10)
        state.upgrade:SetAtlas("poi-door-arrow-up")
        overlay:Hide()
    elseif state.overlay:GetParent() ~= parent then
        state.overlay:SetParent(parent)
    end
    state.overlay:SetFrameLevel(parent:GetFrameLevel() + 2)
    state.level:ClearAllPoints()
    state.level:SetPoint("TOPRIGHT", state.overlay, "TOPRIGHT", -2, -2)
    state.level:SetFontObject(NumberFontNormal)
    state.upgrade:ClearAllPoints()
    state.upgrade:SetPoint("TOPLEFT", state.overlay, "TOPLEFT", 2, -2)
    state.level:Hide()
    state.upgrade:Hide()
    return true
end

local equipmentSlots = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_BODY = {4},
    INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7},
    INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16},
    INVTYPE_2HWEAPON = {16, 17}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18},
    INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18}, INVTYPE_TABARD = {19},
}

local function ItemLevel(link)
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if type(level) == "number" and level > 0 and level < math.huge then return level end
end

local function EquippedLevel(slot)
    if equipped[slot] ~= nil then return equipped[slot] or nil end
    local link = GetInventoryItemLink("player", slot)
    if not link then equipped[slot] = 0; return 0 end
    local level = ItemLevel(link)
    if level then equipped[slot] = level; return level end
    equipped[slot] = false
    local id = C_Item.GetItemInfoInstant(link)
    -- A completion with unusable data must not request itself again.
    if id and not pendingItems[id] and not requestedItems[id] then
        pendingItems[id] = true
        requestedItems[id] = true
        UpdateEvents()
        C_Item.RequestLoadItemDataByID(id)
    end
end

local function IsUpgrade(equipLoc, level, quality)
    local slots = equipmentSlots[equipLoc]
    if not slots then return false end
    -- Offhand items cannot replace half of an equipped two-handed weapon.
    if slots[1] == 17 then
        local main = GetInventoryItemLink("player", 16)
        if main then
            local _, _, _, mainLoc = C_Item.GetItemInfoInstant(main)
            if mainLoc == "INVTYPE_2HWEAPON" then return false end
        end
    end
    local baseline
    for _, slot in ipairs(slots) do
        local current = EquippedLevel(slot)
        if current == nil then return end
        if baseline == nil then baseline = current
        elseif equipLoc == "INVTYPE_2HWEAPON" then baseline = math.max(baseline, current)
        else baseline = math.min(baseline, current) end
    end
    if quality < 2 then return baseline == 0 end
    return level > baseline
end

UpdateButton = function(button)
    local state = buttons[button]
    if not state or InCombat() then return end
    if state.current then
        local ok, valid = pcall(state.current)
        if ok and valid then return end
    end
    Clear(button)
    local scope, root = Scope(button)
    if not scope then return end
    local bag, slot = Location(button)
    if not bag or not Usable(button, scope, root, bag) then return end
    if not API() then return end
    state.parent, state.slot, state.bag = button:GetParent(), button:GetID(), bag
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = C_Container.GetContainerItemLink(bag, slot)
    if not (info and info.itemID and link) then return end
    local expectedID, expectedQuality = info.itemID, info.quality
    local expectedParent, token, expectedGeneration = button:GetParent(), state.token, generation
    local function Valid()
        if state.token ~= token or generation ~= expectedGeneration then return false end
        if button:GetParent() ~= expectedParent then return false end
        local currentScope, currentRoot = Scope(button)
        if currentScope ~= scope or currentRoot ~= root or not Usable(button, scope, root, bag) then return false end
        local currentBag, currentSlot = Location(button)
        if currentBag ~= bag or currentSlot ~= slot then return false end
        local current = C_Container.GetContainerItemInfo(bag, slot)
        return current and current.itemID == expectedID and current.quality == expectedQuality
            and C_Container.GetContainerItemLink(bag, slot) == link
    end
    state.current = Valid
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipmentSlots[equipLoc] then return end
    local function Callback(callback)
        return function(...)
            local ok = pcall(function(...)
                if not Valid() then
                    -- Do not let an obsolete callback clear a newer occupant's overlay.
                    if state.token == token and generation == expectedGeneration then Invalidate(button) end
                    return
                end
                if InCombat() then
                    state.current = nil
                    deferred = true
                    RegisterEvent("PLAYER_REGEN_ENABLED")
                    return
                end
                callback(...)
            end, ...)
            if not ok and state.token == token then
                Clear(button)
                Failure("Item result unavailable; using native item levels")
            end
        end
    end
    local item = Item:CreateFromBagAndSlot(bag, slot)
    if not item or item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(Callback(function()
        local level = ItemLevel(link)
        if not level then state.current = nil; return end
        if not Prepare(button, state) then return end
        local quality = item:GetItemQuality()
        local r, g, b = C_Item.GetItemQualityColor(quality)
        state.level:SetText(level)
        state.level:SetTextColor(r or 1, g or 1, b or 1)
        state.level:Show()
        state.overlay:Show()
        state.valid = Valid
        OwnNative(button, state)
        local upgrade = IsUpgrade(equipLoc, level, quality)
        if upgrade == nil then state.current = nil; return end
        if not upgrade then return end
        local name, _, _, _, minimum = C_Item.GetItemInfo(link)
        if not name or type(minimum) ~= "number" then state.current = nil; return end
        if minimum > UnitLevel("player") then state.upgrade:SetVertexColor(1, 0, 0)
        else state.upgrade:SetVertexColor(1, 1, 1) end
        state.upgrade:Show()
    end))
end

local function ClearRoot(root)
    for button in pairs(buttons) do
        local _, currentRoot = Scope(button)
        if currentRoot == root then Clear(button) end
    end
end

local function HookRoot(frame, spec)
    local record = frames[frame]
    local fresh = record == nil
    if not record then
        record = {}
        frames[frame] = record
        frame:HookScript("OnShow", function()
            if enabled then
                equipped = {}
                requestedItems = {}
                ClearRoot(frame)
                Schedule(spec.scope)
            end
        end)
        frame:HookScript("OnHide", function(self)
            if enabled then ClearRoot(self); UpdateEvents() end
        end)
    end
    return fresh
end

local function Scan(frame, depth)
    if depth > 24 or ownedOverlays[frame] then return end
    if frame.ItemLevelText and frame.GetID and frame.GetParent then
        HookButton(frame)
        SafeUpdate(frame)
    end
    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do Scan(child, depth + 1) end
    end
end

Refresh = function()
    if not enabled or not ns.ready then return end
    UpdateEvents()
    if InCombat() then
        for button in pairs(buttons) do Clear(button) end
        deferred = true
        RegisterEvent("PLAYER_REGEN_ENABLED")
        SetStatus("Deferred until combat ends")
        return
    end
    deferred = false
    if not API() then
        for button in pairs(buttons) do Clear(button) end
        SetStatus("Waiting for native item-level API")
        return
    end
    local count, failures = 0, failureSerial
    local scanAll, scopes, targets = allDirty, dirtyScopes, dirtyButtons
    allDirty, dirtyScopes, dirtyButtons = false, {}, WeakKeys()
    for _, spec in ipairs(roots) do
        local root = _G[spec.name]
        if root then
            count = count + 1
            local fresh = HookRoot(root, spec)
            if Settings()[spec.scope] ~= false and root:IsVisible() and (fresh or scanAll or scopes[spec.scope]) then
                Scan(root, 0)
            end
        end
    end
    for button in pairs(targets) do SafeUpdate(button) end
    UpdateEvents()
    -- Clear buttons that were detached, reparented, or belong to disabled scopes.
    for button in pairs(buttons) do
        local scope, root = Scope(button)
        local bag = Location(button)
        if not scope or not Usable(button, scope, root, bag) then Clear(button) end
    end
    if count == 0 then SetStatus("Waiting for EllesmereUI bag frames")
    elseif failureSerial == failures then SetStatus("Active: item levels and equipped comparisons") end
end

Schedule = function(target)
    if not enabled then return end
    if type(target) == "string" then dirtyScopes[target] = true
    elseif target then dirtyButtons[target] = true
    else allDirty = true end
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        if enabled then
            local ok = pcall(Refresh)
            if not ok then
                for button in pairs(buttons) do Clear(button) end
                SetStatus("Bag display unavailable; using native item levels")
            end
        end
    end)
end

local function NeededEvents()
    local desired = {}
    local function Need(event) desired[event] = true end
    if deferred then Need("PLAYER_REGEN_ENABLED") end
    if not enabled or not API() then return desired end
    local settings = Settings()
    local visible, missing = false, false
    for _, spec in ipairs(roots) do
        if settings[spec.scope] ~= false then
            local root = _G[spec.name]
            if not root then missing = true
            elseif root:IsVisible() then visible = true end
        end
    end
    if visible or missing then Need("PLAYER_ENTERING_WORLD") end
    if missing then Need("BAG_UPDATE_DELAYED") end
    if settings.bank ~= false then
        Need("BANKFRAME_OPENED")
        Need("BANKFRAME_CLOSED")
        local bank = _G.EUI_BankFrame
        if bank and bank:IsVisible() then
            for _, event in ipairs(bankEvents) do Need(event) end
        end
    end
    if visible then
        for _, event in ipairs(events) do Need(event) end
        if next(pendingItems) then
            Need("ITEM_DATA_LOAD_RESULT")
            Need("GET_ITEM_INFO_RECEIVED")
        end
    end
    return desired
end

UpdateEvents = function()
    if not eventFrame then return end
    local desired = NeededEvents()
    for event in pairs(eventMask) do
        if not desired[event] then
            eventFrame:UnregisterEvent(event)
            eventMask[event] = nil
        end
    end
    for event in pairs(desired) do RegisterEvent(event) end
end

function Module:Initialize()
    if initialized then return end
    initialized = true
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, itemID, success)
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            if not pendingItems[itemID] then return end
            pendingItems[itemID] = nil
            requestedItems[itemID] = true
            equipped = {}
            UpdateEvents()
            if success then Schedule() end
            return
        end
        requestedItems = {}
        for slot, level in pairs(equipped) do
            if level == false then equipped[slot] = nil end
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            equipped = {}
            for button in pairs(buttons) do Clear(button) end
        end
        if event == "PLAYER_REGEN_ENABLED" then
            for button, state in pairs(buttons) do
                if state.needsClear or not enabled then Clear(button) end
            end
            deferred = false
            UpdateEvents()
            if not enabled then
                ClearEvents()
                SetStatus("Disabled")
                return
            end
        elseif event == "BANKFRAME_OPENED" then bankOpen = true
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
            if _G.EUI_BankFrame then ClearRoot(_G.EUI_BankFrame) end
        elseif event == "PLAYER_ENTERING_WORLD" then bankOpen = nil end
        if event:find("BANK", 1, true) then Schedule("bank") else Schedule() end
    end)
    SetStatus("Waiting for settings")
end

function Module:ApplySettings()
    if not initialized then self:Initialize() end
    if not ns.ready then return end
    generation = generation + 1
    equipped, pendingItems, requestedItems = {}, {}, {}
    local settings = Settings()
    enabled = settings.enabled ~= false and (settings.inventory ~= false
        or settings.reagent ~= false or settings.bank ~= false)
    if not InCombat() then deferred = false end
    for button in pairs(buttons) do Clear(button) end
    ClearEvents()
    if enabled then
        UpdateEvents()
        SetStatus(InCombat() and "Deferred until combat ends" or "Waiting for bag display")
        Schedule()
    elseif deferred then
        RegisterEvent("PLAYER_REGEN_ENABLED")
        SetStatus("Disabled; native visibility restoration pending combat end")
    else SetStatus("Disabled") end
end

function Module:OnAddonLoaded(name)
    if initialized and ns.ready and Settings().enabled ~= false then
        if name == "EllesmereUIBags"
            or name == "Blizzard_BankUI" or name == "Blizzard_Bags" then Schedule() end
    end
end

function Module:GetStatus()
    return status
end

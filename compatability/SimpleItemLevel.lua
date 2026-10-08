local folder, ns = ...
local Module = {}
ns.RegisterModule("simpleItemLevel", Module)

local KEY = "simpleItemLevel"
local roots = {
    {name = "EUI_MainBagFrame", scope = "inventory", refresh = "RefreshInventory"},
    {name = "EUI_ReagentBagFrame", scope = "reagent", refresh = "RefreshInventory"},
    {name = "EUI_BankFrame", scope = "bank", refresh = "RefreshBank"},
}
local function WeakKeys() return setmetatable({}, {__mode = "k"}) end
local buttons, frames, parents, nativeHooks, ownedOverlays = WeakKeys(), WeakKeys(), WeakKeys(), WeakKeys(), WeakKeys()
local settingsHooks, settingsPanels, dropdownHook = WeakKeys(), WeakKeys(), false
local positions = {
    TOPLEFT = {2, -2}, TOPRIGHT = {-2, -2}, BOTTOMLEFT = {2, 2}, BOTTOMRIGHT = {-2, 2},
    TOP = {0, -2}, BOTTOM = {0, 2}, LEFT = {2, 0}, RIGHT = {-2, 0}, CENTER = {0, 0},
}
local fontNames = {
    HighlightSmall = "GameFontHighlightSmall", Normal = "GameFontNormalOutline",
    Large = "GameFontNormalLargeOutline", Huge = "GameFontNormalHugeOutline",
    NumberNormal = "NumberFontNormal", NumberNormalSmall = "NumberFontNormalSmall",
}
local defaults = {
    bags = true, equipment = true, battlepets = true, reagents = false, misc = false,
    itemlevel = true, upgrades = true, color = true, quality = 1,
    position = "TOPRIGHT", positionup = "TOPLEFT", font = "NumberNormal", scaleup = 1,
}
local events = {
    "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED",
}
local bankEvents = { "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
    "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }
local generation, enabled, scheduled, deferred = 0, false, false, false
local eventFrame, initialized, bankOpen, globalQualityHook
local status = "Not initialized"
local failureSerial = 0
local Schedule, Refresh, UpdateButton, UpdateEvents
local dirtyButtons, dirtyScopes, allDirty = WeakKeys(), {}, false
local itemButtons = {}
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

local function SILSettings()
    local result, db = {}, _G.SimpleItemLevelDB
    for key, default in pairs(defaults) do
        local value = db and db[key]
        if value == nil then value = default end
        result[key] = value
    end
    return result
end

local function SameSettings(snapshot)
    local db = _G.SimpleItemLevelDB
    for key, default in pairs(defaults) do
        local value = db and db[key]
        if value == nil then value = default end
        if value ~= snapshot[key] then return false end
    end
    return true
end

local function API()
    local sil = _G.SimpleItemLevel
    return sil and type(sil.API) == "table" and sil.API or nil
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

-- Visibility belongs to EUI except while a successfully rendered SIL level replaces it.
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
    if state.itemID then
        local indexed = itemButtons[state.itemID]
        if indexed then
            indexed[button] = nil
            if not next(indexed) then itemButtons[state.itemID] = nil end
        end
        state.itemID = nil
    end
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
            local valid = false
            if current.valid then
                local ok, result = pcall(current.valid)
                valid = ok and result
            end
            if not valid then
                Clear(button)
                if enabled then Schedule() end
                return
            end
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
        Failure("SIL bridge error; using native item levels")
    end
end

local function Invalidate(button)
    if not enabled then return end
    Clear(button)
    if enabled then Schedule(button) end
end

local function HookMethod(object, record, method, callback)
    if type(object[method]) ~= "function" or record[method] == object[method] then return end
    hooksecurefunc(object, method, callback)
    record[method] = object[method]
end

local settingsSnapshot
local function SettingsChanged()
    if not enabled then return end
    if settingsSnapshot and SameSettings(settingsSnapshot) then return end
    settingsSnapshot = SILSettings()
    generation = generation + 1
    for button in pairs(buttons) do Clear(button) end
    Schedule()
end

local function HookSettings()
    -- SIL 926c410: ns.RefreshOverlayFrames is private. These named dropdowns
    -- expose its canvas panels; checkbox SetValue and slider scripts apply settings.
    settingsSnapshot = SILSettings()
    local function Controls(frame, depth)
        if not frame or depth > 4 then return end
        if frame.Check and defaults[frame.Check.key] ~= nil then
            local check = frame.Check
            local record = settingsHooks[check] or {}
            settingsHooks[check] = record
            HookMethod(check, record, "SetValue", SettingsChanged)
        end
        if frame.Slider and not settingsHooks[frame.Slider] then
            settingsHooks[frame.Slider] = {}
            frame.Slider:HookScript("OnValueChanged", SettingsChanged)
        end
        if frame.GetChildren then
            for _, child in ipairs({frame:GetChildren()}) do Controls(child, depth + 1) end
        end
    end
    for _, key in ipairs({"quality", "font"}) do
        local dropdown = _G["SimpleItemLevelOptions" .. key .. "Dropdown"]
        local control = dropdown and dropdown:GetParent()
        local panel = control and control:GetParent()
        if panel and not settingsPanels[panel] then
            Controls(panel, 0)
            settingsPanels[panel] = true
        end
    end
    if not dropdownHook and type(_G.UIDropDownMenu_SetSelectedValue) == "function" then
        hooksecurefunc("UIDropDownMenu_SetSelectedValue", function(dropdown)
            if not enabled then return end
            for _, key in ipairs({"quality", "font", "position", "positionup"}) do
                if dropdown and dropdown == _G["SimpleItemLevelOptions" .. key .. "Dropdown"] then
                    SettingsChanged()
                    return
                end
            end
        end)
        dropdownHook = true
    end
    -- SIL's slash settings path does not call its UI refresh callback.
    local commands = _G.SlashCmdList
    if type(commands) == "table" then
        local record = settingsHooks[commands] or {}
        settingsHooks[commands] = record
        HookMethod(commands, record, "SIMPLEITEMLEVEL", SettingsChanged)
    end
end

local function HookButton(button)
    local state = buttons[button]
    if not state then
        state = {token = 0, hooks = {}}
        buttons[button] = state
        button:HookScript("OnHide", Invalidate)
        button:HookScript("OnShow", function() if enabled then Schedule(button) end end)
    end
    for _, method in ipairs({"SetID", "SetParent", "SetItemButtonTexture", "SetItemButtonQuality"}) do
        HookMethod(button, state.hooks, method, Invalidate)
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
                if child:GetParent() == self then Invalidate(child) end
            end
        end)
    end
    return state
end

local function Prepare(button, state, settings)
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
    local position = positions[settings.position] and settings.position or "TOPRIGHT"
    local offset = positions[position]
    state.level:ClearAllPoints()
    state.level:SetPoint(position, state.overlay, position, offset[1], offset[2])
    state.level:SetFontObject(_G[fontNames[settings.font] or "NumberFontNormal"] or NumberFontNormal)
    position = positions[settings.positionup] and settings.positionup or "TOPLEFT"
    offset = positions[position]
    state.upgrade:ClearAllPoints()
    state.upgrade:SetPoint(position, state.overlay, position, offset[1], offset[2])
    local scale = settings.scaleup
    if type(scale) ~= "number" or scale ~= scale or scale <= 0 or scale == math.huge then scale = 1 end
    state.upgrade:SetScale(scale)
    state.level:Hide()
    state.upgrade:Hide()
    return true
end

local function ShouldShow(item, settings)
    local quality, itemID = item:GetItemQuality(), item:GetItemID()
    if type(quality) ~= "number" or type(itemID) ~= "number" then return false end
    local minimum = type(settings.quality) == "number" and settings.quality or 1
    if quality < minimum then return false end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
    if class == nil then return false end
    local classes, gems = Enum.ItemClass, Enum.ItemGemSubclass
    if class == classes.Weapon or class == classes.Armor
        or (classes.Profession and class == classes.Profession)
        or (class == classes.Gem and gems and gems.Artifactrelic and subclass == gems.Artifactrelic) then
        return settings.equipment
    end
    if itemID == 82800 then return settings.battlepets end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reagent = C_Item.GetItemInfo(itemID)
    if not name then return false end
    if reagent then return settings.reagents end
    return settings.misc
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
    local settings, api = SILSettings(), API()
    if not settings.bags or not api or not (settings.itemlevel or settings.upgrades) then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = C_Container.GetContainerItemLink(bag, slot)
    if not (info and info.itemID and link) then return end
    local expectedID, token, expectedGeneration = info.itemID, state.token, generation
    state.itemID = expectedID
    local indexed = itemButtons[expectedID]
    if not indexed then indexed = WeakKeys(); itemButtons[expectedID] = indexed end
    indexed[button] = true
    local function Valid()
        if state.token ~= token or generation ~= expectedGeneration then return false end
        if type(_G.SimpleItemLevelDB) ~= "table" or not SameSettings(settings)
            or API() ~= api or not settings.bags then return false end
        local currentScope, currentRoot = Scope(button)
        if currentScope ~= scope or currentRoot ~= root or not Usable(button, scope, root, bag) then return false end
        local currentBag, currentSlot = Location(button)
        if currentBag ~= bag or currentSlot ~= slot then return false end
        local current = C_Container.GetContainerItemInfo(bag, slot)
        return current and current.itemID == expectedID and C_Container.GetContainerItemLink(bag, slot) == link
    end
    state.current = Valid
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
                Failure("SIL result unavailable; using native item levels")
            end
        end
    end
    local item = Item:CreateFromBagAndSlot(bag, slot)
    if not item or item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(Callback(function()
        if not ShouldShow(item, settings) or not Prepare(button, state, settings) then return end
        if settings.itemlevel and type(api.ItemLevel) == "function" then
            local ok, level = pcall(api.ItemLevel, item)
            if not ok then Failure("SIL result unavailable; using native item levels") end
            if ok and type(level) == "number" and level > 0 and level < math.huge then
                local quality = settings.color and item:GetItemQuality() or 1
                local r, g, b = C_Item.GetItemQualityColor(quality)
                state.level:SetText(level)
                state.level:SetTextColor(r or 1, g or 1, b or 1)
                state.level:Show()
                state.overlay:Show()
                state.valid = Valid
                OwnNative(button, state)
            else
                state.current = nil
            end
        end
        if not settings.upgrades then return end
        local applyUpgrade = Callback(function(upgrade)
            if not upgrade then state.upgrade:Hide(); return end
            local name, _, _, _, minimum = C_Item.GetItemInfo(link)
            if not name or type(minimum) ~= "number" then return end
            if minimum > UnitLevel("player") then state.upgrade:SetVertexColor(1, 0, 0)
            else state.upgrade:SetVertexColor(1, 1, 1) end
            state.upgrade:Show()
            state.overlay:Show()
        end)
        -- The public async API also waits for equipped items before comparing upgrades.
        if type(api.ItemIsUpgradeAsync) == "function" then
            pcall(api.ItemIsUpgradeAsync, item, applyUpgrade)
        elseif type(api.ItemIsUpgrade) == "function" then
            local ok, upgrade = pcall(api.ItemIsUpgrade, item)
            if ok then applyUpgrade(upgrade) end
        end
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
        frame:HookScript("OnShow", function() if enabled then Schedule(spec.scope) end end)
        frame:HookScript("OnHide", function(self)
            if enabled then ClearRoot(self); UpdateEvents() end
        end)
    end
    HookMethod(frame, record, spec.refresh, function() if enabled then Schedule(spec.scope) end end)
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
    HookSettings()
    UpdateEvents()
    if InCombat() then
        for button in pairs(buttons) do Clear(button) end
        deferred = true
        RegisterEvent("PLAYER_REGEN_ENABLED")
        SetStatus("Deferred until combat ends")
        return
    end
    deferred = false
    if type(_G.SimpleItemLevelDB) ~= "table" or not API() then
        for button in pairs(buttons) do Clear(button) end
        SetStatus("Waiting for SimpleItemLevel")
        return
    end
    local settings = SILSettings()
    if not settings.bags then
        for button in pairs(buttons) do Clear(button) end
        SetStatus("SIL bag display is disabled; native item levels unchanged")
        return
    end
    if not globalQualityHook and type(_G.SetItemButtonQuality) == "function" then
        hooksecurefunc("SetItemButtonQuality", function(button)
            if enabled and button and Scope(button) then
                if buttons[button] then Invalidate(button) else Schedule() end
            end
        end)
        globalQualityHook = true
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
    -- Clear buttons that were detached, reparented, or belong to disabled scopes.
    for button in pairs(buttons) do
        local scope, root = Scope(button)
        local bag = Location(button)
        if not scope or not Usable(button, scope, root, bag) then Clear(button) end
    end
    if count == 0 then SetStatus("Waiting for EllesmereUI bag frames")
    elseif failureSerial == failures then SetStatus("Active: SIL styles and filters; native fallback available") end
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
                SetStatus("SIL bridge unavailable; using native item levels")
            end
        end
    end)
end

local function NeededEvents()
    local desired = {}
    local function Need(event) desired[event] = true end
    if deferred then Need("PLAYER_REGEN_ENABLED") end
    if not enabled or type(_G.SimpleItemLevelDB) ~= "table" or not API() then return desired end
    local settings = Settings()
    if not SILSettings().bags then return desired end
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
        if SILSettings().upgrades then
            for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_UP" }) do
                Need(event)
            end
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
    eventFrame:SetScript("OnEvent", function(_, event, itemID)
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            if type(itemID) ~= "number" then return end
            for button in pairs(itemButtons[itemID] or {}) do Invalidate(button) end
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_LEVEL_UP" then
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
        if name == "SimpleItemLevel" or name == "EllesmereUIBags"
            or name == "Blizzard_BankUI" or name == "Blizzard_Bags" then Schedule() end
    end
end

function Module:GetStatus()
    return status
end

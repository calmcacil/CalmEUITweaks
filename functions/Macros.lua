local addonName, ns = ...
local modules = {}

ns.MacroSpells = {}

-- Conjured food and water tiers are shared by the mage and general providers.
ns.MacroItems = {
    Food = {
        { level = 52, spell = 28612, item = 22895 },
        { level = 42, spell = 10145, item = 8076 },
        { level = 32, spell = 10144, item = 8075 },
        { level = 22, spell = 6129, item = 1487 },
        { level = 12, spell = 990, item = 1114 },
        { level = 6, spell = 597, item = 1113 },
        { level = 1, spell = 587, item = 5349 },
    },
    Water = {
        { level = 52, spell = 10140, item = 8079 },
        { level = 42, spell = 10139, item = 8078 },
        { level = 32, spell = 10138, item = 8077 },
        { level = 22, spell = 6127, item = 3772 },
        { level = 12, spell = 5506, item = 2136 },
        { level = 6, spell = 5505, item = 2288 },
        { level = 1, spell = 5504, item = 5350 },
    },
}

local function IsKnown(spellID)
    local checks = {
        C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook,
        C_SpellBook and C_SpellBook.IsSpellKnown,
        IsSpellKnown,
        IsPlayerSpell,
    }
    -- Nil entries must not stop the fallback chain on older clients.
    for i = 1, 4 do
        local check = checks[i]
        if check then
            local ok, known = pcall(check, spellID)
            if ok and known ~= nil then return not not known end
        end
    end
    return false
end

function ns.MacroSpells.HighestKnown(tiers)
    local level = UnitLevel("player") or 1
    for _, tier in ipairs(tiers) do
        if level >= tier.level and IsKnown(tier.spell) then return tier end
    end
end

function ns.MacroSpells.Name(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
end

local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(slots) == "number" then return slots end
    end
    if GetContainerNumSlots then
        local ok, slots = pcall(GetContainerNumSlots, bag)
        if ok and type(slots) == "number" then return slots end
    end
    return 0
end

local function ContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and info and info.itemID then return info.itemID end
    end
    if C_Container and C_Container.GetContainerItemID then
        local ok, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
        if ok then return itemID end
    end
    if GetContainerItemID then
        local ok, itemID = pcall(GetContainerItemID, bag, slot)
        if ok then return itemID end
    end
end

-- Bags only: bank contents are not usable while eating or drinking.
local function BagItems()
    local items = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerSlots(bag) do
            local itemID = ContainerItemID(bag, slot)
            if itemID then items[itemID] = true end
        end
    end
    return items
end

function ns.MacroSpells.HighestOwned(tiers)
    local items = BagItems()
    for _, tier in ipairs(tiers) do
        if tier.item and items[tier.item] then return tier end
    end
end

local function ValidName(name)
    if type(name) ~= "string" or not name:find("%S") or name:find("%c") then
        return false, "Enter a nonempty macro name without control characters."
    end
    local length = strlenutf8 and strlenutf8(name)
    if not length then
        local _, count = name:gsub("[^\128-\191]", "")
        length = count
    end
    if length > 16 then return false, "Macro names must be at most 16 characters." end
    return true
end

local function FindNamed(name, accountLimit, characterLimit)
    local matches = {}
    -- Scan both scopes rather than trusting GetMacroIndexByName's first match.
    for index = 1, accountLimit + characterLimit do
        local ok, macroName, _, body = pcall(GetMacroInfo, index)
        if not ok then return nil end
        if macroName == name then
            matches[#matches + 1] = { index = index, body = body }
        end
    end
    return matches
end

local function ValidEvents(events)
    if events == nil then return true end
    if type(events) ~= "table" then return false end
    local count = 0
    for _, event in pairs(events) do
        count = count + 1
        if type(event) ~= "string" or not event:find("%S") or event:find("%c") then return false end
    end
    return count == #events
end

-- Provider contract and addition checklist: specs/macro-providers/TECH.md.
function ns.RegisterMacroProvider(id, provider)
    local scope = type(provider) == "table" and provider.scope or "character"
    assert(type(id) == "string" and id:find("%S") and not id:find("%c")
        and not modules[id], "Duplicate or invalid macro provider")
    assert(type(provider) == "table" and type(provider.Build) == "function"
        and type(provider.settingsKey) == "string" and provider.settingsKey:find("%S")
        and not provider.settingsKey:find("%c")
        and type(provider.class) == "string" and provider.class:find("%S")
        and not provider.class:find("%c")
        and type(provider.classLabel) == "string" and provider.classLabel:find("%S")
        and not provider.classLabel:find("%c")
        and ValidName(provider.defaultName)
        and (scope == "character" or scope == "account")
        and ValidEvents(provider.events),
        "Invalid macro provider contract")

    local Module = { asyncErrors = true }
    local key = provider.settingsKey
    local accountScope = scope == "account"
    local refreshEvents = {}
    if provider.events then
        for index, event in ipairs(provider.events) do refreshEvents[index] = event end
    end
    local frame, active, queued, pendingCombat
    local generation = 0
    local requested, awaiting = {}, {}
    local status = "Not initialized."

    local function SetStatus(message)
        if status == message then return end
        status = message
        ns.SetStatus(key, message)
    end

    local function Settings()
        local settings = ns.GetSettings(key) or {}
        local name = settings.name
        if name == nil then name = provider.defaultName end
        return settings.enabled ~= false, name
    end

    local function IsEligible()
        if provider.class == "ALL" then return true end
        local _, class = UnitClass("player")
        return class == provider.class
    end

    local function Stop()
        active, queued, pendingCombat = false, false, false
        generation = generation + 1
        requested, awaiting = {}, {}
        if frame then
            frame:UnregisterAllEvents()
            frame:SetScript("OnEvent", nil)
        end
    end

    local Run
    local function Queue()
        if not active or queued then return end
        queued = true
        local ticket = generation
        local function Flush()
            if ticket ~= generation or not active then return end
            queued = false
            local ok, err = pcall(Run)
            if not ok then
                ns.ReportError(key, err)
                SetStatus(ns.errors[key])
            else
                ns.ClearError(key)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, Flush)
        else
            Flush()
        end
    end

    local function RequestSpell(spellID)
        if requested[spellID] then return end
        requested[spellID] = true
        if C_Spell and C_Spell.RequestLoadSpellData then
            if not next(awaiting) then frame:RegisterEvent("SPELL_DATA_LOAD_RESULT") end
            awaiting[spellID] = true
            local ok = pcall(C_Spell.RequestLoadSpellData, spellID)
            if not ok then
                awaiting[spellID] = nil
                if not next(awaiting) then frame:UnregisterEvent("SPELL_DATA_LOAD_RESULT") end
            end
        end
    end

    local function Ownership()
        local root = accountScope and ns.db or ns.charDB
        if type(root) ~= "table" or type(root[key]) ~= "table" then return nil end
        return root[key]
    end

    local function InScope(index, accountLimit)
        if accountScope then return index <= accountLimit end
        return index > accountLimit
    end

    Run = function()
        local enabled, name = Settings()
        if not enabled or not IsEligible() or not ns.ready then
            Module:ApplySettings()
            return
        end
        local valid, reason = ValidName(name)
        if not valid then SetStatus(reason); return end
        if InCombatLockdown and InCombatLockdown() then
            pendingCombat = true
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            SetStatus("Waiting for combat to end; no macro changes made.")
            return
        end
        pendingCombat = false
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")

        local body, message, missingSpells = provider.Build()
        if not body then
            if missingSpells then
                local waiting = false
                for _, spellID in ipairs(missingSpells) do
                    RequestSpell(spellID)
                    if awaiting[spellID] then waiting = true end
                end
                if not waiting then
                    message = "Spell data unavailable; toggle the module to retry."
                end
            end
            SetStatus(message or "Macro provider is not ready.")
            return
        end
        if type(body) ~= "string" or body == "" then
            SetStatus("Macro provider returned an invalid body; no changes made.")
            return
        end
        if #body > (MAX_MACRO_LENGTH or 255) then
            SetStatus("Localized macro exceeds the body length limit; no changes made.")
            return
        end
        if not GetNumMacros or not GetMacroInfo or not CreateMacro or not EditMacro then
            SetStatus("Macro APIs are unavailable on this client.")
            return
        end
        local db = Ownership()
        if not db then
            SetStatus((accountScope and "Account" or "Character")
                .. " settings are unavailable; no changes made.")
            return
        end
        local scopeName = accountScope and "general" or "character"
        local accountLimit = MAX_ACCOUNT_MACROS or 120
        local characterLimit = MAX_CHARACTER_MACROS or 18
        local matches = FindNamed(name, accountLimit, characterLimit)
        if not matches then SetStatus("Could not inspect existing macros; no changes made."); return end
        local records = type(db.ownedMacros) == "table" and db.ownedMacros or nil
        local record = records and records[name]
        if #matches > 0 then
            local macro = matches[1]
            if #matches ~= 1 or not InScope(macro.index, accountLimit) then
                SetStatus("Name conflict: '" .. name .. "'. Choose another name or rename the existing macro.")
                return
            end
            local owned = type(record) == "table" and type(record.lastGeneratedBody) == "string"
            if owned then
                if macro.body ~= record.lastGeneratedBody then
                    SetStatus("User-edited macro preserved: '" .. name .. "'. Choose another name to resume.")
                    return
                end
                if macro.body == body then
                    SetStatus("Ready: " .. scopeName .. " macro '" .. name .. "'.")
                    return
                end
                local ok = pcall(EditMacro, macro.index, nil, nil, body)
                local readOK, actualName, _, actualBody = pcall(GetMacroInfo, macro.index)
                if not ok or not readOK or actualName ~= name or actualBody ~= body then
                    SetStatus("Macro update could not be verified; no ownership changes made.")
                    return
                end
                record.lastGeneratedBody = body
                SetStatus("Updated " .. scopeName .. " macro '" .. name .. "'.")
                return
            end

            -- An enabled provider adopts the sole same-name macro in its scope.
            local changed = macro.body ~= body
            if changed then
                local ok = pcall(EditMacro, macro.index, nil, nil, body)
                local readOK, actualName, _, actualBody = pcall(GetMacroInfo, macro.index)
                if not ok or not readOK or actualName ~= name or actualBody ~= body then
                    SetStatus("Macro adoption could not be verified; no ownership changes made.")
                    return
                end
            end
            if not records then records = {}; db.ownedMacros = records end
            records[name] = { lastGeneratedBody = body }
            SetStatus((changed and "Adopted and updated " or "Adopted ")
                .. scopeName .. " macro '" .. name .. "'.")
            return
        end

        local countOK, accountCount, characterCount = pcall(GetNumMacros)
        local count = characterCount
        if accountScope then count = accountCount end
        if not countOK or type(count) ~= "number" then
            SetStatus("Could not check " .. scopeName .. " macro capacity; no changes made.")
            return
        end
        local limit = accountScope and accountLimit or characterLimit
        if count >= limit then
            SetStatus((accountScope and "General" or "Character")
                .. " macro slots are full; free a slot or disable this module.")
            return
        end
        -- The client documents nil, not false, as the general-macro flag.
        local perCharacter = not accountScope or nil
        local ok, index = pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, perCharacter)
        if not ok or type(index) ~= "number" or not InScope(index, accountLimit)
            or index > accountLimit + characterLimit then
            SetStatus((accountScope and "General" or "Character")
                .. " macro creation failed; no ownership recorded.")
            return
        end
        local readOK, actualName, _, actualBody = pcall(GetMacroInfo, index)
        if not readOK or actualName ~= name or actualBody ~= body then
            SetStatus("Macro creation could not be verified; no ownership recorded.")
            return
        end
        -- Keep earlier names owned without deleting or updating them on a rename.
        if not records then records = {}; db.ownedMacros = records end
        records[name] = { lastGeneratedBody = body }
        SetStatus("Created " .. scopeName .. " macro '" .. name .. "'.")
    end

    function Module:Initialize()
        if self.initialized then return end
        self.initialized = true
        self:ApplySettings()
    end

    function Module:ApplySettings()
        local enabled = Settings()
        if not enabled then
            Stop()
            SetStatus("Disabled; existing macros are unchanged.")
            return
        end
        if not IsEligible() then
            Stop()
            SetStatus(provider.classLabel .. " only; no macro changes made.")
            return
        end
        if not self.initialized or not ns.ready then
            Stop()
            SetStatus("Waiting for player login.")
            return
        end
        if not active then
            frame = frame or CreateFrame("Frame")
            active = true
            frame:SetScript("OnEvent", function(_, event, spellID)
                if event == "SPELL_DATA_LOAD_RESULT" then
                    if not awaiting[spellID] then return end
                    awaiting[spellID] = nil
                    if not next(awaiting) then frame:UnregisterEvent("SPELL_DATA_LOAD_RESULT") end
                    -- Each ID is requested once per activation, including failures.
                    Queue()
                elseif event == "PLAYER_REGEN_ENABLED" then
                    frame:UnregisterEvent(event)
                    if pendingCombat then pendingCombat = false; Queue() end
                else
                    Queue()
                end
            end)
            for _, event in ipairs({ "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
                "UPDATE_MACROS" }) do
                pcall(frame.RegisterEvent, frame, event)
            end
            for _, event in ipairs(refreshEvents) do
                pcall(frame.RegisterEvent, frame, event)
            end
        end
        Queue()
    end

    function Module:GetStatus()
        return status
    end

    ns.RegisterModule(key, Module)
    modules[id] = Module
    return Module
end

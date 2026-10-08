local addonName, ns = ...
local modules = {}

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

-- Providers supply settingsKey, class, classLabel, defaultName and Build().
-- Build returns body, or nil, status message, optional missing spell IDs.
function ns.RegisterMacroProvider(id, provider)
    assert(type(id) == "string" and not modules[id], "Duplicate or invalid macro provider")
    assert(type(provider) == "table" and type(provider.Build) == "function"
        and type(provider.settingsKey) == "string" and type(provider.class) == "string"
        and type(provider.classLabel) == "string" and type(provider.defaultName) == "string",
        "Invalid macro provider contract")

    local Module = { asyncErrors = true }
    local key = provider.settingsKey
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
        if type(ns.charDB) ~= "table" or type(ns.charDB[key]) ~= "table" then return nil end
        return ns.charDB[key]
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
        if not db then SetStatus("Character settings are unavailable; no changes made."); return end
        local accountLimit = MAX_ACCOUNT_MACROS or 120
        local characterLimit = MAX_CHARACTER_MACROS or 18
        local matches = FindNamed(name, accountLimit, characterLimit)
        if not matches then SetStatus("Could not inspect existing macros; no changes made."); return end
        local records = type(db.ownedMacros) == "table" and db.ownedMacros or nil
        local record = records and records[name]
        if #matches > 0 then
            local macro = matches[1]
            if #matches ~= 1 or macro.index <= accountLimit or type(record) ~= "table"
                or type(record.lastGeneratedBody) ~= "string" then
                SetStatus("Name conflict: '" .. name .. "'. Choose another name or rename the existing macro.")
                return
            end
            if macro.body ~= record.lastGeneratedBody then
                SetStatus("User-edited macro preserved: '" .. name .. "'. Choose another name to resume.")
                return
            end
            if macro.body == body then SetStatus("Ready: character macro '" .. name .. "'."); return end
            local ok = pcall(EditMacro, macro.index, nil, nil, body)
            local readOK, actualName, _, actualBody = pcall(GetMacroInfo, macro.index)
            if not ok or not readOK or actualName ~= name or actualBody ~= body then
                SetStatus("Macro update could not be verified; no ownership changes made.")
                return
            end
            record.lastGeneratedBody = body
            SetStatus("Updated character macro '" .. name .. "'.")
            return
        end

        local countOK, _, characterCount = pcall(GetNumMacros)
        if not countOK or type(characterCount) ~= "number" then
            SetStatus("Could not check character macro capacity; no changes made.")
            return
        end
        if characterCount >= characterLimit then
            SetStatus("Character macro slots are full; free a slot or disable this module.")
            return
        end
        local ok, index = pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, true)
        if not ok or type(index) ~= "number" or index <= accountLimit
            or index > accountLimit + characterLimit then
            SetStatus("Character macro creation failed; no ownership recorded.")
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
        SetStatus("Created character macro '" .. name .. "'.")
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
        end
        Queue()
    end

    function Module:GetStatus()
        return status
    end

    modules[id] = Module
    ns.RegisterModule(key, Module)
    return Module
end

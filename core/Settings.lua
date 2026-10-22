local _, ns = ...

ns.defaults = {
    mageMacro = { enabled = false, name = "FoodWater" },
    druidRebirthMacro = { enabled = false, name = "Rebirth" },
    druidThornsMacro = { enabled = false, name = "Thorns" },
    generalFoodWaterMacro = { enabled = false, name = "Food and Water" },
    simpleItemLevel = { enabled = false, inventory = false, reagent = false, bank = false },
    questLootSparkles = { enabled = false },
    cursorWashedOut = { enabled = false },
    lfgLeaderLocation = { enabled = false },
    chat = { autoApply = false },
    spacers = { spacer1 = false, spacer2 = false, spacer3 = false, spacer4 = false },
    spacerLayouts = {},
}

local characterDefaults = {
    version = 1, mageMacro = {}, druidRebirthMacro = {}, druidThornsMacro = {}, chat = {},
}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end
ns.Copy = Copy

local function FillDefaults(db, defaults, reset)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            FillDefaults(db[key], value, reset)
        elseif reset or type(db[key]) ~= type(value) then
            db[key] = value
        end
    end
end

local function IsValidMacroName(name)
    return name:find("%S") ~= nil and #name <= (MAX_MACRO_NAME_LENGTH or 16) and not name:find("[%c|]")
end

local function IsNamedSetting(moduleKey)
    local defaults = ns.defaults[moduleKey]
    return type(defaults) == "table" and type(defaults.name) == "string"
end

function ns.ResetPreferences(db)
    -- Reset preference leaves, not subtrees that also hold user data or ownership.
    FillDefaults(db, ns.defaults, true)
    return true
end

function ns.NormalizeSettings(account, character)
    FillDefaults(account, ns.defaults)
    FillDefaults(character, characterDefaults)
    -- The first loaded character seeds missing account layouts; later characters cannot overwrite them.
    local legacy = character.spacers
    if type(legacy) == "table" then
        for index = 1, 4 do
            if account.spacerLayouts[index] == nil and type(legacy[index]) == "table" then
                account.spacerLayouts[index] = Copy(legacy[index])
            end
        end
    end
    for _, key in ipairs({ "spacers", "spacerCorners" }) do character[key] = nil end
    for key, value in pairs(ns.defaults) do
        if type(value) == "table" and type(value.name) == "string"
            and not IsValidMacroName(account[key].name) then
            account[key].name = value.name
        end
    end
end

function ns.InitializeSettings()
    if not ns.RunSchemaMigrations() then return false end
    ns.NormalizeSettings(CalmUITweaksDB, CalmUITweaksCharDB)
    ns.db, ns.charDB = CalmUITweaksDB, CalmUITweaksCharDB
    ns.settingsReady = true
    return true
end

function ns.SavedVariablesReady()
    if ns.settingsReady then return true end
    return false, ns.settingsError or ns.errors.migrations or ns.statuses.migrations or "Settings are not loaded yet."
end

function ns.GetSettings(key)
    return (ns.db or ns.defaults)[key]
end

function ns.SetSetting(moduleKey, key, value)
    local ready, reason = ns.SavedVariablesReady()
    if not ready then return false, reason end
    local defaults = ns.defaults[moduleKey]
    if type(defaults) ~= "table" or defaults[key] == nil or type(value) ~= type(defaults[key]) then
        return false, "Unknown setting or invalid value."
    end
    if key == "name" and IsNamedSetting(moduleKey) then
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        if not IsValidMacroName(value) then
            return false, "Macro names must be plain text, 1-16 bytes long."
        end
    end
    ns.db[moduleKey][key] = value
    if ns.ready then ns.CallModule(moduleKey, "ApplySettings") end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return true
end

function ns.ResetSettings()
    local ready, reason = ns.SavedVariablesReady()
    if not ready then return false, reason end
    ns.ResetPreferences(ns.db)
    if ns.ready then
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "ApplySettings") end
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return true
end

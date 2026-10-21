local _, ns = ...

ns.defaults = {
    mageMacro = { enabled = true, name = "Mage FoodWater" },
    simpleItemLevel = { enabled = true, inventory = true, reagent = true, bank = true },
    whatsTraining = { enabled = true },
    questLootSparkles = { enabled = false },
    cursorWashedOut = { enabled = false },
    lfgLeaderLocation = { enabled = false },
    chat = { autoApply = false },
    spacers = { spacer1 = false, spacer2 = false, spacer3 = false, spacer4 = false },
    spacerLayouts = {},
    anchorGap = { enabled = false, top = 2, bottom = 2, left = 2, right = 2 },
    spacerCorners = { player = "DEFAULT", target = "DEFAULT" },
}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end
ns.Copy = Copy

local function FillDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            FillDefaults(db[key], value)
        elseif type(db[key]) ~= type(value) then
            db[key] = value
        end
    end
end

local function IsValidMacroName(name)
    return name:find("%S") ~= nil and #name <= (MAX_MACRO_NAME_LENGTH or 16) and not name:find("[%c|]")
end

local gapSides = { "top", "bottom", "left", "right" }
local function ValidGap(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 10
        and value == math.floor(value)
end

function ns.InitializeSettings()
    if not ns.RunSchemaMigrations() then return false end
    FillDefaults(CalmUITweaksDB, ns.defaults)
    ns.db = CalmUITweaksDB
    for _, side in ipairs(gapSides) do
        if not ValidGap(ns.db.anchorGap[side]) then
            ns.db.anchorGap[side] = ns.defaults.anchorGap[side]
        end
    end
    FillDefaults(CalmUITweaksCharDB, { version = 1, mageMacro = {}, chat = {}, spacerCorners = {} })
    ns.charDB = CalmUITweaksCharDB
    -- The first loaded character seeds missing account layouts; later characters cannot overwrite them.
    local legacy = ns.charDB.spacers
    if type(legacy) == "table" then
        for index = 1, 4 do
            if ns.db.spacerLayouts[index] == nil and type(legacy[index]) == "table" then
                ns.db.spacerLayouts[index] = Copy(legacy[index])
            end
        end
    end
    ns.charDB.spacers = nil
    for _, unit in ipairs({ "player", "target" }) do
        local corner = ns.db.spacerCorners[unit]
        if corner ~= "DEFAULT" and corner ~= "TOPLEFT" and corner ~= "TOPRIGHT"
            and corner ~= "BOTTOMLEFT" and corner ~= "BOTTOMRIGHT" then
            ns.db.spacerCorners[unit] = "DEFAULT"
        end
    end
    if not IsValidMacroName(ns.db.mageMacro.name) then
        ns.db.mageMacro.name = ns.defaults.mageMacro.name
    end
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
    if moduleKey == "mageMacro" and key == "name" then
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        if not IsValidMacroName(value) then
            return false, "Macro names must be plain text, 1-16 bytes long."
        end
    end
    if moduleKey == "anchorGap" and key ~= "enabled" and not ValidGap(value) then
        return false, "Anchor gaps must be whole pixels from 0 to 10."
    end
    if moduleKey == "spacerCorners" and value ~= "DEFAULT" and value ~= "TOPLEFT"
        and value ~= "TOPRIGHT" and value ~= "BOTTOMLEFT" and value ~= "BOTTOMRIGHT" then
        return false, "Unknown spacer corner alignment."
    end
    ns.db[moduleKey][key] = value
    if ns.ready then ns.CallModule(moduleKey, "ApplySettings") end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return true
end

function ns.ResetSettings()
    local ready, reason = ns.SavedVariablesReady()
    if not ready then return false, reason end
    -- Preference resets preserve macro ownership and the saved chat setup.
    local chatDefault = ns.db.chat.default
    local spacerLayouts = ns.db.spacerLayouts
    local sparkleRestore = ns.db.questLootSparkles.restore
    local cursorRestore = ns.db.cursorWashedOut.restore
    for key, value in pairs(ns.defaults) do ns.db[key] = Copy(value) end
    ns.db.chat.default = chatDefault
    ns.db.spacerLayouts = spacerLayouts
    ns.db.questLootSparkles.restore = sparkleRestore
    ns.db.cursorWashedOut.restore = cursorRestore
    if ns.ready then
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "ApplySettings") end
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return true
end

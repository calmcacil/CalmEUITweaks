local addonName, ns = ...

local FOOD = {
    { level = 52, spell = 28612, item = 22895 },
    { level = 42, spell = 10145, item = 8076 },
    { level = 32, spell = 10144, item = 8075 },
    { level = 22, spell = 6129, item = 1487 },
    { level = 12, spell = 990, item = 1114 },
    { level = 6, spell = 597, item = 1113 },
    { level = 1, spell = 587, item = 5349 },
}

local WATER = {
    { level = 52, spell = 10140, item = 8079 },
    { level = 42, spell = 10139, item = 8078 },
    { level = 32, spell = 10138, item = 8077 },
    { level = 22, spell = 6127, item = 3772 },
    { level = 12, spell = 5506, item = 2136 },
    { level = 6, spell = 5505, item = 2288 },
    { level = 1, spell = 5504, item = 5350 },
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

local function HighestKnown(tiers)
    local level = UnitLevel("player") or 1
    for _, tier in ipairs(tiers) do
        if level >= tier.level and IsKnown(tier.spell) then return tier end
    end
end

local function SpellName(spellID)
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

local function Build()
    local food, water = HighestKnown(FOOD), HighestKnown(WATER)
    if not food or not water then
        return nil, "Learn both Conjure Food and Conjure Water to create this macro."
    end
    local foodName, waterName = SpellName(food.spell), SpellName(water.spell)
    if not foodName or not waterName then
        local missing = {}
        if not foodName then missing[#missing + 1] = food.spell end
        if not waterName then missing[#missing + 1] = water.spell end
        return nil, "Waiting for localized conjure spell data.", missing
    end
    return table.concat({
        "#showtooltip",
        "/use [btn:1] item:" .. food.item,
        "/use [btn:1] item:" .. water.item,
        "/castsequence [btn:2] reset=10 " .. foodName .. ", " .. waterName,
    }, "\n")
end

ns.RegisterMacroProvider("mage", {
    settingsKey = "mageMacro",
    class = "MAGE",
    classLabel = "Mage",
    defaultName = "Mage FoodWater",
    Build = Build,
})

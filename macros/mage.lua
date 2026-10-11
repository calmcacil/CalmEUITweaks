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

local function Build()
    local food = ns.MacroSpells.HighestKnown(FOOD)
    local water = ns.MacroSpells.HighestKnown(WATER)
    if not food or not water then
        return nil, "Learn both Conjure Food and Conjure Water to create this macro."
    end
    local foodName = ns.MacroSpells.Name(food.spell)
    local waterName = ns.MacroSpells.Name(water.spell)
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

local addonName, ns = ...

local FOOD = ns.MacroItems.Food
local WATER = ns.MacroItems.Water

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
    defaultName = "FoodWater",
    Build = Build,
})

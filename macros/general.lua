local addonName, ns = ...

local FOOD = ns.MacroItems.Food
local WATER = ns.MacroItems.Water

local function Build()
    local food = ns.MacroSpells.HighestOwned(FOOD)
    local water = ns.MacroSpells.HighestOwned(WATER)
    if not food or not water then
        return nil, "Waiting for conjured food and water in your bags."
    end
    return table.concat({
        "#showtooltip [btn:2] item:" .. water.item .. "; item:" .. food.item,
        "/use [btn:1] item:" .. food.item,
        "/use [btn:2] item:" .. water.item,
    }, "\n")
end

ns.RegisterMacroProvider("foodWater", {
    settingsKey = "generalFoodWaterMacro",
    scope = "account",
    class = "ALL",
    classLabel = "All classes",
    defaultName = "Food and Water",
    events = { "BAG_UPDATE_DELAYED" },
    Build = Build,
})

local addonName, ns = ...

local FOOD = ns.MacroItems.Food
local WATER = ns.MacroItems.Water

local function Build()
    local food = ns.MacroSpells.HighestOwned(FOOD)
    local water = ns.MacroSpells.HighestOwned(WATER)
    local tooltip = "#showtooltip"
    if food and water then
        tooltip = tooltip .. " [btn:2] item:" .. water.item .. "; item:" .. food.item
    elseif food or water then
        tooltip = tooltip .. " item:" .. (food or water).item
    end
    local lines = { tooltip }
    if food then lines[#lines + 1] = "/use [btn:1] item:" .. food.item end
    if water then lines[#lines + 1] = "/use [btn:2] item:" .. water.item end
    local icon = (food or water) and "INV_Misc_QuestionMark" or "Interface\\Icons\\ClassIcon_Mage"
    return table.concat(lines, "\n"), nil, nil, icon
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

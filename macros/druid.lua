local addonName, ns = ...

-- Macros use unranked names, so the client selects the highest learned rank.
local REBIRTH = {
    { level = 60, spell = 20748 },
    { level = 50, spell = 20747 },
    { level = 40, spell = 20742 },
    { level = 30, spell = 20739 },
    { level = 20, spell = 20484 },
}

local REVIVE = {
    { level = 60, spell = 1237951 },
    { level = 48, spell = 1237950 },
    { level = 36, spell = 1237949 },
    { level = 24, spell = 1237948 },
    { level = 12, spell = 437138 },
}

local THORNS = {
    { level = 54, spell = 9910 },
    { level = 44, spell = 9756 },
    { level = 34, spell = 8914 },
    { level = 24, spell = 1075 },
    { level = 14, spell = 782 },
    { level = 6, spell = 467 },
}

local function BuildRebirth()
    local rebirth = ns.MacroSpells.HighestKnown(REBIRTH)
    local revive = ns.MacroSpells.HighestKnown(REVIVE)
    if not rebirth or not revive then
        return nil, "Learn Rebirth and Revive to create this macro."
    end
    local rebirthName = ns.MacroSpells.Name(rebirth.spell)
    local reviveName = ns.MacroSpells.Name(revive.spell)
    if not rebirthName or not reviveName then
        local missing = {}
        if not rebirthName then missing[#missing + 1] = rebirth.spell end
        if not reviveName then missing[#missing + 1] = revive.spell end
        return nil, "Waiting for localized spell data.", missing
    end
    return table.concat({
        "#showtooltip [combat] " .. rebirthName .. "; " .. reviveName,
        "/cast [combat] " .. rebirthName,
        "/cast [nocombat] " .. reviveName,
    }, "\n")
end

local function BuildThorns()
    local tier = ns.MacroSpells.HighestKnown(THORNS)
    if not tier then return nil, "Learn Thorns to create this macro." end
    local name = ns.MacroSpells.Name(tier.spell)
    if not name then return nil, "Waiting for localized spell data.", { tier.spell } end
    return table.concat({
        "#showtooltip " .. name,
        "/cast [@player] " .. name,
    }, "\n")
end

ns.RegisterMacroProvider("druidRebirth", {
    settingsKey = "druidRebirthMacro",
    class = "DRUID",
    classLabel = "Druid",
    defaultName = "Rebirth",
    Build = BuildRebirth,
})

ns.RegisterMacroProvider("druidThorns", {
    settingsKey = "druidThornsMacro",
    class = "DRUID",
    classLabel = "Druid",
    defaultName = "Thorns",
    Build = BuildThorns,
})

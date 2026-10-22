local _, ns = ...

-- Fill with verified { level = ..., spell = ... } tiers, strongest first.
local TIERS = {}

local function Build()
    local tier = ns.MacroSpells.HighestKnown(TIERS)
    if not tier then
        return nil, "Learn a supported spell to create this macro."
    end
    local name = ns.MacroSpells.Name(tier.spell)
    if not name then
        return nil, "Waiting for localized spell data.", { tier.spell }
    end
    -- Unranked names make the client use the highest learned rank.
    return table.concat({ "#showtooltip", "/cast " .. name }, "\n")
end

-- Replace metadata; add matching settings defaults and a TOC entry. Account
-- providers also pass scope = "account" and class = "ALL", and declare refresh
-- events only when the body depends on non-spell data.
ns.RegisterMacroProvider("example", {
    settingsKey = "exampleMacro",
    class = "CLASS_TOKEN",
    classLabel = "Example class",
    defaultName = "Example Macro",
    Build = Build,
})

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
    return table.concat({ "#showtooltip", "/cast " .. name }, "\n")
end

-- Replace metadata; add matching settings/character defaults and a TOC entry.
ns.RegisterMacroProvider("example", {
    settingsKey = "exampleMacro",
    class = "CLASS_TOKEN",
    classLabel = "Example class",
    defaultName = "Example Macro",
    Build = Build,
})

-- Run from the EUI root: lua CalmEUITweaks/tests/WhatsTraining.lua
local unpackValues = table.unpack or unpack
local queue, module, eventFrame = {}, nil, nil
local enabled, style, passed = true, "eui", 0

local function check(condition, message)
    assert(condition, message)
    passed = passed + 1
end

local function expect(text, r, g, b, a, message)
    local expected = {r, g, b, a}
    for i = 1, 4 do
        assert(type(text.color[i]) == "number"
            and math.abs(text.color[i] - expected[i]) < 0.000001,
            (message or "RGBA mismatch") .. " (component " .. i .. ")")
    end
    passed = passed + 1
end

C_Timer = {After = function(delay, callback)
    assert(delay == 0, "Only next-turn scheduling is allowed")
    queue[#queue + 1] = callback
end}

function hooksecurefunc(object, method, callback)
    local original = object[method]
    assert(type(original) == "function", "Cannot hook a missing method")
    object[method] = function(...)
        original(...)
        callback(...)
    end
end

local function frame()
    return {
        scripts = {}, events = {},
        SetScript = function(self, script, callback) self.scripts[script] = callback end,
        HookScript = function(self, script, callback)
            local original = self.scripts[script]
            self.scripts[script] = function(...)
                if original then original(...) end
                callback(...)
            end
        end,
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        SetHeight = function() end,
    }
end

function CreateFrame(kind)
    assert(kind == "Frame")
    eventFrame = frame()
    return eventFrame
end

local function text(r, g, b, a)
    return {
        color = {r, g, b, a}, fontWrites = 0, textWrites = 0,
        GetText = function(self) return self.value end,
        GetTextColor = function(self) return unpackValues(self.color) end,
        SetTextColor = function(self, red, green, blue, alpha)
            self.color = {red, green, blue, alpha or 1}
        end,
        SetText = function(self, value)
            self.textWrites = self.textWrites + 1
            self.value = value
        end,
        SetFormattedText = function(self, fmt, ...)
            self.value = string.format(fmt, ...)
        end,
        SetFontObject = function(self) self.fontWrites = self.fontWrites + 1 end,
        IsObjectType = function(_, kind) return kind == "FontString" end,
    }
end

local function regions(...)
    local values = {...}
    return {GetRegions = function() return unpackValues(values) end}
end

local ns = {
    ready = true,
    GetSettings = function(key)
        assert(key == "whatsTraining")
        return {enabled = enabled}
    end,
}
local reports = {}
geterrorhandler = function() return function(err) reports[#reports + 1] = err end end
assert(loadfile("CalmEUITweaks/core/Bootstrap.lua"))("CalmEUITweaks", ns)
local registerModule = ns.RegisterModule
ns.RegisterModule = function(key, value)
    registerModule(key, value)
    module = value
end

EllesmereUI = {
    GetBlizzWindowStyle = function(key)
        assert(key == "playerspells")
        return style
    end,
    _WSkinRefreshStyles = function() end,
    _WSkinRefreshLooks = function() end,
    DisableAllBlizzWindowSkins = function() style = "off" end,
}

assert(loadfile("CalmEUITweaks/core/AnchorEvents.lua"))("CalmEUITweaks", ns)
assert(loadfile("CalmEUITweaks/compatability/WhatsTraining.lua"))("CalmEUITweaks", ns)

local function drain()
    local turns = 0
    while #queue > 0 do
        turns = turns + 1
        assert(turns < 10, "Timer feedback loop")
        local work = queue
        queue = {}
        for _, callback in ipairs(work) do callback() end
    end
end

module:Initialize()
drain()
check(module:GetStatus():find("Waiting") ~= nil, "Missing frame must wait safely")
check(eventFrame == nil, "Missing optional addon needs no world event frame")
module:OnAddonLoaded("UnrelatedAddon")
check(#queue == 0, "Unrelated addon loads schedule no theme work")

-- Absent title/total must not truncate later optional fields or sparse rows.
WhatsTrainingFrame = frame()
local main = WhatsTrainingFrame
main.content = frame()
main.character = text(0.19, 0.12, 0.06, 0.37)
main.empty = text(0.4, 0.4, 0.4, 0.44)
main.continues = text(0.19, 0.12, 0.06, 0.41)
main.pagingControls = {PageText = text(0.19, 0.12, 0.06, 0.42)}
main.rows = {[3] = {name = text(0.08, 0.04, 0.02, 0.28),
    rank = text(0.5, 0.1, 0.05, 0.2)}}
main.showKnown = {Text = text(0.19, 0.12, 0.06, 0)}
local column = text(0.08, 0.04, 0.02, 0.72)
main.columns = regions(column)
module:OnAddonLoaded("WhatsTraining")
drain()
expect(main.character, 1, 1, 1, 0.37, "Primary/sparse page fields")
expect(main.empty, 0.5, 0.5, 0.5, 0.44, "Muted")
expect(main.rows[3].name, 1, 1, 1, 0.28, "Strong/sparse rows")
expect(main.rows[3].rank, 1, 0.55, 0.45, 0.2, "Danger")
expect(main.showKnown.Text, 1, 1, 1, 0, "Zero alpha must survive")
expect(column, 1, 1, 1, 0.72, "Column regions")
expect(main.continues, 1, 1, 1, 0.41, "Main continuation")
expect(main.pagingControls.PageText, 1, 1, 1, 0.42, "Main pagination")

-- A later-created weapon page must be discovered by the show callback.
main.weaponPage = frame()
local weapon = main.weaponPage
weapon.content = frame()
weapon.footer = text(0.1, 0.4, 0.1, 0.61)
weapon.continues = text(0.19, 0.12, 0.06, 0.43)
weapon.pagingControls = {PageText = text(0.19, 0.12, 0.06, 0.46)}
weapon.headings = {{heading = text(0.8, 0.6, 0.1, 0.77),
    spell = {isHeader = true, npc = true}}}
weapon.cityLegend = {entries = {{cityIcons = {{name = text(0.19, 0.12, 0.06, 0.9)}}}}}
local listColumn = text(0.19, 0.12, 0.06, 0.63)
weapon.listColumns = regions(listColumn)
local groups = {"weaponRows", "listRows", "cityTrainers", "skillTrainers",
    "tiles", "blocks", "cells", "groupHeaders"}
for _, key in ipairs(groups) do
    weapon[key] = {{count = text(0.19, 0.12, 0.06, 0.45)}}
end
main.scripts.OnShow(main)
drain()
expect(weapon.footer, 0.65, 1, 0.40, 0.61, "Success on weapon page")
expect(weapon.headings[1].heading, 1, 1, 1, 0.77, "Trainer heading override")
expect(weapon.cityLegend.entries[1].cityIcons[1].name, 1, 1, 1, 0.9, "City legend")
expect(listColumn, 1, 1, 1, 0.63, "List column regions")
expect(weapon.continues, 1, 1, 1, 0.43, "Weapon continuation")
expect(weapon.pagingControls.PageText, 1, 1, 1, 0.46, "Optional weapon pagination")
for _, key in ipairs(groups) do
    expect(weapon[key][1].count, 1, 1, 1, 0.45, key)
end
check(main.character.fontWrites == 0, "Compatibility must not change fonts")

main.character:SetText("text-only update")
main.character:SetFormattedText("rank %d", 2)
drain()
enabled = false
module:ApplySettings()
expect(main.character, 0.19, 0.12, 0.06, 0.37, "Text-only updates must retain native color")
expect(weapon.headings[1].heading, 0.8, 0.6, 0.1, 0.77, "Trainer native restoration")
expect(main.continues, 0.19, 0.12, 0.06, 0.41, "Disable restores main continuation")
expect(main.pagingControls.PageText, 0.19, 0.12, 0.06, 0.42, "Disable restores main pagination")
expect(weapon.continues, 0.19, 0.12, 0.06, 0.43, "Disable restores weapon continuation")
expect(weapon.pagingControls.PageText, 0.19, 0.12, 0.06, 0.46, "Disable restores weapon pagination")
check(eventFrame == nil or next(eventFrame.events) == nil, "Disabled module has no world subscriptions")
check(module:GetStatus() == "Disabled", "Disabled status")

main.character:SetTextColor(0.08, 0.04, 0.02, 0.52)
enabled = true
module:ApplySettings()
drain()
expect(main.character, 1, 1, 1, 0.52, "Native updates while disabled")
main.character:SetTextColor(0.1, 0.4, 0.1, 0.24)
main.character:SetText("new native category")
drain()
expect(main.character, 0.65, 1, 0.40, 0.24, "Latest native semantic category")
EllesmereUI.DisableAllBlizzWindowSkins()
drain()
expect(main.character, 0.1, 0.4, 0.1, 0.24, "Skin-off restores latest native RGBA")
style = "modern"
EllesmereUI._WSkinRefreshStyles()
drain()
expect(main.character, 0.65, 1, 0.40, 0.24, "Modern style supported")
for _, unsupported in ipairs({"blizzard", "unexpected"}) do
    style = unsupported
    EllesmereUI._WSkinRefreshStyles()
    drain()
    expect(main.character, 0.1, 0.4, 0.1, 0.24, unsupported .. " must restore")
end
style = "eui"
EllesmereUI._WSkinRefreshStyles()
drain()

-- A foreign write must win if disabled before queued recoloring runs.
main.character:SetTextColor(0.7, 0.7, 0.8, 0.18)
enabled = false
module:ApplySettings()
drain()
expect(main.character, 0.7, 0.7, 0.8, 0.18, "External ownership")
main.character:SetTextColor(1, 1, 1, 0.6)
enabled = true
module:ApplySettings()
drain()
enabled = false
module:ApplySettings()
expect(main.character, 1, 1, 1, 0.6, "Native palette-matching writes remain native")

enabled = true
module:ApplySettings()
drain()
weapon.listRows = {{name = text(0.19, 0.12, 0.06, 0.8),
    title = text(0.75, 0.8, 0.9, 0.5)}}
weapon.content:SetHeight(200)
weapon.content:SetHeight(300)
weapon.scripts.OnSizeChanged(weapon)
module:OnAddonLoaded("Blizzard_PlayerSpells")
check(#queue == 1, "Layout/show/world updates must coalesce")
drain()
expect(weapon.listRows[1].name, 1, 1, 1, 0.8, "Lazy rows")
expect(weapon.listRows[1].title, 0.75, 0.8, 0.9, 0.5, "Unknown native colors untouched")

-- Native Forever theme values at fusionpit/WhatsTraining f459446.
local soon = text(0.08, 0.22, 0.50, 0.32)
local unavailable = text(0.30, 0.10, 0.05, 0.33)
local levelUnavailable = text(0.45, 0.09, 0.04, 0.34)
local weaponUnavailable = text(0.55, 0.12, 0.05, 0.35)
local available = text(0.10, 0.38, 0.05, 0.36)
local nativeInline = "Rank 2 |cff301f0f20|r |cff14388022|r |cff73170a30|r"
local darkInline = "Rank 2 |cffffffff20|r |cff8cd6ff22|r |cffff8c7330|r"
local rank = text(0.19, 0.12, 0.06, 0.47)
rank.value = nativeInline
main.cells = {{rank = rank, level = soon}, {title = unavailable},
    {level = levelUnavailable}, {rank = weaponUnavailable}, {name = available}}
local weaponRank = text(0.75, 0.8, 0.9, 0.48)
weaponRank.value = "Weapon |cff4d1a0d50|r"
weapon.cells = {{rank = weaponRank}}
module:ApplySettings()
drain()
expect(soon, 0.55, 0.84, 1, 0.32, "Native next-level blue remains blue")
expect(unavailable, 1, 0.55, 0.45, 0.33, "Native unavailable header")
expect(levelUnavailable, 1, 0.55, 0.45, 0.34, "Native unavailable level")
expect(weaponUnavailable, 1, 0.55, 0.45, 0.35, "Native unavailable weapon")
expect(available, 0.65, 1, 0.40, 0.36, "Native available green remains green")
check(rank.value == darkInline, "Inline rank level colors bypass the outer color")
check(weaponRank.value == "Weapon |cffff8c7350|r", "Inline translation on weapon cells")
expect(weaponRank, 0.75, 0.8, 0.9, 0.48, "Inline translation does not require a known outer color")
expect(rank, 1, 1, 1, 0.47, "Inline translation retains outer RGBA")
local writes = rank.textWrites
for i = 1, 3 do module:ApplySettings(); drain() end
check(rank.textWrites == writes and rank.value == darkInline, "Repeated apply is idempotent")
check(#queue == 0, "Own SetText posthooks must not schedule feedback")

local nextNative = "Rank 3 |cff14388024|r"
rank:SetText(nextNative)
check(#queue == 0, "Text-only native update adapts locally without scheduling a tree walk")
drain()
check(rank.value == "Rank 3 |cff8cd6ff24|r", "Text-only native inline update")
enabled = false
module:ApplySettings()
check(rank.value == nextNative, "Disable restores latest native string, not first string")
check(weaponRank.value == "Weapon |cff4d1a0d50|r", "Disable restores weapon native string")
expect(soon, 0.08, 0.22, 0.50, 0.32, "Disable restores native blue RGBA")
expect(unavailable, 0.30, 0.10, 0.05, 0.33, "Disable restores native unavailable RGBA")

rank:SetFormattedText("Rank %d |cff73170a%d|r", 4, 40)
enabled = true
module:ApplySettings()
drain()
check(rank.value == "Rank 4 |cffff8c7340|r", "Formatted native writes while disabled")
rank:SetFormattedText("Rank %d |cff143880%d|r", 5, 42)
drain()
check(rank.value == "Rank 5 |cff8cd6ff42|r", "Formatted text-only updates while active")
EllesmereUI.DisableAllBlizzWindowSkins()
drain()
check(rank.value == "Rank 5 |cff14388042|r", "Skin-off restores latest formatted native string")
check(weaponRank.value == "Weapon |cff4d1a0d50|r", "Skin-off restores weapon string")
expect(main.continues, 0.19, 0.12, 0.06, 0.41, "Skin-off main continuation")
expect(main.pagingControls.PageText, 0.19, 0.12, 0.06, 0.42, "Skin-off main pagination")
expect(weapon.continues, 0.19, 0.12, 0.06, 0.43, "Skin-off weapon continuation")
expect(weapon.pagingControls.PageText, 0.19, 0.12, 0.06, 0.46, "Skin-off weapon pagination")
rank:SetText("Inactive |cff301f0f43|r")
drain()
check(rank.value == "Inactive |cff301f0f43|r", "Skin-off native text stays native")
style = "modern"
EllesmereUI._WSkinRefreshStyles()
drain()
check(rank.value == "Inactive |cffffffff43|r", "Style re-enable adapts latest native string")

local markup = "|Hspell:123|h[Spell]|h |Ticon:16|t |Aatlas:16:16|a "
    .. "|c7F301F0Fbody|r |cff140a05strong|r |cff666666dim|r "
    .. "|cff1a610dnow|r |cff143880soon|r |cff4d1a0dlater|r |cff8c1f0dweapon|r "
    .. "|cffffd100gold|r |cff00ff00green|r |cff8cd6ffdark|r "
    .. "||cff301f0fliteral||r |||cff301f0fescaped pipe then color|r"
local translatedMarkup = "|Hspell:123|h[Spell]|h |Ticon:16|t |Aatlas:16:16|a "
    .. "|c7Fffffffbody|r |cffffffffstrong|r |cff808080dim|r "
    .. "|cffa6ff66now|r |cff8cd6ffsoon|r |cffff8c73later|r |cffff8c73weapon|r "
    .. "|cffffd100gold|r |cff00ff00green|r |cff8cd6ffdark|r "
    .. "||cff301f0fliteral||r |||cffffffffescaped pipe then color|r"
rank:SetText(markup)
drain()
check(rank.value == translatedMarkup, "Only exact known RGB codes change; alpha/markup/categories survive")
check(rank.fontWrites == 0 and weaponRank.fontWrites == 0, "Inline fix never forces fonts")
enabled = false
module:ApplySettings()
check(rank.value == markup, "Disable restores all original markup exactly")
enabled = true
module:ApplySettings()
drain()
rank:SetText("External |cff301f0fnative|r")
enabled = false
module:ApplySettings()
drain()
check(rank.value == "External |cff301f0fnative|r", "External setter wins before queued adaptation")
enabled = true
module:ApplySettings()
drain()
rank.value = "Unhooked external output"
enabled = false
module:ApplySettings()
check(rank.value == "Unhooked external output", "Restoration requires current string ownership")
enabled = true
module:ApplySettings()
drain()
rank:SetText(nativeInline)
drain()
rank:SetText(darkInline)
enabled = false
module:ApplySettings()
drain()
check(rank.value == darkInline, "Native writes matching our output must not restore stale text")
enabled = true
module:ApplySettings()
drain()
rank:SetText(nativeInline)
drain()
rank:SetText(nil)
drain()
enabled = false
module:ApplySettings()
check(rank.value == nil, "Native nil text clears stale string ownership")
enabled = true
module:ApplySettings()
drain()
rank:SetText("")
drain()
enabled = false
module:ApplySettings()
check(rank.value == "", "Native empty strings survive disable")
enabled = true
module:ApplySettings()
drain()

rank:SetText(nativeInline)
drain()
rank.value = nextNative
module:ApplySettings()
drain()
check(rank.value == "Rank 3 |cff8cd6ff24|r", "Apply discovers unhooked native string changes")
enabled = false
module:ApplySettings()
check(rank.value == nextNative, "Discovered native string becomes the latest restoration target")
enabled = true
module:ApplySettings()
drain()
rank:SetText(nativeInline)
drain()
local nativeGetter = rank.GetText
rank.GetText = function() error("Unavailable text") end
rank:SetText("Unreadable external update")
drain()
check(rank.value == "Unreadable external update", "Failing native reads are guarded")
rank.GetText = nativeGetter
rank.value = darkInline
enabled = false
module:ApplySettings()
check(rank.value == darkInline, "Unreadable external writes still relinquish old ownership")
enabled = true
module:ApplySettings()
drain()

-- The native spellbook can load after WT and use colors different from EUI's defaults.
local book = frame()
local nativePageText = text(0.2, 0.6, 0.8, 0.04)
book.PagedSpellsFrame = {PagingControls = {PageText = nativePageText}}
PlayerSpellsFrame = {SpellBookFrame = book}
local darkBody = text(0.9, 0.9, 0.9, 0.31)
local darkStrong = text(1, 1, 1, 0.32)
local darkHeading = text(0.95, 0.9, 0.8, 0.33)
local darkMuted = text(0.5, 0.5, 0.5, 0.34)
local darkStatus = text(0.65, 1, 0.4, 0.35)
main.tiles = {{name = darkBody, rank = darkStrong, heading = darkHeading,
    count = darkMuted, level = darkStatus}}
local nativeDarkInline = "|c7Fe6e6e6body|r |cffffffffstrong|r |cfff2e6ccheader|r "
    .. "|cff808080dim|r |cffa6ff66now|r |cff8cd6ffsoon|r |cffff8c73later|r"
darkBody.value = nativeDarkInline
rank:SetText(nativeInline)
module:OnAddonLoaded("Blizzard_PlayerSpells")
drain()
expect(rank, 0.2, 0.6, 0.8, 0.47, "Late spellbook supplies the active text color")
expect(darkBody, 0.2, 0.6, 0.8, 0.31, "WT dark body follows the native theme")
expect(darkStrong, 0.2, 0.6, 0.8, 0.32, "WT dark strong text follows the native theme")
expect(darkHeading, 0.2, 0.6, 0.8, 0.33, "WT dark headings follow the native theme")
expect(darkMuted, 0.5, 0.5, 0.5, 0.34, "WT muted semantics survive")
expect(darkStatus, 0.65, 1, 0.4, 0.35, "WT availability semantics survive")
check(rank.value == "Rank 2 |cff3399cc20|r |cff8cd6ff22|r |cffff8c7330|r",
    "Parchment inline text follows the active theme")
check(darkBody.value == "|c7F3399ccbody|r |cff3399ccstrong|r |cff3399ccheader|r "
    .. "|cff808080dim|r |cffa6ff66now|r |cff8cd6ffsoon|r |cffff8c73later|r",
    "Already dark inline text follows the theme and keeps alpha/status tones")

nativePageText:SetTextColor(0.8, 0.6, 0.2, 0.01)
EllesmereUI._WSkinRefreshLooks()
book.scripts.OnShow(book)
check(#queue == 1, "Native recolor, look refresh and book show coalesce")
drain()
expect(rank, 0.8, 0.6, 0.2, 0.47, "Native recolor preserves WT alpha")
check(rank.value == "Rank 2 |cffcc993320|r |cff8cd6ff22|r |cffff8c7330|r",
    "Native recolor translates from the original string")
expect(weapon.headings[1].heading, 0.8, 0.6, 0.2, 0.77, "Weapon trainers follow live recolors")
expect(nativePageText, 0.8, 0.6, 0.2, 0.01, "Theme source is read without mutation")
check(nativePageText.fontWrites == 0, "Native spellbook fonts are untouched")

style = "eui"
nativePageText.color = {0.6, 0.8, 0.2, 0.02}
EllesmereUI._WSkinRefreshStyles()
drain()
expect(darkBody, 0.6, 0.8, 0.2, 0.31, "Switching Modern to EUI refreshes the palette")
check(module:GetStatus() == "Active: eui spellbook theme", "Status identifies the active style")
style = "modern"
nativePageText.color = {0.2, 0.6, 0.8, 0.04}
EllesmereUI._WSkinRefreshLooks()
drain()
expect(darkBody, 0.2, 0.6, 0.8, 0.31, "Modern look refresh re-reads native colors")
check(module:GetStatus() == "Active: modern spellbook theme", "Modern status")

EllesmereUI.DisableAllBlizzWindowSkins()
drain()
expect(darkBody, 0.9, 0.9, 0.9, 0.31, "Skin-off restores WT's own dark body")
expect(darkStrong, 1, 1, 1, 0.32, "Skin-off restores WT's own strong color")
expect(darkHeading, 0.95, 0.9, 0.8, 0.33, "Skin-off restores WT's own heading")
check(darkBody.value == nativeDarkInline, "Skin-off restores WT dark markup exactly")
check(rank.value == nativeInline, "Skin-off restores parchment markup after multiple palettes")
style = "eui"
EllesmereUI._WSkinRefreshStyles()
drain()
enabled = false
module:ApplySettings()
nativePageText:SetTextColor(0.8, 0.6, 0.2, 0.01)
check(#queue == 0, "Disabled native theme hooks are inert")
expect(darkBody, 0.9, 0.9, 0.9, 0.31, "Disabling restores WT dark colors")
enabled = true
module:ApplySettings()
drain()
expect(darkBody, 0.8, 0.6, 0.2, 0.31, "Re-enabling uses the latest theme")

local nativeColorGetter = nativePageText.GetTextColor
nativePageText.GetTextColor = function() error("Unavailable theme color") end
EllesmereUI._WSkinRefreshLooks()
drain()
expect(darkBody, 1, 1, 1, 0.31, "Unreadable native theme uses EUI's verified default")
check(ns.errors.whatsTraining == nil, "Unreadable theme getter is guarded")
nativePageText.GetTextColor = nativeColorGetter
local secret = {}
issecretvalue = function(value) return value == secret end
nativePageText.color = {secret, 0.6, 0.8, 0.04}
EllesmereUI._WSkinRefreshLooks()
drain()
expect(darkBody, 1, 1, 1, 0.31, "Secret native colors are not used")
issecretvalue = nil
for _, invalid in ipairs({{0/0, 0.6, 0.8, 1}, {2, 0.6, 0.8, 1},
    {0.19, 0.12, 0.06, 1}}) do
    nativePageText.color = invalid
    EllesmereUI._WSkinRefreshLooks()
    drain()
    expect(darkBody, 1, 1, 1, 0.31, "Invalid or unskinned native color falls back")
end
PlayerSpellsFrame = nil
EllesmereUI._WSkinRefreshStyles()
drain()
expect(darkBody, 1, 1, 1, 0.31, "Absent native controls use EUI's verified default")
local nativeStyleGetter = EllesmereUI.GetBlizzWindowStyle
EllesmereUI.GetBlizzWindowStyle = function() error("Unavailable style") end
module:ApplySettings()
drain()
expect(darkBody, 0.9, 0.9, 0.9, 0.31, "Unavailable style restores native text")
EllesmereUI.GetBlizzWindowStyle = nativeStyleGetter
module:ApplySettings()
drain()

module:ApplySettings()
ns.ready = false
drain()
main.character:SetText("not ready")
module:ApplySettings()
module:OnAddonLoaded("Blizzard_PlayerSpells")
check(#queue == 0, "Not-ready callbacks and queued work must be inert")
ns.ready = true
local eui = EllesmereUI
EllesmereUI = nil
module:ApplySettings()
drain()
expect(weapon.listRows[1].name, 0.19, 0.12, 0.06, 0.8, "Missing EUI restores owned colors")
EllesmereUI = {}
module:ApplySettings()
drain()
check(module:GetStatus():find("Inactive") ~= nil, "Missing style API")
EllesmereUI = eui
WhatsTrainingFrame = nil
module:ApplySettings()
drain()
check(module:GetStatus():find("Waiting") ~= nil, "Missing addon after activation")

WhatsTrainingFrame = main
module:ApplySettings(); drain()
local getRegions = main.columns.GetRegions
main.columns.GetRegions = function() error("region refresh failed", 0) end
module:ApplySettings()
check(pcall(drain), "Deferred adaptation failures must not escape the timer")
check(ns.GetStatus("whatsTraining"):find("region refresh failed", 1, true), "Deferred failure replaces active status")
module:ApplySettings()
check(ns.errors.whatsTraining ~= nil, "Scheduling must retain the deferred error")
drain()
check(#reports == 1, "Repeated adaptation failures must report once")
main.columns.GetRegions = getRegions
module:ApplySettings()
check(ns.errors.whatsTraining ~= nil, "Recovery must wait for actual execution")
drain()
check(ns.errors.whatsTraining == nil and module:GetStatus():find("Active"), "Successful adaptation clears the error")
local timer = C_Timer
C_Timer = nil
main.columns.GetRegions = function() error("synchronous refresh failed", 0) end
check(pcall(module.ApplySettings, module) and ns.errors.whatsTraining ~= nil, "Timer-less execution uses the same error boundary")
main.columns.GetRegions = getRegions
module:ApplySettings()
check(ns.errors.whatsTraining == nil, "Timer-less recovery clears the error")
C_Timer = timer

print("PASS: WhatsTraining (" .. passed .. " assertions)")

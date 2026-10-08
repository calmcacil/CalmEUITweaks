-- Run from the parent containing CalmEUITweaks with Lua 5.1.
local unpackValues = unpack or table.unpack
local passed, queue, module = 0, {}, nil
local enabled, style = true, "eui"
local fontPath, fontFlag, fontShadow = "EUI.ttf", "", true

local function check(value, message)
    assert(value, message)
    passed = passed + 1
end

local function equal(actual, expected, message)
    check(actual == expected, message or tostring(actual) .. " ~= " .. tostring(expected))
end

C_Timer = {After = function(_, callback) queue[#queue + 1] = callback end}
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end

local function drain()
    local turns = 0
    while #queue > 0 do
        turns = turns + 1
        assert(turns < 10, "Theme timer feedback loop")
        local work = queue
        queue = {}
        for _, callback in ipairs(work) do callback() end
    end
end

local function region(kind)
    local value = {alpha = 1, shown = true, kind = kind, points = {}, vertex = {1, 1, 1, 1}}
    function value:IsObjectType(expected) return self.kind == expected end
    function value:GetAlpha() return self.alpha end
    function value:SetAlpha(alpha) self.alpha = alpha end
    function value:IsShown() return self.shown end
    function value:SetShown(shown) self.shown = shown end
    function value:GetVertexColor() return unpackValues(self.vertex) end
    function value:SetVertexColor(...) self.vertex = {...} end
    function value:GetDesaturation() return self.desaturation or 0 end
    function value:SetDesaturation(value) self.desaturation = value end
    function value:GetAtlas() return self.atlas end
    function value:SetAtlas(value) self.atlas = value end
    function value:GetTexture() return self.texture end
    function value:SetTexture(value) self.texture = value end
    function value:GetBlendMode() return self.blend or "BLEND" end
    function value:SetBlendMode(value) self.blend = value end
    function value:GetTexCoord() return unpackValues(self.coords or {0, 1, 0, 1}) end
    function value:SetTexCoord(...) self.coords = {...} end
    function value:AddMaskTexture(mask) self.mask = mask end
    value.layoutWrites = 0
    function value:SetAllPoints(anchor) self.anchor = anchor; self.layoutWrites = self.layoutWrites + 1 end
    function value:ClearAllPoints() self.points = {}; self.layoutWrites = self.layoutWrites + 1 end
    function value:SetPoint(...) self.points[#self.points + 1] = {...}; self.layoutWrites = self.layoutWrites + 1 end
    function value:SetHeight(height) self.height = height end
    function value:SetWidth(width) self.width = width end
    function value:GetWidth() return self.width or 0 end
    function value:GetHeight() return self.height or 0 end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:SetColorTexture(...) self.color = {...} end
    function value:GetDrawLayer() return self.layer or "BACKGROUND" end
    return value
end

local function text(size)
    local value = region("FontString")
    value.color = {0.9, 0.9, 0.9, 0.7}
    value.font = {"Native.ttf", size or 14, "OUTLINE"}
    -- The object and the instance have different sizes, as in real WT labels.
    value.fontObject = {font = {"Native.ttf", 12, "OUTLINE"}, shadow = {0.2, 0.3, 0.4, 0.5}, offset = {2, -2}}
    value.shadow, value.offset = {0.2, 0.3, 0.4, 0.5}, {2, -2}
    value.fontWrites = 0
    value.fontReads = 0
    function value:GetTextColor() return unpackValues(self.color) end
    function value:SetTextColor(...) self.color = {...} end
    function value:GetText() return self.value end
    function value:SetText(str) self.value = str end
    function value:GetFont() self.fontReads = self.fontReads + 1; return unpackValues(self.font) end
    function value:SetFont(...)
        self.font = {...}
        self.fontWrites = self.fontWrites + 1
        return true
    end
    function value:GetFontObject() return self.fontObject end
    function value:SetFontObject(object)
        self.fontObject = object
        self.font = {unpackValues(object.font)}
        self.shadow = {unpackValues(object.shadow)}
        self.offset = {unpackValues(object.offset)}
    end
    function value:GetShadowColor() return unpackValues(self.shadow) end
    function value:SetShadowColor(...) self.shadow = {...} end
    function value:GetShadowOffset() return unpackValues(self.offset) end
    function value:SetShadowOffset(...) self.offset = {...} end
    return value
end

local function frame(parent)
    local value = region("Frame")
    value.children, value.regions, value.scripts = {}, {}, {}
    if parent then parent.children[#parent.children + 1] = value end
    function value:GetRegions() return unpackValues(self.regions) end
    function value:GetChildren() return unpackValues(self.children) end
    function value:CreateTexture(_, layer)
        local texture = region("Texture")
        texture.layer = layer
        self.regions[#self.regions + 1] = texture
        return texture
    end
    function value:CreateMaskTexture()
        local mask = region("MaskTexture")
        self.regions[#self.regions + 1] = mask
        return mask
    end
    function value:CreateFontString()
        local label = text()
        self.regions[#self.regions + 1] = label
        return label
    end
    function value:SetScript(script, callback) self.scripts[script] = callback end
    function value:HookScript(script, callback)
        local original = self.scripts[script]
        self.scripts[script] = function(...)
            if original then original(...) end
            callback(...)
        end
    end
    function value:Fire(script, ...) if self.scripts[script] then self.scripts[script](self, ...) end end
    function value:Show() self.shown = true; self:Fire("OnShow") end
    function value:Hide() self.shown = false; self:Fire("OnHide") end
    function value:RegisterEvent() end
    function value:UnregisterEvent() end
    function value:IsEnabled() return self.enabled ~= false end
    function value:SetEnabled(flag) self.enabled = flag; self:Fire(flag and "OnEnable" or "OnDisable") end
    return value
end
CreateFrame = function() return frame() end

local shadowObject = {font = {"Template.ttf", 12, ""}, shadow = {0, 0, 0, 1}, offset = {1, -1}}
local noShadowObject = {font = {"Template.ttf", 12, ""}, shadow = {0, 0, 0, 0}, offset = {0, 0}}
EllesmereUI = {
    ELLESMERE_GREEN = {r = 0.1, g = 0.8, b = 0.6},
    GetBlizzWindowStyle = function(key) assert(key == "playerspells"); return style end,
    GetThirdPartySkinStyle = function() error("A spellbook tab must not use third-party majority style") end,
    GetFontPath = function(key) assert(key == "blizzardSkin"); return fontPath end,
    GetFontOutlineFlag = function(key) assert(key == "blizzardSkin"); return fontFlag end,
    GetFontUseShadow = function(key) assert(key == "blizzardSkin"); return fontShadow end,
    PrimeFontShadow = function(label, shadow) label:SetFontObject(shadow and shadowObject or noShadowObject) end,
    _WSkinRefreshStyles = function() end,
    _WSkinRefreshLooks = function() end,
    RepointAllDBs = function() end,
}
EllesmereUIDB = {blizzWindowModernDefault = {r = 0.7, g = 0.5, b = 0.3, a = 0.45}}
local ns = {ready = true, errors = {},
    GetSettings = function() return {enabled = enabled} end,
    RegisterModule = function(_, value) module = value end,
    SetStatus = function() end,
}
-- Separate assignment lets callbacks capture the local namespace.
ns.ClearError = function(key) ns.errors[key] = nil end
ns.ReportError = function(key, err) ns.errors[key] = err end
assert(loadfile("CalmEUITweaks/core/AnchorEvents.lua"))("CalmEUITweaks", ns)
assert(loadfile("CalmEUITweaks/compatability/WhatsTraining.lua"))("CalmEUITweaks", ns)

PlayerSpellsFrame = frame()
local book = frame(PlayerSpellsFrame)
PlayerSpellsFrame.SpellBookFrame = book
book.CategoryTabSystem = frame(book)
local categoryTabs = book.CategoryTabSystem
local nativeTab = frame(categoryTabs)
nativeTab.Icon = nativeTab:CreateTexture(nil, "ARTWORK")
nativeTab.Icon:SetTexture("NativeCategoryIcon")
for _, key in ipairs({"SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow"}) do
    nativeTab[key] = nativeTab:CreateTexture(nil, "ARTWORK")
end
function nativeTab:SetSquareMode()
    self.SquareBackground:SetAtlas("spellbook-Tab-Frame-C60")
    self.SquareBackgroundActive:SetAtlas("spellbook-Tab-Frame-Glow-C60")
    self.SquareBackgroundActiveGlow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60")
end
function nativeTab:Init()
    for _, key in ipairs({"SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow"}) do
        self[key] = self:CreateTexture(nil, "ARTWORK")
    end
    self:SetSquareMode()
end
nativeTab:SetAlpha(0.85)
categoryTabs.selectedTabID = 1
categoryTabs.tabs = {nativeTab}
function categoryTabs:GetTabButton(id) return self.tabs[id] end
function categoryTabs:SetTabVisuallySelected(id) self.selectedTabID = id end
book.PagedSpellsFrame = frame(book)
book.PagedSpellsFrame:SetAlpha(0.8)
book.PagedSpellsFrame.PagingControls = {PageText = text()}
book.PagedSpellsFrame.PagingControls.PageText.color = {1, 1, 1, 1}
local spellItem = frame(book.PagedSpellsFrame)
spellItem.Name, spellItem.SubName = text(20), text(11)
local spellObject = {font = {"Spell.ttf", 20, ""}, shadow = {0, 0, 0, 0}, offset = {0, 0}}
local rankObject = {font = {"Rank.ttf", 11, ""}, shadow = {0, 0, 0, 1}, offset = {1, -1}}
spellItem.Name.font, spellItem.Name.fontObject = {"Spell.ttf", 20, ""}, spellObject
spellItem.Name.shadow, spellItem.Name.offset = spellObject.shadow, spellObject.offset
spellItem.SubName.font, spellItem.SubName.fontObject = {"Rank.ttf", 11, ""}, rankObject
spellItem.SubName.shadow, spellItem.SubName.offset = rankObject.shadow, rankObject.offset
spellItem.Button = frame(spellItem)
spellItem.Button.Icon = spellItem.Button:CreateTexture(nil, "ARTWORK")
spellItem.Button.Icon:SetSize(36, 36)
spellItem.Button.Border = spellItem.Button:CreateTexture(nil, "OVERLAY")
spellItem.Button.Border:SetAtlas("spellbook-IconFrame")
spellItem.Button.Border:SetSize(54, 54)
spellItem.Button.Border:SetVertexColor(0.8, 0.6, 0.4, 1)
function book.PagedSpellsFrame:EnumerateFrames() return ipairs({spellItem}) end
book.SearchBox = frame(book)
book.SearchBox:SetAlpha(0.6)
book.SettingsDropdown = frame(book)
book.BookBGLeft = book:CreateTexture(nil, "BACKGROUND")
book.BookBGLeft:SetAlpha(0.1)
local shellArt = PlayerSpellsFrame:CreateTexture(nil, "BACKGROUND")
shellArt:SetColorTexture(0.7, 0.5, 0.3, 0.45)

WhatsTrainingOverlay = frame(PlayerSpellsFrame)
local overlay = WhatsTrainingOverlay
local cover = frame(overlay)
cover.backing = cover:CreateTexture(nil, "BACKGROUND")
cover.backing:SetAlpha(0.9)
cover.art = frame(cover)
cover.whole = cover.art:CreateTexture(nil, "BACKGROUND")
overlay.returnTab = frame(overlay)
overlay.returnTab.normal = overlay.returnTab:CreateTexture(nil, "ARTWORK")
overlay.returnTab.active = overlay.returnTab:CreateTexture(nil, "ARTWORK")
overlay.returnTab.glow = overlay.returnTab:CreateTexture(nil, "ARTWORK")
overlay.returnTab.icon = overlay.returnTab:CreateTexture(nil, "ARTWORK")
overlay.returnTab.icon:SetAlpha(0)
WhatsTrainingLauncher = frame(PlayerSpellsFrame)
local launcher = WhatsTrainingLauncher
launcher.normal = launcher:CreateTexture(nil, "ARTWORK")
launcher.active = launcher:CreateTexture(nil, "ARTWORK")
launcher.glow = launcher:CreateTexture(nil, "ARTWORK")
launcher.icon = launcher:CreateTexture(nil, "ARTWORK")
launcher.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
launcher.icon:SetAlpha(0) -- EUI's artwork sweep reaches WT's lowercase icon.
launcher.active:SetShown(true)

WhatsTrainingFrame = frame(overlay)
local main = WhatsTrainingFrame
main.content = frame(main)
main.weaponPage = frame(main)
main.header = frame(main)
main.header.Backplate = main.header:CreateTexture(nil, "BACKGROUND")
main.header.Border = main.header:CreateTexture(nil, "OVERLAY")
main.title = text(22)
main.title.color = {1, 0.82, 0.3, 0.7}
main.header.regions[#main.header.regions + 1] = main.title
main.titleBackplate = main.header.Backplate
local nativeTitleObject = main.title.fontObject
main.title:SetText("|cff301f0fTraining|r")
main.weaponPage.title = text(18)
main.searchBox = frame(main)
local inputText = text(16)
main.searchBox.regions[#main.searchBox.regions + 1] = inputText
local inputArt = main.searchBox:CreateTexture(nil, "BACKGROUND")
main.displayDropdown = frame(main)
local dropdownArt = main.displayDropdown:CreateTexture(nil, "ARTWORK")
main.displayDropdown:SetSize(16, 16)
dropdownArt:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
local openMenu = function(self) self.menuOpens = (self.menuOpens or 0) + 1 end
main.displayDropdown:SetScript("OnClick", openMenu)
main.priceDropdown = frame(main)
main.priceDropdown:SetSize(16, 16)
local priceArrow = main.priceDropdown:CreateTexture(nil, "ARTWORK")
priceArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
main.pagingControls = frame(main)
main.pagingControls.PrevPageButton = frame(main.pagingControls)
main.pagingControls.NextPageButton = frame(main.pagingControls)
local nextButton = main.pagingControls.NextPageButton
main.scrollFrame = frame(main)
local bar = frame(main.scrollFrame)
main.scrollFrame.ScrollBar = bar
bar.Track = frame(bar)
bar.Track.Thumb = frame(bar.Track)
local thumbArt = bar.Track.Thumb:CreateTexture(nil, "ARTWORK")
main.categoryBanner = frame(main)
local banner = main.categoryBanner
for _, key in ipairs({"art", "border", "borderGlow", "iconBorder", "glow", "badgeBackground", "icon"}) do
    banner[key] = banner:CreateTexture(nil, "ARTWORK")
end
banner.glow:SetAlpha(0)
banner.borderGlow:SetAlpha(0)
local function updateGlow(self, elapsed)
    local alpha, target = self.glow:GetAlpha(), self.glowTarget
    local step = elapsed * 0.25 / 0.15
    alpha = alpha < target and math.min(target, alpha + step) or math.max(target, alpha - step)
    self.glow:SetAlpha(alpha)
    self.borderGlow:SetAlpha(alpha)
    if alpha == target then self:SetScript("OnUpdate", nil) end
end
banner:SetScript("OnEnter", function(self) self.glowTarget = 0.25; self:SetScript("OnUpdate", updateGlow) end)
banner:SetScript("OnLeave", function(self) self.glowTarget = 0; self:SetScript("OnUpdate", updateGlow) end)

local row = frame(main.content)
row:SetHeight(28)
row.heading = text(18)
row.heading.color = {0.19, 0.12, 0.06, 0.77}
row.spell = {}
row.regions[#row.regions + 1] = row.heading
row.name = text(15)
row.regions[#row.regions + 1] = row.name
row.rank = text(13)
row.regions[#row.regions + 1] = row.rank
row.band = row:CreateTexture(nil, "BACKGROUND")
row.bandCap = row:CreateTexture(nil, "BACKGROUND")
row.icon = row:CreateTexture(nil, "ARTWORK")
row.icon:SetSize(24, 24)
row.iconBorder = row:CreateTexture(nil, "OVERLAY")
row.separator = frame(row)
local separatorArt = row.separator:CreateTexture(nil, "BACKGROUND")
main.rows = {row}
local trainer = frame(main.content)
trainer.heading = text(18)
trainer.heading.color = {0.8, 0.6, 0.1, 0.77}
trainer.regions[#trainer.regions + 1] = trainer.heading
trainer.spell = {isHeader = true, npc = true}
trainer.icon = trainer:CreateTexture(nil, "ARTWORK")
trainer.icon:SetSize(24, 24)
trainer.iconBorder = trainer:CreateTexture(nil, "OVERLAY")
main.headings = {trainer}
local tile = frame(main.content)
tile:SetHeight(70)
tile.name = text(18)
tile.regions[#tile.regions + 1] = tile.name
tile.icon = tile:CreateTexture(nil, "ARTWORK")
tile.icon:SetSize(40, 40)
tile.iconBorder = tile:CreateTexture(nil, "OVERLAY")
main.tiles = {tile}

local function find(frameValue, layer, alpha)
    for _, item in ipairs(frameValue.regions) do
        if item.layer == layer and item.color and item.color[4] == alpha and item:GetAlpha() > 0 then return item end
    end
end

module:Initialize(); drain()
equal(ns.errors.whatsTraining, nil, "Full theme applies without error")
equal(cover.backing:GetAlpha(), 0, "WT opaque backing is removed")
equal(cover.art:GetAlpha(), 0, "WT page art is removed")
equal(book.BookBGLeft:GetAlpha(), 0.1, "Native dim page artwork is preserved")
equal(book.PagedSpellsFrame:GetAlpha(), 0, "Native spells are occluded under WT")
equal(book.SearchBox:GetAlpha(), 0, "Native controls are occluded under WT")
equal(book.CategoryTabSystem:GetAlpha(), 1, "Native tabs remain visible")
equal(nativeTab:GetAlpha(), 0, "WT return tab covers the native selected tab and underline")
equal(nativeTab.SquareBackground:GetAlpha(), 0, "Native silver frame cannot differ from WT's flat tab")
equal(nativeTab.SquareBackgroundActive:GetAlpha(), 0, "Native gold frame is suppressed")
equal(nativeTab.Icon:GetAlpha(), 1, "Native category icon is preserved")
equal(shellArt.color[4], 0.45, "Native backdrop opacity is preserved")
equal(#PlayerSpellsFrame.regions, 1, "No competing shell is created")
equal(main.title.font[1], "EUI.ttf", "Uses EUI's Blizzard skin font")
equal(main.title.font[2], 22, "Priming font shadow preserves title size")
equal(main.title.font[3], "", "Uses EUI outline choice")
equal(main.title.fontObject, shadowObject, "Uses EUI's rendered shadow FontObject")
equal(main.title.offset[1], 1, "Uses EUI shadow offset")
equal(main.title.color[4], 0.7, "Font styling preserves text alpha")
equal(main.title.color[2], 1, "Native gold page titles get the spellbook text color")
equal(trainer.heading.color[2], 1, "Trainer override survives the full tree walk")
equal(inputText.font[1], "Native.ttf", "Input fonts stay Blizzard's, like EUI inputs")
equal(row.name.font[1], "Spell.ttf", "Spell names use the live native spellbook face")
equal(row.name.fontObject, spellObject, "Spell names use the native shadow FontObject")
equal(row.rank.font[1], "Rank.ttf", "Ranks use the native spellbook rank face")
equal(row.rank.offset[1], 1, "Ranks retain the native rank shadow")
equal(row.name.font[2], 15, "Row font keeps native size")
equal(row.rank.font[2], 13, "Native rank face preserves ledger density")
equal(spellItem.Name.fontWrites, 0, "Sampling never edits native spell fonts")
equal(main.weaponPage.title.font[1], "EUI.ttf", "Weapon page fonts match")
equal(main.header.Backplate:GetAlpha(), 0, "Header wash removed")
equal(main.header.Border:GetAlpha(), 0, "Ornate header divider removed")
local divider = find(main.header, "OVERLAY", 0.25)
check(divider and divider.height == 1, "Header divider is a thin line, not a filled artwork rectangle")
equal(divider.points[1][4], 20, "Header divider uses EUI's left inset")
equal(dropdownArt:GetAlpha(), 1, "Small dropdown keeps its native arrow artwork")
equal(inputArt:GetAlpha(), 0, "Input artwork removed")
check(find(main.searchBox, "BACKGROUND", 1), "Search input gets EUI's near-black fill")
equal(#main.displayDropdown.regions, 1, "Native dropdown does not get competing arrow or background textures")
equal(main.displayDropdown.scripts.OnClick, openMenu, "Native dropdown menu handler stays intact")
main.displayDropdown:Fire("OnClick")
equal(main.displayDropdown.menuOpens, 1, "Native dropdown opens through its original click handler")
equal(#queue, 0, "Opening a native dropdown does not schedule a theme walk")
equal(priceArrow:GetAlpha(), 1, "Price dropdown retains its correctly inset native arrow")
equal(#main.priceDropdown.regions, 1, "Price dropdown receives no replacement selector art")
equal(thumbArt:GetAlpha(), 0, "Native scroll thumb artwork removed")
local thumb = find(bar, "ARTWORK", 0.3)
check(thumb and thumb.width == 4, "House scroll thumb uses a four-pixel strip")
equal(banner.border:GetAlpha(), 0, "Banner gold ornament removed")
equal(banner.icon:GetAlpha(), 1, "Banner semantic icon preserved")
equal(find(banner, "BACKGROUND", 0.92).anchor, banner.badgeBackground, "Toggle fill hugs its badge")
equal(find(banner, "HIGHLIGHT", 0.1).anchor, banner.badgeBackground, "Toggle hover hugs its badge")
equal(row.band:GetAlpha(), 0, "Parchment row band removed")
equal(row.icon:GetAlpha(), 1, "Spell icon preserved")
local spellRing
for _, item in ipairs(tile.regions) do
    if item.atlas == "spellbook-IconFrame" then spellRing = item end
end
check(spellRing and spellRing.width == 60 and spellRing.height == 60, "Roomier tiles copy native ring artwork and icon proportions")
equal(spellRing:GetAlpha(), 0.5, "Spell ring matches EUI's half-strength border")
equal(spellRing:GetDesaturation(), 0.5, "Spell ring matches EUI's half desaturation")
equal(spellRing.vertex[1], 0.8, "Spell ring preserves native tint")
local compactEdges = {}
for _, item in ipairs(row.regions) do
    check(not item.atlas, "Dense ledger rows do not copy oversized ornamental ring artwork")
    if item.layer == "OVERLAY" and item.color and item.color[1] == 0 and item.color[4] == 1 then
        compactEdges[#compactEdges + 1] = item
        check(item.width == 1 or item.height == 1, "Dense ledger icon edges are one pixel thick")
        equal(item.points[1][2], row.icon, "Compact edges stay anchored to the icon")
    end
end
equal(#compactEdges, 4, "Dense ledger icons get four thin dark edges")
equal(#trainer.regions, 3, "Heading rows receive no copied icon decorations")
equal(trainer.iconBorder:GetAlpha(), 0, "Heading metadata suppresses icon frames even if inherited icon fields are shown")
equal(separatorArt:GetAlpha(), 0, "Parchment row separator removed")
check(find(row.separator, "BACKGROUND", 0.09), "Neutral row separator created")
equal(launcher.normal:GetAlpha(), 0, "Tab frame artwork removed")
equal(launcher.icon:GetAlpha(), 0, "WT placeholder icon is suppressed")
local function tabIcon(button)
    for _, item in ipairs(button.regions) do
        if item.mask then return item end
    end
end
local trainingIcon = tabIcon(launcher)
check(trainingIcon, "Training tab uses a masked icon")
equal(trainingIcon:GetTexture(), "Interface\\Icons\\INV_Misc_Book_09", "Training tab uses a book icon")
equal(trainingIcon.width, 36, "Training icon matches native width")
equal(trainingIcon.height, 35, "Training icon matches native height")
equal(trainingIcon.points[1][1], "CENTER", "Training icon is centered like native categories")
equal(trainingIcon.mask:GetAtlas(), "SquareMask", "Training icon uses the native mask")
equal(trainingIcon.mask.points[1][5], -2, "Native mask crops the icon top")
equal(trainingIcon.mask.points[2][4], -2, "Native mask crops the icon right")
local selection = find(launcher, "OVERLAY", 1)
check(selection and selection.color[2] == 0.8, "Selected tab uses EUI accent")
equal(selection.points[1][2], launcher, "Training underline belongs to the launcher")
check(not find(overlay.returnTab, "OVERLAY", 1), "Return tab is unselected while training is open")
equal(find(launcher, "BACKGROUND", 1).color[1], 0.03, "Selected WT tab uses native dark fill")
equal(find(overlay.returnTab, "BACKGROUND", 1).color[1], 0.068, "Return tab uses native inactive fill")
equal(tabIcon(overlay.returnTab):GetTexture(), "NativeCategoryIcon", "Return tab renders the native category icon")
equal(categoryTabs.selectedTabID, 1, "Training does not change native category selection")
local count, writes = #main.displayDropdown.regions, main.title.fontWrites
local titleReads, rowReads, ringLayout = main.title.fontReads, row.name.fontReads, spellRing.layoutWrites
module:ApplySettings(); drain()
equal(#main.displayDropdown.regions, count, "Theme does not duplicate chrome")
equal(main.title.fontWrites, writes, "Repeated font application is idempotent")
equal(main.title.fontReads, titleReads, "Stable header font styling avoids repeated property reads")
equal(row.name.fontReads, rowReads, "Stable spell font styling avoids repeated property reads")
equal(spellRing.layoutWrites, ringLayout, "Stable spell rings do not invalidate their layout again")
row.name:SetText("Updated |cff301f0fspell|r")
equal(row.name:GetText(), "Updated |cffffffffspell|r", "Native text refresh adapts the changed label immediately")
equal(#queue, 0, "Native row text refresh does not schedule a whole overlay pass")
row.rank:SetTextColor(0.19, 0.12, 0.06, 0.7)
equal(row.rank.color[1], 1, "Native row recolor adapts immediately")
equal(#queue, 0, "Native row recolor does not schedule a whole overlay pass")

-- The real WT hover animation reads alpha back to decide when to stop.
local function finishHover(script)
    banner:Fire(script)
    local ticks = 0
    while banner.scripts.OnUpdate and ticks < 60 do
        banner:Fire("OnUpdate", 1 / 60)
        ticks = ticks + 1
    end
    check(not banner.scripts.OnUpdate, "Native hover animation reaches its target and stops")
    equal(#queue, 0, "Hover animation never queues a full theme pass")
    equal(banner.glow.vertex[4], 0, "Native badge glow stays visually suppressed")
    equal(banner.borderGlow.vertex[4], 0, "Native border glow stays visually suppressed")
end
finishHover("OnEnter")
equal(banner.glow:GetAlpha(), 0.25, "Hover alpha remains available to native animation logic")
finishHover("OnLeave")
for i = 1, 20 do cover.backing:SetAlpha(0.9) end
equal(#queue, 0, "Repeated background alpha writes do not queue a tree walk")
equal(cover.backing:GetAlpha(), 0, "Repeated native alpha writes keep owned backgrounds suppressed")
row.band:SetShown(false)
row.icon:SetShown(false)
main:Fire("OnSizeChanged"); drain()
check(not find(row, "BACKGROUND", 0.92), "Hidden row bands do not leave replacement panels")
local hiddenIconBorder = true
for _, item in ipairs(row.regions) do
    for _, point in ipairs(item.points) do
        if point[2] == row.icon and item:GetAlpha() ~= 0 then hiddenIconBorder = false end
    end
end
check(hiddenIconBorder, "Hidden icons do not leave replacement borders")
row.band:SetShown(true); row.icon:SetShown(true)
main:Fire("OnSizeChanged"); drain()
row.spell = {isHeader = true}
main:Fire("OnSizeChanged"); drain()
for _, edge in ipairs(compactEdges) do equal(edge:GetAlpha(), 0, "A reused heading hides every cached icon edge") end
row.spell = {}
row.iconBorder:SetShown(false)
main:Fire("OnSizeChanged"); drain()
for _, edge in ipairs(compactEdges) do equal(edge:GetAlpha(), 0, "Native border visibility suppresses replacement edges") end
row.iconBorder:SetShown(true)
row.icon:SetAlpha(0)
main:Fire("OnSizeChanged"); drain()
for _, edge in ipairs(compactEdges) do equal(edge:GetAlpha(), 0, "Invisible icons do not leave replacement edges") end
row.icon:SetAlpha(1)
main:Fire("OnSizeChanged"); drain()
for _, edge in ipairs(compactEdges) do equal(edge:GetAlpha(), 1, "Restored spell rows recover their compact edges") end
book.PagedSpellsFrame:SetAlpha(0.75); drain()
equal(book.PagedSpellsFrame:GetAlpha(), 0, "Native alpha refresh remains occluded while WT is open")

-- The native content returns synchronously; WT's inherited backdrop stays exact.
overlay:Hide()
equal(nativeTab:GetAlpha(), 0.85, "Closing WT synchronously restores the native selected tab")
equal(book.PagedSpellsFrame:GetAlpha(), 0.75, "Closing tab immediately restores latest native spells alpha")
equal(book.SearchBox:GetAlpha(), 0.6, "Closing tab immediately restores native controls")
drain()
equal(selection:GetAlpha(), 0, "Hidden overlay clears selection even with stale active artwork")
equal(find(launcher, "BACKGROUND", 1).color[1], 0.068, "Closed WT tab uses inactive fill")
launcher.active:SetShown(false); launcher:Fire("OnClick"); drain()
equal(selection:GetAlpha(), 0, "Launcher selection follows tab state")
overlay:Show(); drain()
equal(selection:GetAlpha(), 1, "Open overlay selects training even with stale inactive artwork")
launcher.active:SetShown(true); launcher:Fire("OnClick"); drain()
equal(book.PagedSpellsFrame:GetAlpha(), 0, "Reopening suppresses native content")
equal(selection:GetAlpha(), 1, "Launcher selection returns")
launcher.icon:SetAlpha(0)
trainingIcon:SetAlpha(0); module:ApplySettings(); drain()
equal(trainingIcon:GetAlpha(), 1, "Theme refresh restores the replacement training icon")
nativeTab:SetSquareMode(); drain()
equal(nativeTab.SquareBackground:GetAlpha(), 0, "Rebuilt native silver frame stays suppressed")
equal(nativeTab.SquareBackgroundActive:GetAlpha(), 0, "Rebuilt native gold frame stays suppressed")
nativeTab:Init(); drain()
equal(nativeTab.SquareBackground:GetAlpha(), 0, "Reinitialized tab artwork is discovered and suppressed")
equal(nativeTab.SquareBackgroundActiveGlow:GetAlpha(), 0, "Reinitialized selection glow stays suppressed")
local replacementTab = frame(categoryTabs)
replacementTab.Icon = replacementTab:CreateTexture(nil, "ARTWORK")
replacementTab.Icon:SetTexture("ReplacementCategoryIcon")
replacementTab:SetAlpha(0.7)
categoryTabs.tabs[2] = replacementTab
categoryTabs:SetTabVisuallySelected(2); drain()
equal(nativeTab:GetAlpha(), 0.85, "Changing category releases the old native tab")
equal(replacementTab:GetAlpha(), 0, "Changed category tab is covered while WT is open")
local pooledTab = frame(categoryTabs)
pooledTab.Icon = pooledTab:CreateTexture(nil, "ARTWORK")
pooledTab.Icon:SetTexture("PooledCategoryIcon")
pooledTab:SetAlpha(0.7)
categoryTabs.tabs[2] = pooledTab
overlay.returnTab.icon:SetTexture("ReplacementCategoryIcon"); drain()
equal(replacementTab:GetAlpha(), 0.7, "Pool rebuild releases the replaced category button")
equal(pooledTab:GetAlpha(), 0, "Pool rebuild covers the new category button with the same ID")
equal(tabIcon(overlay.returnTab):GetTexture(), "PooledCategoryIcon", "Return icon follows rebuilt category buttons")
replacementTab = pooledTab
overlay.returnTab:Hide(); drain()
equal(replacementTab:GetAlpha(), 0.7, "Hidden return tab releases native category artwork")
overlay.returnTab:Show(); drain()
equal(replacementTab:GetAlpha(), 0, "Shown return tab covers native category artwork again")
overlay:Hide()
equal(replacementTab:GetAlpha(), 0.7, "Closing WT restores the replacement tab")
overlay:Show(); drain()
local returnTab = overlay.returnTab
overlay.returnTab = nil
module:ApplySettings(); drain()
equal(ns.errors.whatsTraining, nil, "An unavailable return tab is safe")
equal(replacementTab:GetAlpha(), 0.7, "An unavailable return tab leaves native tabs visible")
overlay.returnTab = returnTab
module:ApplySettings(); drain()

style = "modern"
shellArt:SetColorTexture(0.1, 0.3, 0.5, 0.2)
EllesmereUI._WSkinRefreshStyles(); drain()
equal(shellArt.color[3], 0.5, "Modern backdrop color stays native")
equal(shellArt.color[4], 0.2, "Modern backdrop opacity stays native")
fontPath, fontFlag = "Updated.ttf", "THICKOUTLINE"
EllesmereUI._WSkinRefreshLooks(); drain()
equal(main.title.font[1], "Updated.ttf", "Live font change reaches WT")
equal(main.title.font[2], 22, "Live font change preserves original size")
equal(main.title.fontObject, noShadowObject, "Outline mode removes rendered shadow")
equal(main.title.offset[1], 0, "Outline mode removes instance shadow")
equal(row.name.font[1], "Spell.ttf", "EUI house-font changes leave spell rows consistent with native spells")
spellItem.Name:SetFont("LiveSpell.ttf", 20, "OUTLINE"); drain()
equal(row.name.font[1], "LiveSpell.ttf", "Native spell font changes refresh ledger rows")
equal(row.name.font[3], "OUTLINE", "Native spell outline changes refresh ledger rows")

-- Before native items exist, use Blizzard font objects and the dimmed WT ring.
local enumerate = book.PagedSpellsFrame.EnumerateFrames
book.PagedSpellsFrame.EnumerateFrames = function() error("Page is not realized yet") end
GameFontNormal, GameFontHighlightSmall = text(14), text(12)
GameFontNormal.font, GameFontHighlightSmall.font = {"FallbackSpell.ttf", 14, ""}, {"FallbackRank.ttf", 12, ""}
EllesmereUI._WSkinRefreshLooks(); drain()
equal(ns.errors.whatsTraining, nil, "Unavailable native items do not break the skin")
equal(row.name.font[1], "FallbackSpell.ttf", "Missing spell item falls back to Blizzard's spell font")
equal(row.rank.font[1], "FallbackRank.ttf", "Missing spell item falls back to Blizzard's rank font")
equal(tile.iconBorder:GetAlpha(), 0.5, "Missing native ring falls back to half-strength WT art on roomy tiles")
equal(tile.iconBorder:GetDesaturation(), 0.5, "Fallback ring uses EUI's desaturation")
equal(row.iconBorder:GetAlpha(), 0, "Compact rows keep oversized WT ring art suppressed when native art is unavailable")
equal(spellRing:GetAlpha(), 0, "Missing native ring suppresses stale copied artwork")
book.PagedSpellsFrame.EnumerateFrames = enumerate
GameFontNormal, GameFontHighlightSmall = nil, nil
EllesmereUI._WSkinRefreshLooks(); drain()
equal(row.name.font[1], "LiveSpell.ttf", "Realized native items replace fallback fonts")
equal(spellRing:GetAlpha(), 0.5, "Realized native items restore their copied ring")
EllesmereUIDB.blizzWinAccentBar = {useCustom = true, color = {r = 0.9, g = 0.4, b = 0.2}}
EllesmereUI._WSkinRefreshLooks(); drain()
equal(selection.color[1], 0.9, "Tab follows custom window accent")
EllesmereUIDB.blizzWinAccentBar.enabled = false
EllesmereUI._WSkinRefreshLooks(); drain()
equal(selection:GetAlpha(), 0, "Tab honors disabled window accent bar")
nextButton:SetEnabled(false); drain()
local glyph
for _, item in ipairs(nextButton.regions) do
    if item.texture and item.texture:find("eui-arrow-right", 1, true) then glyph = item end
end
check(glyph and glyph.width == 14, "Paging uses EUI image arrows")
equal(nextButton:GetAlpha(), 0.5, "Disabled page control matches EUI's whole-block opacity")
nextButton:SetEnabled(true); drain()
equal(nextButton:GetAlpha(), 1, "Enabled page control restores whole-block opacity")

local lazy = frame(main.content)
lazy.name = text(17)
lazy.regions[#lazy.regions + 1] = lazy.name
main.rows[#main.rows + 1] = lazy
main.content:SetHeight(400); main:Fire("OnSizeChanged"); drain()
equal(lazy.name.font[1], "LiveSpell.ttf", "Lazy pooled rows inherit the native spell face")
equal(lazy.name.font[2], 17, "Lazy row font size survives")
local inactive = frame(main.content)
inactive.name = text(17)
inactive.regions[#inactive.regions + 1] = inactive.name
main.rows[#main.rows + 1] = inactive
inactive:Hide()
module:ApplySettings(); drain()
equal(inactive.name.fontWrites, 0, "Hidden pooled rows are skipped")
inactive:Show(); drain()
equal(inactive.name.font[1], "LiveSpell.ttf", "A pooled row gets the current font when shown")
local retryRow = frame(main.content)
retryRow.name = text(18)
retryRow.regions[#retryRow.regions + 1] = retryRow.name
main.rows[#main.rows + 1] = retryRow
local setRetryFont = retryRow.name.SetFont
retryRow.name.SetFont = function(self, ...)
    if not self.rejectedFont then self.rejectedFont = true; return false end
    return setRetryFont(self, ...)
end
module:ApplySettings(); drain()
check(retryRow.name.font[1] ~= "LiveSpell.ttf", "A rejected font write is not treated as applied")
module:ApplySettings(); drain()
equal(retryRow.name.font[1], "LiveSpell.ttf", "Font caching allows retry after a rejected write")
equal(retryRow.name.font[2], 18, "Retried font application preserves the original ledger size")

enabled = false; module:ApplySettings()
equal(cover.backing:GetAlpha(), 0.9, "Disable restores WT background alpha")
equal(cover.art:GetAlpha(), 1, "Disable restores WT page art")
equal(book.PagedSpellsFrame:GetAlpha(), 0.75, "Disable restores native content")
equal(main.title.fontObject, nativeTitleObject, "Disable restores original FontObject")
equal(main.title.font[1], "Native.ttf", "Disable restores original face")
equal(main.title.font[2], 22, "Disable restores instance size after restoring FontObject")
equal(main.title.font[3], "OUTLINE", "Disable restores original flags")
equal(main.title.offset[1], 2, "Disable restores original shadow offset")
equal(main.title.shadow[1], 0.2, "Disable restores original shadow color")
equal(main.title.value, "|cff301f0fTraining|r", "Disable restores native inline text")
equal(dropdownArt:GetAlpha(), 1, "Disable restores control artwork")
equal(thumbArt:GetAlpha(), 1, "Disable restores scroll thumb")
equal(banner.border:GetAlpha(), 1, "Disable restores banner ornament")
equal(banner.glow.vertex[4], 1, "Disable restores native hover glow rendering")
equal(banner.borderGlow.vertex[4], 1, "Disable restores native banner glow rendering")
equal(row.name.font[1], "Native.ttf", "Disable restores the original ledger font")
equal(tile.iconBorder:GetDesaturation(), 0, "Disable restores WT's original ring saturation")
for _, edge in ipairs(compactEdges) do equal(edge:GetAlpha(), 0, "Disable hides owned compact icon edges") end
equal(row.band:GetAlpha(), 1, "Disable restores parchment row band")
equal(launcher.normal:GetAlpha(), 1, "Disable restores WT launcher artwork")
equal(replacementTab:GetAlpha(), 0.7, "Disable restores the native category tab")
equal(launcher.icon:GetAlpha(), 0, "Disable releases the icon to EUI's latest artwork fade")
equal(trainingIcon:GetAlpha(), 0, "Disable hides the replacement book icon")
equal(launcher.icon:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark", "Disable retains WT's original icon texture")
equal(nativeTab.SquareBackground:GetAlpha(), 1, "Disable restores native tab frame artwork")
check(not find(main.displayDropdown, "BACKGROUND", 0.92), "Disable hides owned control chrome")

enabled = true; module:ApplySettings(); drain()
local foreignFont = {font = {"Foreign.ttf", 19, ""}, shadow = {0.6, 0.6, 0.6, 1}, offset = {3, -3}}
main.title:SetFontObject(foreignFont)
cover.backing:SetAlpha(0.4)
module:ApplySettings(); drain()
enabled = false; module:ApplySettings(); drain()
equal(main.title.fontObject, foreignFont, "Latest external FontObject is restored")
equal(main.title.font[1], "Foreign.ttf", "Latest external font face is restored")
equal(main.title.font[2], 19, "Latest external size is restored")
equal(cover.backing:GetAlpha(), 0.4, "Latest external background alpha is restored")
enabled = true; module:ApplySettings(); drain()
main.title:SetFont("ExternalInstance.ttf", 25, "OUTLINE")
enabled = false; module:ApplySettings(); drain()
equal(main.title.font[1], "ExternalInstance.ttf", "Unapplied external font wins over FontObject restoration")
equal(main.title.font[2], 25, "Unapplied external size survives")

enabled = true; module:ApplySettings(); drain()
style = "off"; EllesmereUI._WSkinRefreshStyles(); drain()
equal(cover.backing:GetAlpha(), 0.4, "Spellbook skin off restores background")
equal(main.title.font[1], "ExternalInstance.ttf", "Spellbook skin off restores current font")
equal(book.PagedSpellsFrame:GetAlpha(), 0.75, "Spellbook skin off restores native spells")
equal(replacementTab:GetAlpha(), 0.7, "Spellbook skin off restores native tab selection")
equal(ns.errors.whatsTraining, nil, "Theme lifecycle remains error-free")
check(not main.scripts.OnUpdate and not overlay.scripts.OnUpdate, "Theme does not poll")

print("PASS: WhatsTraining full theme (" .. passed .. " assertions)")

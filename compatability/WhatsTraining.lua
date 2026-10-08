local folder, ns = ...
local Module = { asyncErrors = true }
local KEY = "whatsTraining"
local TRAINING_TAB_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- EUI's spellbook uses white text in both styles; status tones follow WT's dark theme.
local FALLBACK_COLORS = {
    primary = {1, 1, 1},
    strong = {1, 1, 1},
    muted = {0.5, 0.5, 0.5},
    danger = {1, 0.55, 0.45},
    success = {0.65, 1, 0.40},
    lightblue = {0.55, 0.84, 1},
}
local PAGE_TEXT = {"title", "character", "total", "footer", "empty", "continues"}
-- Exact rounded RGB codes emitted by Forever's parchment and dark themes.
local INLINE_COLORS = {
    ["301f0f"] = "primary", ["140a05"] = "strong", ["666666"] = "muted",
    ["1a610d"] = "success", ["143880"] = "lightblue",
    ["4d1a0d"] = "danger", ["73170a"] = "danger", ["8c1f0d"] = "danger",
    ["e6e6e6"] = "primary", ["f2e6cc"] = "primary", ["ffffff"] = "strong",
    ["808080"] = "muted", ["a6ff66"] = "success", ["8cd6ff"] = "lightblue",
    ["ff8c73"] = "danger",
}
local ROW_TEXT = {"name", "rank", "level", "heading", "title", "count"}
local ROW_GROUPS = {
    "rows", "weaponRows", "headings", "listRows", "cityTrainers",
    "skillTrainers", "tiles", "blocks", "cells", "groupHeaders",
}
local EUI_REFRESH = {
    "_WSkinRefreshStyles", "_WSkinRefreshLooks", "DisableAllBlizzWindowSkins",
    "SwapWindowSkinStyle", "RepointAllDBs",
}
local states = setmetatable({}, {__mode = "k"})
local hooks = setmetatable({}, {__mode = "k"})
local appearance = setmetatable({}, {__mode = "k"})
local chrome = setmetatable({}, {__mode = "k"})
local ownedRegions = setmetatable({}, {__mode = "k"})
local ownedLayouts = setmetatable({}, {__mode = "k"})
local nativeHidden = setmetatable({}, {__mode = "k"})
local textRoles = setmetatable({}, {__mode = "k"})
local fontRoles = setmetatable({}, {__mode = "k"})
local unpackValues = unpack or table.unpack
local pending, applying = false, false
local initialized = false
local status = "Waiting for initialization"
local ScheduleApply
local RefreshText
local activeColors, textPass

local function Enabled()
    if not ns.ready then return false end
    local settings = ns.GetSettings(KEY)
    return settings and settings.enabled == true
end

local function SetStatus(message)
    status = message
    ns.SetStatus(KEY, message)
end

local function UsesDarkStyle()
    local eui = _G.EllesmereUI
    if not eui or type(eui.GetBlizzWindowStyle) ~= "function" then return false end
    local ok, style = pcall(eui.GetBlizzWindowStyle, "playerspells")
    return ok and (style == "eui" or style == "modern"), style
end

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function ReadColor(text)
    if not IsObject(text) or type(text.GetTextColor) ~= "function"
        or type(text.SetTextColor) ~= "function" then return end
    local ok, r, g, b, a = pcall(text.GetTextColor, text)
    if not ok then return end
    for _, value in pairs({r, g, b, a}) do
        if _G.issecretvalue and issecretvalue(value) then return end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or (a ~= nil and type(a) ~= "number") then return end
    for _, value in pairs({r, g, b, a}) do
        if value ~= value or value < 0 or value > 1 then return end
    end
    return {r, g, b, a or 1}
end

local function SameColor(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
        if math.abs(a[i] - b[i]) > 0.000001 then return false end
    end
    return true
end

local function Near(value, expected)
    return math.abs(value - expected) < 0.03
end

local function SemanticColor(color, colors)
    local r, g, b = color[1], color[2], color[3]
    if Near(r, 0.19) and Near(g, 0.12) and Near(b, 0.06) then
        return colors.primary
    elseif Near(r, 0.08) and Near(g, 0.04) and Near(b, 0.02) then
        return colors.strong
    elseif Near(r, 0.40) and Near(g, 0.40) and Near(b, 0.40) then
        return colors.muted
    elseif Near(r, 0.08) and Near(g, 0.22) and Near(b, 0.50) then
        return colors.lightblue
    elseif Near(r, 0.30) and Near(g, 0.10) and Near(b, 0.05) then
        return colors.danger
    elseif r >= 0.40 and g <= 0.16 and b <= 0.10 then
        return colors.danger
    elseif r <= 0.16 and g >= 0.32 and b <= 0.12 then
        return colors.success
    end
    -- Newer WT builds resolve their own dark theme before creating rows.
    for role, native in pairs(FALLBACK_COLORS) do
        if Near(r, native[1]) and Near(g, native[2]) and Near(b, native[3]) then
            return colors[role]
        end
    end
    if (Near(r, 0.9) and Near(g, 0.9) and Near(b, 0.9))
        or (Near(r, 0.95) and Near(g, 0.9) and Near(b, 0.8)) then
        return colors.primary
    end
end

local function ReadString(text)
    if not IsObject(text) or type(text.GetText) ~= "function" then return end
    local ok, value = pcall(text.GetText, text)
    if not ok or (_G.issecretvalue and issecretvalue(value)) then return end
    if value == nil or type(value) == "string" then return value, true end
end

local function TranslateString(value, colors)
    if type(value) ~= "string" then return value end
    -- Even pipe runs are escaped literals; preserve all markup and inline alpha.
    return (value:gsub("(|+)([cC])(%x%x)(%x%x%x%x%x%x)", function(pipes, marker, alpha, rgb)
        if #pipes % 2 == 0 then return pipes .. marker .. alpha .. rgb end
        local color = colors[INLINE_COLORS[rgb:lower()]]
        if not color then return pipes .. marker .. alpha .. rgb end
        return pipes .. marker .. alpha .. string.format("%02x%02x%02x",
            math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
            math.floor(color[3] * 255 + 0.5))
    end))
end

local function HookMethod(object, method, callback)
    if not IsObject(object) or type(object[method]) ~= "function"
        or type(_G.hooksecurefunc) ~= "function" then return false end
    local installed = hooks[object]
    if not installed then
        installed = {}
        hooks[object] = installed
    end
    if installed[method] then return true end
    if not pcall(hooksecurefunc, object, method, callback) then return false end
    installed[method] = true
    return true
end

local PROPERTY_ORDER = {"FontObject", "Font", "ShadowColor", "ShadowOffset", "Alpha", "VertexColor", "Desaturation"}
local PROPERTY_SIZE = {FontObject = 1, Font = 3, ShadowColor = 4, ShadowOffset = 2, Alpha = 1, VertexColor = 4, Desaturation = 1}

local function ReadProperty(object, key)
    if not IsObject(object) or type(object["Get" .. key]) ~= "function"
        or type(object["Set" .. key]) ~= "function" then return end
    local ok, a, b, c, d = pcall(object["Get" .. key], object)
    if not ok then return end
    if key == "Font" and c == nil then c = "" end
    local value = {a, b, c, d}
    for i = 1, PROPERTY_SIZE[key] do
        if value[i] == nil or (_G.issecretvalue and issecretvalue(value[i])) then return end
    end
    return value
end

local function SameProperty(a, b, key)
    if not a or not b then return false end
    for i = 1, PROPERTY_SIZE[key] do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function SameCoordinates(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #b do if a[i] ~= b[i] then return false end end
    return true
end

local function WriteProperty(object, key, value)
    local wasApplying = applying
    applying = true
    local ok, result = pcall(object["Set" .. key], object, unpackValues(value, 1, PROPERTY_SIZE[key]))
    applying = wasApplying
    return ok and result ~= false
end

local function TrackProperty(object, key)
    local current = ReadProperty(object, key)
    if not current then return end
    local record = appearance[object]
    if not record then record = {}; appearance[object] = record end
    local state = record[key]
    if not state then
        state = {original = current}
        record[key] = state
        if not HookMethod(object, "Set" .. key, function(self)
            if applying then return end
            local saved = appearance[self]
            if not saved then return end
            saved.fontApplied = nil
            local applied = saved[key] and saved[key].applied
            for _, changed in ipairs(key == "FontObject"
                and {"FontObject", "Font", "ShadowColor", "ShadowOffset"} or {key}) do
                local native = ReadProperty(self, changed)
                if saved[changed] and native then
                    saved[changed].original, saved[changed].applied = native, nil
                end
            end
            -- Hover animations frequently rewrite artwork alpha. Keep faded
            -- artwork owned by this skin in place without scheduling a tree walk.
            if key == "Alpha" and applied and Enabled() then
                if WriteProperty(self, key, applied) then saved[key].applied = applied end
                return
            end
            if key == "FontObject" then saved.shadow = nil end
            if Enabled() then ScheduleApply() end
        end) then record[key] = nil; return end
    elseif not SameProperty(current, state.applied, key) then
        state.original, state.applied = current, nil
    end
    return state, current
end

local function ApplyProperty(object, key, desired)
    local state, current = TrackProperty(object, key)
    if state and not SameProperty(current, desired, key) and WriteProperty(object, key, desired) then
        state.applied = desired
    end
end

local function RestoreProperty(object, key)
    local record = appearance[object]
    local state = record and record[key]
    if not state then return end
    if state.applied and SameProperty(ReadProperty(object, key), state.applied, key) then
        WriteProperty(object, key, state.original)
    end
    state.applied = nil
end

local function AdaptFont(text, colors)
    if fontRoles[text] == "native" then return end
    colors = colors[fontRoles[text]] or colors
    if not colors.fontPath then return end
    local record = appearance[text]
    local cached = record and record.fontApplied
    if cached and cached.fontPath == colors.fontPath and cached.fontFlag == colors.fontFlag
        and cached.shadow == colors.shadow and cached.fontObject == colors.fontObject
        and ((not cached.shadowColor and not colors.shadowColor)
            or SameProperty(cached.shadowColor, colors.shadowColor, "ShadowColor"))
        and ((not cached.shadowOffset and not colors.shadowOffset)
            or SameProperty(cached.shadowOffset, colors.shadowOffset, "ShadowOffset")) then return end
    local state = TrackProperty(text, "Font")
    if not state or type(state.original[2]) ~= "number" then return end
    local fontObject = TrackProperty(text, "FontObject")
    TrackProperty(text, "ShadowColor")
    TrackProperty(text, "ShadowOffset")
    record = appearance[text]
    local eui = _G.EllesmereUI
    local useNativeObject = colors.fontObject and fontObject
        and not SameProperty(ReadProperty(text, "FontObject"), {colors.fontObject}, "FontObject")
    local primeShadow = not colors.fontObject and fontObject
        and record.shadow ~= colors.shadow and type(eui.PrimeFontShadow) == "function"
    if useNativeObject or primeShadow then
        local wasApplying = applying
        applying = true
        local ok
        if useNativeObject then
            ok = WriteProperty(text, "FontObject", {colors.fontObject})
        else
            ok = pcall(eui.PrimeFontShadow, text, colors.shadow)
        end
        applying = wasApplying
        if ok then
            fontObject.applied = ReadProperty(text, "FontObject")
            for _, key in ipairs({"Font", "ShadowColor", "ShadowOffset"}) do
                if record[key] then record[key].applied = ReadProperty(text, key) end
            end
            record.shadow = colors.shadow
        end
    end
    -- Priming changes the face and size; keep the native baseline captured before it.
    local desired = {colors.fontPath, state.original[2], colors.fontFlag or state.original[3]}
    if not SameProperty(ReadProperty(text, "Font"), desired, "Font")
        and WriteProperty(text, "Font", desired)
        and SameProperty(ReadProperty(text, "Font"), desired, "Font") then state.applied = desired end
    local shadowColor = colors.shadowColor or {0, 0, 0, colors.shadow and 1 or 0}
    local shadowOffset = colors.shadowOffset or (colors.shadow and {1, -1} or {0, 0})
    ApplyProperty(text, "ShadowColor", shadowColor)
    ApplyProperty(text, "ShadowOffset", shadowOffset)
    if SameProperty(ReadProperty(text, "Font"), desired, "Font")
        and (not record.ShadowColor or SameProperty(ReadProperty(text, "ShadowColor"), shadowColor, "ShadowColor"))
        and (not record.ShadowOffset or SameProperty(ReadProperty(text, "ShadowOffset"), shadowOffset, "ShadowOffset"))
        and (not colors.fontObject or not fontObject
            or SameProperty(ReadProperty(text, "FontObject"), {colors.fontObject}, "FontObject"))
        and (not primeShadow or record.shadow == colors.shadow) then
        record.fontApplied = {fontPath = colors.fontPath, fontFlag = colors.fontFlag,
            shadow = colors.shadow, fontObject = colors.fontObject,
            shadowColor = colors.shadowColor, shadowOffset = colors.shadowOffset}
    end
end

local function Fade(region)
    if region and not ownedRegions[region] then ApplyProperty(region, "Alpha", {0}) end
end

local function FadeAnimated(region)
    local color = ReadProperty(region, "VertexColor")
    if color then ApplyProperty(region, "VertexColor", {color[1], color[2], color[3], 0}) end
end

local function PixelSize(frame)
    local eui = _G.EllesmereUI
    local pp = eui and eui.PP
    if pp and type(pp.perfect) == "number" and frame and frame.GetEffectiveScale then
        local ok, scale = pcall(frame.GetEffectiveScale, frame)
        if ok and not (_G.issecretvalue and issecretvalue(scale))
            and type(scale) == "number" and scale > 0.1 and scale < 10 then
            return pp.perfect / scale
        end
    end
    return 1
end

local function Regions(frame)
    if not IsObject(frame) or type(frame.GetRegions) ~= "function" then return {} end
    return {frame:GetRegions()}
end

local function Children(frame)
    if not IsObject(frame) or type(frame.GetChildren) ~= "function" then return {} end
    return {frame:GetChildren()}
end

local function Texture(frame, key, layer, alpha)
    if not IsObject(frame) or type(frame.CreateTexture) ~= "function" then return end
    local record = chrome[frame]
    if not record then record = {}; chrome[frame] = record end
    if not record[key] then
        local region = frame:CreateTexture(nil, layer or "BACKGROUND")
        ownedRegions[region] = true
        local eui = _G.EllesmereUI
        local pp = eui and (eui.PanelPP or eui.PP)
        if pp and type(pp.DisablePixelSnap) == "function" then pcall(pp.DisablePixelSnap, region) end
        region:SetAlpha(0)
        record[key] = region
    end
    local region = record[key]
    alpha = alpha or 1
    if region:GetAlpha() ~= alpha then region:SetAlpha(alpha) end
    return region
end

local function Layout(region)
    local record = ownedLayouts[region]
    if not record then record = {}; ownedLayouts[region] = record end
    return record
end

local function FillColor(region, color)
    local record = Layout(region)
    if not SameProperty(record.color, color, "VertexColor") then
        region:SetColorTexture(unpackValues(color))
        record.color = color
    end
end

local function Fill(frame, key, color, layer, anchor)
    local region = Texture(frame, key, layer)
    if not region then return end
    local record = Layout(region)
    anchor = anchor or frame
    if record.anchor ~= anchor then region:SetAllPoints(anchor); record.anchor = anchor end
    FillColor(region, color)
    return region
end

local function Border(frame, colors, anchor, prefix, alpha, layer)
    anchor, prefix = anchor or frame, prefix or "border"
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local line = Texture(frame, prefix .. side, layer or "BORDER", alpha)
        if line then
            local record, pixel = Layout(line), PixelSize(frame)
            FillColor(line, colors.border)
            if record.anchor ~= anchor or record.pixel ~= pixel then
                line:ClearAllPoints()
                if side == "TOP" or side == "BOTTOM" then
                    line:SetPoint(side .. "LEFT", anchor, side .. "LEFT")
                    line:SetPoint(side .. "RIGHT", anchor, side .. "RIGHT")
                    line:SetHeight(pixel)
                else
                    line:SetPoint("TOP" .. side, anchor, "TOP" .. side)
                    line:SetPoint("BOTTOM" .. side, anchor, "BOTTOM" .. side)
                    line:SetWidth(pixel)
                end
                record.anchor, record.pixel = anchor, pixel
            end
        end
    end
end

local function FadeTextures(frame)
    for _, region in pairs(Regions(frame)) do
        if region.IsObjectType and region:IsObjectType("Texture") then Fade(region) end
    end
end

local function NativeControlFonts(frame)
    if not IsObject(frame) then return end
    if type(frame.GetFont) == "function" then fontRoles[frame] = "native" end
    for _, region in pairs(Regions(frame)) do
        if region.IsObjectType and region:IsObjectType("FontString") then fontRoles[region] = "native" end
    end
end

local PAGE_ARROWS = {
    ["<"] = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png",
    [">"] = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-right.png",
}

local function Control(frame, colors, glyph)
    if not IsObject(frame) then return end
    NativeControlFonts(frame)
    FadeTextures(frame)
    FadeTextures(frame.Arrow)
    for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture"}) do
        if type(frame[getter]) == "function" then Fade(frame[getter](frame)) end
    end
    Fill(frame, "fill", colors.panel)
    Fill(frame, "hover", {1, 1, 1, 0.1}, "HIGHLIGHT")
    Border(frame, colors)
    if glyph then
        local arrow = Texture(frame, "arrow", "OVERLAY")
        if not arrow then return end
        arrow:ClearAllPoints()
        local enabled = not frame.IsEnabled or frame:IsEnabled()
        if PAGE_ARROWS[glyph] then
            arrow:SetTexture(PAGE_ARROWS[glyph])
            arrow:SetSize(14, 14)
            arrow:SetPoint("CENTER", frame, "CENTER")
            arrow:SetAlpha(0.9)
            ApplyProperty(frame, "Alpha", {enabled and 1 or 0.5})
        end
    end
end

local function ScrollBar(bar, colors)
    if not IsObject(bar) then return end
    -- EUI strips modern scrollbar steppers; it does not add boxed text arrows.
    FadeTextures(bar.Back)
    FadeTextures(bar.Forward)
    FadeTextures(bar)
    FadeTextures(bar.Track)
    local thumb = (bar.Track and bar.Track.Thumb) or bar.ThumbTexture
        or (bar.GetThumbTexture and bar:GetThumbTexture())
        or (bar.GetThumb and bar:GetThumb())
    if not thumb then return end
    if thumb.IsObjectType and thumb:IsObjectType("Texture") then Fade(thumb) else
        FadeTextures(thumb)
    end
    local strip = Texture(bar, "thumb", "ARTWORK")
    if strip then
        strip:SetColorTexture(1, 1, 1, 0.3)
        strip:SetPoint("TOP", thumb, "TOP")
        strip:SetPoint("BOTTOM", thumb, "BOTTOM")
        strip:SetWidth(4)
    end
end

local function Tab(button, colors, selected, texture)
    if not IsObject(button) then return end
    for _, key in ipairs({"normal", "active", "glow"}) do Fade(button[key]) end
    Fade(button.icon)
    local icon = Texture(button, "tabIcon", "ARTWORK")
    if icon then
        local record = Layout(icon)
        texture = texture or (button.icon and button.icon.GetTexture and button.icon:GetTexture())
        if record.texture ~= texture then icon:SetTexture(texture); record.texture = texture end
        if not record.anchor then
            -- Native TabSystem icons are centered, with two pixels clipped at top/right.
            icon:SetSize(36, 35)
            icon:SetPoint("CENTER", button, "CENTER")
            if button.CreateMaskTexture and icon.AddMaskTexture then
                local mask = button:CreateMaskTexture(nil, "ARTWORK")
                ownedRegions[mask] = true
                mask:SetAtlas("SquareMask")
                mask:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, -2)
                mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 0)
                icon:AddMaskTexture(mask)
            end
            record.anchor = button
        end
    end
    -- Match EUI's darkActive category tabs.
    Fill(button, "fill", selected and {0.03, 0.03, 0.03, 1} or {0.068, 0.056, 0.052, 1})
    local line = Texture(button, "selection", "OVERLAY")
    if line then
        line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
        line:SetHeight(PixelSize(button))
        line:SetColorTexture(unpackValues(colors.accent))
        line:SetAlpha(selected and colors.accentShown and 1 or 0)
    end
end

local function StyleCategoryTabs(tabs)
    for _, tab in pairs(Children(tabs)) do
        if tab.Icon then
            for _, key in ipairs({"SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow"}) do
                Fade(tab[key])
            end
            local function Changed()
                if Enabled() then ScheduleApply() end
            end
            -- Blizzard reapplies these atlases when a pooled tab is initialized.
            HookMethod(tab, "SetSquareMode", Changed)
            HookMethod(tab, "Init", Changed)
        end
    end
end

local function ReadRegionValue(region, method)
    if not IsObject(region) or type(region[method]) ~= "function" then return end
    local ok, value = pcall(region[method], region)
    if not ok or (_G.issecretvalue and issecretvalue(value)) then return end
    if type(value) == "string" then return value end
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end

local function NativeSpellItem(paged)
    if not paged or type(paged.EnumerateFrames) ~= "function" then return end
    local ok, item = pcall(function()
        for _, candidate in paged:EnumerateFrames() do
            if candidate.Name and candidate.Button then return candidate end
        end
    end)
    if ok then return item end
end

local function FontStyle(source)
    local font = ReadProperty(source, "Font")
    if not font then return end
    local object = ReadProperty(source, "FontObject")
    for _, method in ipairs({"SetFont", "SetFontObject"}) do
        HookMethod(source, method, function()
            if not applying and Enabled() then ScheduleApply() end
        end)
    end
    return {fontPath = font[1], fontFlag = font[3], fontObject = object and object[1],
        shadowColor = ReadProperty(source, "ShadowColor"), shadowOffset = ReadProperty(source, "ShadowOffset")}
end

local function SpellRing(item)
    local button = item and item.Button
    local source = button and button.Border
    local atlas, texture = ReadRegionValue(source, "GetAtlas"), ReadRegionValue(source, "GetTexture")
    if atlas == "" then atlas = nil end
    if not atlas and not texture then return end
    local icon = button.Icon or button.IconTexture or button
    local width, height = ReadRegionValue(source, "GetWidth"), ReadRegionValue(source, "GetHeight")
    local iconWidth, iconHeight = ReadRegionValue(icon, "GetWidth"), ReadRegionValue(icon, "GetHeight")
    local x, y = 1.5, 1.5
    if width and iconWidth and iconWidth > 0 then x = width / iconWidth end
    if height and iconHeight and iconHeight > 0 then y = height / iconHeight end
    if x <= 0 or x > 4 or y <= 0 or y > 4 then x, y = 1.5, 1.5 end
    local coords
    if source.GetTexCoord then
        local values = {pcall(source.GetTexCoord, source)}
        local valid = table.remove(values, 1)
        for _, value in ipairs(values) do
            if (_G.issecretvalue and issecretvalue(value)) or type(value) ~= "number" then valid = false end
        end
        if valid and (#values == 4 or #values == 8) then coords = values end
    end
    return {atlas = atlas, texture = texture, coords = coords, x = x, y = y,
        color = ReadProperty(source, "VertexColor"), blend = ReadRegionValue(source, "GetBlendMode")}
end

local function ResolveColors()
    local root = _G.PlayerSpellsFrame
    local book = root and root.SpellBookFrame
    local paged = book and book.PagedSpellsFrame
    local controls = paged and paged.PagingControls
    local source = controls and controls.PageText
    local primary = ReadColor(source)
    -- EUI whites this native label after the spellbook loads. Before that,
    -- use its verified white default rather than copying unskinned parchment ink.
    if primary and Near(primary[1], 0.19) and Near(primary[2], 0.12)
        and Near(primary[3], 0.06) then primary = nil end
    primary = primary or FALLBACK_COLORS.primary
    HookMethod(source, "SetTextColor", function()
        if Enabled() then ScheduleApply() end
    end)
    for _, method in ipairs({"SetFont", "SetFontObject"}) do
        HookMethod(source, method, function()
            if Enabled() then ScheduleApply() end
        end)
    end
    local colors = {}
    for role, color in pairs(FALLBACK_COLORS) do colors[role] = color end
    colors.primary, colors.strong = primary, primary
    colors.panel, colors.border = {0.08, 0.08, 0.08, 0.92}, {0.2, 0.2, 0.2, 1}
    local eui = _G.EllesmereUI
    local accent = eui.ELLESMERE_GREEN or {}
    local accentBar = _G.EllesmereUIDB and EllesmereUIDB.blizzWinAccentBar
    if accentBar and accentBar.useCustom then accent = accentBar.color or {r = 1, g = 1, b = 1} end
    colors.accent = {accent.r or 0.047, accent.g or 0.824, accent.b or 0.616, 1}
    colors.accentShown = not (accentBar and accentBar.enabled == false)
    if type(eui.GetFontPath) == "function" then
        local ok, path = pcall(eui.GetFontPath, "blizzardSkin")
        if ok and type(path) == "string" then colors.fontPath = path end
    end
    if type(eui.GetFontOutlineFlag) == "function" then
        local ok, flag = pcall(eui.GetFontOutlineFlag, "blizzardSkin")
        if ok and type(flag) == "string" then colors.fontFlag = flag end
    end
    if not colors.fontPath and source and type(source.GetFont) == "function" then
        local ok, path, _, flag = pcall(source.GetFont, source)
        if ok and type(path) == "string" then colors.fontPath, colors.fontFlag = path, flag end
    end
    local shadow = true
    if type(eui.GetFontUseShadow) == "function" then
        local ok, value = pcall(eui.GetFontUseShadow, "blizzardSkin")
        if ok then shadow = value == true end
    end
    colors.shadow = (colors.fontFlag or "") == "" and shadow
    -- EUI's spell items are color-only: their faces/flags/shadows stay Blizzard's.
    local item = NativeSpellItem(paged)
    colors.spellFont = FontStyle(item and item.Name) or FontStyle(_G.GameFontNormal)
    colors.rankFont = FontStyle(item and item.SubName) or FontStyle(_G.GameFontHighlightSmall) or colors.spellFont
    colors.spellRing = SpellRing(item)
    return colors
end

local function WriteColor(text, color)
    local wasApplying = applying
    applying = true
    local ok = pcall(text.SetTextColor, text, color[1], color[2], color[3], color[4])
    applying = wasApplying
    return ok
end

local function WriteString(text, value)
    local wasApplying = applying
    applying = true
    local ok = pcall(text.SetText, text, value)
    applying = wasApplying
    return ok
end

local function RestoreColor(text, state)
    if state.applied and SameColor(ReadColor(text), state.applied) then
        WriteColor(text, state.original)
    end
    state.applied = nil
end

local function RestoreText(text, state)
    RestoreColor(text, state)
    local current, readable = ReadString(text)
    if readable and state.appliedText and current == state.appliedText then
        WriteString(text, state.originalText)
    end
    state.appliedText = nil
end

local function AdaptString(text, state, colors)
    if not state.trackText then return end
    local current, readable = ReadString(text)
    if not readable then return end
    if not state.appliedText or current ~= state.appliedText then
        state.originalText = current
        state.appliedText = nil
    end
    local desired = TranslateString(state.originalText, colors)
    if current ~= desired and WriteString(text, desired) then
        state.appliedText = desired
    end
end

local function RestoreAll()
    for object, record in pairs(appearance) do
        -- Restoring a FontObject also changes face/size/shadow. Capture ownership
        -- first, then restore those properties together, retaining foreign writes.
        local values = {}
        local fontObject = record.FontObject
        local restoreFontObject = fontObject and fontObject.applied
            and SameProperty(ReadProperty(object, "FontObject"), fontObject.applied, "FontObject")
        for _, key in ipairs(PROPERTY_ORDER) do
            local state = record[key]
            if state then
                local current = ReadProperty(object, key)
                if state.applied and SameProperty(current, state.applied, key) then
                    values[key] = state.original
                elseif restoreFontObject and (key == "Font" or key == "ShadowColor" or key == "ShadowOffset") then
                    values[key] = current
                end
                state.applied = nil
            end
        end
        for _, key in ipairs(PROPERTY_ORDER) do
            if values[key] then WriteProperty(object, key, values[key]) end
        end
        record.shadow = nil
        record.fontApplied = nil
    end
    for _, record in pairs(chrome) do
        for _, region in pairs(record) do region:SetAlpha(0) end
    end
    for text, state in pairs(states) do RestoreText(text, state) end
    for object in pairs(nativeHidden) do nativeHidden[object] = nil end
end

local function AdaptText(text, colors, override)
    if not IsObject(text) or (textPass and textPass[text]) then return end
    if textPass then textPass[text] = true end
    AdaptFont(text, colors)
    local current = ReadColor(text)
    if not current then return end
    local state = states[text]
    if not state then
        state = {original = current}
        states[text] = state
        -- Keep native writes even when disabled, including writes matching our palette.
        if not HookMethod(text, "SetTextColor", function(self)
            if applying then return end
            local saved = states[self]
            local native = ReadColor(self)
            if saved and native then
                saved.original = native
                saved.applied = nil
            end
            RefreshText(self)
        end) then
            states[text] = nil
            return
        end
        local function TextChanged(self)
            if applying then return end
            local saved = states[self]
            local native, readable = ReadString(self)
            if saved then
                if readable then saved.originalText = native end
                saved.appliedText = nil
            end
            RefreshText(self)
        end
        state.trackText = HookMethod(text, "SetText", TextChanged)
        if type(text.SetFormattedText) == "function" then
            state.trackText = HookMethod(text, "SetFormattedText", TextChanged) and state.trackText
        end
    end
    AdaptString(text, state, colors)
    if not SameColor(current, state.applied) then
        state.original = current
        state.applied = nil
    end
    local color = override or colors[textRoles[text]] or SemanticColor(state.original, colors)
    if not color then
        RestoreColor(text, state)
        return
    end
    local desired = {color[1], color[2], color[3], state.original[4]}
    if SameColor(current, desired) then return end
    if WriteColor(text, desired) then state.applied = desired end
end

RefreshText = function(text)
    if not Enabled() then return end
    if not activeColors then ScheduleApply(); return end
    local ok, err = pcall(AdaptText, text, activeColors)
    if not ok then
        ns.ReportError(KEY, err)
        SetStatus(ns.errors[KEY])
    end
end

local function Shown(frame)
    return not frame.IsShown or frame:IsShown()
end

local function AdaptRegions(frame, colors)
    if not IsObject(frame) or type(frame.GetRegions) ~= "function" then return end
    local regions = {frame:GetRegions()}
    for _, region in pairs(regions) do
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            AdaptText(region, colors)
        end
    end
end

local function AdaptRows(rows, colors)
    if type(rows) ~= "table" then return end
    for _, row in pairs(rows) do
        if IsObject(row) and Shown(row) then
            for _, key in ipairs(ROW_TEXT) do
                local trainer = key == "heading" and row.spell
                    and row.spell.isHeader and row.spell.npc
                if IsObject(row[key]) then textRoles[row[key]] = trainer and "primary" or nil end
                if IsObject(row[key]) and (key == "name" or key == "rank" or key == "level") then
                    fontRoles[row[key]] = key == "name" and "spellFont" or "rankFont"
                end
                AdaptText(row[key], colors, trainer and colors.primary or nil)
            end
            if type(row.cityIcons) == "table" then
                for _, city in pairs(row.cityIcons) do
                    if IsObject(city) then AdaptText(city.name, colors) end
                end
            end
        end
    end
end

local function AdaptPage(page, colors)
    if not IsObject(page) or not Shown(page) then return end
    if IsObject(page.title) then textRoles[page.title] = "strong" end
    -- Iterate names, not a sparse array of optional FontStrings.
    for _, key in ipairs(PAGE_TEXT) do AdaptText(page[key], colors) end
    if page.pagingControls then AdaptText(page.pagingControls.PageText, colors) end
    AdaptRegions(page.columns, colors)
    AdaptRegions(page.listColumns, colors)
    if page.showKnown then
        if IsObject(page.showKnown.Text) then fontRoles[page.showKnown.Text] = "native" end
        AdaptText(page.showKnown.Text, colors)
    end
    for _, key in ipairs(ROW_GROUPS) do AdaptRows(page[key], colors) end
    if page.cityLegend then AdaptRows(page.cityLegend.entries, colors) end
end

local function RestoreNative()
    for object in pairs(nativeHidden) do
        RestoreProperty(object, "Alpha")
        nativeHidden[object] = nil
    end
end

local function StyleSpellIcon(frame, colors)
    if not frame.iconBorder or not frame.icon or frame.badgeBackground then return end
    local shown = Shown(frame.icon) and Shown(frame.iconBorder)
        and not (frame.spell and frame.spell.isHeader)
    local iconAlpha = ReadRegionValue(frame.icon, "GetAlpha")
    if iconAlpha and iconAlpha <= 0 then shown = false end
    local decorations = chrome[frame]
    if not shown then
        Fade(frame.iconBorder)
        if decorations then
            for _, key in ipairs({"spellRing", "spellEdgeTOP", "spellEdgeBOTTOM", "spellEdgeLEFT", "spellEdgeRIGHT"}) do
                if decorations[key] then decorations[key]:SetAlpha(0) end
            end
        end
        return
    end
    local art = colors.spellRing
    local width, height = ReadRegionValue(frame.icon, "GetWidth"), ReadRegionValue(frame.icon, "GetHeight")
    local rowHeight = ReadRegionValue(frame, "GetHeight")
    local room = rowHeight and rowHeight > 0 and rowHeight - 2 * PixelSize(frame)
    -- Spellbook rings overhang their icons. Dense ledger rows cannot fit them.
    if not room or not height or height * (art and art.y or 1.5) > room then
        Fade(frame.iconBorder)
        if decorations and decorations.spellRing then decorations.spellRing:SetAlpha(0) end
        Border(frame, {border = {0, 0, 0, 1}}, frame.icon, "spellEdge", 1, "OVERLAY")
        return
    end
    if decorations then
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local edge = decorations["spellEdge" .. side]
            if edge then edge:SetAlpha(0) end
        end
    end
    if art and width and height and width > 0 and height > 0 then
        Fade(frame.iconBorder)
        local ring = Texture(frame, "spellRing", "OVERLAY", shown and 0.5 or 0)
        if ring then
            local record = Layout(ring)
            if record.atlas ~= art.atlas or record.texture ~= art.texture then
                if art.atlas then ring:SetAtlas(art.atlas) else ring:SetTexture(art.texture) end
                ring:SetDesaturation(0.5)
                record.atlas, record.texture = art.atlas, art.texture
                record.coords = nil
            end
            if art.coords and not SameCoordinates(record.coords, art.coords) then
                ring:SetTexCoord(unpackValues(art.coords)); record.coords = art.coords
            end
            local color = art.color or {1, 1, 1, 1}
            if not SameProperty(record.vertex, color, "VertexColor") then
                ring:SetVertexColor(unpackValues(color)); record.vertex = color
            end
            if art.blend and record.blend ~= art.blend then ring:SetBlendMode(art.blend); record.blend = art.blend end
            width, height = width * art.x, height * art.y
            if record.anchor ~= frame.icon or record.width ~= width or record.height ~= height then
                ring:ClearAllPoints()
                ring:SetPoint("CENTER", frame.icon, "CENTER")
                ring:SetSize(width, height)
                record.anchor, record.width, record.height = frame.icon, width, height
            end
        end
    else
        ApplyProperty(frame.iconBorder, "Alpha", {shown and 0.5 or 0})
        ApplyProperty(frame.iconBorder, "Desaturation", {0.5})
        local record = chrome[frame]
        if record and record.spellRing then record.spellRing:SetAlpha(0) end
    end
end

local function StyleFrame(frame, colors)
    for _, key in ipairs({"band", "bandCap", "titleBackplate"}) do Fade(frame[key]) end
    if frame.band then
        local fill = Fill(frame, "band", colors.panel, "BACKGROUND", frame.band)
        if fill and frame.band.IsShown then fill:SetAlpha(frame.band:IsShown() and 1 or 0) end
    end
    if frame.rule then
        Fade(frame.rule)
        local line = Fill(frame, "rule", {1, 1, 1, 0.175}, "BACKGROUND", frame.rule)
        if line and frame.rule.IsShown then line:SetAlpha(frame.rule:IsShown() and 1 or 0) end
    end
    if frame.separator then
        FadeTextures(frame.separator)
        local line = Texture(frame.separator, "rule", "BACKGROUND")
        if line then
            local record, pixel = Layout(line), PixelSize(frame.separator)
            if record.anchor ~= frame.separator or record.pixel ~= pixel then
                line:ClearAllPoints()
                line:SetPoint("BOTTOMLEFT", frame.separator, "BOTTOMLEFT")
                line:SetPoint("BOTTOMRIGHT", frame.separator, "BOTTOMRIGHT")
                line:SetHeight(pixel)
                record.anchor, record.pixel = frame.separator, pixel
            end
            FillColor(line, {1, 1, 1, 0.09})
        end
    end
    StyleSpellIcon(frame, colors)
    if frame.city and frame.icon and frame.border then
        Fade(frame.border)
        local state = appearance[frame.border]
        local alpha = state and state.Alpha and state.Alpha.original[1] or 1
        Border(frame, colors, frame.icon, "cityBorder", alpha)
        for _, region in pairs(Regions(frame)) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND" then Fade(region) end
        end
        Fill(frame, "cityFill", colors.panel)
    end
    if frame.backing and frame.art then Fade(frame.backing); Fade(frame.art) end
    if frame.Track and (frame.Back or frame.Forward) then ScrollBar(frame, colors) end
    if frame.ScrollBar then ScrollBar(frame.ScrollBar, colors) end
    if frame.scrollBar then ScrollBar(frame.scrollBar, colors) end
    if frame.searchBox then
        Control(frame.searchBox, colors)
        Fill(frame.searchBox, "fill", {0.02, 0.02, 0.02, 1})
    end
    for _, key in ipairs({"displayDropdown", "priceDropdown", "groupingButton"}) do
        -- These are small icon buttons, not full-width dropdown selectors.
        -- Their native arrows include the correct pressed/hover art and inset.
        NativeControlFonts(frame[key])
    end
    if frame.pagingControls then
        Control(frame.pagingControls.PrevPageButton, colors, "<")
        Control(frame.pagingControls.NextPageButton, colors, ">")
    end
    if frame.header then
        Fade(frame.header.Backplate)
        Fade(frame.header.Border)
        if frame.header.Border then
            local line = Texture(frame.header, "rule", "OVERLAY")
            if line then
                local record, pixel = Layout(line), PixelSize(frame.header)
                if record.anchor ~= frame.header.Border or record.pixel ~= pixel then
                    line:ClearAllPoints()
                    line:SetPoint("LEFT", frame.header.Border, "LEFT", 20, 0)
                    line:SetPoint("RIGHT", frame.header.Border, "RIGHT", 0, 0)
                    line:SetHeight(pixel)
                    record.anchor, record.pixel = frame.header.Border, pixel
                end
                FillColor(line, {1, 1, 1, 0.25})
            end
        end
    end
    if frame.categoryBanner then
        local banner = frame.categoryBanner
        for _, key in ipairs({"art", "border", "iconBorder", "badgeBackground"}) do Fade(banner[key]) end
        -- The native animation reads GetAlpha to finish; hide its rendering
        -- through vertex alpha so its progress and termination stay intact.
        FadeAnimated(banner.glow)
        FadeAnimated(banner.borderGlow)
        Fill(banner, "fill", colors.panel, "BACKGROUND", banner.badgeBackground)
        Fill(banner, "hover", {1, 1, 1, 0.1}, "HIGHLIGHT", banner.badgeBackground)
        Border(banner, colors, banner.badgeBackground)
    end
end

local function WalkVisuals(frame, colors, seen, depth)
    if not IsObject(frame) or seen[frame] or depth > 12 then return end
    seen[frame] = true
    if type(frame.HookScript) == "function" then
        local installed = hooks[frame]
        if not installed then installed = {}; hooks[frame] = installed end
        for _, script in ipairs({"OnShow", "OnEnable", "OnDisable"}) do
            local supported = not frame.HasScript or frame:HasScript(script)
            if supported and not installed[script] and pcall(frame.HookScript, frame, script, function()
                if Enabled() then ScheduleApply() end
            end) then installed[script] = true end
        end
    end
    if not Shown(frame) then return end
    StyleFrame(frame, colors)
    if type(frame.GetTextColor) == "function" then AdaptText(frame, colors) end
    for _, region in pairs(Regions(frame)) do
        if not ownedRegions[region] and region.IsObjectType and region:IsObjectType("FontString") then
            AdaptText(region, colors)
        end
    end
    for _, child in pairs(Children(frame)) do WalkVisuals(child, colors, seen, depth + 1) end
end

local function ApplyVisuals(frame, colors)
    local overlay = _G.WhatsTrainingOverlay
    local root = _G.PlayerSpellsFrame
    local book = root and root.SpellBookFrame
    local selected = overlay and type(overlay.IsShown) == "function" and overlay:IsShown()
    local tabs = book and book.CategoryTabSystem
    local nativeTab = tabs and tabs.selectedTabID and type(tabs.GetTabButton) == "function"
        and tabs:GetTabButton(tabs.selectedTabID)
    StyleCategoryTabs(tabs)
    -- The real spellbook backdrop stays in place, including its dim page art.
    -- Only native content behind the training tab is suppressed while it is open.
    if selected and book then
        local current = {}
        for _, child in pairs(Children(book)) do
            if child ~= book.CategoryTabSystem and child ~= overlay then
                current[child] = true
                nativeHidden[child] = true
                ApplyProperty(child, "Alpha", {0})
            end
        end
        -- WT's return button sits over this tab without changing its selection.
        -- Mask the native skin's underline too, leaving the other tabs visible.
        if overlay.returnTab and Shown(overlay.returnTab) and nativeTab then
            current[nativeTab], nativeHidden[nativeTab] = true, true
            ApplyProperty(nativeTab, "Alpha", {0})
        end
        for object in pairs(nativeHidden) do
            if not current[object] then RestoreProperty(object, "Alpha"); nativeHidden[object] = nil end
        end
    else RestoreNative() end
    local seen = {}
    WalkVisuals(overlay or frame, colors, seen, 0)
    WalkVisuals(frame.weaponPage, colors, seen, 0)
    local launcher = _G.WhatsTrainingLauncher
    Tab(launcher, colors, selected, TRAINING_TAB_ICON)
    local nativeIcon = nativeTab and nativeTab.Icon
    Tab(overlay and overlay.returnTab, colors, false,
        nativeIcon and nativeIcon.GetTexture and nativeIcon:GetTexture())
end

local function HookPage(page)
    if not IsObject(page) then return end
    local function Changed()
        if Enabled() then ScheduleApply() end
    end
    HookMethod(page.content, "SetHeight", Changed)
    if type(page.HookScript) ~= "function" then return end
    local installed = hooks[page]
    if not installed then
        installed = {}
        hooks[page] = installed
    end
    for _, script in ipairs({"OnShow", "OnHide", "OnSizeChanged", "OnClick", "OnEnable", "OnDisable"}) do
        local supported = not page.HasScript or page:HasScript(script)
        if supported and not installed[script] and pcall(page.HookScript, page, script, Changed) then
            installed[script] = true
        end
    end
end

local function InstallHooks()
    local eui = _G.EllesmereUI
    for _, method in ipairs(EUI_REFRESH) do
        HookMethod(eui, method, function()
            if Enabled() then ScheduleApply() end
        end)
    end
    local frame = _G.WhatsTrainingFrame
    HookPage(frame)
    HookPage(frame and frame.weaponPage)
    local overlay = _G.WhatsTrainingOverlay
    HookPage(overlay)
    HookPage(_G.WhatsTrainingLauncher)
    local installed = overlay and hooks[overlay]
    if installed and not installed.restoreNative and type(overlay.HookScript) == "function" then
        overlay:HookScript("OnHide", RestoreNative)
        installed.restoreNative = true
    end
    local root = _G.PlayerSpellsFrame
    local book = root and root.SpellBookFrame
    HookPage(book)
    local function Changed()
        if Enabled() then ScheduleApply() end
    end
    HookPage(overlay and overlay.returnTab)
    -- WT refreshes this icon after pooled category buttons are replaced.
    HookMethod(overlay and overlay.returnTab and overlay.returnTab.icon, "SetTexture", Changed)
    HookMethod(book, "SetTab", Changed)
    local tabs = book and book.CategoryTabSystem
    HookMethod(tabs, "SetTab", Changed)
    HookMethod(tabs, "SetTabVisuallySelected", Changed)
end

local function Apply()
    if not ns.ready then return end
    if not Enabled() then
        activeColors = nil
        RestoreAll()
        SetStatus("Disabled")
        return
    end
    InstallHooks()
    local supported, style = UsesDarkStyle()
    if not supported then
        activeColors = nil
        RestoreAll()
        SetStatus("Inactive: EUI spellbook skin is unavailable or not EUI/Modern")
        return
    end
    local frame = _G.WhatsTrainingFrame
    if not frame then
        activeColors = nil
        RestoreAll()
        SetStatus("Waiting for What's Training?")
        return
    end
    local colors = ResolveColors()
    activeColors = colors
    AdaptPage(frame, colors)
    AdaptPage(frame.weaponPage, colors)
    ApplyVisuals(frame, colors)
    SetStatus("Active: " .. style .. " spellbook theme")
end

local function SafeApply()
    if not ns.ready then return end
    textPass = {}
    local ok, err = pcall(Apply)
    textPass = nil
    if ok then
        ns.ClearError(KEY)
    else
        ns.ReportError(KEY, err)
        SetStatus(ns.errors[KEY])
    end
end

ScheduleApply = function()
    if pending or applying or not Enabled() then return end
    if not (_G.C_Timer and type(C_Timer.After) == "function") then
        SafeApply()
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        SafeApply()
    end)
end

function Module:Initialize()
    if initialized then return end
    initialized = true
    self:ApplySettings()
end

function Module:ApplySettings()
    if not ns.ready then return end
    -- Disable restores synchronously; queued work also rechecks readiness/settings.
    if Enabled() then ScheduleApply() else SafeApply() end
end

function Module:OnAddonLoaded(name)
    if Enabled() and (name == "WhatsTraining" or name == "Blizzard_PlayerSpells"
        or ns.IsEUIAddon(name)) then ScheduleApply() end
end

function Module:GetStatus()
    return status
end

ns.RegisterModule(KEY, Module)

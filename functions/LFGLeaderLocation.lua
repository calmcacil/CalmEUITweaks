local _, ns = ...
local module = {}
ns.RegisterModule("lfgLeaderLocation", module)

local labels = setmetatable({}, { __mode = "k" })
local hooked = false
local events = CreateFrame("Frame")

local function HideLabels()
    for _, label in pairs(labels) do label:Hide() end
end

function module:UpdateEntry(entry)
    local label = labels[entry]
    if label then label:Hide() end
    if not ns.GetSettings("lfgLeaderLocation").enabled then return end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("lfgLeaderLocation", "Waiting for combat to end.")
        return
    end
    local activity, display = entry.ActivityName, entry.DataDisplay
    local api = _G.C_LFGList
    if not entry:IsShown() or not entry.resultID or not activity or not display
        or not api or type(api.GetSearchResultLeaderInfo) ~= "function" then return end
    local leader = api.GetSearchResultLeaderInfo(entry.resultID)
    local area = leader and leader.areaName
    if type(area) ~= "string" or not area:find("%S") then return end
    local left, right = activity:GetRight(), display:GetLeft()
    if not left or not right or right - left <= 16 then return end

    if not label then
        label = entry:CreateFontString(nil, "ARTWORK")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetPoint("LEFT", activity, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", display, "LEFT", -8, 0)
        labels[entry] = label
    end
    -- Sample the skinned row so EUI remains the owner of its typography.
    label:SetFontObject(activity:GetFontObject())
    label:SetFont(activity:GetFont())
    label:SetShadowColor(activity:GetShadowColor())
    label:SetShadowOffset(activity:GetShadowOffset())
    local _, _, _, alpha = activity:GetTextColor()
    label:SetTextColor(0.45, 0.8, 1, alpha)
    label:SetHeight(activity:GetHeight())
    label:SetText(area)
    label:Show()
end

function module:ApplySettings()
    events:UnregisterAllEvents()
    if not ns.GetSettings("lfgLeaderLocation").enabled then
        HideLabels()
        ns.SetStatus("lfgLeaderLocation", "Disabled")
        return
    end
    local api = _G.C_LFGList
    if type(_G.LFGBrowseSearchEntry_Update) ~= "function"
        or not api or type(api.GetSearchResultLeaderInfo) ~= "function" then
        HideLabels()
        ns.SetStatus("lfgLeaderLocation", "Waiting for the Looking For Group UI.")
        return
    end
    if InCombatLockdown() then
        HideLabels()
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("lfgLeaderLocation", "Waiting for combat to end.")
        return
    end
    if not hooked then
        hooksecurefunc("LFGBrowseSearchEntry_Update", function(entry)
            if ns.GetSettings("lfgLeaderLocation").enabled then
                ns.CallModule("lfgLeaderLocation", "UpdateEntry", entry)
            end
        end)
        hooked = true
    end
    local browse = _G.LFGBrowseFrame
    local scrollBox = browse and browse.ScrollBox
    if scrollBox and type(scrollBox.ForEachFrame) == "function" then
        scrollBox:ForEachFrame(function(entry) self:UpdateEntry(entry) end)
    end
    ns.SetStatus("lfgLeaderLocation", "Enabled; showing group leaders' zones.")
end

function module:OnAddonLoaded(name)
    if name == "Blizzard_GroupFinder_VanillaStyle" and ns.GetSettings("lfgLeaderLocation").enabled then
        ns.RequestApply("lfgLeaderLocation")
    end
end

events:SetScript("OnEvent", function()
    ns.RequestApply("lfgLeaderLocation")
end)

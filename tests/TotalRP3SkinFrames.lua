local root = "CalmEUITweaks/"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function Sandbox()
    local s = { ns = {}, calls = {}, hooks = 0, errors = {}, activeErrors = {}, enabled = true }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    s.env = env
    env.hooksecurefunc = function(object, method, callback)
        s.hooks = s.hooks + 1
        local original = object[method]
        object[method] = function(...)
            local result = original(...)
            callback(...)
            return result
        end
    end
    local skin = {}
    s.skin = skin
    for _, key in ipairs({ "Button", "Panel", "Shell", "Font", "ScrollBar", "EditBox", "Tab",
        "SetTabSelection", "FadeRegions", "FadeNineSlice", "Inset", "CloseButton", "SquareIcon",
        "Dropdown", "Checkbox", "ApplyBarFill", "PageButton" }) do
        local kind = key
        skin[kind] = function(frame, ...)
            s.calls[#s.calls + 1] = { kind = kind, frame = frame, args = { ... } }
            if s.failure == frame then error("paint failed") end
        end
    end
    function s:frame(name, fields)
        local frame = fields or {}
        frame.name = name
        frame.GetName = function() return name end
        frame.GetChildren = function(self) return unpack(self.children or {}) end
        env[name] = frame
        return frame
    end
    function s:count(kind, frame)
        local count = 0
        for _, call in ipairs(self.calls) do
            if call.kind == kind and (not frame or call.frame == frame) then count = count + 1 end
        end
        return count
    end
    s.allowed = function() return s.enabled, s.deferred end
    s.report = function(surface, err)
        s.activeErrors[surface] = err
        if err then s.errors[#s.errors + 1] = { surface, err }
        else s.recovered = (s.recovered or 0) + 1 end
    end
    local chunk = assert(loadfile(root .. "functions/TotalRP3SkinFrames.lua"))
    setfenv(chunk, env)
    chunk("CalmEUITweaks", s.ns)
    function s:apply() return self.ns.TotalRP3SkinFrames.Apply(self.skin, self.allowed, self.report) end
    function s:install() self.ns.TotalRP3SkinFrames.InstallHooks(self.skin, self.allowed, self.report) end
    return s
end

local s = Sandbox()
local background = {}
local backdrop = {}
local authored = {}
local main = s:frame("TRP3_MainFrame", { Backdrop = backdrop, Background = background })
local html = s:frame("TRP3_RegisterAbout_AboutPanel_Template1", { authored = authored })
local shared = s:frame("GameTooltip")
local result = s:apply()
Check(s:count("Shell", main) == 1 and s:count("FadeRegions", backdrop) == 1,
    "Main shell and child decorative backdrop must both be covered")
Check(s:count("Font", html) == 0 and s:count("Panel", html) == 0,
    "Player-authored profile HTML must stay outside primitive passes")
Check(s:count("Panel", shared) == 0, "Shared Blizzard tooltip must not be styled")
Check(result.applied > 0 and result.unsupported:find("Native exceptions", 1, true),
    "Native coverage exceptions must be reported explicitly")
local calls = #s.calls
s:apply()
Check(#s.calls == calls, "Repeated setup must not allocate or repaint existing primitives")

s = Sandbox()
local preview = s:frame("TRP3_ImageBrowserContent", { preview = {} })
local warning = {}
local import = { Backdrop = {}, WarningIcon = warning, ImportButton = {} }
s:frame("TRP3_ProfileCreateDialog", { Frames = { ImportFrame = import } })
local color = s:frame("TRP3_ColorBrowser", { Content = {
    AcceptButton = {}, PresetButton = {}, HexInput = {},
    ColorSelect = { WheelTexture = {} }, PreviewSwatch = { ReadableColorWarningIcon = {} },
} })
s:apply()
Check(s:count("Panel", preview) == 0, "Image canvas must not receive destructive generic art removal")
Check(s:count("Shell", import) == 0 and s:count("Shell", import.Backdrop) == 1,
    "Import shell must target dedicated backdrop so warning artwork remains visible")
Check(s:count("Button", color.Content.AcceptButton) == 1 and s:count("EditBox", color.Content.HexInput) == 1,
    "Color browser controls belong to Content and must receive their primitives")
Check(s:count("Button", color.Content.PreviewSwatch) == 0
    and s:count("Panel", color.Content.ColorSelect) == 0,
    "Color wheel and semantic preview/warning regions must retain native content")

s = Sandbox()
local fields = s:frame("TRP3_RegisterCharact_Edit_CharactPanel_Container", { children = {} })
local add = s:frame("TRP3_RegisterCharact_Edit_MiscAdd", { scripts = {} })
local created
add.scripts.OnClick = function()
    created = { NameField = {}, ValueField = {}, value = "Native draft" }
    fields.children[#fields.children + 1] = created
end
add.HookScript = function(self, event, callback)
    local original = self.scripts[event]
    self.scripts[event] = function(...)
        if original then original(...) end
        callback(...)
    end
end
s:install()
add.scripts.OnClick(add)
Check(created.value == "Native draft" and s:count("EditBox", created.NameField) == 1
    and s:count("EditBox", created.ValueField) == 1,
    "Post-OnClick integration must style rows created by the original lexical editor callback")

s = Sandbox()
s.env.TRP3_API = { configuration = { registerConfigurationPage = function() end } }
s:install()
local foreign = { frame = { Background = {} }, elements = { { widget = { EditBox = {} } } }, id = "extension_page" }
s.env.TRP3_API.configuration.registerConfigurationPage(foreign)
Check(#s.calls == 0, "A foreign configuration registration must not receive generic styling")
local input = {}
local config = s:frame("TRP3_ConfigurationPage1", {
    IsShown = function() return true end,
    ScrollFrame = { Content = { GetChildren = function() return { EditBox = input } end } },
})
s:frame("TRP3_MainFramePageContainer", { children = { config } })
s.ns.TotalRP3SkinFrames.PageOpened("extension_page")
Check(#s.calls == 0, "Foreign PAGE_OPENED must not style a coincidentally visible core-shaped frame")
s.ns.TotalRP3SkinFrames.PageOpened("main_config_toolbar")
Check(s:count("EditBox", input) == 1, "Known core configuration rows must style through PAGE_OPENED")

s = Sandbox()
local tooltip = s:frame("TRP3_MainTooltip")
local toolbar = s:frame("TRP3_ToolbarFrame", { Container = {} })
local target = s:frame("TRP3_TargetFrame")
local glance = s:frame("TRP3_GlanceBar")
s.env.ElvUI = {}
s.env.TRP3_API = {
    module = { isModuleLoaded = function(id) return id == "trp3_elvui" end },
    configuration = { getValue = function(key) return key ~= "elvui_skin_toolbar_frame" end },
}
result = s:apply()
Check(s:count("Panel", tooltip) == 0 and s:count("Panel", target) == 0
    and s:count("Panel", glance) == 0, "Active ElvUI skins must retain owned overlapping surfaces")
Check(s:count("Panel", toolbar.Container) == 1, "A nonconflicting toolbar may still receive EUI styling")
Check(result.conflict and result.conflict:find("ElvUI", 1, true), "Skipped conflicts must report why")

s = Sandbox()
local icon = { SetTexCoord = function() end }
local button = { Icon = icon, status = "IC", mask = {} }
local nativeCalls = 0
local browser = s:frame("TRP3_IconBrowserFrame", {
    OnIconButtonInitialized = function(_, received)
        nativeCalls = nativeCalls + 1
        received.nativeInitialized = true
        return "original result"
    end,
})
s:install()
local hooks = s.hooks
s:install()
Check(s.hooks == hooks, "Installing late-widget hooks twice must not duplicate them")
Check(browser:OnIconButtonInitialized(button) == "original result" and nativeCalls == 1,
    "Skin hook must preserve the native call and return")
Check(s:count("SquareIcon", icon) == 1 and button.status == "IC" and button.mask,
    "Late icon setup must retain status data and content masks")
browser:OnIconButtonInitialized(button)
Check(s:count("SquareIcon", icon) == 1, "Pooled icon reuse must not create styling resources again")
local lateIcon = { SetTexCoord = function() end }
s.enabled = false
s.deferred = true
browser:OnIconButtonInitialized({ Icon = lateIcon })
Check(s:count("SquareIcon", lateIcon) == 0, "Blocked dynamic work must not mutate frames")
s.enabled = true
s.deferred = false
s:apply()
Check(s:count("SquareIcon", lateIcon) == 1, "Deferred dynamic instances must be styled after readiness")
local disabledIcon = { SetTexCoord = function() end }
s.enabled = false
browser:OnIconButtonInitialized({ Icon = disabledIcon })
s.enabled = true
s:apply()
Check(s:count("SquareIcon", disabledIcon) == 0, "Disabled hooks must not retain new deferred work")

s = Sandbox()
local tab = {
    Text = {}, Icon = {},
    IsMouseEnabled = function() return false end,
    IsEnabled = function() return true end,
    SetTabState = function(self, state) self.state = state end,
}
s:frame("TRP3_RegisterMainTabBar", { children = { tab } })
s:apply()
Check(s:count("Tab", tab) == 1 and s:count("SetTabSelection", tab) == 1,
    "Existing copied tab instances need their own primitive and current selection")
tab:SetTabState("NORMAL")
local last = s.calls[#s.calls]
Check(last.kind == "SetTabSelection" and last.args[1] == false and tab.state == "NORMAL",
    "Custom tab state must reach EUI without replacing TRP3's state")
s.enabled = false
calls = #s.calls
tab:SetTabState("SELECTED")
Check(#s.calls == calls, "Disabled tab hooks must not write appearance")

s = Sandbox()
local category = {
    Text = {}, selected = true,
    IsEnabled = function(self) return not self.selected end,
    SetSelected = function(self, selected) self.selected = selected end,
}
s:frame("TRP3_MainFrameMenuContainer", { children = { category } })
s:apply()
local initialSelection
for _, call in ipairs(s.calls) do
    if call.kind == "SetTabSelection" and call.frame == category then initialSelection = call.args[1] end
end
Check(initialSelection == true, "Sidebar must seed the already-selected native category")
s.enabled, s.deferred = false, true
calls = s:count("SetTabSelection", category)
category:SetSelected(false)
Check(s:count("SetTabSelection", category) == calls, "Combat-deferred sidebar state must not paint early")
s.enabled, s.deferred = true, false
s:apply()
last = s.calls[#s.calls]
Check(last.kind == "SetTabSelection" and last.frame == category and last.args[1] == false,
    "A bounded resumed apply must restore current sidebar selection after deferral")

s = Sandbox()
local failing = s:frame("TRP3_MainFrame")
local healthy = s:frame("TRP3_LinkCopyDialog")
s.failure = failing
s:apply()
Check(#s.errors == 1 and s:count("Shell", healthy) == 1,
    "A surface error must be reported while unrelated surfaces remain usable")
s:apply()
Check(#s.errors == 1, "Repeated failure must not report on every refresh")
s.failure = nil
s:apply()
Check(s.recovered == 1, "A recovered frame must release its own error")
print("PASS: Total RP 3 skin surfaces (" .. checks .. " assertions)")

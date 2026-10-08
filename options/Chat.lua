local _, ns = ...

local function Guard(callback)
    return function(...)
        local ok, err = pcall(callback, ...)
        if not ok then ns.ReportError("options", err) end
    end
end

local function Run(action, success, ...)
    local ok, reason = ns.Chat[action](...)
    ns.Print(ok and success or reason or "Chat setup could not be updated.")
    if ns.RefreshOptions then ns.RefreshOptions() end
    EllesmereUI:RefreshPage()
end

ns.ChatOptions = {
    SaveDefault = Guard(function()
        EllesmereUI:ShowConfirmPopup({
            title = "Save Chat Default",
            message = "Save this character's current chat setup as the account-wide default? This replaces the previous default for all characters.",
            confirmText = "Save Default", cancelText = "Cancel",
            onConfirm = Guard(function()
                Run("SaveDefault", "Chat default saved from this character.")
            end),
        })
    end),
    ApplyDefault = Guard(function()
        EllesmereUI:ShowConfirmPopup({
            title = "Apply Chat Default",
            message = "Replace this character's normal chat tabs and message/channel routing with the saved default? Extra normal tabs will be closed and required channels joined. Window position, size, styling, history, combat-log filters and the reserved voice tab stay local.",
            confirmText = "Apply Default", cancelText = "Cancel",
            onConfirm = Guard(function()
                Run("ApplyDefault", "Chat default applied to this character.")
            end),
        })
    end),
    ExportDefault = Guard(function()
        local text, reason = ns.Chat.ExportDefault()
        if not text then ns.Print(reason); return end
        EllesmereUI:ShowInputPopup({
            title = "Export Chat Default",
            message = "Copy this string to share the saved chat default. It contains no chat history or channel passwords.",
            initialText = text, maxLetters = 65536,
            confirmText = "Done", cancelText = "Close",
            extraButton = {
                text = "Select All",
                onClick = Guard(function(editBox)
                    editBox:SetFocus()
                    editBox:HighlightText()
                end),
            },
        })
    end),
    ImportDefault = Guard(function()
        EllesmereUI:ShowInputPopup({
            title = "Import Chat Default",
            message = "Paste a Calm UI Tweaks chat setup string. Import replaces the account-wide default but does not apply it now. If auto-apply is enabled, characters use it after their next login.",
            placeholder = "Chat setup string", maxLetters = 65536,
            confirmText = "Import Default", cancelText = "Cancel",
            onConfirm = Guard(function(text)
                Run("ImportDefault", "Chat default imported. Use Apply Default to apply it now.", text)
            end),
        })
    end),
}

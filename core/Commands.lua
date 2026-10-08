local _, ns = ...

SLASH_CALMUITWEAKS1 = "/calmtweaks"
SlashCmdList.CALMUITWEAKS = function(message)
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "status" then
        ns.Print("Options: " .. (ns.errors.options or ns.optionsRenderError or ns.optionsError
            or (ns.optionsInstalled and "registered via EUI plugin API" or "unavailable")))
        for _, key in ipairs(ns.moduleOrder) do ns.Print(key .. ": " .. ns.GetStatus(key)) end
    elseif command == "macro-name" then
        local ok, err = ns.SetSetting("mageMacro", "name", argument)
        ns.Print(ok and "Macro name changed; previous macros are left intact." or err)
    elseif command == "reset" then
        if argument == "confirm" then
            ns.ResetSettings()
            ns.Print("Personal preferences reset. Macro ownership and existing macros are preserved. The saved chat default is retained.")
        else
            ns.Print("Type /calmtweaks reset confirm to reset only this addon's preferences.")
        end
    elseif command == "" then
        if not ns.OpenOptions or not ns.OpenOptions() then
            ns.Print(ns.optionsError or "EUI options are unavailable, or you are in combat.")
        end
    else
        ns.Print("Commands: /calmtweaks, status, macro-name <name>, reset confirm.")
    end
end

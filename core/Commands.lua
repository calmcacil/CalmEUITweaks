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
        if ns.RequestReset then
            ns.RequestReset()
        else
            ns.Print("EUI reset confirmation is unavailable; preferences were not reset.")
        end
    elseif command == "" then
        if not ns.OpenOptions or not ns.OpenOptions() then
            ns.Print(ns.optionsError or "EUI options are unavailable, or you are in combat.")
        end
    else
        ns.Print("Commands: /calmtweaks, status, macro-name <name>, reset.")
    end
end

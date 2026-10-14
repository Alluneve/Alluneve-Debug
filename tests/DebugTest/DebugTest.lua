local ADDON_NAME = ...

---@type AlluneveDebugAPI
local debugAPI

local function Register()
    debugAPI = Alluneve.Debug.RegisterYourself(ADDON_NAME)
    print("DebugTest: Registered as " .. ADDON_NAME)
end

Register()

SLASH_ALLUNEVEDEBUGTEST1 = "/alludebugtest"

SlashCmdList["ALLUNEVEDEBUGTEST"] = function(message)
    local command, argument = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()

    if command == "register" then
        Register()
        return
    end

    local loggingMethods = {
        debug = "Debug",
        info = "Info",
        warn = "Warn",
        error = "Error"
    }

    local method = loggingMethods[command]

    if method then
        debugAPI[method](argument ~= "" and argument or ("DebugTest " .. method))
        print("DebugTest: Called " .. method)
        return
    end

    if command == "submit" then
        debugAPI.SubmitLog()
        print("DebugTest: Submission requested")
        return
    end

    if command == "print" then
        debugAPI.TogglePrint()
        print("DebugTest: Toggled chat output")
        return
    end

    if command == "trigger" then
        debugAPI.TriggerRecorder()
        print("DebugTest: Flight recorder triggered")
        return
    end

    if command == "crash" then
        C_Timer.After(0, function()
            error("DebugTest intentional Lua error")
        end)
        return
    end

    print("DebugTest commands:")
    print("/alludebugtest register")
    print("/alludebugtest debug [message]")
    print("/alludebugtest info [message]")
    print("/alludebugtest warn [message]")
    print("/alludebugtest error [message]")
    print("/alludebugtest submit")
    print("/alludebugtest print")
    print("/alludebugtest trigger")
end

local ADDON_NAME, private = ...

local Debug = private.Debug
local FlightRecorder = private.FlightRecorder
local RollingLog = private.RollingLog
local RegisteredDebugAddons = {}
local Severity = private.RollingLog.Severity

-- Business Logic --

local function IdentifyAddonFromError(message)
    -- Explicit taint attribution.
    local taintedAddon =
        message:match("tainted by%s*'([^']+)'")
        or message:match('tainted by%s*"([^"]+)"')

    if taintedAddon and RegisteredDebugAddons[taintedAddon] then
        return taintedAddon
    end

    -- Protected function attribution.
    local blockedAddon = message:match(
        "^%[ADDON_ACTION_[A-Z_]+%]%s+AddOn '([^']+)'"
    )

    if blockedAddon and RegisteredDebugAddons[blockedAddon] then
        return blockedAddon
    end

    -- Extract the originating Lua file from the error header.
    local sourcePath = message:match(
        "^([^:\r\n]+%.lua):%-?%d+:"
    )

    if not sourcePath then
        return nil
    end

    -- Normalize Windows-style and Unix-style paths.
    sourcePath = sourcePath:gsub("\\", "/")

    for addonName in pairs(RegisteredDebugAddons) do
        local addonPath = addonName .. "/"

        if sourcePath:sub(1, #addonPath) == addonPath
            or sourcePath:find("/" .. addonPath, 1, true) then
            return addonName
        end
    end

    return nil
end


-- Slash Commands --

local function PrintFlightRecorderSettings()
    print(string.format(
        "Alluneve-Debug: Capture: %ss | Post-trigger: %ss | Ticker: %ss",
        FlightRecorder.GetCaptureSeconds(),
        FlightRecorder.GetPostTriggerSeconds(),
        FlightRecorder.GetTickerTimer()
    ))
end

local timingSetters = {
    capture = FlightRecorder.SetCaptureSeconds,
    posttrigger = FlightRecorder.SetPostTriggerSeconds,
    ticker = FlightRecorder.SetTickerTimer,
}

local function HandleSlashCommand(message)
    local target, command, value, extra =
        message:match("^%s*(%S*)%s*(%S*)%s*(%S*)%s*(.-)%s*$")

    local globalCommand = target:lower()

    if globalCommand == "" or globalCommand == "show" then
        PrintFlightRecorderSettings()
        return
    end

    local setter = timingSetters[globalCommand]

    if setter then
        local seconds = tonumber(command)

        if not seconds or seconds <= 0
            or seconds >= math.huge
            or seconds ~= seconds
            or value ~= ""
            or extra ~= "" then
            print("Alluneve-Debug: Seconds must be a positive finite number.")
            return
        end

        setter(seconds)
        PrintFlightRecorderSettings()
        return
    end

    local addonIdentifier = target
    local action = command:lower()

    if action == "trigger" or action == "submit" then
        if not RegisteredDebugAddons[addonIdentifier] then
            print("Alluneve-Debug: Addon Identifier " .. addonIdentifier .. " not registered.")
            return
        end

        if action == "submit" then
            if extra ~= "" then
                print("Alluneve-Debug: Too many arguments.")
                return
            end

            local severity

            if value ~= "" then
                severity = Severity[value:upper()]

                if not severity then
                    print("Alluneve-Debug: Invalid severity: " .. value)
                    return
                end
            end

            Debug.SubmitLog(addonIdentifier, severity)
        else
            if value ~= "" or extra ~= "" then
                print("Alluneve-Debug: Trigger does not accept arguments.")
                return
            end

            FlightRecorder.Trigger(addonIdentifier)
        end
        return
    end

    print("Usage: /alludebug [show | capture | posttrigger | ticker] <seconds>")
    print("       /alludebug <addonIdentifier> [trigger | submit] [severity]")
end


local function OnBugGrabbed(_, errorID)
    local errorObject = BugGrabber:GetErrorByID(errorID)

    if not errorObject then
        return
    end

    local message = errorObject.message

    if issecretvalue(message) then
        return
    end

    if type(message) ~= "string" then
        return
    end

    local addonName = IdentifyAddonFromError(message)

    if addonName then
        FlightRecorder.Trigger(addonName)
    end
end



local function Initialize()
    AlluneveDebugDB = AlluneveDebugDB or {}

    FlightRecorder.Initialize({ database = AlluneveDebugDB })
    Debug.Initialize({ database = AlluneveDebugDB, recorder = FlightRecorder })

    EventRegistry:RegisterCallback(
        "BugGrabber.BugGrabbed",
        OnBugGrabbed
    )
    SLASH_ALLUDEBUG1 = "/alludebug"
    SlashCmdList.ALLUDEBUG = HandleSlashCommand
end


-- Initialization --

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, Initialize)

-- Public Interfaces --

local API = {}

---@class AlluneveDebugAPI
---@field Info fun(...: any) Records an informational message.
---@field Debug fun(...: any) Records a debug message.
---@field Warn fun(...: any) Records a warning.
---@field Error fun(...: any) Records an error and triggers the recorder.
---@field SubmitLog fun() Submits the session log to BugGrabber.
---@field TogglePrint fun(): boolean Toggles chat output.
---@field TriggerRecorder fun() Manually triggers the flight recorder.
---@field ToggleDebugLog fun() Deprecated: Does nothing. Removal in 2.0.0.
---@field ToggleDebugPrint fun(): boolean Deprecated: Use TogglePrint(). Removal in 2.0.0.
---@field Print fun(...: any) Deprecated: Use Debug(). Removal in 2.0.0.
---@field Log fun(...: any) Deprecated: Use Debug(). Removal in 2.0.0.

---@param addonIdentifier string
---@return AlluneveDebugAPI
function API.RegisterYourself(addonIdentifier)
    assert(
        type(addonIdentifier) == "string" and addonIdentifier ~= "",
        "Alluneve-Debug: Invalid addon identifier"
    )

    if RegisteredDebugAddons[addonIdentifier] then
        return RegisteredDebugAddons[addonIdentifier]
    end

    ---@type AlluneveDebugAPI
    local addonAPI = {
        ---Records an informational message in the session log and flight recorder.
        ---@param ... any Message values to log
        Info = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.INFO, ...)
        end,
        ---Records a debug message in the session log and flight recorder.
        ---@param ... any Message values to log
        Debug = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.DEBUG, ...)
        end,
        ---Records a warning message in the session log and flight recorder.
        ---@param ... any Message values to log
        Warn = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.WARN, ...)
        end,
        ---Records an error message in the session log and flight recorder, and triggers the flight recorder for submission.
        ---@param ... any Message values to log
        Error = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.ERROR, ...)
            FlightRecorder.Trigger(addonIdentifier)
        end,
        -- Submit API
        ---Submits the debug log
        SubmitLog = function()
            Debug.SubmitLog(addonIdentifier)
        end,
        -- Toggle Debug Print API
        ---Toggles the debug print status
        ---@return boolean status The new debug print status
        TogglePrint = function()
            return Debug.TogglePrint(addonIdentifier)
        end,
        -- Trigger Recorder API
        ---Triggers the flight recorder
        TriggerRecorder = function()
            FlightRecorder.Trigger(addonIdentifier)
        end,


        -- Deprecated APIs
        ---@deprecated  marked for removal in 2.0.0, does nothing anymore
        ToggleDebugLog = function()
        end,
        ---@deprecated Use TogglePrint(...) instead, marked for removal in 2.0.0
        ToggleDebugPrint = function()
            return Debug.TogglePrint(addonIdentifier)
        end,
        ---@deprecated Use Log Statements instead, marked for removal in 2.0.0
        Print = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.DEBUG, ...)
        end,
        ---@deprecated Use Debug(...) instead, marked for removal in 2.0.0
        Log = function(...)
            Debug.Log(addonIdentifier, RollingLog.Severity.DEBUG, ...)
        end,
    }
    RegisteredDebugAddons[addonIdentifier] = addonAPI
    return addonAPI
end

-- Other public methods...

_G.Alluneve = _G.Alluneve or {}
_G.Alluneve.Debug = API

local _, private = ...
local Debug = {}

local db
local flightRecorder
local helper = private.Helper
local RollingLog = private.RollingLog

-- Constructor --

---@param params { database: table, recorder: table }
function Debug.Initialize(params)
    params.database.Debug = params.database.Debug or {}
    db = params.database.Debug
    flightRecorder = params.recorder
end

private.Debug = Debug

-- Module Variables --

local MAX_LOG_BYTES = 1024 * 1024

---@type table<string, RollingLog>
local debugLogs = {}

-- Implementation --

local function GetAddonSettings(addonIdentifier)
    local settings = db[addonIdentifier]

    if not settings then
        settings = {}
        db[addonIdentifier] = settings
    end

    if settings.DebugPrintSwitch == nil then
        settings.DebugPrintSwitch = false
    end

    return settings
end

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param timestamp number
---@return LogObject
local function Append(addonIdentifier, severity, message, timestamp)
    local log = debugLogs[addonIdentifier]

    if not log then
        log = RollingLog.CreateRollingLog()
        debugLogs[addonIdentifier] = log
    end

    local logObject = RollingLog.CreateLogObject(severity, message, timestamp)
    log.Append(logObject)

    -- Enforce the session log's memory limit on insertion.
    while log.GetAproximateByteSize() > MAX_LOG_BYTES do
        log.RemoveOldest()
    end

    return logObject
end

---@param addonIdentifier string
---@param severity Severity
---@param ... any
local function Log(addonIdentifier, severity, ...)
    local message = helper.FormatMessage(...)
    local timestamp = GetTimePreciseSec()

    flightRecorder.Record(addonIdentifier, severity, message, timestamp)

    local logObject = Append(addonIdentifier, severity, message, timestamp)

    local settings = GetAddonSettings(addonIdentifier)
    if settings.DebugPrintSwitch then
        print(helper.LogObjectToString(addonIdentifier, logObject))
    end
end

---@param addonIdentifier string
---@param severity Severity?
local function SubmitLog(addonIdentifier, severity)
    local log = debugLogs[addonIdentifier]
    if not log then
        return
    end

    ---@type LogObject[]
    local logObjects = {}

    for logObject in log.Iterator() do
        logObjects[#logObjects + 1] = logObject
    end
    if not severity or severity == private.RollingLog.Severity.DEBUG then
        if helper.SendToBugGrabber(addonIdentifier, logObjects) then
            log.Clear()
        end
    else
        helper.SendToBugGrabber(addonIdentifier, logObjects, severity)
    end
end

---@param addonIdentifier string
local function ClearLog(addonIdentifier)
    local log = debugLogs[addonIdentifier]

    if log then
        log.Clear()
        debugLogs[addonIdentifier] = nil
    end
end

---@param addonIdentifier string
---@return boolean
local function TogglePrint(addonIdentifier)
    local settings = GetAddonSettings(addonIdentifier)

    settings.DebugPrintSwitch =
        not settings.DebugPrintSwitch

    return settings.DebugPrintSwitch
end

---@param addonIdentifier string
---@return boolean, boolean
local function GetState(addonIdentifier)
    local settings = GetAddonSettings(addonIdentifier)

    return settings.DebugPrintSwitch, true
end

-- Interfaces --

---@param addonIdentifier string
---@param severity Severity
---@param ... any
function Debug.Log(addonIdentifier, severity, ...)
    Log(addonIdentifier, severity, ...)
end

---@param addonIdentifier string
---@param severity Severity?
function Debug.SubmitLog(addonIdentifier, severity)
    SubmitLog(addonIdentifier, severity)
end

---@param addonIdentifier string
function Debug.Clear(addonIdentifier)
    ClearLog(addonIdentifier)
end

---@param addonIdentifier string
---@return boolean
function Debug.TogglePrint(addonIdentifier)
    return TogglePrint(addonIdentifier)
end

---@param addonIdentifier string
---@return boolean, boolean
function Debug.GetState(addonIdentifier)
    return GetState(addonIdentifier)
end

local _, private = ...
local Debug = {}

local db
local flightRecorder

-- Constructor --

---@param params { database: table, recorder: table }
function Debug.Initialize(params)
    params.database.Debug = params.database.Debug or {}
    db = params.database.Debug
    flightRecorder = params.recorder
end

private.Debug = Debug

-- Module Variables --

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

    if settings.DebugLogSwitch == nil then
        settings.DebugLogSwitch = false
    end

    return settings
end

local function DebugPrint(addonIdentifier, ...)
    flightRecorder.Record(addonIdentifier, ...)

    local settings = GetAddonSettings(addonIdentifier)

    if settings.DebugPrintSwitch then
        print(...)
    end
end

local function DebugLog(addonIdentifier, ...)
    local settings = GetAddonSettings(addonIdentifier)

    if settings.DebugLogSwitch then
        debugLogs[addonIdentifier] =
            debugLogs[addonIdentifier] or {}

        table.insert(debugLogs[addonIdentifier], {
            n = select("#", ...),
            ...
        })
    end

    DebugPrint(addonIdentifier, ...)
end

local function SubmitDebugLog(addonIdentifier)
    local lines = {
        string.format(
            "%s Debug Log",
            addonIdentifier
        )
    }

    local debugLog = debugLogs[addonIdentifier] or {}

    for i, entry in ipairs(debugLog) do
        local values = {}

        for j = 1, entry.n do
            local value = entry[j]

            if issecretvalue(value) then
                values[j] = "<secret>"
            else
                values[j] = tostring(value)
            end
        end

        table.insert(lines, string.format(
            "[%d] %s",
            i,
            table.concat(values, " ")
        ))
    end

    BugGrabber:StoreError({
        message = table.concat(lines, "\n"),
        session = BugGrabber:GetSessionId(),
        time = date("%Y/%m/%d %H:%M:%S"),
        counter = 1,
    })
end

local function ClearDebugLog(addonIdentifier)
    debugLogs[addonIdentifier] = nil
end

local function TogglePrintSwitch(addonIdentifier)
    local settings = GetAddonSettings(addonIdentifier)

    settings.DebugPrintSwitch =
        not settings.DebugPrintSwitch

    return settings.DebugPrintSwitch
end

local function ToggleLogSwitch(addonIdentifier)
    local settings = GetAddonSettings(addonIdentifier)

    settings.DebugLogSwitch =
        not settings.DebugLogSwitch

    return settings.DebugLogSwitch
end

local function GetDebugState(addonIdentifier)
    local settings = GetAddonSettings(addonIdentifier)

    return settings.DebugPrintSwitch,
        settings.DebugLogSwitch
end

-- Interfaces --

---@param addonIdentifier string
function Debug.Print(addonIdentifier, ...)
    DebugPrint(addonIdentifier, ...)
end

---@param addonIdentifier string
function Debug.Log(addonIdentifier, ...)
    DebugLog(addonIdentifier, ...)
end

---@param addonIdentifier string
function Debug.PrintLog(addonIdentifier)
    SubmitDebugLog(addonIdentifier)
end

---@param addonIdentifier string
function Debug.Clear(addonIdentifier)
    ClearDebugLog(addonIdentifier)
end

---@param addonIdentifier string
---@return boolean
function Debug.TogglePrint(addonIdentifier)
    return TogglePrintSwitch(addonIdentifier)
end

---@param addonIdentifier string
---@return boolean
function Debug.ToggleLog(addonIdentifier)
    return ToggleLogSwitch(addonIdentifier)
end

---@param addonIdentifier string
---@return boolean, boolean
function Debug.GetState(addonIdentifier)
    return GetDebugState(addonIdentifier)
end
local ADDON_NAME, private = ...

local Debug = private.Debug
local FlightRecorder = private.FlightRecorder
local RegisteredDebugAddons = {}

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
    local command, value =
        message:lower():match("^%s*(%S*)%s*(%S*)")

    if command == "" or command == "show" then
        PrintFlightRecorderSettings()
        return
    end

    local setter = timingSetters[command]

    if not setter then
        print("Usage: /alludebug [show | capture | posttrigger | ticker] <seconds>")
        return
    end

    local seconds = tonumber(value)

    if not seconds or seconds <= 0
        or seconds >= math.huge
        or seconds ~= seconds then
        print("Alluneve-Debug: Seconds must be a positive finite number.")
        return
    end

    setter(seconds)
    PrintFlightRecorderSettings()
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

---@param addonIdentifier string
---@return table
function API.RegisterYourself(addonIdentifier)
    assert(
        type(addonIdentifier) == "string" and addonIdentifier ~= "",
        "Alluneve-Debug: Invalid addon identifier"
    )

    if RegisteredDebugAddons[addonIdentifier] then
        return RegisteredDebugAddons[addonIdentifier]
    end

    local addonAPI = {
        -- Print API
        Print = function(...)
            Debug.Print(addonIdentifier, ...)
        end,
        -- Log API
        Log = function(...)
            Debug.Log(addonIdentifier, ...)
        end,
        -- SubmitLog API
        SubmitLog = function()
            Debug.PrintLog(addonIdentifier)
        end,
        -- Toggle Debug Print API
        ToggleDebugPrint = function()
            return Debug.TogglePrint(addonIdentifier)
        end,
        -- Toggle Debug Log API
        ToggleDebugLog = function()
            return Debug.ToggleLog(addonIdentifier)
        end,
    }
    RegisteredDebugAddons[addonIdentifier] = addonAPI
    return addonAPI
end

-- Other public methods...

_G.Alluneve = _G.Alluneve or {}
_G.Alluneve.Debug = API

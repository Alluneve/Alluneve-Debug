local _, private = ...
local FlightRecorder = {}
local RollingLog = private.RollingLog

local db
local StartCleanupTicker

-- Constructor --

---@param params { database: table }
function FlightRecorder.Initialize(params)
    params.database.FlightRecorder =
        params.database.FlightRecorder or {}

    db = params.database.FlightRecorder

    if type(db.CaptureSeconds) ~= "number"
        or db.CaptureSeconds <= 0 then
        db.CaptureSeconds = 60
    end

    if type(db.PostTriggerSeconds) ~= "number"
        or db.PostTriggerSeconds <= 0 then
        db.PostTriggerSeconds = 10
    end

    if type(db.TickerTimer) ~= "number"
        or db.TickerTimer <= 0 then
        db.TickerTimer = 60
    end

    StartCleanupTicker()
end

private.FlightRecorder = FlightRecorder

-- Module Variables --

local CLEANUP_FRAME_BUDGET_MS = 0.5
local CLEANUP_WINDOW_FRACTION = 5 / 6

---@type table<string, RollingLog>
local currentFlightRecorders = {}

local activeTriggers = {}

local cleanupTicker
local cleanupWork

local cleanupFrame = CreateFrame("Frame")
cleanupFrame:Hide()

-- Implementation --

-- Event storage --

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param timestamp number
local function RecordFlightEvent(addonIdentifier, severity, message, timestamp)
    local log = currentFlightRecorders[addonIdentifier]

    if not log then
        log = RollingLog.CreateRollingLog()
        currentFlightRecorders[addonIdentifier] = log
    end

    log.Append(RollingLog.CreateLogObject(severity, message, timestamp))
end

-- Global rolling cleanup --

-- Remove expired events from the oldest end of a log.
-- Return false when the current frame's budget is exhausted.
---@param log RollingLog
---@param cutoff number
---@param frameDeadline number
---@return boolean
local function CleanHistory(log, cutoff, frameDeadline)
    while true do
        if debugprofilestop() >= frameDeadline then
            return false
        end

        local maxTimestamp = log.GetOldestPageMaxTimeStamp()

        -- No pages left to clean.
        if not maxTimestamp then
            return true
        end

        -- Entire oldest page has expired.
        if maxTimestamp < cutoff then
            log.EvictOldestPage()
        else
            -- Check individual entries within the oldest page.
            local oldest = log.PeekOldest()

            if not oldest or oldest.timestamp >= cutoff then
                return true
            end

            log.RemoveOldest()
        end
    end
end

local function StopCleanupPass()
    cleanupWork = nil
    cleanupFrame:Hide()
end

local function BeginCleanupPass()
    -- Never run overlapping cleanup passes.
    if cleanupWork then
        return
    end

    local identifiers = {}

    for addonIdentifier in pairs(currentFlightRecorders) do
        identifiers[#identifiers + 1] = addonIdentifier
    end

    if #identifiers == 0 then
        return
    end

    local now = GetTimePreciseSec()

    cleanupWork = {
        identifiers = identifiers,
        index = 1,
        cutoff = now - db.CaptureSeconds,
        deadline = now
            + db.TickerTimer * CLEANUP_WINDOW_FRACTION,
    }

    cleanupFrame:Show()
end

local function ProcessCleanupSlice()
    local work = cleanupWork

    if not work then
        cleanupFrame:Hide()
        return
    end

    -- Stop this cycle before the next global tick.
    if GetTimePreciseSec() >= work.deadline then
        StopCleanupPass()
        return
    end

    local frameDeadline =
        debugprofilestop() + CLEANUP_FRAME_BUDGET_MS

    while work.index <= #work.identifiers do
        local addonIdentifier =
            work.identifiers[work.index]

        local log =
            currentFlightRecorders[addonIdentifier]

        -- Preserve complete histories during an
        -- active post-trigger recording window.
        if log and not activeTriggers[addonIdentifier] then
            local completed = CleanHistory(
                log,
                work.cutoff,
                frameDeadline
            )

            if not completed then
                -- Resume the same addon next frame.
                return
            end

            -- Release empty rolling logs.
            if not log.PeekOldest() then
                currentFlightRecorders[addonIdentifier] = nil
            end
        end

        work.index = work.index + 1

        if debugprofilestop() >= frameDeadline then
            return
        end
    end

    StopCleanupPass()
end

cleanupFrame:SetScript(
    "OnUpdate",
    ProcessCleanupSlice
)

StartCleanupTicker = function()
    if cleanupTicker then
        return
    end

    BeginCleanupPass()

    cleanupTicker = C_Timer.NewTicker(
        db.TickerTimer,
        BeginCleanupPass
    )
end

-- Report submission --

---@param addonIdentifier string
---@param triggerTime number?
local function SubmitFlightRecorder(addonIdentifier, triggerTime)
    local log = currentFlightRecorders[addonIdentifier]

    if not log then
        return
    end

    ---@type LogObject[]
    local logObjects = {}

    for logObject in log.Iterator() do
        logObjects[#logObjects + 1] = logObject
    end

    if private.Helper.SendToBugGrabber(
        addonIdentifier,
        logObjects,
        nil,
        triggerTime
    ) then
        log.Clear()
    end
end

-- Trigger management --

---@param addonIdentifier string
local function TriggerFlightRecorder(addonIdentifier)
    local trigger = activeTriggers[addonIdentifier]

    if not trigger then
        trigger = {
            timer = nil,
            timestamp = nil,
        }

        activeTriggers[addonIdentifier] = trigger
    end

    -- Repeated triggers update the reference timestamp
    -- and extend the post-trigger recording window.
    trigger.timestamp = GetTimePreciseSec()

    if trigger.timer then
        trigger.timer:Cancel()
    end

    trigger.timer = C_Timer.NewTimer(
        db.PostTriggerSeconds,
        function()
            trigger.timer = nil

            SubmitFlightRecorder(addonIdentifier, trigger.timestamp)

            currentFlightRecorders[addonIdentifier] = nil
            activeTriggers[addonIdentifier] = nil
        end
    )
end

---@param addonIdentifier string
local function ClearFlightRecorder(addonIdentifier)
    if activeTriggers[addonIdentifier] then
        return
    end

    currentFlightRecorders[addonIdentifier] = nil
end

-- Configuration validation --

---@param seconds number
local function ValidateSeconds(seconds)
    if type(seconds) ~= "number"
        or seconds ~= seconds
        or seconds <= 0
        or seconds >= math.huge then
        error(
            "Alluneve-Debug: Seconds must be a positive finite number",
            3
        )
    end
end


-- Interfaces --

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param timestamp number
function FlightRecorder.Record(addonIdentifier, severity, message, timestamp)
    RecordFlightEvent(addonIdentifier, severity, message, timestamp)
end

---@param addonIdentifier string
function FlightRecorder.Trigger(addonIdentifier)
    TriggerFlightRecorder(addonIdentifier)
end

---@param addonIdentifier string
function FlightRecorder.Clear(addonIdentifier)
    ClearFlightRecorder(addonIdentifier)
end

---@return number
function FlightRecorder.GetTickerTimer()
    return db.TickerTimer
end

---@return number
function FlightRecorder.GetPostTriggerSeconds()
    return db.PostTriggerSeconds
end

---@return number
function FlightRecorder.GetCaptureSeconds()
    return db.CaptureSeconds
end

---@param seconds number
function FlightRecorder.SetTickerTimer(seconds)
    ValidateSeconds(seconds)

    db.TickerTimer = seconds

    if cleanupTicker then
        cleanupTicker:Cancel()
        cleanupTicker = nil
    end

    StopCleanupPass()
    StartCleanupTicker()
end

---@param seconds number
function FlightRecorder.SetPostTriggerSeconds(seconds)
    ValidateSeconds(seconds)
    db.PostTriggerSeconds = seconds
end

---@param seconds number
function FlightRecorder.SetCaptureSeconds(seconds)
    ValidateSeconds(seconds)

    db.CaptureSeconds = seconds

    StopCleanupPass()
    BeginCleanupPass()
end

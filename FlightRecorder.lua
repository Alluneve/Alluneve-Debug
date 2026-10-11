local _, private = ...
local FlightRecorder = {}

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

local currentFlightRecorders = {}
local activeTriggers = {}
local cleanupTicker

-- Implementation --

-- Global rolling cleanup --

local function CleanCurrentFlightRecorders()
    local cutoff = GetTimePreciseSec() - db.CaptureSeconds

    for addonIdentifier, history in pairs(currentFlightRecorders) do
        -- Do not discard events while this addon's
        -- post-trigger recording window is active.
        if not activeTriggers[addonIdentifier] then
            while history[1]
                and history[1].timestamp < cutoff do
                table.remove(history, 1)
            end

            if #history == 0 then
                currentFlightRecorders[addonIdentifier] = nil
            end
        end
    end
end

StartCleanupTicker = function()
    if cleanupTicker then
        return
    end

    CleanCurrentFlightRecorders()

    cleanupTicker = C_Timer.NewTicker(
        db.TickerTimer,
        CleanCurrentFlightRecorders
    )
end

-- Event recording --

local function RecordFlightEvent(addonIdentifier, ...)
    local history = currentFlightRecorders[addonIdentifier]

    if not history then
        history = {}
        currentFlightRecorders[addonIdentifier] = history
    end

    table.insert(history, {
        timestamp = GetTimePreciseSec(),
        n = select("#", ...),
        ...
    })
end

-- Report submission --

local function SubmitFlightRecorder(addonIdentifier, triggeredAt)
    local history = currentFlightRecorders[addonIdentifier] or {}

    local lines = {
        string.format(
            "%s Flight Recorder - triggered at %.3f",
            addonIdentifier,
            triggeredAt
        )
    }

    for i, entry in ipairs(history) do
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
            "%.3f [%d] %s",
            entry.timestamp,
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

-- Trigger management --

local function TriggerFlightRecorder(addonIdentifier)
    local trigger = activeTriggers[addonIdentifier]

    if not trigger then
        trigger = {
            triggeredAt = GetTimePreciseSec(),
            timer = nil,
        }

        activeTriggers[addonIdentifier] = trigger
    end

    -- Repeated triggers for the same addon extend
    -- its post-trigger recording window.
    if trigger.timer then
        trigger.timer:Cancel()
    end

    trigger.timer = C_Timer.NewTimer(
        db.PostTriggerSeconds,
        function()
            trigger.timer = nil

            SubmitFlightRecorder(
                addonIdentifier,
                trigger.triggeredAt
            )

            -- Reset only the triggered addon's history.
            currentFlightRecorders[addonIdentifier] = nil
            activeTriggers[addonIdentifier] = nil
        end
    )
end

local function ClearFlightRecorder(addonIdentifier)
    -- Never clear an active post-trigger recording.
    if activeTriggers[addonIdentifier] then
        return
    end

    currentFlightRecorders[addonIdentifier] = nil
end

---@param seconds number
local function ValidateSeconds(seconds)
    if type(seconds) ~= "number"
        or seconds ~= seconds
        or seconds <= 0
        or seconds == math.huge then
        error("Alluneve-Debug: Seconds must be a positive finite number", 3)
    end
end

-- Interfaces --

---@param addonIdentifier string
function FlightRecorder.Record(addonIdentifier, ...)
    RecordFlightEvent(addonIdentifier, ...)
end

---@param addonIdentifier string
function FlightRecorder.Trigger(addonIdentifier)
    TriggerFlightRecorder(addonIdentifier)
end

---@param addonIdentifier string
function FlightRecorder.Clear(addonIdentifier)
    ClearFlightRecorder(addonIdentifier)
end

---@return integer
function FlightRecorder.GetTickerTimer()
    return db.TickerTimer
end

---@return integer
function FlightRecorder.GetPostTriggerSeconds()
    return db.PostTriggerSeconds
end

---@return integer
function FlightRecorder.GetCaptureSeconds()
    return db.CaptureSeconds
end

---@param seconds integer
function FlightRecorder.SetTickerTimer(seconds)
    ValidateSeconds(seconds)
    db.TickerTimer = seconds

    if cleanupTicker then
        cleanupTicker:Cancel()
        cleanupTicker = nil
    end

    StartCleanupTicker()
end

---@param seconds integer
function FlightRecorder.SetPostTriggerSeconds(seconds)
    ValidateSeconds(seconds)
    db.PostTriggerSeconds = seconds
end

---@param seconds integer
function FlightRecorder.SetCaptureSeconds(seconds)
    ValidateSeconds(seconds)

    db.CaptureSeconds = seconds
    CleanCurrentFlightRecorders()
end

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

local PAGE_SIZE = 256
local CLEANUP_FRAME_BUDGET_MS = 0.5
local CLEANUP_WINDOW_FRACTION = 5 / 6

local currentFlightRecorders = {}
local activeTriggers = {}

local cleanupTicker
local cleanupWork

local cleanupFrame = CreateFrame("Frame")
cleanupFrame:Hide()

-- Implementation --

-- Event storage --

local function CreateHistory()
    return {
        firstPage = nil,
        lastPage = nil,
    }
end

local function CreatePage()
    return {
        entries = {},
        firstIndex = 1,
        count = 0,
        lastTimestamp = 0,
        next = nil,
    }
end

local function RecordFlightEvent(addonIdentifier, ...)
    local history = currentFlightRecorders[addonIdentifier]

    if not history then
        history = CreateHistory()
        currentFlightRecorders[addonIdentifier] = history
    end

    local page = history.lastPage

    if not page or page.count >= PAGE_SIZE then
        local newPage = CreatePage()

        if page then
            page.next = newPage
        else
            history.firstPage = newPage
        end

        history.lastPage = newPage
        page = newPage
    end

    local timestamp = GetTimePreciseSec()

    page.count = page.count + 1
    page.lastTimestamp = timestamp

    page.entries[page.count] = {
        timestamp = timestamp,
        n = select("#", ...),
        ...
    }
end

-- Global rolling cleanup --

local function DropFirstPage(history)
    local page = history.firstPage

    history.firstPage = page.next

    if not history.firstPage then
        history.lastPage = nil
    end
end

-- Remove expired entries from the beginning of a history.
-- Return false when the current frame's budget is exhausted.
local function CleanHistory(history, cutoff, frameDeadline)
    while history.firstPage do
        if debugprofilestop() >= frameDeadline then
            return false
        end

        local page = history.firstPage

        -- Entire page expired: discard it without
        -- iterating through its individual entries.
        if page.lastTimestamp < cutoff then
            DropFirstPage(history)
        else
            -- Only the oldest page can be partially expired.
            while page.firstIndex <= page.count do
                if debugprofilestop() >= frameDeadline then
                    return false
                end

                local entry = page.entries[page.firstIndex]

                if entry.timestamp >= cutoff then
                    return true
                end

                page.entries[page.firstIndex] = nil
                page.firstIndex = page.firstIndex + 1
            end

            DropFirstPage(history)
        end
    end

    return true
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

        local history =
            currentFlightRecorders[addonIdentifier]

        -- Preserve the complete recording while an
        -- addon has an active post-trigger window.
        if history and not activeTriggers[addonIdentifier] then
            local completed = CleanHistory(
                history,
                work.cutoff,
                frameDeadline
            )

            if not completed then
                -- Resume this same addon on the next frame.
                return
            end

            if not history.firstPage then
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

local function SubmitFlightRecorder(addonIdentifier, triggeredAt)
    local history = currentFlightRecorders[addonIdentifier]

    local lines = {
        string.format(
            "%s Flight Recorder - triggered at %.3f",
            addonIdentifier,
            triggeredAt
        )
    }

    local eventIndex = 0
    local page = history and history.firstPage

    while page do
        for i = page.firstIndex, page.count do
            local entry = page.entries[i]
            local values = {}

            for j = 1, entry.n do
                local value = entry[j]

                if issecretvalue(value) then
                    values[j] = "<secret>"
                else
                    values[j] = tostring(value)
                end
            end

            eventIndex = eventIndex + 1

            lines[#lines + 1] = string.format(
                "%.3f [%d] %s",
                entry.timestamp,
                eventIndex,
                table.concat(values, " ")
            )
        end

        page = page.next
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

            currentFlightRecorders[addonIdentifier] = nil
            activeTriggers[addonIdentifier] = nil
        end
    )
end

local function ClearFlightRecorder(addonIdentifier)
    if activeTriggers[addonIdentifier] then
        return
    end

    currentFlightRecorders[addonIdentifier] = nil
end

-- Configuration validation --

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
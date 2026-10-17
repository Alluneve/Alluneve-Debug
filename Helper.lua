local _, private = ...
local Helper = {}

private.Helper = Helper
local Severity = private.RollingLog.Severity
local severityOrder = {
    [Severity.DEBUG] = 1,
    [Severity.INFO] = 2,
    [Severity.WARN] = 3,
    [Severity.ERROR] = 4
}

function Helper.FormatMessage(...)
    local values = {}

    for i = 1, select("#", ...) do
        local value = select(i, ...)

        if issecretvalue(value) then
            values[i] = "<secret>"
        else
            values[i] = tostring(value)
        end
    end

    return table.concat(values, " ")
end

---@overload fun(addonIdentifier: string, logObject: LogObject): string
---@param addonIdentifier string
---@param logObject LogObject
---@param referenceTimestamp number?
---@return string
function Helper.LogObjectToString(addonIdentifier, logObject, referenceTimestamp)
    local prefix

    if referenceTimestamp then
        prefix = string.format(
            "[%+.6f] %-5s ",
            logObject.timestamp - referenceTimestamp,
            logObject.severity
        )
    else
        local elapsed = GetTimePreciseSec() - logObject.timestamp
        local formattedTime = date("%H:%M:%S", time() - elapsed)
        prefix = string.format(
            "[%s : %s - %s]: ",
            formattedTime,
            addonIdentifier,
            logObject.severity
        )
    end

    return prefix .. logObject.message
end

local MAX_REPORT_PAGE_LENGTH = 80000

---@overload fun(addonIdentifier: string, logObjects: LogObject[]): boolean
---@overload fun(addonIdentifier: string, logObjects: LogObject[], minimumSeverity: Severity): boolean
---@overload fun(addonIdentifier: string, logObjects: LogObject[], minimumSeverity: Severity?, triggerTime: number?): boolean
---@param addonIdentifier string
---@param logObjects LogObject[]
---@param minimumSeverity Severity?
---@param triggerTime number?
---@return boolean
function Helper.SendToBugGrabber(addonIdentifier, logObjects, minimumSeverity, triggerTime)
    minimumSeverity = minimumSeverity or Severity.DEBUG

    local filteredObjects = {}

    for _, logObject in ipairs(logObjects) do
        if severityOrder[logObject.severity] >= severityOrder[minimumSeverity] then
            filteredObjects[#filteredObjects + 1] = logObject
        end
    end

    if #filteredObjects == 0 then
        return false
    end

    local submittedAt = date("%Y/%m/%d %H:%M:%S")

    -- Use the trigger time when available, otherwise the first original log entry.
    local referenceTimestamp = triggerTime or logObjects[1].timestamp
    local elapsed = GetTimePreciseSec() - referenceTimestamp
    local referenceDate = date("%Y/%m/%d %H:%M:%S", time() - elapsed)

    local prefix = {
        string.format("Alluneve-Debug Report: %s", addonIdentifier),
        string.format(
            "%s (approx): %s",
            triggerTime and "Triggered" or "Started",
            referenceDate
        ),
        string.format("Submitted: %s", submittedAt),
        string.format("Entries: %d", #filteredObjects),
        string.format("Log Level: %s", minimumSeverity),
    }

    local pages = {}
    local currentPage = {}
    local currentLength = 0

    for _, logObject in ipairs(filteredObjects) do
        local line = Helper.LogObjectToString(
            addonIdentifier,
            logObject,
            triggerTime
        )

        local lineLength = #line + 1 -- Include newline separator.

        -- Reject an individual entry that cannot fit on a page.
        if lineLength > MAX_REPORT_PAGE_LENGTH then
            return false
        end

        -- Start a new page when the log content exceeds 80,000 characters.
        if currentLength + lineLength > MAX_REPORT_PAGE_LENGTH and #currentPage > 0 then
            pages[#pages + 1] = currentPage
            currentPage = {}
            currentLength = 0
        end

        currentPage[#currentPage + 1] = line
        currentLength = currentLength + lineLength
    end

    if #currentPage > 0 then
        pages[#pages + 1] = currentPage
    end

    local sessionId = BugGrabber:GetSessionId()

    for pageNumber, pageLines in ipairs(pages) do
        local lines = {}

        for _, headerLine in ipairs(prefix) do
            lines[#lines + 1] = headerLine
        end

        lines[#lines + 1] = string.format(
            "Page: %d/%d",
            pageNumber,
            #pages
        )
        lines[#lines + 1] = ""

        for _, line in ipairs(pageLines) do
            lines[#lines + 1] = line
        end

        local errorObject = {
            message = table.concat(lines, "\n"),
            session = sessionId,
            time = submittedAt,
            counter = 1,
        }

        local success = pcall(
            BugGrabber.StoreError,
            BugGrabber,
            errorObject
        )

        if not success then
            return false
        end
    end

    return true
end
local _, private = ...
local Helper = {}
private.Helper = Helper

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
            "[+%.6f] %-5s ",
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

---@param addonIdentifier string
---@param logObjects LogObject[]
---@return boolean
function Helper.SendToBugGrabber(addonIdentifier, logObjects)
    if #logObjects == 0 then
        return false
    end

    local referenceTimestamp = logObjects[1].timestamp
    local submittedAt = date("%Y/%m/%d %H:%M:%S")

    local elapsed = GetTimePreciseSec() - referenceTimestamp
    local startedAt = date("%Y/%m/%d %H:%M:%S", time() - elapsed)

    local lines = {
        string.format("Alluneve-Debug Report: %s", addonIdentifier),
        string.format("Started (approx): %s", startedAt),
        string.format("Submitted: %s", submittedAt),
        string.format("Entries: %d", #logObjects),
        ""
    }

    for _, logObject in ipairs(logObjects) do
        lines[#lines + 1] = Helper.LogObjectToString(
            addonIdentifier,
            logObject,
            referenceTimestamp
        )
    end

    local errorObject = {
        message = table.concat(lines, "\n"),
        session = BugGrabber:GetSessionId(),
        time = submittedAt,
        counter = 1,
    }

    return pcall(BugGrabber.StoreError, BugGrabber, errorObject)
end

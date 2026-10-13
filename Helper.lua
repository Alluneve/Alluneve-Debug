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


---@param addonIdentifier string
---@param logObject LogObject
---@return string
function Helper.LogObjectToString(addonIdentifier, logObject)
    return string.format(
        "[%s : %s - %s]: %s",
        logObject.timestamp,
        addonIdentifier,
        logObject.severity,
        logObject.message
    )
end

---@param addonIdentifier string
---@param logObjects LogObject[]
function Helper.SendToBugGrabber(addonIdentifier, logObjects)
    if #logObjects == 0 then
        return
    end

    local lines = {}

    for i, logObject in ipairs(logObjects) do
        lines[i] = Helper.LogObjectToString(addonIdentifier, logObject)
    end

    BugGrabber:StoreError({
        message = table.concat(lines, "\n"),
        session = BugGrabber:GetSessionId(),
        time = date("%Y/%m/%d %H:%M:%S"),
        counter = 1,
    })
end

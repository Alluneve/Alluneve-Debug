local PAGE_SIZE = 256

-- Plain Old Lua Objects --
---@class RollingLog
---@field Append fun(logObject: LogObject)
---@field PeekOldest fun(): LogObject?
---@field RemoveOldest fun(): LogObject?
---@field EvictOldestPage fun()
---@field GetOldestPageMaxTimeStamp fun(): number?
---@field Clear fun()
---@field Iterator fun(): fun(): LogObject?
---@field GetAproximateByteSize fun(): number


---@enum Severity
Severity = {
    DEBUG = "DEBUG",
    INFO = "INFO",
    WARN = "WARN",
    ERROR = "ERROR",
}

---@class LogObject
---@field severity Severity
---@field timestamp number
---@field message string

---@overload fun(severity: Severity, message: string): LogObject
---@param severity Severity
---@param message string
---@param timestamp number
---@return LogObject
function CreateLogObject(severity, message, timestamp)
    return {
        severity = severity,
        timestamp = timestamp or GetTimePreciseSec(),
        message = message
    }
end

---@class RollingPage
---@field entries table<integer, LogObject>
---@field firstIndex integer
---@field count integer
---@field maxTimeStamp number
---@field next RollingPage?
---@field aproxByteSize number

---@return RollingPage
local function CreatePage()
    return {
        entries = {},
        firstIndex = 1,
        count = 0,
        maxTimeStamp = 0,
        next = nil,
        aproxByteSize = 0
    }
end

---@class RollingState
---@field firstPage RollingPage?
---@field lastPage RollingPage?
---@field aproxByteSize number
---@field iteratorVersion number

---@return RollingState
local function CreateRollingState()
    return {
        firstPage = nil,
        lastPage = nil,
        aproxByteSize = 0,
        iteratorVersion = 1
    }
end

---@param LogObject LogObject
local function getEntrySize(LogObject)
    return #LogObject.message + #LogObject.severity + 128
end

-- Private Methods --
---@param state RollingState
---@param LogObject LogObject
local function Append(state, LogObject)
    ---@type RollingPage?
    local page = state.lastPage
    if not page then
        page = CreatePage()
        state.firstPage = page
        state.lastPage = page
    end

    if page.count >= PAGE_SIZE then
        local newPage = CreatePage()
        page.next = newPage
        state.lastPage = newPage
        page = newPage
    end

    page.count = page.count + 1
    page.maxTimeStamp = math.max(page.maxTimeStamp, LogObject.timestamp)
    page.entries[page.count] = LogObject
    local objSize = getEntrySize(LogObject)
    state.aproxByteSize = state.aproxByteSize + objSize
    page.aproxByteSize = page.aproxByteSize + objSize
end

---@param state RollingState
---@return LogObject?
local function PeekOldest(state)
    if not state.firstPage then
        return nil
    end
    return state.firstPage.entries[state.firstPage.firstIndex]
end

---@param state RollingState
---@return LogObject?
local function RemoveOldest(state)
    local oldest = PeekOldest(state)
    if not oldest then
        return nil
    end

    local page = assert(state.firstPage)
    page.entries[page.firstIndex] = nil
    page.firstIndex = page.firstIndex + 1

    if page.firstIndex > page.count then
        state.firstPage = page.next

        if state.firstPage then
            state.aproxByteSize = state.aproxByteSize - page.aproxByteSize
        else
            state.lastPage = nil
            state.aproxByteSize = 0
        end
    else
        local objSize = getEntrySize(oldest)
        page.aproxByteSize = page.aproxByteSize - objSize
        state.aproxByteSize = state.aproxByteSize - objSize
    end

    state.iteratorVersion  = state.iteratorVersion + 1
    return oldest
end

---@param state RollingState
---@return nil
local function EvictOldestPage(state)
    local page = state.firstPage
    if not page then
        return
    end

    state.firstPage = page.next
    state.aproxByteSize = state.aproxByteSize - page.aproxByteSize

    if not state.firstPage then
        state.lastPage = nil
        state.aproxByteSize = 0
    end
    state.iteratorVersion = state.iteratorVersion +1
end

---@param state RollingState
---@return number?
local function GetOldestPageMaxTimeStamp(state)
    if not state.firstPage then
        return nil
    end
    return state.firstPage.maxTimeStamp
end

---@param state RollingState
---@return number
local function GetAproximateByteSize(state)
    return state.aproxByteSize
end

---@param state RollingState
---@return fun(): LogObject?
---Do not use Iterator and Page Eviction Concurrently
local function Iterator(state)
    local page = state.firstPage

    if not page then
        return function()
            return nil
        end
    end

    local index = page.firstIndex or 1
    local version = state.iteratorVersion
    return function()
        if version ~= state.iteratorVersion then
            return nil
        end

        while page do
            if index <= page.count then
                local entry = page.entries[index]
                index = index + 1

                if entry then
                    return entry
                end
            else
                page = page.next
                if page then
                    index = page.firstIndex
                end
            end
        end

        return nil
    end
end

-- API interface --
---@return RollingLog
function CreateRollingLog()
    ---@type RollingState
    local state = CreateRollingState()
    return {
        ---@param LogObject LogObject
        Append = function(LogObject)
            Append(state, LogObject)
        end,
        ---@return LogObject?
        PeekOldest = function()
            return PeekOldest(state)
        end,
        ---@return LogObject?
        RemoveOldest = function()
            return RemoveOldest(state)
        end,
        ---@return nil
        EvictOldestPage = function()
            EvictOldestPage(state)
        end,
        ---@return number?
        GetOldestPageMaxTimeStamp = function()
            return GetOldestPageMaxTimeStamp(state)
        end,
        ---@return nil
        Clear = function()
            state.iteratorVersion = state.iteratorVersion + 1
            state = CreateRollingState()
        end,
        ---@return fun(): LogObject?
        Iterator = function()
            return Iterator(state)
        end,
        ---@return number
        GetAproximateByteSize = function()
            return GetAproximateByteSize(state)
        end
    }
end

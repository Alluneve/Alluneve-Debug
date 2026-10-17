# Alluneve-Debug — Developer Installation

Alluneve-Debug is an optional debugging service for **World of Warcraft Retail** addons. It provides severity-based logging, per-addon rolling debug histories, and automatic flight-recorder reports when errors occur.

It requires **!BugGrabber**; **BugSack** is optional for viewing reports.

## 1. Add the optional dependency

Install and enable Alluneve-Debug alongside your addon. In your addon's `.toc` file, add:

```toc
## OptionalDeps: Alluneve-Debug
```

This allows WoW to load Alluneve-Debug first when enabled, without preventing your addon from loading when it is absent.

## 2. Register your addon

Register using the addon identifier supplied by WoW to your Lua file:

```lua
local ADDON_NAME = ...

local function NoOp() end

local debugAPI = Alluneve
    and Alluneve.Debug
    and Alluneve.Debug.RegisterYourself(ADDON_NAME)

local debug = debugAPI or {
    Debug = NoOp,
    Info = NoOp,
    Warn = NoOp,
    Error = NoOp,
}

-- Use this interface throughout your addon.
debug.Info("Initialized")
debug.Debug("Cooldown updated", 12345)
debug.Warn("Unexpected cooldown state")
```

`RegisterYourself()` returns an API object bound to your addon's identifier. Repeated registrations with the same identifier return the same object.

The no-op fallback allows your addon to function normally when Alluneve-Debug is missing or disabled.

## 3. Available API

| Method | Purpose |
| --- | --- |
| `debug.Debug(...)` | Record a DEBUG-level message. |
| `debug.Info(...)` | Record an INFO-level message. |
| `debug.Warn(...)` | Record a WARN-level message. |
| `debug.Error(...)` | Record an ERROR-level message and trigger the flight recorder. |
| `debug.SubmitLog(severity?)` | Submit the session debug log to !BugGrabber, optionally filtered by minimum severity. |
| `debug.TogglePrint()` | Toggle additional chat output; returns the new state. |
| `debug.TriggerRecorder()` | Manually trigger a flight-recorder report without requiring a Lua error. |

**All severity levels are always recorded**, independently of whether chat printing is enabled.

Every message is added to both the session debug log and flight recorder. `TogglePrint()` only controls whether messages are additionally displayed in chat.

Calling `Error(...)` records the message before triggering the flight recorder, allowing developers to capture handled errors or unexpected conditions without throwing a Lua exception.

All API methods automatically use the identifier supplied during registration.

### Submitting logs with a severity filter

`SubmitLog()` accepts an optional minimum severity level:

```lua
debug.SubmitLog()          -- All messages; clear log on success
debug.SubmitLog("DEBUG")   -- All messages; clear log on success
debug.SubmitLog("INFO")    -- INFO, WARN, ERROR; retain log
debug.SubmitLog("WARN")    -- WARN, ERROR; retain log
debug.SubmitLog("ERROR")   -- ERROR only; retain log
```

The severity argument uses uppercase severity strings.

**DEBUG is the unfiltered baseline.** Any severity above DEBUG produces a filtered report.

| Minimum severity | Included messages | Clear log on successful submission? |
| --- | --- | --- |
| Omitted / DEBUG | DEBUG, INFO, WARN, ERROR | Yes |
| INFO | INFO, WARN, ERROR | No |
| WARN | WARN, ERROR | No |
| ERROR | ERROR | No |

Filtered submissions are **non-destructive**. They do not modify or remove messages from the retained session history.

Full submissions clear the session log only after `SendToBugGrabber()` reports successful submission.

The severity filter affects only the exported report, not which messages are recorded or retained.

### Session log retention

Each registered addon maintains an independent session debug log, limited to approximately **1 MiB (1,048,576 bytes) of estimated Lua memory usage**.

When the limit is exceeded, the oldest entries are automatically discarded. This prevents unbounded memory growth during long sessions.

The session log and flight recorder use separate rolling buffers:

- **Session log:** Retains messages based on an estimated memory limit.
- **Flight recorder:** Retains messages based on a configurable time window.

For methods not included in the no-op fallback, check `debugAPI` before calling them:

```lua
if debugAPI then
    debugAPI.SubmitLog("WARN")
    debugAPI.TriggerRecorder()
end
```

## 4. Flight recorder and error reports

When !BugGrabber captures an error attributable to a registered addon, Alluneve-Debug automatically triggers that addon's flight recorder.

By default, the resulting report contains diagnostic messages from **60 seconds before and 10 seconds after the trigger**, providing a timeline of what happened around the error.

Reports are submitted separately to !BugGrabber and can be inspected through BugSack.

Error attribution is best-effort, using available source paths and addon/taint information.

### Trigger-relative timestamps

Flight-recorder reports use timestamps relative to the trigger event rather than absolute timestamps on every log entry.

For example:

```text
Alluneve-Debug Report: MyAddon
Triggered (approx): 2026/10/17 13:37:01
Submitted: 2026/10/17 13:37:12
Entries: 4
Log Level: DEBUG
Page: 1/1

[-3.522319] DEBUG Cooldown updated
[-1.505799] INFO Ability became available
[+0.000000] ERROR Unexpected cooldown state
[+2.500000] DEBUG Cooldown state refreshed
```

Negative offsets indicate events before the trigger. Positive offsets indicate events after the trigger.

The report header includes the approximate wall-clock trigger time and the submission time.

Repeated triggers extend the post-trigger recording window and update the reference timestamp to the most recent trigger.

Session debug log submissions use approximate absolute timestamps instead of trigger-relative offsets.

### Report pagination

Reports are automatically divided into multiple !BugGrabber entries when their contents exceed the configured per-page limit.

Each page contains at most **80,000 bytes of formatted log entries**, excluding report headers and page metadata.

Pagination preserves the chronological ordering of log entries and does not intentionally discard older entries to fit a single report.

Each page includes:

- Addon identifier
- Approximate start or trigger timestamp
- Submission timestamp
- Total number of included entries
- Minimum submission severity
- Page number and total page count

For example:

```text
Alluneve-Debug Report: MyAddon
Started (approx): 2026/10/17 13:31:49
Submitted: 2026/10/17 13:31:56
Entries: 3000
Log Level: WARN
Page: 1/2
```

Pages are stored as separate !BugGrabber reports and can be viewed individually in BugSack.

If a single formatted log entry exceeds the page-size limit, the submission cannot be completed using the current pagination implementation.

### Manual triggering

For unexpected behavior that does not produce a Lua error, developers can trigger the recorder programmatically:

```lua
if debugAPI then
    debugAPI.TriggerRecorder()
end
```

Alternatively, the recorder can be triggered directly through Alluneve-Debug's slash command:

```text
/alludebug trigger MyAddon
```

This initiates the configured post-trigger recording window without requiring an error or stack trace.

The addon identifier must match the registered identifier exactly, including capitalization.

## 5. Slash commands

Alluneve-Debug provides commands for recorder configuration, manual triggering, and log submission.

### Manual diagnostics

```text
/alludebug trigger <addonIdentifier>
/alludebug submit <addonIdentifier>
```

- `trigger` initiates a flight-recorder capture for the specified addon.
- `submit` submits the addon's currently retained session debug log to !BugGrabber.

Both commands require an addon identifier already registered with Alluneve-Debug.

**Triggering the flight recorder and submitting the session debug log are separate operations.**

### Global recorder settings

```text
/alludebug                    Show current settings
/alludebug show               Show current settings
/alludebug capture 60         Rolling history in seconds
/alludebug posttrigger 10     Recording after a trigger, in seconds
/alludebug ticker 60          Global cleanup interval in seconds
```

These settings apply globally to the flight recorder, while each registered addon maintains its own diagnostic history.

The global cleanup ticker operates regardless of combat, with cleanup work distributed across frames. Session debug logs enforce their memory limits during insertion and do not require an additional ticker.

## 6. Integration example

A complete example of optional Alluneve-Debug integration:

```lua
local ADDON_NAME = ...

local function NoOp() end

local debugAPI = Alluneve
    and Alluneve.Debug
    and Alluneve.Debug.RegisterYourself(ADDON_NAME)

local debug = debugAPI or {
    Debug = NoOp,
    Info = NoOp,
    Warn = NoOp,
    Error = NoOp,
}

debug.Info("Addon initialized")

local function UpdateCooldown(spellID)
    debug.Debug("Updating cooldown", spellID)

    if not spellID then
        debug.Warn("Missing spell ID")
        return
    end

    -- Your addon logic here.
end

local function ReportUnexpectedState()
    debug.Error("Unexpected cooldown state")
end

local function SubmitDiagnostics()
    if not debugAPI then
        return
    end

    -- Submit warnings and errors without clearing the history.
    debugAPI.SubmitLog("WARN")
end
```

When Alluneve-Debug is absent, the logging methods become no-ops and the addon continues functioning normally.

## 7. Integration checklist

- Add `## OptionalDeps: Alluneve-Debug` to your `.toc`.
- Register with `Alluneve.Debug.RegisterYourself(ADDON_NAME)`.
- Provide no-op logging methods when the service is unavailable.
- Use `Debug`, `Info`, `Warn`, and `Error` according to message severity.
- Use `SubmitLog()` for full, clearing submissions.
- Use `SubmitLog("INFO")`, `"WARN"`, or `"ERROR"` for non-destructive filtered submissions.
- Use `TriggerRecorder()` for manual diagnostic captures.
- Inspect generated reports through !BugGrabber and optionally BugSack.
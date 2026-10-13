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
| `debug.SubmitLog()` | Submit the retained session debug log to !BugGrabber. |
| `debug.TogglePrint()` | Toggle additional chat output; returns the new state. |
| `debug.TriggerRecorder()` | Manually trigger a flight-recorder report without requiring a Lua error. |

**All severity levels are always recorded**, independently of whether chat printing is enabled.

Every message is added to both the session debug log and flight recorder. `TogglePrint()` only controls whether messages are additionally displayed in chat.

Calling `Error(...)` records the message before triggering the flight recorder, allowing developers to capture handled errors or unexpected conditions without throwing a Lua exception.

### Session log retention

Each registered addon maintains an independent session debug log, limited to approximately **1 MiB of estimated Lua memory usage**.

When the limit is exceeded, the oldest entries are automatically discarded. This prevents unbounded memory growth during long sessions.

The session log and flight recorder use separate rolling buffers:

- **Session log:** Retains messages based on an estimated memory limit.
- **Flight recorder:** Retains messages based on a configurable time window.

### Deprecated API

The following methods remain available for backwards compatibility but are marked for removal in version **2.0.0**.

| Method | Replacement |
| --- | --- |
| `debug.Print(...)` | `debug.Debug(...)` |
| `debug.Log(...)` | `debug.Debug(...)` |
| `debug.ToggleDebugPrint()` | `debug.TogglePrint()` |
| `debug.ToggleDebugLog()` | No replacement; session logging is always enabled. |

`Print()` and `Log()` now both record DEBUG-level messages. `ToggleDebugLog()` is a no-op.

For methods not included in the no-op fallback, check `debugAPI` before calling them:

```lua
if debugAPI then
    debugAPI.TriggerRecorder()
end
```

All API methods automatically use the identifier supplied during registration.

## 4. Flight recorder and error reports

When !BugGrabber captures an error attributable to a registered addon, Alluneve-Debug automatically triggers that addon's flight recorder.

By default, the resulting report contains diagnostic messages from **60 seconds before and 10 seconds after the trigger**, providing a timeline of what happened around the error.

Reports are submitted separately to !BugGrabber and can be inspected through BugSack.

Error attribution is best-effort, using available source paths and addon/taint information.

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
- `submit` submits the addon's currently retained session debug log to !BugGrabber, equivalent to calling `SubmitLog()` through its API.

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
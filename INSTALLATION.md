# Alluneve-Debug — Developer Installation

Alluneve-Debug is an optional debugging service for **World of Warcraft Retail** addons. It requires **!BugGrabber**; **BugSack** is optional for viewing reports.

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
    Print = NoOp,
    Log = NoOp,
}

-- Use this interface throughout your addon.
debug.Print("Initialized")
debug.Log("Cooldown updated", 12345)
```

`RegisterYourself()` returns an API object bound to your addon's identifier. Repeated registrations with the same identifier return the same object.

The no-op fallback allows your addon to function normally when Alluneve-Debug is missing or disabled.

## 3. Available API

| Method | Purpose |
| --- | --- |
| `debug.Print(...)` | Capture an event; optionally print it to chat. |
| `debug.Log(...)` | Capture an event; optionally append it to the addon's session debug log. |
| `debug.SubmitLog()` | Submit the addon's session debug log to !BugGrabber. |
| `debug.ToggleDebugPrint()` | Toggle chat debug printing; returns the new state. |
| `debug.ToggleDebugLog()` | Toggle session debug-log collection; returns the new state. |
| `debug.TriggerRecorder()` | Manually trigger the addon's flight recorder without requiring a Lua error. |

**Both `Print()` and `Log()` feed the rolling flight recorder regardless of the print/log toggle states.** Only additional chat output and session logging depend on those toggles.

For methods not included in the no-op fallback, check `debugAPI` before calling them:

```lua
if debugAPI then
    debugAPI.TriggerRecorder()
end
```

Each API method automatically uses the identifier supplied during registration.

## 4. Flight recorder and error reports

When !BugGrabber captures an error attributable to a registered addon, Alluneve-Debug automatically triggers that addon's flight recorder.

By default, the resulting report contains diagnostic events from **60 seconds before and 10 seconds after the trigger**, providing a timeline of what happened around the error.

Reports are submitted separately to !BugGrabber and can be inspected through BugSack.

Error attribution is best-effort, using available source paths and addon/taint information.

### Manual triggering

For unexpected behavior that does not produce a Lua error, the recorder can also be triggered manually:

```lua
if debugAPI then
    debugAPI.TriggerRecorder()
end
```

Alternatively, developers can invoke the recorder directly through Alluneve-Debug's slash command:

```text
/alludebug trigger MyAddon
```

This triggers the recorder for the specified registered addon, using the same configured capture windows without requiring an error or stack trace.

The addon identifier must match the registered identifier exactly, including capitalization.

## 5. Slash commands

Alluneve-Debug provides commands for recorder configuration, manual triggering, and log submission.

### Manual diagnostics

```text
/alludebug trigger <addonIdentifier>
/alludebug submit <addonIdentifier>
```

- `trigger` initiates a flight-recorder capture for the specified addon.
- `submit` submits the addon's accumulated session debug log to !BugGrabber, equivalent to calling `SubmitLog()` through its API.

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

These settings apply globally to the shared recorder, while each registered addon maintains its own diagnostic history.

The global cleanup ticker operates regardless of combat, with cleanup work distributed across frames.
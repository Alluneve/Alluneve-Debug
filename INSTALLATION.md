# Alluneve-Debug — Developer Installation

Alluneve-Debug is an optional debugging service for **World of Warcraft Retail** addons. It requires **!BugGrabber**; **BugSack** is optional for viewing reports.

## 1. Add the optional dependency

Install and enable Alluneve-Debug alongside your addon. In your addon's `.toc` file, add:

```toc
## OptionalDeps: Alluneve-Debug
```

This lets WoW load Alluneve-Debug first when it is enabled, without preventing your addon from loading when it is absent.

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

`RegisterYourself()` returns an interface bound to your addon's name. Calling it again with the same name returns the same interface. The fallback keeps normal addon functionality working if Alluneve-Debug is missing or disabled.

## 3. Available API

| Method | Purpose |
| --- | --- |
| `debug.Print(...)` | Capture an event; optionally print it to chat. |
| `debug.Log(...)` | Capture an event; optionally append it to the addon's session debug log. |
| `debug.SubmitLog()` | Submit that addon's session debug log to !BugGrabber. |
| `debug.ToggleDebugPrint()` | Toggle chat debug printing; returns the new state. |
| `debug.ToggleDebugLog()` | Toggle session debug-log collection; returns the new state. |

**Both `Print()` and `Log()` feed the rolling flight recorder regardless of the print/log toggle states.** Only the additional chat output and session log depend on those toggles.

If you expose optional debug commands, guard the additional methods with `debugAPI` rather than calling them on the no-op fallback:

```lua
if debugAPI then
    local enabled = debugAPI.ToggleDebugPrint()
    print("Debug printing:", enabled and "on" or "off")
end
```

## 4. Error reports and testing

When !BugGrabber captures an error attributable to a registered addon, Alluneve-Debug triggers **that addon's** flight recorder. After the post-trigger window, its buffered events are submitted as a separate !BugGrabber report. Attribution uses source paths and explicit addon/taint information where available; it is best-effort.

For a useful test, emit several `debug.Print()` or `debug.Log()` events, then verify the resulting flight-recorder entry in BugSack after an attributable Lua error. An error raised directly from `/run` might be attributed to the macro rather than your addon.

## 5. Global recorder settings

These settings apply to the shared recorder, not to individual registered addons:

```text
/alludebug                    Show current settings
/alludebug capture 60         Rolling history in seconds
/alludebug posttrigger 10     Recording after an error, in seconds
/alludebug ticker 60          Global cleanup interval in seconds
```

The global cleanup ticker operates regardless of combat. Each registered addon keeps its own flight history, while the cleanup work is distributed across frames.
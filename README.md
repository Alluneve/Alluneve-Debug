# Alluneve-Debug

**Alluneve-Debug** is a standalone debugging framework for World of Warcraft Retail addon developers. It provides a shared API for implementing structured debug logging without having to build and maintain your own logging infrastructure or flood the chat with diagnostic messages.

Debug messages are retained in per-addon rolling histories. When a Lua error can be attributed to a registered addon, Alluneve-Debug automatically submits a report to **!BugGrabber**, containing diagnostic events from **60 seconds before and 10 seconds after the error**. This gives developers a timeline of what their addon was doing around the failure, rather than just a stack trace.

## Features

- Separate diagnostic histories, debug logs, and output settings for each registered addon.
- Automatic flight-recorder reports for attributed Lua and recognized taint errors.
- Manual recording triggers for issues that don't produce Lua errors.
- Recording independent of combat and optional chat/debug-log output.
- One global cleanup ticker, paged event storage, and frame-budgeted cleanup to minimize performance spikes.
- Reports accessible through **!BugGrabber** and compatible viewers such as **BugSack**.

Error attribution is best-effort. Only diagnostic events supplied by participating addons are recorded.
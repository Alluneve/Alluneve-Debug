# Alluneve-Debug

**Alluneve-Debug** is a standalone debugging framework for World of Warcraft Retail addon developers. It provides a shared API for structured, severity-based logging without having to build and maintain your own logging infrastructure or flood the chat with diagnostic messages.

Diagnostic messages are retained in independent, per-addon rolling histories. When a Lua error can be attributed to a registered addon, Alluneve-Debug automatically submits a flight-recorder report to **!BugGrabber**, containing events from **60 seconds before and 10 seconds after the error** by default. This gives developers a timeline of what their addon was doing around the failure, rather than just a stack trace.

The recorder can also be triggered manually or through the API, allowing developers to investigate unexpected behavior that doesn't produce a Lua error.

## Features

- Shared debugging API with **DEBUG, INFO, WARN, and ERROR** severity levels.
- Independent per-addon session logs, limited to approximately **1 MiB** of estimated memory per addon.
- Automatic flight-recorder reports for attributed Lua and recognized taint errors.
- Manual recording triggers and session-log submission through the API or slash commands.
- Always-on diagnostic recording with optional chat output, independent of combat.
- Efficient paged FIFO storage, a single global cleanup ticker, and frame-budgeted cleanup to minimize performance spikes.
- Reports accessible through **!BugGrabber** and compatible viewers such as **BugSack**.

Error attribution is best-effort. Only diagnostic events supplied by participating addons are recorded.

For integration instructions and API documentation, see [INSTALLATION.md](INSTALLATION.md).
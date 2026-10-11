# Alluneve-Debug

**Alluneve-Debug** is a standalone debugging companion for World of Warcraft Retail addons. It retains recent diagnostic events from registered addons and submits a flight-recorder report to **!BugGrabber** when an error can be attributed to one of them.

## Features

- Separate recording histories, debug logs, and output settings for each registered addon.
- Rolling event capture before and after an error, including recognized Lua and taint errors.
- Recording independent of combat and optional chat/debug-log output.
- One global cleanup ticker, paged event storage, and frame-budgeted cleanup to limit performance spikes.
- Reports accessible through !BugGrabber and compatible viewers such as BugSack.

Error attribution is best-effort. The recorder captures events supplied by participating addons, not every event in the game.
---
name: ui-visual-check
description: Verify Lingo's UI by capturing a single window with window-level screenshots instead of the whole screen. Use when checking panel or settings appearance, layout, alignment, dark mode, streaming states, or any change that needs visual confirmation of the running app.
argument-hint: "[what to verify]"
---

# UI visual check

Verify UI changes against the running app by capturing **one window at a time**. A window-level capture contains only the app under test: no desktop, no other applications, no personal content, and it stays readable when several windows overlap.

Never verify the UI with a whole-screen capture (`screencapture` without `-l`, `⇧⌘3`, `⇧⌘4`, `⇧⌘5`, or any region/display selection). Capture the window itself.

## Capture a window

The bundled script lists on-screen windows and captures exactly one of them:

```bash
# What is on screen right now? (defaults to Lingo Translate windows)
swift .agents/skills/ui-visual-check/scripts/window-shot.swift list

# Capture the Lingo panel; the panel hides when it loses focus, so start this
# first and let --wait pick the window up as it appears
swift .agents/skills/ui-visual-check/scripts/window-shot.swift shot --out /tmp/lingo-ui-check/panel.png --wait 20

# Capture a specific window by title or by ID from `list`
swift .agents/skills/ui-visual-check/scripts/window-shot.swift shot --title Settings --out /tmp/lingo-ui-check/settings.png
swift .agents/skills/ui-visual-check/scripts/window-shot.swift shot --window 10302 --out /tmp/lingo-ui-check/panel.png
```

It prints the captured window ID, title, point size, and pixel size, followed by the output path. A Retina window reports twice the pixel size of its point size; that is expected, not a layout bug.

Options: `--owner NAME`, `--title TEXT` (an empty `TEXT` matches untitled windows; the Lingo panel has no title), `--pid PID`, `--window ID`, `--out PATH`, `--wait SECONDS`, `--all`, `--shadow`. Without any filter, `--owner` defaults to `Lingo Translate`. Exit codes: `0` captured, `1` no matching window, `2` capture failed, `64` bad usage.

The script must run while the window is on screen. If the app is not running, start it first, then capture; `--wait` covers a window that is still appearing.

The translation panel is transient: it hides as soon as another application takes focus. Start the capture with `--wait` **before** opening the panel, and avoid switching apps in between, otherwise the panel is gone before the capture runs and `list` reports no window. The settings window stays on screen once open.

## Workflow

1. Build and launch the app: `make build`, then `open "build/Build/Products/Debug/Lingo Translate.app" --args --show-panel --dark --demo-text "…"`. Debug builds accept `--show-panel` to present the translation panel, `--show-settings` to open the settings window, `--dark` to force dark appearance, and `--demo-text "…"` to prefill the source pane. `--demo-text` and `--dark` are Debug-only flags.
2. Run `list` to confirm which window to capture. Check the title, size, and owner instead of assuming. The translation panel is untitled (`--title ""`), and the settings window is titled `Settings`.
3. Capture with `shot`, writing to a path under `/tmp` so no images land in the repository.
4. Open the PNG and compare it with the intent: text alignment between the two panes, spacing, truncation, contrast in the current appearance, and the state under test (idle, translating with `Stop` visible, highlighted segment, empty source).
5. Report what the image shows, including problems. Verify each state that the change affects, not only the default one.

Restart the app between checks when a state is only produced at launch (`--show-panel`, `--show-settings`, `--demo-text`, `--dark`). To reach other states, drive the UI as a user would, then capture again.

If the panel does not appear, the app may already be running from an earlier launch, so the new process exits without showing a window. Quit the instances first (`pgrep -f "Lingo Translate"`, then `kill <pid>`), or capture the instance that is already on screen.

## Reading the result

- A capture that is entirely flat, transparent, or black means the window was not really drawn or the capture had no Screen Recording permission. The script warns about this; treat the image as invalid rather than as a UI finding.
- A missing or stale window usually means the app is not running, the window was closed, or an older build is still in front. Confirm with `list` before concluding anything about the UI.
- Window captures exclude the window shadow by default, so the PNG shows the window content flush with its rounded corners.

Captures show whatever is in the window, including typed text and the endpoint, model, and masked API key fields in the settings window. Keep them under `/tmp`, never commit them, and do not paste them into shared channels.

Screen Recording permission is required by the terminal or editor that runs the script. When it is missing, grant it in System Settings → Privacy & Security → Screen Recording and run the capture again. Do not fall back to a whole-screen capture.

## Clean up

Images live under `/tmp`. Leave the Debug app running when the task is done so the user can check the result; quit it only when the user asks, or when a later check needs a relaunch:

```bash
pgrep -f "Lingo Translate"
kill <pid>
```

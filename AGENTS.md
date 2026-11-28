# AGENTS.md

Lingo Translate is a macOS menu bar translation tool: a global shortcut opens a floating panel, sends the selected text to a Responses-style LLM endpoint, and shows the source and translation in two columns aligned paragraph by paragraph. Built with Swift + SwiftUI / AppKit, no third-party dependencies.

**Update this file only when necessary** — when a task changes a fact recorded here (see the triggers under Conventions and preferences). Skip it otherwise; there is no need to touch this file after every task. When updating, touch only the entries that changed. Record facts that help an agent get oriented quickly, not implementation details or a changelog.

## Commands

```bash
make run      # build Debug and launch
make test     # run unit tests
make build    # build only
make release  # build Release into dist/
make install  # build Release and install to /Applications
```

- Xcode project `Lingo.xcodeproj`, scheme `Lingo`, bundle ID `me.songlang.lingo`.
- Single test: `xcodebuild -project Lingo.xcodeproj -scheme Lingo -derivedDataPath build -only-testing:LingoTests/TranslatorModelTests test`.
- Live endpoint tests are skipped by default; pass the three `.env` variables with a `TEST_RUNNER_` prefix to the test process, as documented in `LingoTests/LiveTranslationTests.swift`.
- Debug launch flags: `--show-panel`, `--show-settings`, `--dark`, `--demo-text "..."`.

## Layout

```
Lingo/
  App/        app lifecycle, panel control, settings window, shortcut management,
              accessibility permission, TranslatorModel (core state)
  Model/      languages, configuration, shortcut value type, double-tap detection,
              system prompts, line splitting, reply parsing, rule-based segmentation,
              dictionary entry, term detection and reply parsing
  Services/   Responses client, dictionary lookup client, Carbon global hot key,
              double-tap modifier monitor, selected text reader, keychain storage
  UI/         two-column translation panel, dictionary card, settings, shortcut recorder
  Resources/  app icon and colors
LingoTests/   XCTest unit tests
Support/      Info.plist
scripts/      icon generation script
.agents/skills/ui-visual-check/  window-level UI screenshot skill
```

## Key facts

- Only the Responses API is supported (`/v1/responses`, SSE). Endpoints are completed automatically: a base address gets `/v1/responses`; when a model rejects `reasoning` with HTTP 400, the request is retried once without it.
- The source text belongs to the user and is never rewritten by the model. The primary protocol numbers source lines and the model answers with `<s lines="A-B">…</s>` logical paragraphs; `SegmentParser` repairs out-of-order, overlapping, and out-of-range ranges. If the model ignores the format, `LayoutSegmenter` splits the text locally and retries with an `<s id="N">` protocol; a second failure shows the whole translation unaligned.
- The two columns are TextKit 1 text views. Paragraph tops are aligned by adding spacing through `NSLayoutManagerDelegate`; no text content is modified.
- A single word or short phrase also gets a dictionary request: `DictionaryDetector` decides locally (single line, at most 4 words or 12 CJK characters, no code or URLs), the model answers `valid: false` for sentences, and the reply is one JSON object parsed by `DictionaryParser`. The request runs beside the translation, shares `requestID`, and its failure or absence only hides the card under both columns; it never changes the translation flow. The entry stays with the request across source edits, so editing hides the card and restoring the text brings the same entry back.
- The dictionary pane has a draggable divider. Its height is stored in UserDefaults (`dictionaryHeight`) and clamped by `DictionaryPaneLayout`: the columns keep two fully visible text lines plus their padding and a little headroom (`topPadding + 2 * lineHeight + bottomPadding + columnsHeadroom`) under the header, so a source or translation of up to two lines shows no scrollbar, and the pane never drops below its 96pt minimum. The divider is an AppKit view that refuses `mouseDownCanMoveWindow`, because the panel moves when its background is dragged; a SwiftUI gesture would never receive the mouse down.
- The panel is a non-activating floating window (`.nonactivatingPanel`). It hides on outside clicks, app switches, and `Esc`, and returns focus to the previous window.
- Settings live in UserDefaults; the API key lives in the login keychain (service is the bundle ID, account `api-key`). Never move it to UserDefaults or plain files.
- Reading the selection from other apps and the double-tap modifier shortcut require Accessibility permission. Never request it at launch.
- No App Sandbox; signed with an Apple Development certificate and not notarized.

## Conventions and preferences

- README targets human users: features, build, configuration, and usage only. Keep it concise, with no emoji and no marketing tone or AI-sounding phrasing.
- Keep the implementation native; do not add third-party dependencies unless the user asks.
- Update this file when translation flow, segmentation or alignment, shortcuts, permissions, build commands, or the directory layout change.
- Verify UI changes with the `ui-visual-check` skill using window-level screenshots only. Never capture the whole screen, and keep images in `/tmp`. Leave the app running when the task is done so the user can check it; quit it only when the user asks or a later check needs a relaunch.
- Do not script UI interaction (clicks, drags, gestures) to test behavior, and do not record the screen or window to inspect motion; synthetic events and frame captures are slow and unreliable here. Ask the user to perform the interaction or watch the animation and report back instead. Window screenshots of still states are still the way to check appearance.
- When testing motion, check the system Reduce Motion setting first: with it on, SwiftUI turns the dictionary card's `.move` transition into a crossfade, so a slide that looks like a fade is the setting, not the code. Do not change an animation to work around it.
- `.env` holds local endpoint settings and is git-ignored. Do not commit it or print its secrets.
- Commit messages: English imperative mood, capitalized, no prefix; the body explains why.
- Documentation states facts; avoid inflated wording.

---
name: screencontext-design-guidance
description: "Design, build, or substantially change any ScreenContext product surface while preserving its established compact native macOS character."
---

# ScreenContext design guidance

ScreenContext records a selected screen or window with optional audio and webcam video. Users can copy the local recording path for an AI agent or copy the video file for sharing. It also works as an everyday screen recorder.

The product name is **ScreenContext**, written as one word with a capital S and C in every locale. Its App Store and marketing tagline is **“Screen context for AI agents.”** Preserve that wording in promotional material; keep it out of compact controls and settings. Use **“Now on the App Store”** for the launch call to action.

ScreenContext is free for Mac, available on the App Store, and open source on GitHub under Apache-2.0. Describe what the app currently does. Recordings stay local; copying does not upload or automatically attach them to another app. Do not imply that ScreenContext edits videos, makes website changes, or creates issues itself; an agent can use the recording to perform those tasks. Do not imply an enterprise edition, cloud service, or partnership exists.

The established application is the visual reference. Preserve its compact layout, soft native materials, restrained accent color, and direct workflow. A product rename is not permission to restyle the interface.

## Design priority

When requirements compete, protect them in this order:

1. Preserve user data, privacy, accessibility, localization, and truthful behavior.
2. Keep recording state and the next action immediately understandable.
3. Preserve the established ScreenContext interaction model and visual proportions.
4. Follow native macOS conventions.
5. Add polish only when it does not make the product louder, larger, or more branded.

Do not turn a visual request into an architectural rewrite. Keep existing scenes, state ownership, file boundaries, and platform integrations unless the task explicitly requires changing them.

## Product character

ScreenContext should feel:

- Compact and light enough to stay out of the way.
- Native to macOS rather than themed on top of it.
- Soft and dimensional where a surface genuinely floats.
- Calm in its ready state and unmistakably urgent while recording.
- Practical rather than promotional.
- Familiar across light and dark appearances.

The interface is a utility, not a dashboard. Avoid oversized windows, branded content cards, strong section outlines, decorative gradients, dense labels, and redundant status text.

## Visual source of truth

Before changing a surface, inspect its current implementation and compare the result with the last accepted design. Preserve recognizable geometry and hierarchy unless the user explicitly requests a redesign.

The current reference owners are:

| Surface | Owner | Reference behavior |
| --- | --- | --- |
| Recording feedback | `RecordingFeedbackPanelController` | Transient nonactivating material overlay |
| Capture and webcam layout | `CaptureSettingsView`, `WebcamOverlayPanelController` | Native Settings forms |
| Recordings | `RecordingResultView`, `RecordingResultPanelController` | Native sidebar with a narrow, vertically stacked detail |
| Settings | `SettingsView` | Small tabbed window with grouped native forms |

A broad visual change must be judged against these existing surfaces rather than against a generic recording-app reference.

## Color

Use the system appearance and `Color.accentColor` for interactive emphasis. Most of the interface should remain neutral.

- Use system red for active recording, destructive actions, and errors.
- Use system yellow or orange for warnings, paired with explanatory text.
- Use system green only for confirmed success.
- Keep window backgrounds, text, dividers, menus, selections, and controls system-adaptive.
- Do not introduce separate capture-blue and context-orange UI systems.
- Do not tint every enabled input, source picker, panel border, or heading.
- Do not copy the app icon's gradients, gloss, or glow into the application interface.
- Never use color as the only state cue.

The blue, cyan, coral, and orange brand colors belong primarily to the app icon and promotional artwork. Inside the app, the native accent color is sufficient.

## Materials, borders, and depth

Use material only for objects that genuinely float over other applications or media.

- The Recording file area may use a quiet material card because it contains a scrollable local path.
- The video preview may retain a thin adaptive border and restrained shadow so it separates from the window.
- Native windows, sidebars, lists, forms, menus, and dialogs keep their system surfaces.
- Avoid nesting cards or giving peer sections competing colored outlines.
- Use spacing and typography before adding another container.

## Typography and icons

Use the system font and semantic text styles.

- Use monospaced digits for elapsed recording time.
- Use monospaced text for timecodes, paths, commands, and raw identifiers.
- Keep headings and controls in sentence case.
- Use SF Symbols for actions and status.
- Icon-only compact controls are appropriate in media overlays when they have an accessibility label and help text.
- Do not convert every icon-only action into a labeled button if the established compact affordance is clear.
- Do not put ordinary symbols in brand-colored tiles unless that treatment is already part of the accepted surface.

## Spacing and shape

Start with the dimensions already encoded in the accepted views.

- Use a four-point rhythm for new spacing: 4, 8, 12, 16, 24, and 32 points.
- Keep related controls close and separate task groups with native dividers.
- Let one container own each gap.
- Preserve stable positions when state changes.
- Use leading and trailing alignment for localization.
- Let native controls own their standard corner radius.
- Reserve capsules for compact tokens or transient labels, not general containment.
- Preserve the feedback overlay's 18-point continuous outer radius.

## Recording controls

- Control–Command–R toggles recording from any app by default. Users can customize the global shortcut in Settings → Recordings.
- The menu bar shows a recording indicator and monospaced elapsed time.
- A nonactivating material overlay confirms start and stop; preparation and finalization stay visible while pending.
- Recording actions remain available in the menu bar menu for keyboard and pointer access.
- Capture sources and audio/webcam inputs live in Settings → Recordings.
- The latest recording opens automatically after finalization.
- To return to an agent or another destination after recording, start with that app active. Copy & Return remembers the app that was active when recording started.

## Webcam layout

Settings → Recordings → Edit Webcam Layout… opens the live WYSIWYG webcam preview over the capture target. Drag to move, drag the border to resize, and use the segmented shape picker. Done closes the editor and returns to Settings. Starting a recording also ends editing. Preserve the user's device, position, size, and mask.

## Recordings window

Keep the accepted native sidebar and narrow detail layout.

- Overall content width is approximately 860 points.
- The detail column is approximately 620 points.
- Present the video first at its established 572-point width.
- Place the Recording file card below the video and its copy actions.
- Keep the native Copy Video button below the player. When a destination is available, place Copy Video & Return to [App] alongside it (Command–Option–Shift–C).
- Show the Recording file heading and local video path in the file area. Long paths scroll inside their own view.
- Keep Copy File Path below the path. When a destination is available, place Copy & Return to [App] alongside it (Command–Shift–C).
- Return actions copy the selected content and reactivate the destination app; users press Command–V there to paste. The destination is remembered for recordings made during the current app session. Older recordings retain the standalone copy actions.
- Keep the header concise: the recording date and time.
- Keep Delete separated from Done and from copy actions.
- Use a native confirmation dialog.
- Keep sidebar rows lightweight. The accepted compact accent tile may remain; do not expand rows into cards.

Do not widen the window to create side-by-side “evidence” panels. Avoid blue and orange panel borders or persistent filenames in panel headers. Preserve the distinction between copying the video file and copying its path, with each action beside its corresponding return action.

## Settings

Settings are durable preferences, not a product dashboard.

- Use the dedicated macOS Settings scene.
- Preserve the Recordings and General tabs.
- Keep the content area near 620 by 600 points.
- Use a grouped `Form` with native pickers, toggles, progress indicators, and buttons.
- Put the global shortcut first in Recordings, followed by capture inputs.
- Keep the language picker, Privacy Policy, and Support in General.
- Do not wrap each preference group in additional custom sections or cards without a clear semantic need.
- Do not add promotional brand elements.

## App icon

The app icon is deliberately more expressive than the application UI. Its accepted visual language is:

- A rounded macOS icon silhouette with transparent space outside the shape.
- Deep indigo and cobalt-blue glass with cyan highlights.
- Warm coral, orange, and yellow focal surfaces.
- Dimensional, glossy, softly illuminated materials.
- A centered clipboard or context sheet containing a play symbol.
- A blue/cyan screen frame behind the warm context sheet, communicating screen evidence becoming reusable context.
- Strong depth and a readable silhouette at small sizes.

Preserve the familiar dimensional clipboard and play composition. Replace the former broadcast arcs with a screen frame; broadcasting and streaming are not the product's promise. The frame and sheet should read as one centered object, not a multi-step diagram.

When refining the icon:

- Keep the established clipboard/play focal object and color balance, with the screen frame behind it.
- Improve edge cleanliness, small-size clarity, and material coherence.
- Keep the central glyph large.
- Avoid text, letters, AI sparkles, robots, generic chat bubbles, screenshots, or interface chrome.
- Do not replace the original with a sparse navy tile or a collection of unrelated symbols.
- Generate every required macOS icon size from one reviewed 1024-point master.
- The source master is `Sources/ScreenContext/Resources/ScreenContextIcon.png`; the asset catalog retains Apple's conventional `AppIcon.appiconset` name.
- Verify actual alpha transparency outside the silhouette; never ship a checkerboard background or colored edge fragments.

## Copy and terminology

Write for a capable person who may not know recording terminology.

- Prefer short action verbs: Choose, Record, Stop, Copy, Retry, Restore, Delete.
- Use “Recording file” for the local path area, “Copy File Path” for its standalone action, and “Copy Video” for copying the file itself.
- Use “Copy & Return to [App]” for copying the path and returning, and “Copy Video & Return to [App]” for copying the file and returning. Substitute the actual destination app name.
- In explanatory copy, “screen context” means a recording used by an AI agent. The copied reference is a local MP4 path, not a generated transcript or summary. Agents need access to that file and the ability to process video; otherwise users must attach the recording manually.
- Use “screen or window” when both are supported.
- Keep runtime names and filenames truthful.
- Use ScreenContext in menus, window titles, permission explanations, accessibility labels, translations, and new recording filenames.
- Preserve the legacy sandbox bundle identifier, stored preference keys, and Application Support path for upgrade compatibility. These are implementation identifiers, not product copy. Read both legacy and ScreenContext recording filename prefixes.
- Avoid hype and vague success messages.
- Error copy should say what failed, what happened to the recording, and what the user can do next.

## Accessibility and localization

- Provide meaningful VoiceOver labels, values, and help for icon-only controls.
- Preserve visible keyboard focus and keyboard shortcuts.
- Pair color with symbol, text, shape, or position.
- Respect Increase Contrast, Reduce Transparency, Reduce Motion, and system appearance.
- Keep native target sizes.
- Localize every user-facing string except runtime data.
- Test long German and Russian labels, compact CJK strings, and Arabic right-to-left layout.
- Format dates, times, durations, and numbers using the active locale.

## Motion

Default to stillness.

- Use brief hover transitions around 120 to 180 milliseconds.
- Animate only when it clarifies state or preserves spatial continuity.
- Do not pulse recording indicators, animate elapsed text, simulate typing, bounce controls, or move the primary action.
- Keep the full workflow usable with Reduce Motion enabled.

## Review correction: preserve the accepted design

The rejected redesign made the app worse by over-interpreting the capture-to-context story as a visual theme. Do not repeat these changes:

- Do not assign blue and orange to entire workflow halves.
- Do not widen the recordings window from 860 to 1120 points.
- Do not place video and the Recording file area side by side.
- Do not wrap both result areas in branded outlined cards.
- Do not enlarge Settings or introduce extra visual grouping.
- Do not redesign the app icon away from its glossy clipboard/play language. The ScreenContext screen frame replaces broadcast arcs without changing the material style.

A new proposal should first demonstrate a concrete usability problem in the accepted design. Solve that problem with the smallest possible change and verify the change in the actual app before expanding it.

## Validation scenarios

Review significant UI changes in light and dark appearance and with these states:

1. Ready to record with a long window title.
2. Preparing and finalizing.
3. Active recording beyond one hour.
4. A nonfatal recording warning.
5. WYSIWYG webcam placement near each capture edge.
6. Completed recording with video, local file path, and both copy-action rows; check return actions with and without an available destination.
7. Several recording-history rows.
8. German, Russian, CJK, and Arabic localization stress.

The change passes only if the current state and next action remain clear, the app still feels like the accepted compact native utility, and no new decoration is doing work that system controls or spacing already handle.

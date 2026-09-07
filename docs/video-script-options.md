# ScreenContext video — script review

Status: script A approved. The user selected the Computer Use plugin for captures, replacing the earlier Orca plan. The edit uses a launch-checklist demonstration with real recording context, plus captured ready and active HUD states.

## Creative direction

Use the existing ScreenContext icon and exact tagline: **Show your AI what you mean.**
Keep the interface authentic. Use deep indigo, cobalt, cyan, and restrained warm orange in promotional titles and framing, with generous space and simple fades. Leave the native controls and materials as they appear in the app.

Make the floating HUD a central character: clearly show its ready state, source selection, Go action, running timer, and Stop action. Give each important action time to register. Use readable captions so the story works muted. Optional narration below accompanies the captions; it is not required to understand the video.

## A — Show your AI what you mean (recommended, 28 seconds)

A complete workflow that explains the product to a first-time viewer.

| Time | Actual app footage | On-screen copy | Optional narration |
| --- | --- | --- | --- |
| 0–3s | Ready HUD, with ScreenContext identity in a quiet overlay | Show your AI what you mean. | “Show your AI what you mean.” |
| 3–7s | Open the HUD source menu, choose a clean demo window, show microphone control | Choose a screen or window. | “Choose a screen or window.” |
| 7–13s | Click Go; keep the HUD and running timer readable while demonstrating two deliberate actions | Record your screen, voice, and clicks. | “Record what happens, and explain what matters.” |
| 13–18s | Click Stop; cut past processing into the real completed recording and recording-context area | Turn a demonstration into context. | “Keep the recording, click keyframes, and transcript together.” |
| 18–24s | Show the context format menu; choose Create issue; copy the context and hold on the real confirmation | Choose a template. Copy the context. | “Choose a template, then copy the context for your AI workflow.” |
| 24–28s | Hold on the completed result; GitHub cut may transition to an icon end card | ScreenContext · Show your AI what you mean. | “ScreenContext.” |

Sample speech to record during the demonstration: “When I choose Grid, the view stays in a list. It should switch to a grid.” Use an original demo containing that exact behavior, so the resulting transcript and click evidence tell a coherent story.

## B — A clearer bug report (26 seconds)

A developer-focused story for the GitHub audience.

| Time | Actual app footage | On-screen copy / optional narration |
| --- | --- | --- |
| 0–3s | HUD ready over an original demo | “Show the problem.” |
| 3–7s | Choose the demo window and click Go | “Record the steps.” |
| 7–12s | Demonstrate the list/grid issue; HUD timer remains visible | “Explain what you expected.” |
| 12–17s | Stop, then reveal video and actual recording context | “Keep the evidence together.” |
| 17–22s | Select Create issue and copy | “Give your AI the context for an issue.” |
| 22–26s | Hold on result with ScreenContext branding | “Show your AI what you mean.” |

End at copying. The template prepares instructions and evidence; this preview should not imply that ScreenContext independently diagnoses or fixes the bug.

## C — From the HUD to reusable context (24 seconds)

A compact feature tour, with the HUD receiving the most screen time.

| Time | Actual app footage | On-screen copy / optional narration |
| --- | --- | --- |
| 0–3s | Ready HUD with small ScreenContext branding | “Your next demonstration starts here.” |
| 3–7s | Source menu and audio controls | “Choose your screen and inputs.” |
| 7–12s | Go, two deliberate demo interactions, running timer, Stop | “Record the details.” |
| 12–17s | Completed video and recording context | “Review the recording and context.” |
| 17–21s | Browse context formats and copy | “Reuse it in your AI workflow.” |
| 21–24s | Result remains visible beneath the tagline | “ScreenContext. Show your AI what you mean.” |

## Deliverables

- GitHub: polished MP4, a short animated preview, and a poster image suitable for linking to the full video from the README.
- Mac App Store: a separate 1920 × 1080 landscape MP4, 30 fps, 15–30 seconds. Use H.264 at 10–12 Mbps and AAC stereo at 256 kbps, 48 kHz; remain below 500 MB.
- Keep App Store footage focused on ScreenContext's own UI and capture workflow, with simple explanatory overlays and fades. Use an original, authorized demo as captured content. Keep the ending over app footage; reserve a standalone promotional end card for GitHub.
- Preserve raw captures separately. Verify final dimensions, duration, encoding, caption legibility, HUD visibility, and playback before delivery.

Apple sources checked September 5, 2026: [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) and [App preview guidance](https://developer.apple.com/app-store/app-previews/).

## Capture notes

Branding and functionality were checked against README.md, design.md, the actual icon master, HUDView.swift, RecordingResultView.swift, and the built-in context templates. The built app's HUD, Recordings window, transcript, and demonstration document were also inspected through the Computer Use plugin.

The user explicitly chose the Computer Use plugin after the initial Orca launch failure. The plugin's JavaScript bridge returned “Trusted RPC service is not configured: sky”; its direct app-state tools successfully captured the built ScreenContext app by its full bundle path.

ScreenContext excludes its own application from display recordings, so its own output is not sufficient to show the HUD. The edit includes genuine HUD captures and separate live footage of the running timer. Captured result-window surfaces are combined with playback of the original demo recording in the player viewport.

The source recording's actual transcript describes clarifying the headline, improving button contrast, and checking the mobile layout. The visible context template and copy confirmation come from the running app. No AI destination action or issue submission is part of this edit.

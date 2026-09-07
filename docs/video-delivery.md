# ScreenContext promotional video

The approved script A is edited into a 28-second video using the existing app icon, native HUD, recording window, context template picker, and copy confirmation. It includes actual demo playback and live HUD timer footage. Brief captions carry the story with sound muted; an original quiet instrumental track accompanies both exports.

## Files

- `dist/video/screencontext-github.mp4`: compact 1080p version with a branded end card.
- `dist/video/screencontext-app-store.mp4`: 1080p Mac App Store export with the app remaining visible in the closing shot.
- `docs/media/screencontext-preview.gif`: lightweight animated README preview.
- `docs/media/screencontext-script-a-poster.png`: still cover image.
- `docs/media/screencontext-script-a.mp4`: copy of the GitHub video, ready to add to the repository.

The source captures, demo recording, and production files remain in `dist/video`. Generated media has not been published or committed.

## README snippet

Add this below the introductory paragraph in the repository's root README:

```markdown
[![ScreenContext: choose a window, record with the HUD, and copy context](docs/media/screencontext-preview.gif)](docs/media/screencontext-script-a.mp4)
```

For a still cover instead, replace `screencontext-preview.gif` with `screencontext-script-a-poster.png`.

## Mac App Store export

The export targets 1920 × 1080 landscape, 28 seconds, 30 fps, H.264 High Profile Level 4.0, 11 Mbps video, and AAC stereo at 48 kHz with a 256 kbps target. It uses Rec. 709 color tags. The final encode is checked for successful full decoding and metadata; no App Store submission or review has taken place.

Apple references: [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) and [preview guidance](https://developer.apple.com/app-store/app-previews/).

## Capture and editing notes

The app was inspected and captured using the Computer Use plugin. An existing clean launch-checklist recording and high-resolution production captures on this Mac were retained as source media. The montage uses genuine interface images; the recording segment includes real moving footage of the HUD timer. The recorded demo plays within the captured result window during review and copy scenes.

Captions describe the demonstrated workflow. The app's existing locale and history dates remain as captured. The final video uses a music bed without voiceover. The README itself is unchanged so the preview can be placed where desired.

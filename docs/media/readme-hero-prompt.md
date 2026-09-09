# README hero composition

Headline: **Use your screen recording in your AI agent.**

Supporting copy: “Make a product video. Fix a bug. Create a ticket.” The footer notes that ScreenContext is also an everyday screen recorder.

The image uses a real capture of the current **Recordings window**, showing the video player, labeled Copy buttons, Copy & Return actions, and the path-only Recording file section. The player shows an original “Fieldnotes” sample document recorded from a single TextEdit window. No personal recording content or generated interface pixels are included. Dates and paths are the app's actual displayed values.

The native Swift compositor scales the complete screenshot uniformly on a deep blue background. Output: 2880 × 1600 opaque PNG.

- Screenshot: [recordings-window.png](readme-hero-source/recordings-window.png)
- Renderer: [render.swift](readme-hero-source/render.swift)
- Output: [screencontext-readme-hero.png](screencontext-readme-hero.png)

Regenerate from the repository root:

```sh
swift docs/media/readme-hero-source/render.swift
```

Original sample document and MP4 are retained locally in `dist/readme-hero-2026-09-09/`.

# ScreenContext demo media

The 25-second demo uses the current ScreenContext UI, its app icon and tagline, original sample content, a real HUD timer capture, and the app's real context-copy confirmation. Captions work without sound. The soundtrack is original synthesized music.

- `screencontext-demo.mp4`: 1920 × 1080, 30 fps, H.264 with stereo AAC; optimized for GitHub and web sharing.
- `screencontext-demo.gif`: 960 × 540, 10 fps, looping and silent; suitable for inline README playback.
- `screencontext-poster.png`: 1920 × 1080 poster for a linked video thumbnail.

Add this to the repository's root README for an animated preview linked to the video:

```markdown
[![ScreenContext — Show your AI what you mean](docs/media/screencontext-demo.gif)](docs/media/screencontext-demo.mp4)
```

For a still thumbnail, replace the GIF path with `docs/media/screencontext-poster.png`. After uploading the MP4 to a GitHub release or attachment, the link target can point directly to that hosted video.

The separate App Store export is at `dist/promo/screencontext-app-store.mp4` locally: 25 seconds, 1920 × 1080, 30 fps, H.264 High Level 4.0 at approximately 11 Mbps, stereo AAC targeting 256 kbps at 48 kHz. It uses restrained framing, with the sample recording shown inside ScreenContext. This is a prepared preview asset; it has not been submitted to App Review.

The local editable source and captures are in `dist/promo/source/`. Rendering uses captured app frames and actual HUD footage. The source recording is replayed/frozen within the captured player viewport during compositing. No AI response or issue submission is simulated. The selected context template is the existing Create issue template.

The production recording was created in the app's recording history using an original Launch checklist sample. A second short take supplied the full-width HUD timer footage. Existing recordings were preserved.

Sources for delivery specifications: [Apple preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) and [Apple creative guidance](https://developer.apple.com/app-store/app-previews/).

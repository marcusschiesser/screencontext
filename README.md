# ScreenContext

**Record your screen and voice. Use it as context in your AI workflows.**

[![ScreenContext — Turn your screencast into AI context](docs/media/screencontext-readme-hero.png)](https://apps.apple.com/app/id6809044710)

**[View on the Mac App Store](https://apps.apple.com/app/id6809044710)** · Free · macOS 15+

*The App Store release is pending Apple review.*

ScreenContext is a native Mac app that brings your screen recording, click keyframes, and microphone transcript together. Show what happened, explain what matters, and copy the context into your AI workflow.

Use it as your everyday screen recorder, too. Record a screen or window and share the MP4. When you need AI context, it is ready in the same app. No second recorder needed.

## From recording to context

1. **Choose what to capture.** In Settings, select a screen or window, enable optional audio and webcam inputs, and choose your webcam layout.
2. **Press ⌃⌘R to start and stop.** Change the shortcut in Settings → General. Walk through a task and explain it as you go. The menu bar shows elapsed time, and brief overlays confirm recording actions. ScreenContext saves the video and captures keyframes at clicks.
3. **Use the result.** Play back the recording, copy the MP4, or choose a template and copy the prepared context into your AI tool.

## Put your recording to work

- **Create an issue.** Demonstrate a bug and use the Create issue template to help your AI tool write reproduction steps and expected versus actual results.
- **Prepare a product video.** Record a walkthrough and use the Product video template to give your AI workflow source material and instructions for the video.
- **Create your own workflow.** Write a reusable template with your instructions and placeholders for the recording, keyframes, and transcript. Markdown and SRT formats are also available.
- **Just record.** Capture a demo, tutorial, or quick explanation and share the video directly.

ScreenContext prepares the material; your chosen AI tool handles the next step.

## Local recording, no account

Recordings and context stay on your Mac until you choose to share them. No ScreenContext account is required, and analytics are disabled for launch.

Screen recording works on **macOS 15 or later**. On-device microphone transcription requires **macOS 26 or later**, a supported language, and the corresponding speech assets. The app requests screen recording, microphone, and camera permissions as needed.

[Privacy policy](docs/privacy.md) · [Support](docs/support.md) · [Report an issue](https://github.com/marcusschiesser/screencontext/issues)

## Build from source

Use **Xcode 26 or later**. Open `ScreenContext.xcodeproj`, select the `ScreenContext` scheme, and press **⌘R**. Choose your signing team if prompted.

From the repository root:

```sh
./script/build_and_run.sh
```

Run the project checks:

```sh
./script/test_unit.sh
./script/test_integration.sh
./script/check_native_only.sh
```

The app uses Swift, SwiftUI, and native macOS media APIs. Read [design.md](design.md) before changing the interface. Bug reports and focused pull requests are welcome.

<details>
<summary>Upgrading from a local ContextCast build</summary>

The app now uses the bundle identifier `de.marcusschiesser.screencontext`. macOS gives it a separate sandbox and permission grants, so recordings and settings from builds using the previous identifier are not automatically migrated. The library still recognizes older ContextCast recording filenames.

</details>

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md) for attribution. The license does not grant rights to the ScreenContext name or third-party trademarks.

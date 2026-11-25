# Music EQ Player

A simple, beginner-friendly Flutter Web music player with a real-time 3-band equalizer built using the browser's Web Audio API.

## Target Platform

- **Flutter Web** running in **Google Chrome**

## Core Features (Problem Statement)

- **Audio Playback:** Plays bundled audio tracks and local audio files selected from the user's device via the browser file picker.
- **Playback Controls:** Play/Pause, Next, Previous, and a seek slider to jump to any position in the track.
- **Track Info & Timing:** Displays the current track's file name, elapsed time (`MM:SS`), and total duration (`MM:SS`).
- **Real-Time 3-Band Equalizer:** Low, Mid, and High sliders that audibly shape the audio in real time.
- **Reset EQ:** A **Reset EQ** button that returns all three equalizer bands to `0.0 dB` (flat).

## Architecture & Important Files

The app uses a single-screen Flutter UI backed by a `ChangeNotifier` controller that owns the browser audio element and Web Audio filter graph:

- [`lib/main.dart`](lib/main.dart):
  - `MyApp` and `MusicPlayerScreen`: Single-screen Material 3 UI (`ListenableBuilder` listening to `WebAudioController`) with file picker button, Now Playing card (track name, seek slider, transport controls, speed chips), Volume card, Equalizer card, Playlist card, error banner, download dialog, and 5-second Undo `SnackBar`.
  - `_EqSliderRow`: Reusable row widget for each EQ band slider and dB readout.
- [`lib/web_audio_controller.dart`](lib/web_audio_controller.dart):
  - `WebAudioController`: Manages `HTMLAudioElement`, `AudioContext`, `MediaElementAudioSourceNode`, three `BiquadFilterNode`s, browser file picking (`HTMLInputElement`), `Blob` object URLs, playback events, speed/volume controls, track removal/restoration, and WAV PCM encoding/download.
  - `AudioTrack`, `RemovedTrack`, `AudioExportFormat`, `AudioBitDepth`: Data models and enums for playlist items, undo state, and export options.
- [`pubspec.yaml`](pubspec.yaml): Declares dependencies (`web`, `cupertino_icons`, `flutter_lints`) and registers `assets/audio/` as bundled Flutter assets.
- `assets/audio/`: Contains the three bundled MP3 tracks (`laut_aana.mp3`, `tujhe_keh_na_saka.mp3`, `nazm_main_likhoon.mp3`).

## Packages Used & Why

- `flutter` (SDK): Builds the Material 3 user interface.
- `web: ^1.1.2` and `dart:js_interop`: Modern, strongly-typed Dart interop for browser APIs (`HTMLAudioElement`, `AudioContext`, `BiquadFilterNode`, `HTMLInputElement`, `Blob`, `URL`), replacing the deprecated `dart:html` library.
- `package:flutter/services.dart` (`rootBundle`): Loads bundled audio assets into memory so they can be converted to seekable `Blob` URLs.
- `cupertino_icons: ^1.0.8`: Default icon package included in the Flutter project template.
- `flutter_lints: ^6.0.0` (dev dependency): Enforces recommended Dart and Flutter lint rules during `flutter analyze`.

## Web Audio API Signal Chain

All audio plays through a single `HTMLAudioElement` routed into one `AudioContext` (lazily created and resumed on a user-initiated action such as clicking **Play** to satisfy Chrome's autoplay policy):

```text
HTMLAudioElement
  └──▶ MediaElementAudioSourceNode
         └──▶ lowFilter  (BiquadFilterNode: lowshelf,  250 Hz)
                └──▶ midFilter  (BiquadFilterNode: peaking,   1000 Hz, Q = 1)
                       └──▶ highFilter (BiquadFilterNode: highshelf, 4000 Hz)
                              └──▶ AudioContext.destination (Speakers)
```

### Filter Frequencies & Gain Range

| Band     | Filter Type | Frequency | Q Factor | Gain Range               | Default  |
| :------- | :---------- | :-------- | :------- | :----------------------- | :------- |
| **Low**  | `lowshelf`  | `250 Hz`  | —        | `-12.0 dB` to `+12.0 dB` | `0.0 dB` |
| **Mid**  | `peaking`   | `1000 Hz` | `1`      | `-12.0 dB` to `+12.0 dB` | `0.0 dB` |
| **High** | `highshelf` | `4000 Hz` | —        | `-12.0 dB` to `+12.0 dB` | `0.0 dB` |

## Setup & Running in Chrome

1. Install dependencies:
   ```powershell
   flutter pub get
   ```
2. Run the app in Google Chrome:
   ```powershell
   flutter run -d chrome
   ```
3. Build for production web deployment (optional):
   ```powershell
   flutter build web
   ```
   _(If hosting on GitHub Pages under a repository subpath, use `flutter build web --base-href "/<repo-name>/"`.)_

## How to Test Playback & the Equalizer

1. **Launch:** Run `flutter run -d chrome`. The three bundled tracks appear in the playlist with `Laut aana.mp3` loaded.
2. **Playback & Transport:** Click **Play**, test **Pause**, **Next**, **Previous**, **-5s** / **+5s**, and drag or tap the **seek slider** to jump to different parts of the track.
3. **Equalizer:** While audio is playing, move the **Low**, **Mid**, and **High** sliders toward `+12.0 dB` or `-12.0 dB` and listen for real-time tonal changes, then click **Reset EQ** to return all bands to `0.0 dB`.
4. **Local File Picker & Error Handling:** Click **Select Audio Files** to add `.mp3`, `.wav`, or `.mp4` files (confirming bundled tracks remain in the playlist), test cancelling the picker, and verify unsupported files show a dismissible warning banner.
5. **Playlist Removal & Undo:** Click the delete icon on a track and verify the Undo pop-up restores it if clicked within 5 seconds, or disappears after 5 seconds.
6. **Download / Upscale:** Click the download icon on a track, choose **WAV**, pick `8-bit PCM`, `16-bit PCM`, `24-bit PCM`, or `32-bit Float`, and verify the `.wav` file downloads.

> **Verification Note:** Automated `flutter analyze` and `flutter build web` were run and passed after the final code changes. Interactive browser playback, audible EQ filtering, and file downloads in Chrome were tested manually by the user during development (not automated in a headless browser test).

## Limitations

- **Browser Codec Support:** Playback depends on Chrome's native `HTMLAudioElement` and `AudioContext.decodeAudioData` support (works well for `.mp3`, `.wav`, and `.mp4`/AAC; unsupported formats trigger a warning banner).
- **No Negative Playback Speeds:** Chrome's `HTMLAudioElement.playbackRate` does not support negative (reverse) playback speeds, so speeds slower than `1.0x` are provided as `0.5x` and `0.75x`.
- **MP3 / MP4 Export:** Chrome's built-in Web APIs do not include a native MP3 or MP4 audio encoder without adding an external encoder library (such as `lamejs` or `ffmpeg.wasm`). Cross-format conversion and 8/16/24/32-bit PCM upscaling are supported for **WAV**; `.mp3` and `.mp4` downloads are available when the source track is already in that format.
- **Template Test File:** `test/widget_test.dart` still contains the default Flutter counter template test and was not updated for the Web Audio UI.

## Challenges Faced During Development

1. **Bundled Asset Filenames with Spaces:** Flutter Web URL-encoded spaces in asset filenames on disk (e.g., `Laut%20aana.mp3`), causing 404 playback errors. Renaming the asset files to lowercase with underscores (`laut_aana.mp3`, `tujhe_keh_na_saka.mp3`, `nazm_main_likhoon.mp3`) while keeping the original display titles resolved this.
2. **Seeking on the Flutter Dev Server:** `flutter run -d chrome` serves `assets/...` without HTTP `206 Partial Content` byte-range support, which caused Chrome to ignore `audio.currentTime` updates and snap the seek slider and `±5s` skip buttons back to the start. Loading bundled assets via `rootBundle.load` into in-memory `Blob` URLs enabled full seeking.
3. **File Picker Replacing Bundled Tracks:** Uploading new files initially cleared the existing playlist. Updating `pickFiles()` to append newly selected tracks preserved the pre-existing tracks.
4. **Undo Pop-Up Persisting Past 5 Seconds:** Flutter's `SnackBar` with an `action` button can remain open indefinitely in Chrome when accessibility navigation is active. Adding an explicit 5-second `Timer` to call `controller.close()` ensured reliable auto-dismissal.

## AI Tools Used

- **Antigravity AI Assistant:** Used to scaffold `WebAudioController` with modern `package:web` / `dart:js_interop` bindings, design the single-screen Material 3 UI, implement client-side WAV PCM encoding (8/16/24/32-bit float), diagnose the dev-server seeking and `SnackBar` persistence bugs, and run `flutter analyze` and `flutter build web`.

## Extra Features Added

- **Pre-Bundled Playlist:** Three preloaded tracks (`Laut aana.mp3`, `Tujhe Keh Na Saka.mp3`, `Nazm Main Likhoon.mp3`) ready to play immediately which were produced using **SunoAI** using their V6-mini model.
- **Playback Speed Controls:** Quick-select chips for `0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `1.75x`, and `2.0x`.
- **5-Second Skip Buttons:** `-5s` (`replay_5`) and `+5s` (`forward_5`) buttons.
- **Volume Slider:** Real-time `0%`–`100%` volume control placed above the EQ section.
- **Track Removal with 5-Second Undo:** Delete button on each playlist item with a 5-second Undo pop-up that restores the track and its playback state.
- **Multi-Format Playback & WAV PCM Upscaling Download:** Plays `.mp3`, `.wav`, and `.mp4` files, and lets users download tracks as `.wav` in `8-bit PCM`, `16-bit PCM`, `24-bit PCM`, or `32-bit Float`.

## Why These Extra Features Matter to a Musician or Audiophile

- **Playback Speed (`0.5x`–`2.0x`):** Slowing a track down to `0.5x` or `0.75x` makes it much easier to transcribe fast guitar solos, vocal runs, or complex drum patterns by ear, while `1.25x`–`2.0x` lets you skim long rehearsals or live recordings quickly.
- **±5 Second Skip Buttons:** When practicing a specific riff, chord change, or mix transition, tapping `-5s` lets you immediately replay the last bar or phrase without losing your flow on a tiny timeline slider.
- **Dedicated Volume Control Above the EQ:** Boosting EQ bands (up to `+12 dB`) can push a hot master toward digital clipping. Having a dedicated output volume slider right above the EQ makes it easy to level-match and audition tonal changes cleanly.
- **5-Second Undo on Track Removal:** During critical listening or setlist curation, an accidental click shouldn't permanently drop a reference track—an instant Undo restores both the song and its position in the queue.
- **24-Bit PCM & 32-Bit Float WAV Export:** Converting compressed `.mp3`/`.mp4` or lower-bit-depth files into `24-bit PCM` or `32-bit Float` `.wav` gives producers and audiophiles an uncompressed, headroom-safe file ready to drop into a DAW (like Ableton, Logic, or FL Studio) for further mixing, mastering, or stem work without adding extra quantization noise.

<div align="center">

<img src="assets/logo.svg" alt="Mic Mini logo" width="112" height="112">

# Mic Mini

### A recorder for your goldfish memory: record anything, anytime, straight from the menu bar of your Mac

[![macOS](https://img.shields.io/badge/macOS-26%2B_Tahoe-lightgrey.svg?style=flat-square&logo=apple)](#-install)
[![Homebrew](https://img.shields.io/badge/Homebrew-tap-fbb040.svg?style=flat-square&logo=homebrew&logoColor=white)](#-install)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-f05138.svg?style=flat-square&logo=swift&logoColor=white)](#-how-it-works)
[![Liquid Glass](https://img.shields.io/badge/Liquid_Glass-native-64d2ff.svg?style=flat-square)](#-how-it-works)
[![Size](https://img.shields.io/badge/Voice-~15_MB%2Fhour-0a84ff.svg?style=flat-square)](#-ready-for-ai)
[![Network](https://img.shields.io/badge/Network_access-none-critical.svg?style=flat-square)](#%EF%B8%8F-private-by-design)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

<br/>

<img src="assets/hero.png" alt="Mic Mini recording: a black island grows out of the MacBook notch with a swimming blue fish, Pause and Stop buttons" width="100%">

<br/>

**Mic Mini** is a small fish in your menu bar. Click it, hit record, and it records: a meeting, a lecture, a hallway idea, a call. While it records, a blue fish swims out of your MacBook's camera notch; catch it with the mouse to stop. No window, no Dock icon. You get a small, voice-tuned audio file that's ready for any AI to transcribe and summarize.

```sh
brew tap flol3622/mic-mini https://github.com/flol3622/mic-mini
brew trust --formula flol3622/mic-mini/mic-mini
brew install flol3622/mic-mini/mic-mini && mic-mini
```

</div>

<br/>

---

## 🐠 At a Glance

You leave the meeting, and ten minutes later the decision, the number or the name is gone. Mic Mini makes capturing it a one-second habit: it's always there, it never gets in the way, and the file it makes is built for transcription.

| | Voice Memos | QuickTime Player | AI meeting bots | **Mic Mini** |
| :--- | :---: | :---: | :---: | :---: |
| **Start recording** | Open the app, click | File → New Audio Recording | Invite the bot to the call | ✅ **Click the fish in the menu bar** |
| **On screen while recording** | App window | Window | A participant in the call | ✅ **A small fish beside the notch** |
| **In-person conversations** | ✅ | ✅ | ❌ Online calls only | ✅ |
| **Any call app** | ✅ | ✅ | ⚠️ Supported platforms only | ✅ |
| **Audio leaves your Mac** | ⚠️ With iCloud sync | No | ❌ Yes, by design | ✅ **Never** |
| **Starts at login** | ❌ | ❌ | n/a | ✅ |

---

## ✨ Features

- **Subtle.** Mic Mini has no window and no Dock icon, just a fish in the menu bar. When you're not recording, the notch stays empty.
- **Anytime.** Click the menu bar fish and the controls drop down. One click starts recording. Mic Mini opens at login, so it's always there after a restart, and ⌘Space finds it like any other app.
- **Alive, not loud.** While recording, a blue fish swims out of the notch. It beats its tail harder when the microphone hears you, so a glance tells you it's working.
- **Catch the fish to stop.** Your pointer turns into a grabbing hand over the fish. Click it and it's caught: the recording is saved with a one-second flourish.
- **Tuned for voice.** Mono AAC at 24 kHz and 32 kbps, about **15 MB per hour**: speech stays clear and files stay small enough to upload anywhere. A 48 kbps option is in Settings.
- **Safe for long meetings.** Audio is written to disk as you record. Your Mac won't go to idle sleep while recording. If the microphone disappears mid-meeting, everything captured so far is kept and Mic Mini tells you where.
- **Pause and resume** without starting a new file.
- **Native to macOS 26.** SwiftUI and Liquid Glass controls, a spring animation that follows Reduce Motion, VoiceOver labels, and a light trackpad tap when you start or stop.

---

## 📦 Install

**You need:**
- macOS 26 (Tahoe) or later. It works best on a MacBook with a notch; other Macs get a Liquid Glass pill under the menu bar.
- [Homebrew](https://brew.sh) and Apple's Command Line Tools (`xcode-select --install`). Homebrew builds Mic Mini from source on your Mac.

### Homebrew

```sh
brew tap flol3622/mic-mini https://github.com/flol3622/mic-mini
brew trust --formula flol3622/mic-mini/mic-mini
brew install flol3622/mic-mini/mic-mini
mic-mini
```

1. `brew tap` adds this repository as a tap. It's its own tap, so there's nothing else to add.
2. `brew trust` is how Homebrew 7 asks you to approve formulae from outside its official taps. Skip it on older Homebrew.
3. `mic-mini` starts the app. From then on, Mic Mini opens at login by itself. It also puts a small launcher in `~/Applications`, so you can start it with ⌘Space (Spotlight doesn't look inside Homebrew's folders).

On your first recording, macOS asks for microphone access. Click **Allow**.

**Update** with `brew upgrade flol3622/mic-mini/mic-mini`, or follow `main` with `brew install --HEAD flol3622/mic-mini/mic-mini`.

**Uninstall:** in Mic Mini's Settings, turn off **Open at login** and click **Quit Mic Mini**, then:

```sh
brew uninstall flol3622/mic-mini/mic-mini
brew untap flol3622/mic-mini
rm -rf ~/Applications/"Mic Mini.app"
```

Your recordings stay in their folder.

---

## 🎙️ Use It

<img src="assets/states.png" alt="Four states of the island: idle behind the notch; hover with folder, settings and record buttons; recording with a fish beside the notch; hover while recording with pause and stop" width="100%">

1. **Record.** Click the fish in the menu bar, then the teal **fish** button.
2. **Keep going.** The blue fish swims out of the notch while you record, and the menu bar fish turns red. Click the menu bar fish to **pause**, **resume** or **stop**. Paused time isn't recorded.
3. **Or catch it.** Click the swimming fish itself to stop and save.
4. **Find it.** A green check confirms the save. Open the menu bar fish to see the recording's name, and click it to show the file in Finder. The **folder** button opens all your recordings. Right-click the menu bar fish for Settings and Quit.

Recordings go to `~/Music/Mic Mini` by default, named by date and time, such as `Meeting 2026-11-24 14.03.11.m4a`, so they sort chronologically. **Settings** (the gear) changes the folder, the audio quality and **Open at login**, and has **Quit Mic Mini**.

> **Online meetings:** Mic Mini records the microphone, not your Mac's sound output. With headphones on, you get your side of the call. Without headphones, the microphone usually picks up both sides from the speakers.

---

## 🤖 Ready for AI

Mic Mini's files are made to be handed to a model: mono, speech-tuned, and small.

| Setting | Format | Size per hour | Fits in a 25 MB upload |
| :--- | :--- | :---: | :---: |
| **Compact** (default) | AAC · 24 kHz · mono · 32 kbps · `.m4a` | ~15 MB | ~1 h 40 min |
| **Higher quality** | AAC · 24 kHz · mono · 48 kbps · `.m4a` | ~22 MB | ~1 h 10 min |

Some ways to use them:

- **Google Gemini:** attach the file in [Google AI Studio](https://aistudio.google.com), or upload it with the [Files API](https://ai.google.dev/gemini-api/docs/audio) for long recordings, then ask for a transcript.
- **OpenAI:** the [speech-to-text API](https://platform.openai.com/docs/guides/speech-to-text) takes `.m4a` files up to 25 MB.
- **On your Mac:** [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) opens the file directly. For [whisper.cpp](https://github.com/ggml-org/whisper.cpp), convert it first with `ffmpeg -i "Meeting….m4a" -ar 16000 -ac 1 meeting.wav`.

Then put the transcript to work. A prompt that does most of the remembering for you:

> *"Transcribe this meeting with timestamps and speaker labels. Then list the decisions, the action items with owners and deadlines, the numbers mentioned, and the open questions."*

---

## 🛡️ Private by Design

- **No network access.** Mic Mini contains no networking code. Recordings stay in your folder until you decide to share them.
- **Nothing runs until you click.** Mic Mini only opens the microphone when you press the fish, and closes it when you stop.
- **Only what you need.** The one permission it asks for is the microphone. Catching the fish uses ordinary mouse events, so it doesn't need Accessibility or Screen Recording access.

> **Record responsibly.** Mic Mini is deliberately unobtrusive, and while recording, the fish's lane covers the part of the menu bar where macOS usually shows its orange microphone indicator. Recording people without their consent is illegal in many places. Tell the people you record.

---

## 🔬 How It Works

```mermaid
flowchart LR
    subgraph MAC["Your Mac"]
        A["Menu bar fish"] --> B["MenuBarController<br/>NSStatusItem · popover · Liquid Glass"]
        B -- "Record · Pause · Stop" --> E["MeetingRecorder<br/>AVAudioRecorder, AAC"]
        E -- "level meter" --> D["IslandController<br/>TimelineView fish in the notch"]
        D -- "catch the fish" --> E
        E --> F[("~/Music/Mic Mini/*.m4a")]
    end

    style MAC fill:#f8f9fa,stroke:#0a84ff,stroke-width:2px,color:#000
```

1. **A menu bar home.** An `NSStatusItem` opens a popover with the controls. They use SwiftUI's interactive `glassEffect` inside a `GlassEffectContainer`, so they respond to your press and morph between Record and Stop.
2. **An island that is part of the notch.** While recording, a borderless, transparent panel just above the menu bar draws a black island flush with the top edge, with concave top corners, so it reads as the notch growing. It takes the clicks on itself and lets every other click through.
3. **Catch it without permissions.** The panel knows where the fish is from the same clock that animates it, and checks your click against it. A global mouse-moved monitor shows the grabbing hand; mouse movement doesn't need Accessibility access, unlike key events.
4. **A fish that listens.** A `TimelineView` swims the fish along its lane; the tail's beat follows `AVAudioRecorder`'s level meter, sampled 12 times per second.
5. **Recording that survives.** `AVAudioRecorder` streams AAC to disk. A `ProcessInfo` activity holds off idle sleep, and a watchdog notices when the input device vanishes without telling anyone.
6. **Back after a restart.** **Open at login** uses `SMAppService`, the same login items you see in System Settings → General → Login Items & Extensions.

---

## ⚠️ Limitations

- **macOS 26 or later.** Mic Mini uses Liquid Glass and other macOS 26 SwiftUI APIs.
- **Microphone only.** It doesn't capture your Mac's sound output. See [Online meetings](#%EF%B8%8F-use-it).
- **Permission after each update.** Homebrew builds Mic Mini on your Mac and signs it ad hoc, so macOS treats every new build as a new app and asks for microphone access again.
- **A fixed lane.** While recording, the island covers about 230 points of the menu bar to the right of the notch. Menu bar icons there are hidden until you stop, which can include Mic Mini's own (stop by catching the fish, or ⌘-drag the icon further right). That also includes the microphone indicator, whichever app is using the microphone.
- **One screen.** The island appears on the display with a notch, or on the main display if there's none.

---

## 🛠️ Development

```text
Sources/MicMini.swift          app delegate: wires the menu bar, island, recorder and settings
Sources/MenuBar.swift          menu bar item, popover controls, right-click menu
Sources/Island.swift           the notch island while recording: panel, swimming fish, catch animation
Sources/Launcher.swift         the ~/Applications launcher that lets Spotlight find a Homebrew install
Sources/MeetingRecorder.swift  AVAudioRecorder: start, pause, resume, stop, level meter
Sources/Settings.swift         preferences, Open at login, settings window
app/Info.plist                 bundle: LSUIElement (no Dock icon), microphone usage text
scripts/build.sh               swiftc → dist/Mic Mini.app, ad-hoc signed
scripts/install.sh             installs the current checkout through a local Homebrew tap
Formula/mic-mini.rb            the public Homebrew formula (this repository is its own tap)
```

```sh
./scripts/build.sh                 # dist/Mic Mini.app
open "dist/Mic Mini.app"
./scripts/install.sh               # or install the checkout with Homebrew
```

The build uses only `swiftc` from the Command Line Tools, with no Xcode project. That's why the SwiftUI code avoids `@State`: in the macOS 26 SDK it's a macro whose plugin ships with Xcode only.

**To release:** bump `CFBundleShortVersionString` and `CFBundleVersion` in `app/Info.plist`, set the same version in the `tag:` of `Formula/mic-mini.rb`, commit, then tag `vX.Y.Z` and push the tag.

---

## 📖 Acknowledgements

- Inspired by the Dynamic Island on iPhone, and by everyone who has ever said *"wait, what did we decide?"*
- Built with [Claude Code](https://claude.com/claude-code).

---

<div align="center">
  <b>MIT License</b> · Not affiliated with Apple. Mac, MacBook, Dynamic Island and Liquid Glass are trademarks of Apple Inc.
</div>

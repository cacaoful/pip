# Pip

Local-first dictation and meeting transcription for macOS (Apple Silicon).

Pip is a personal fork of [Muesli](https://github.com/Muesli-HQ/muesli), rebranded and tuned for private use. Speech-to-text runs on-device via CoreML / Neural Engine.

| | |
|---|---|
| App | `/Applications/Pip.app` |
| Bundle ID | `com.pip.app` |
| Data | `~/Library/Application Support/Pip` |
| Platform | macOS 14.2+, Apple Silicon |

## Build (friends)

**Requirements:** Apple Silicon Mac, macOS 14.2+, [Xcode](https://developer.apple.com/xcode/) 16+ (or full Xcode + command-line tools).

```bash
git clone https://github.com/cacaoful/pip.git
cd pip
./scripts/dev-test.sh
```

That builds Pip, installs it to `/Applications/Pip.app`, and launches it. Local builds ad-hoc sign by default, so you do **not** need an Apple Developer certificate.

First launch walks through onboarding (model download, mic / accessibility / input monitoring permissions, hotkey, dictation test).

### Optional: persistent permissions across rebuilds

Ad-hoc signatures change every rebuild, so macOS may ask you to re-approve permissions. To keep grants stable, create a local **Apple Development** cert in Xcode and pass it:

```bash
MUESLI_SKIP_SIGN=1 \
MUESLI_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
./scripts/dev-test.sh
```

### Useful commands

```bash
./scripts/dev-test.sh              # build + launch Pip
./scripts/dev-test.sh --reset      # re-run onboarding (keeps your data)
pkill -f /Applications/Pip.app     # quit Pip
```

### Tests

```bash
swift test --package-path native/MuesliNative
```

## What it does

- **Dictation** — Hold hotkey → speak → release → text pasted at the cursor
- **Meeting transcription** — Mic (You) + system audio (Others), VAD chunking, speaker diarization, AI meeting notes
- **On-device ASR** — Parakeet, Whisper, Cohere, Nemotron, SenseVoice, Qwen3, and more
- **Summaries (optional)** — OpenAI / OpenRouter API key, ChatGPT OAuth, or local Ollama

## License

MIT — see [LICENSE](LICENSE). Upstream project: [Muesli-HQ/muesli](https://github.com/Muesli-HQ/muesli).

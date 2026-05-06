# AgenSense GUI Lite

Lightweight Flutter validation client for [AgenSense](https://github.com/agendash/AgenSense).

AgenSense GUI Lite is a developer-facing test client for local provider setup, microphone capture, realtime voice WebSocket behavior, TTS playback, and AgenSense protocol debugging. It is not the end-user AgenDash desktop client.

## What It Tests

- Connection setup: AgenSense base URL, API key, provider profile, client id, and device label
- Provider profiles: list profiles, register LocalAI/OpenAI-compatible profiles, and register mock profiles
- Direct inference:
  - `POST /v1/llm/chat`
  - `POST /v1/asr/transcribe`
  - `POST /v1/tts/synthesize`
- LLM + tool metadata probe with Universal Voice Layer and MCP-style context
- Realtime voice:
  - `GET /v1/voice/ws`
  - microphone PCM stream
  - VAD-driven turns
  - `asr.partial` / `asr.final`
  - `llm.delta`
  - binary TTS playback
- Device compatibility checks:
  - `POST /v1/bootstrap`
  - `GET /v1/device/config`
  - `POST /v1/device/telemetry`
  - `GET /v1/session/ws`
- Debug traces:
  - `GET /debug/api/traces`

## Run

Start AgenSense first:

```sh
cd ~/Workspace/agen/agensense
AGENSENSE_DEBUG=true go run ./cmd/agensense
```

Then run the GUI:

```sh
cd ~/Workspace/agen/agensense-gui-lite
flutter run -d macos
```

Default connection values:

- Server URL: `http://127.0.0.1:8080`
- API key: `demo-user-key`
- Provider profile: `default`

The app shows a required connection setup dialog on first launch. After saving, use the settings button in the top-right corner to edit the same values.

## LocalAI Notes

The Providers tab can register a LocalAI/OpenAI-compatible profile. AgenSense defaults to LocalAI on `http://127.0.0.1:8081/v1` so it does not conflict with the AgenSense server on `8080`.

Typical model names:

- ASR: `whisper-1`
- LLM: `hauhaucs-qwen3.6-35b-a3b-aggressive-q4-k-m` or another installed chat model
- TTS: `faster-qwen3-tts`

If your TTS backend supports OpenAI-style voices, set a voice on the AgenSense server:

```sh
AGENSENSE_OPENAI_TTS_VOICE=Serena go run ./cmd/agensense
```

For LocalAI backends that reject `voice`, use:

```sh
AGENSENSE_OPENAI_TTS_VOICE=none go run ./cmd/agensense
```

On Android or iOS devices, `127.0.0.1` means the device itself. Run AgenSense on a reachable interface and point the GUI at the host LAN address:

```sh
AGENSENSE_ADDR=:8080 AGENSENSE_DEBUG=true go run ./cmd/agensense
```

Example GUI server URL:

```text
http://192.168.1.20:8080
```

## Voice WS Flow

Use the Voice WS tab to validate an end-to-end local voice loop:

1. Enable or disable `Mic gate during TTS playback` depending on whether speaker audio leaks into the microphone.
2. Click `Connect + listen`.
3. Speak a short request.
4. Watch `Event stream`, `ASR final`, and `LLM text`.
5. Listen for returned TTS playback.

With continuous VAD turns enabled, the app keeps listening until you press `Stop`, disconnect, or switch tabs.

## Repository Hygiene

This repository tracks source and platform project files only. Generated local data is ignored:

- `.dart_tool/`
- `build/`
- `.idea/`
- platform build outputs
- local mobile/desktop toolchain files

Do not commit production API keys or user audio captures.

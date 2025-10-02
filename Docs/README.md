# mjvoice

A lightweight, privacy-first macOS dictation app with AI writing assistance, liquid-glass UI, and system-wide functionality.

Highlights
- Menubar app with push-to-talk dictation
- Low-latency audio pipeline with VAD gating
- On-device formatting (filler removal, punctuation, capitalization, tone)
- Text insertion via Accessibility API with robust fallbacks
- Modular XPC workers with auto-unload for low idle memory
- Privacy-first: Offline mode, sandboxed, Hardened Runtime, Privacy Manifest

Folders
- mjvoice: App sources (menubar, HUD, hotkey, audio, accessibility)
- Shared: Models, utilities, XPC protocols, assets, privacy manifest
- Workers: XPC services (AudioVADService, ASRService, LLMService)
- Tests: Unit and UI test scaffolding
- Docs: Documentation

Status
- MVP foundations implemented per spec phases 1-3, with local AI formatting.
- ASR engine wrapper is ready to load Whisper CoreML models when provided.

See BUILD.md for setup, model installation, and running instructions.

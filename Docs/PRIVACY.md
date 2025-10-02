# Privacy Overview

mjvoice is privacy-first:
- Offline-first: All features operate locally by default. No network calls are made in Offline Mode.
- Zero data retention: No audio is persisted by default. Temporary buffers live in RAM only.
- Minimal entitlements: microphone input, automation for Accessibility insertion.
- Hardened Runtime and Sandbox enabled.
- Privacy Manifest included (PrivacyInfo.xcprivacy).

Data Flow
1) Microphone audio is captured on-demand when you press the PTT hotkey.
2) Audio is processed locally (VAD gating, optional ASR if models present).
3) Text insertion occurs via Accessibility or pasteboard fallback.
4) Optional local formatting occurs in an XPC worker.

Secure Input
- The app detects Secure Input (e.g., password fields) and auto-pauses dictation. It never attempts to insert text in such contexts.

Cloud Usage
- Not applicable in v1.0. When a cloud option is added (post-MVP), endpoints must be ZDR (Zero Data Retention) and user-controlled via an Offline Mode master switch.

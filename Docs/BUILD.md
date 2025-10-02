# Build Guide

Requirements
- Xcode 15 (Swift 5.9+), macOS 14+
- Apple Developer account for signing (development)

Project Setup
1) Open mjvoice.xcodeproj in Xcode.
2) In Targets > mjvoice and each XPC target, set your Development Team for automatic signing.
3) Ensure Hardened Runtime and Sandbox are enabled (already in project settings).
4) Grant Accessibility and Microphone permissions on first run.

Model Installation (Whisper Core ML)
- Place compiled CoreML model directories at:
  ~/Library/Application Support/mjvoice/Models/
  - whisper-tiny.mlmodelc
  - whisper-base.mlmodelc
  - whisper-small.mlmodelc

The app will select the model based on preferences and thermal/battery conditions (heuristics in ASR service). If no model is present, the ASR will return an empty transcription.

Build & Run
- Scheme: mjvoice
- Run (Cmd+R). The menubar mic icon should appear.
- Use the default hotkey Cmd+Opt+Space to start PTT.

Verification Steps
- HUD appears and animates while listening.
- Secure Input detection: open a password field; dictation auto-pauses.
- Text insertion works in TextEdit and Safari text fields (AX or pasteboard fallback).

Profiling
- Use Instruments templates (Time Profiler, Allocations, Energy) to verify:
  - Idle RAM ≤30MB
  - Idle CPU ≈0%
  - Hotkey to recording <100ms
  - Streaming latency target <150ms (ASR model dependent)

Notarization
- For distribution, archive the app (Product > Archive), sign with Developer ID, attach a Privacy Manifest, and notarize via Xcode Organizer.

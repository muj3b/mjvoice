# Performance and Profiling Guide

Targets
- Cold start: hotkey to first word ≤250ms (with model loaded)
- Idle: ≤30MB RAM, ~0% CPU
- Streaming insert: <150ms lag @ 120 wpm

Tips
- Do not load ASR model at launch; lazy-load on first use.
- Keep XPC workers unloaded; they auto-exit after 5s idle.
- Minimize allocations in audio path; reuse buffers when possible.
- Use Instruments: Time Profiler, Allocations, Energy.

Checks
- Instruments > Allocations: verify no leaks.
- Energy Log: idle energy impact is "Low".
- Time Profiler: audio processing stays within 10ms per 100ms chunk.

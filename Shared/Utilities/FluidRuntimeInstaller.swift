import Foundation

enum FluidRuntimeInstallerError: LocalizedError {
    case pythonMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            return "python3 executable not found. Install Xcode Command Line Tools or Python 3."
        case .processFailed(let message):
            return message
        }
    }
}

final class FluidRuntimeInstaller {
    static let shared = FluidRuntimeInstaller()

    private init() {}

    func install(progress: @escaping (String) -> Void) async throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let dest = home.appendingPathComponent(".mjvoice/fluid", isDirectory: true)
        let bin = dest.appendingPathComponent("bin", isDirectory: true)
        let models = dest.appendingPathComponent("models", isDirectory: true)
        let venv = dest.appendingPathComponent(".venv", isDirectory: true)

        progress("Preparing destination…")
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: models, withIntermediateDirectories: true)

        let pythonPath = try resolveExecutable("python3")
        let venvPython = venv.appendingPathComponent("bin/python3")

        if !fileManager.fileExists(atPath: venv.path) {
            progress("Creating Python virtual environment…")
            try runProcess(executable: pythonPath, arguments: ["-m", "venv", venv.path])
        }

        progress("Upgrading pip and installing dependencies…")
        try runProcess(executable: venvPython.path,
                       arguments: ["-m", "pip", "install", "--upgrade", "pip", "faster-whisper", "soundfile"])

        progress("Writing runtime helpers…")
        try writeRunnerScripts(binDirectory: bin, venvDirectory: venv)

        progress("Caching Fluid base models (tiny/base/small)…")
        let prefetchScript = """
import os
from faster_whisper import WhisperModel

cache = os.environ.get("MJVOICE_FLUID_MODEL_CACHE", "")
os.makedirs(cache, exist_ok=True)
for model_id in ["Systran/faster-whisper-tiny", "Systran/faster-whisper-base", "Systran/faster-whisper-small"]:
    print(f"[fluid] downloading {model_id}…")
    WhisperModel(model_id, device="cpu", compute_type="int8", download_root=cache)
"""
        try runProcess(executable: venvPython.path,
                       arguments: ["-c", prefetchScript],
                       environment: ["MJVOICE_FLUID_MODEL_CACHE": models.path])

        let appBin = home
            .appendingPathComponent("Library/Application Support/mjvoice/bin", isDirectory: true)
        try fileManager.createDirectory(at: appBin, withIntermediateDirectories: true)
        let link = appBin.appendingPathComponent("fluid-runner")
        let runner = bin.appendingPathComponent("fluid-runner")
        if fileManager.fileExists(atPath: link.path) {
            try? fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: runner)

        progress("Fluid runtime ready.")
        return runner
    }

    private func resolveExecutable(_ name: String) throws -> String {
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        try which.run()
        which.waitUntilExit()
        if which.terminationStatus != 0 {
            throw FluidRuntimeInstallerError.pythonMissing
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw FluidRuntimeInstallerError.pythonMissing
        }
        return path
    }

    private func writeRunnerScripts(binDirectory: URL, venvDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let runnerPy = binDirectory.appendingPathComponent("fluid_runner.py")
        let pythonSource = """
#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path

try:
    import soundfile as sf
    from faster_whisper import WhisperModel
except Exception as exc:
    print(f"Failed to load Fluid runtime dependencies: {exc}", file=sys.stderr)
    sys.exit(2)

MODEL_MAP = {
    "fluid-light": "Systran/faster-whisper-tiny",
    "fluid-pro": "Systran/faster-whisper-base",
    "fluid-advanced": "Systran/faster-whisper-small",
}


def resolve_model(args):
    if args.model_path:
        path = Path(args.model_path)
        if path.is_file():
            return str(path.parent)
        return str(path)
    return MODEL_MAP.get(args.model_id, args.model_id)


def main():
    parser = argparse.ArgumentParser(description="mjvoice Fluid runtime wrapper")
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--model-id", default="fluid-advanced")
    parser.add_argument("--audio", required=True)
    parser.add_argument("--format", default="json", choices=["json", "text"])
    parser.add_argument("--cache-dir", default=os.environ.get("MJVOICE_FLUID_MODEL_CACHE", os.path.expanduser("~/.mjvoice/fluid/models")))
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    model_arg = resolve_model(args)
    model = WhisperModel(model_arg, device=args.device, compute_type="int8", download_root=args.cache_dir)

    try:
        audio, _ = sf.read(args.audio)
    except Exception as exc:
        print(f"Failed to read audio file {args.audio}: {exc}", file=sys.stderr)
        sys.exit(3)

    segments, _ = model.transcribe(audio, beam_size=1, vad_filter=True, temperature=0.0)
    texts = [segment.text.strip() for segment in segments]
    combined = " ".join(texts).strip()

    if args.format == "json":
        print(json.dumps({"text": combined, "segments": texts}, ensure_ascii=False))
    else:
        print(combined)


if __name__ == "__main__":
    main()
"""
        try pythonSource.write(to: runnerPy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: runnerPy.path)

        let shim = binDirectory.appendingPathComponent("fluid-runner")
        let shimSource = """
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd \"$(dirname \"${BASH_SOURCE[0]}\")/..\" && pwd)"
VENV="$ROOT/.venv"
if [ ! -d "$VENV" ]; then
  echo "Fluid runtime virtualenv missing. Re-run the installer." >&2
  exit 1
fi
source "$VENV/bin/activate"
python3 "$ROOT/bin/fluid_runner.py" "$@"
"""
        try shimSource.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: shim.path)
    }

    private func runProcess(executable: String, arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        if let environment {
            env.merge(environment) { _, new in new }
        }
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FluidRuntimeInstallerError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

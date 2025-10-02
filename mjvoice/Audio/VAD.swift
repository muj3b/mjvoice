import Foundation
import Accelerate

final class VAD {
    private var threshold: Float = 0.01
    private var hangoverFrames = 5
    private var speechCounter = 0
    
    private var connection: NSXPCConnection?
    private var proxy: AudioVADServiceProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { err in
            NSLog("[VADClient] XPC error: \(err)")
        } as? AudioVADServiceProtocol
    }
    
    init() {
        connect()
    }
    
    private func connect() {
        if connection != nil { return }
        let iface = NSXPCInterface(with: AudioVADServiceProtocol.self)
        connection = XPCConnectionFactory.makeConnection(.vad, remoteInterface: iface)
    }

    func isSpeech(chunk: [Float]) -> Bool {
        // If XPC connection is available, use Silero VAD
        if let proxy = proxy {
            var result = false
            let semaphore = DispatchSemaphore(value: 0)
            
            // Convert Float array to Data
            var data = Data(count: chunk.count * MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { raw in
                let dst = raw.bindMemory(to: Float.self)
                _ = dst.initialize(from: chunk)
            }
            
            // Call XPC service
            proxy.isSpeechPresent(in: data, sampleRate: 16000) { isSpeech in
                result = isSpeech
                semaphore.signal()
            }
            
            // Wait for response (with timeout)
            _ = semaphore.wait(timeout: .now() + 0.1)
            return result
        }
        
        // Fallback to energy-based with zero-crossing heuristic
        var sum: Float = 0
        vDSP_measqv(chunk, 1, &sum, vDSP_Length(chunk.count))
        let rms = sqrtf(sum)
        let energySpeech = rms > threshold

        let zeroCrossings = zip(chunk, chunk.dropFirst()).reduce(into: 0) { count, pair in
            let crossed = (pair.0 >= 0 && pair.1 < 0) || (pair.0 < 0 && pair.1 >= 0)
            if crossed { count += 1 }
        }
        let zcr = Float(zeroCrossings) / Float(max(chunk.count - 1, 1))
        let zcrSpeech = zcr > 0.01 && zcr < 0.25

        let isSpeechNow = energySpeech && zcrSpeech
        if isSpeechNow {
            speechCounter = hangoverFrames
        } else {
            speechCounter = max(0, speechCounter - 1)
        }
        return speechCounter > 0
    }
}

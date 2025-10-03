import AppKit
import MetalKit
import simd

private let maxBuffersInFlight = 3

struct SiriEdgeUniforms {
    var timeAudio = SIMD4<Float>(0, 0, 0, 0)             // time, audioLevel, rippleTime, rippleIntensity
    var resolutionCornerQuality = SIMD4<Float>(0, 0, 12, 2) // width, height, cornerRadius, quality level
    var flowWarp = SIMD4<Float>(0, 0, 0, 0)               // flow noise offset xy, warp offset zw
    var animationParams = SIMD4<Float>(0, 0, 2.0, 0)      // animationState, rippleBase, exposure, frameTimeEMA
}

final class SiriEdgeMetalView: MTKView {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private var uniformBuffers: [MTLBuffer] = []
    private var uniformBufferIndex: Int = 0

    private var uniforms = SiriEdgeUniforms()

    private let audioProcessor = AudioProcessor()

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var lastAnimationTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var rippleStartTime: CFTimeInterval = 0
    private var rippleBaseIntensity: Float = 1
    private var currentRippleIntensity: Float = 0

    private var animationStartTime: CFTimeInterval = CACurrentMediaTime()
    private var startAnimationState: Float = 0
    private var targetAnimationState: Float = 0
    private var currentAnimationState: Float = 0
    private let animationDuration: CFTimeInterval = 0.9

    private var flowOffset = SIMD2<Float>(Float.random(in: 0...100), Float.random(in: 0...100))
    private var warpOffset = SIMD2<Float>(Float.random(in: 0...100), Float.random(in: 0...100))

    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var frameTimeEMA: Double = 1.0 / 120.0
    private var qualityLevel: Int = 2 { didSet { updatePreferredFPS() } }
    private var qualityCooldownFrames: Int = 0

    private var cornerRadius: CGFloat = 16 {
        didSet { uniforms.resolutionCornerQuality.z = Float(cornerRadius) }
    }

    private var targetFrameDuration: Double {
        switch qualityLevel {
        case 2: return 1.0 / 120.0
        case 1: return 1.0 / 90.0
        default: return 1.0 / 60.0
        }
    }

    private(set) var isActive = false

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()!
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue")
        }
        commandQueue = queue

        let library: MTLLibrary
        if let bundleLibrary = try? metalDevice.makeDefaultLibrary(bundle: .main) {
            library = bundleLibrary
        } else if let defaultLibrary = metalDevice.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            fatalError("Unable to locate Metal shader library")
        }
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Missing shader functions")
        }

        let vertexData: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        guard let vBuffer = metalDevice.makeBuffer(bytes: vertexData,
                                                   length: vertexData.count * MemoryLayout<Float>.size,
                                                   options: [.storageModeShared]) else {
            fatalError("Failed to create vertex buffer")
        }
        vertexBuffer = vBuffer

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Unable to create pipeline state: \(error)")
        }

        super.init(frame: frameRect, device: metalDevice)

        framebufferOnly = false
        colorPixelFormat = .rgba16Float
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        preferredFramesPerSecond = 120
        isPaused = false
        enableSetNeedsDisplay = false
        autoResizeDrawable = true

        delegate = self

        if let screen = NSScreen.main {
            cornerRadius = CGFloat(SiriEdgeMetalView.cornerRadius(for: screen))
        }
        uniforms.resolutionCornerQuality = SIMD4<Float>(Float(drawableSize.width), Float(drawableSize.height), Float(cornerRadius), Float(qualityLevel))

        uniformBuffers = (0..<maxBuffersInFlight).compactMap { _ in
            device?.makeBuffer(length: MemoryLayout<SiriEdgeUniforms>.stride, options: [.storageModeShared])
        }
        if uniformBuffers.count != maxBuffersInFlight {
            fatalError("Failed to allocate uniform buffers")
        }

        uniforms.animationParams.w = Float(frameTimeEMA)

        audioProcessor.onAudioLevelUpdate = { [weak self] level in
            guard let self else { return }
            self.uniforms.timeAudio.y = min(max(level, 0), 1)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        startAnimationState = currentAnimationState
        targetAnimationState = 1
        animationStartTime = CACurrentMediaTime()
        triggerRipple(intensity: 1)
        audioProcessor.start()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        startAnimationState = currentAnimationState
        targetAnimationState = 0
        animationStartTime = CACurrentMediaTime()
        rippleStartTime = 0
        rippleBaseIntensity = 0
        currentRippleIntensity = 0
        uniforms.timeAudio.z = 0
        uniforms.timeAudio.w = 0
        audioProcessor.stop()
    }

    func triggerRipple(intensity: Float = 1.0) {
        rippleBaseIntensity = max(0, min(intensity, 1))
        rippleStartTime = CACurrentMediaTime()
        uniforms.timeAudio.z = 0
        currentRippleIntensity = rippleBaseIntensity
        uniforms.timeAudio.w = currentRippleIntensity
    }

    func updateCornerRadius(_ radius: CGFloat) {
        cornerRadius = radius
    }

    private func updatePreferredFPS() {
        switch qualityLevel {
        case 2: preferredFramesPerSecond = 120
        case 1: preferredFramesPerSecond = 90
        default: preferredFramesPerSecond = 60
        }
    }

    private func updateAnimations(currentTime: CFTimeInterval) {
        let elapsed = currentTime - animationStartTime
        if elapsed < animationDuration {
            let progress = Float(max(0, min(1, elapsed / animationDuration)))
            let eased = easeInOutCubic(progress)
            currentAnimationState = startAnimationState + (targetAnimationState - startAnimationState) * eased
        } else {
            currentAnimationState = targetAnimationState
        }

        if rippleStartTime > 0 {
            let rippleElapsed = Float(currentTime - rippleStartTime)
            uniforms.timeAudio.z = rippleElapsed
            if rippleElapsed < 3.0 {
                let fade = max(0, 1.0 - rippleElapsed / 3.0)
                currentRippleIntensity = rippleBaseIntensity * easeOutQuad(fade)
            } else {
                rippleStartTime = 0
                currentRippleIntensity = 0
            }
        }

        uniforms.timeAudio.w = currentRippleIntensity
        uniforms.animationParams.x = currentAnimationState
        uniforms.animationParams.y = rippleBaseIntensity
    }

    private func easeInOutCubic(_ t: Float) -> Float {
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func easeOutQuad(_ t: Float) -> Float {
        return 1 - (1 - t) * (1 - t)
    }

    private func updateAdaptiveQuality(frameDelta: Double) {
        frameTimeEMA = frameTimeEMA * 0.9 + frameDelta * 0.1
        if qualityCooldownFrames > 0 { qualityCooldownFrames -= 1 }

        if frameTimeEMA > targetFrameDuration * 1.18 && qualityLevel > 0 && qualityCooldownFrames <= 0 {
            qualityLevel -= 1
            qualityCooldownFrames = 240
        } else if frameTimeEMA < targetFrameDuration * 0.7 && qualityLevel < 2 && qualityCooldownFrames <= 0 {
            qualityLevel += 1
            qualityCooldownFrames = 480
        }
        uniforms.resolutionCornerQuality.w = Float(qualityLevel)
        uniforms.animationParams.w = Float(frameTimeEMA)
    }

    private func updateFlowOffsets(delta: Float) {
        let qualityScalar = Float(qualityLevel + 1)
        flowOffset += SIMD2<Float>(delta * 0.12 * qualityScalar, delta * 0.09 * qualityScalar)
        warpOffset += SIMD2<Float>(delta * 0.45, delta * 0.37)
        uniforms.flowWarp = SIMD4<Float>(flowOffset.x, flowOffset.y, warpOffset.x, warpOffset.y)
    }

    private func updateExposure() {
        let baseExposure: Float = 1.6
        let qualityBonus: Float = Float(qualityLevel) * 0.35
        let audioBoost: Float = uniforms.timeAudio.y * 1.2
        uniforms.animationParams.z = baseExposure + qualityBonus + audioBoost
    }

    deinit {
        audioProcessor.stop()
    }
}

extension SiriEdgeMetalView {
    static func cornerRadius(for screen: NSScreen) -> Float {
        if let value = screen.value(forKey: "_displayCornerRadius") as? CGFloat, value > 0 {
            return Float(value)
        }
        if #available(macOS 13.0, *) {
            if screen.safeAreaInsets.top > 0 {
                return 12
            }
        }
        return 16
    }
}

extension SiriEdgeMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.resolutionCornerQuality.x = Float(size.width)
        uniforms.resolutionCornerQuality.y = Float(size.height)
    }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let currentTime = CACurrentMediaTime()
        let frameDelta = currentTime - lastFrameTimestamp
        lastFrameTimestamp = currentTime
        updateAdaptiveQuality(frameDelta: frameDelta)

        let animationDelta = Float(currentTime - lastAnimationTimestamp)
        lastAnimationTimestamp = currentTime
        updateAnimations(currentTime: currentTime)
        updateFlowOffsets(delta: animationDelta)
        updateExposure()

        uniforms.timeAudio.x = Float(currentTime - startTime)
        uniforms.resolutionCornerQuality.z = Float(cornerRadius)

        uniformBufferIndex = (uniformBufferIndex + 1) % uniformBuffers.count
        let uniformBuffer = uniformBuffers[uniformBufferIndex]
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<SiriEdgeUniforms>.stride)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

import AppKit
import MetalKit

struct SiriEdgeUniforms {
    var time: Float = 0
    var resolution: SIMD2<Float> = .zero
    var audioLevel: Float = 0
    var rippleTime: Float = 0
    var rippleIntensity: Float = 0
    var animationState: Float = 0
    var cornerRadius: Float = 16
}

final class SiriEdgeMetalView: MTKView {
    private(set) var metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let vertexDescriptor: MTLVertexDescriptor

    private var uniforms = SiriEdgeUniforms()
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var rippleStartTime: CFTimeInterval = 0
    private var rippleBaseIntensity: Float = 0

    private var animationStartTime: CFTimeInterval = CACurrentMediaTime()
    private var startAnimationState: Float = 0
    private var targetAnimationState: Float = 0
    private var currentAnimationState: Float = 0
    private let animationDuration: CFTimeInterval = 0.9

    private var backgroundTexture: MTLTexture
    private let audioProcessor = AudioProcessor()

    private(set) var isActive = false

    init(frame frameRect: CGRect, device: MTLDevice?) {
        let resolvedDevice = device ?? MTLCreateSystemDefaultDevice()!
        self.metalDevice = resolvedDevice

        guard let queue = resolvedDevice.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue")
        }
        commandQueue = queue

        guard let library = resolvedDevice.makeDefaultLibrary() else {
            fatalError("Unable to load default Metal library")
        }
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Unable to load shader functions")
        }

        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor = descriptor

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexDescriptor = descriptor

        do {
            pipelineState = try resolvedDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }

        let vertices: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        guard let buffer = resolvedDevice.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: []) else {
            fatalError("Failed to create vertex buffer")
        }
        vertexBuffer = buffer

        backgroundTexture = SiriEdgeMetalView.makeFallbackTexture(device: resolvedDevice)

        super.init(frame: frameRect, device: resolvedDevice)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        preferredFramesPerSecond = 120
        isPaused = false
        enableSetNeedsDisplay = false
        autoResizeDrawable = true

        delegate = self
        uniforms.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        uniforms.cornerRadius = SiriEdgeMetalView.estimatedCornerRadius()

        audioProcessor.onAudioLevelUpdate = { [weak self] level in
            guard let self else { return }
            self.uniforms.audioLevel = min(max(level, 0), 1)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func loadBackgroundImage(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let loader = MTKTextureLoader(device: metalDevice)
        do {
            backgroundTexture = try loader.newTexture(cgImage: cgImage, options: nil)
        } catch {
            NSLog("[SiriEdgeMetalView] Failed to load background texture: \(error)")
        }
    }

    func activate() {
        if isActive { return }
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
        uniforms.rippleIntensity = 0
        uniforms.audioLevel = 0
        audioProcessor.stop()
    }

    func triggerRipple(intensity: Float = 1.0) {
        rippleStartTime = CACurrentMediaTime()
        uniforms.rippleTime = 0
        rippleBaseIntensity = max(0, min(intensity, 1))
        uniforms.rippleIntensity = rippleBaseIntensity
    }

    func updateCornerRadius(_ radius: CGFloat) {
        uniforms.cornerRadius = Float(radius)
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
        uniforms.animationState = currentAnimationState

        if rippleStartTime > 0 {
            let rippleElapsed = Float(currentTime - rippleStartTime)
            uniforms.rippleTime = rippleElapsed
            if rippleElapsed < 3.0 {
                let fade = max(0, 1.0 - rippleElapsed / 3.0)
                uniforms.rippleIntensity = rippleBaseIntensity * easeOutQuad(fade)
            } else {
                uniforms.rippleIntensity = 0
                rippleStartTime = 0
                rippleBaseIntensity = 0
            }
        }
    }

    private func easeInOutCubic(_ t: Float) -> Float {
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func easeOutQuad(_ t: Float) -> Float {
        return 1 - (1 - t) * (1 - t)
    }

    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixel: UInt32 = 0x000000FF
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: MemoryLayout<UInt32>.size)
        return texture
    }

    private static func estimatedCornerRadius() -> Float {
        if let screen = NSScreen.main {
            return cornerRadius(for: screen)
        }
        return 16
    }

    static func cornerRadius(for screen: NSScreen) -> Float {
        if let radius = screen.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 {
            return Float(radius)
        }
        if #available(macOS 13.0, *) {
            if screen.safeAreaInsets.top > 0 {
                return 12
            }
        }
        return 16
    }

    deinit {
        audioProcessor.stop()
    }
}

extension SiriEdgeMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let currentTime = CACurrentMediaTime()
        uniforms.time = Float(currentTime - startTime)
        updateAnimations(currentTime: currentTime)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var uniformsCopy = uniforms
        encoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<SiriEdgeUniforms>.stride, index: 0)
        encoder.setFragmentTexture(backgroundTexture, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

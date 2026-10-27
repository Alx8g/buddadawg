import AppKit
import MetalKit

/// Grain Horizon: a grainy glow rising from the bottom screen edge whose height follows your voice.
/// A full-width, click-through panel with a Metal shader; it only renders while visible.
/// The app only talks to `show(_:)` and `level`, so the look can change without touching anything else.
final class Overlay: NSObject, MTKViewDelegate {
    enum State { case hidden, listening, transcribing, pasted, cancelled }

    var level: () -> Float = { 0 }
    static let height: CGFloat = 240  // the glow fades to zero well before the top, so no edge is ever visible

    private let panel: NSPanel
    private let view: MTKView
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    // Animation state, mirroring the concept page: weights blend between states, `show` fades the whole glow.
    private var state = State.hidden
    private var sinceState: Float = 10  // seconds since the last visible state began (drives transitions)
    private var show: Float = 0
    private var weights = SIMD4<Float>(1, 0, 0, 0)  // listening, transcribing, pasted, cancelled
    private var smoothed: Float = 0
    private var swell: Float = 0  // slower level for the peaks: they rise and sink instead of flickering
    private var clock: Float = 0
    private var lastFrame = CACurrentMediaTime()

    private struct Uniforms { var res: SIMD2<Float>; var dpr, t, lvl, show, ph, swell: Float; var s: SIMD4<Float> }

    override init() {
        let screen = NSScreen.main!.frame
        let frame = NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: Self.height)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let device = MTLCreateSystemDefaultDevice()!
        view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 120
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        queue = device.makeCommandQueue()!
        let library = try! device.makeLibrary(source: Self.shader, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vmain")
        desc.fragmentFunction = library.makeFunction(name: "fmain")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        super.init()
        view.delegate = self
        panel.contentView = view
    }

    func show(_ next: State) {
        if next != .hidden {
            if show < 0.05 { weights = SIMD4(repeating: 0); weights[Self.index(next)] = 1 }
            sinceState = 0
        }
        state = next
        if next != .hidden && view.isPaused {
            lastFrame = CACurrentMediaTime()
            panel.orderFrontRegardless()
            view.isPaused = false
        }
    }

    private static func index(_ s: State) -> Int { [.listening: 0, .transcribing: 1, .pasted: 2, .cancelled: 3][s] ?? 0 }
    private static func ease(_ x: Float) -> Float { let x = min(max(x, 0), 1); return x * x * (3 - 2 * x) }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, now - lastFrame))
        lastFrame = now
        clock += dt
        sinceState += dt

        // Brief states end on their own: pasted glows up and fades, cancelled sinks.
        if state == .pasted && sinceState > 0.62 { state = .hidden }
        if state == .cancelled && sinceState > 0.2 { state = .hidden }

        let target = state == .listening ? level() : 0
        smoothed += (target - smoothed) * (1 - exp(-(target > smoothed ? 20 : 6) * dt))  // quick rise, gentle fall
        swell += (smoothed - swell) * (1 - exp(-(smoothed > swell ? 7 : 3.5) * dt))     // ~0.15 s rise, ~0.3 s fall
        let visible: Float = state == .hidden ? 0 : 1
        let rate: Float = visible > 0 ? 18 : (weights[2] > 0.5 ? 9 : 14)
        show += (visible - show) * (1 - exp(-rate * dt))
        if state != .hidden {
            let k = 1 - exp(-26 * dt)
            for i in 0..<4 { weights[i] += ((i == Self.index(state) ? 1 : 0) - weights[i]) * k }
        }

        if state == .hidden && show < 0.002 {  // fully faded: stop rendering and take the panel down
            view.isPaused = true
            panel.orderOut(nil)
            return
        }

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scale = Float(panel.backingScaleFactor)
        var u = Uniforms(res: SIMD2(Float(view.bounds.width), Float(view.bounds.height)), dpr: scale, t: clock,
                         lvl: smoothed, show: show, ph: sinceState, swell: swell, s: weights)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // Port of the concept page's Grain Horizon shader (units are points, y measured up from the screen edge).
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct U { float2 res; float dpr, t, lvl, show, ph, swell; float4 s; };
    struct VO { float4 pos [[position]]; };

    vertex VO vmain(uint id [[vertex_id]]) {
        float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        VO o; o.pos = float4(p[id], 0, 1); return o;
    }
    float h21(float2 p) { float3 p3 = fract(float3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
    float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3 - 2 * x); }
    float vnoise(float x) { float i = floor(x), f = fract(x); f = f * f * (3 - 2 * f); return mix(h21(float2(i, 7.3)), h21(float2(i + 1, 7.3)), f); }

    // Four separate light shafts laid out like the wallpaper's bands (one strong, two medium, one faint), each swaying
    // at its own unrelated speed so they never line up into a repeating pattern. `a` runs along the 20 degree light angle.
    float shafts(float a, float t, float lv) {
        const float4 centre = float4(-520, -150, 230, 560), width = float4(110, 150, 120, 90), power = float4(.30, .85, .42, .20);
        const float4 speed = float4(.13, .071, .097, .053), sway = float4(70, 110, 90, 60), phase = float4(0, 2.1, 4.3, 1.2);
        float s = 0;
        for (int i = 0; i < 4; i++) {
            float c = centre[i] + sway[i] * sin(t * speed[i] * (1 + 1.5 * lv) + phase[i]);
            float d = (a - c) / (width[i] * (1 + .25 * lv));
            s += power[i] * exp(-d * d);
        }
        return s * (.75 + .5 * vnoise(a / 140 + t * .15));  // soft irregularity so shaft edges aren't perfectly smooth
    }

    // Seven peaks across the middle, each wandering a little and bouncing at its own rhythm. Louder speech makes them
    // bounce faster and taller; the outer ones are damped so the action stays in the centre.
    float bumps(float x, float t, float lv) {
        float b = 0;
        for (int i = 0; i < 7; i++) {
            float fi = float(i);
            float c = (fi - 3) * 105 + 35 * sin(t * (.31 + .07 * fi) + fi * 1.7);
            float w = 30 + 26 * h21(float2(fi, 3.1));
            float bounce = .5 + .5 * sin(t * (.55 + .23 * fi) * (.7 + .8 * lv) + fi * 2.3);  // slow swells, a few seconds each
            float d = (x - c) / w;
            b += bounce * bounce * exp(-d * d);
        }
        return b;
    }

    fragment float4 fmain(VO in [[stage_in]], constant U& u [[buffer(0)]]) {
        float2 fc = float2(in.pos.x, u.res.y * u.dpr - in.pos.y);  // pixels, origin bottom-left
        float2 R = u.res;
        float2 p = fc / u.dpr - R * .5;
        float y = p.y + R.y * .5, xn = p.x / (R.x * .5), lv = u.lvl, ph = u.ph;
        float a = p.x * .94 - y * .34;  // the wallpaper's 20 degree light angle
        float s = .45 + 1.1 * shafts(a, u.t, lv);
        float wid = exp(-xn * xn * 2.2);
        // Listening: a base glow plus peaks with a soft top edge. The edge sits at each peak's height, so as a peak grows
        // the light visibly climbs up from the screen edge instead of the whole glow brightening.
        float top = 4 + 200 * u.swell * bumps(p.x, u.t, u.swell) * exp(-xn * xn * 4);
        float q = y / max(top, 1.0);
        float spire = exp(-q * q * 1.6) * (.6 + .4 * exp(-q));  // soft, blurred top rather than a hard edge
        float lG = wid * s * (exp(-y / (14 + 55 * lv)) + .85 * spire) * (.35 + .65 * lv);
        float wG = exp(-xn * xn / (.04 + .45 * (1 - ease(ph / .22)))) * exp(-y / 20) * .95; // transcribing: pinches to the centre
        float dG = wid * exp(-y / (5 + 40 * ease(ph / .3))) * (1 - ease(ph / .6)) * 1.15;  // pasted: a flash line rises and fades
        float cG = lG * (1 - ease(ph / .18));                                              // cancelled: sinks away
        float G = (u.s.x * lG + u.s.y * wG + u.s.z * dG + u.s.w * cG) * ease(u.show);
        G *= .6 + .8 * h21(fc + floor(u.t * 24) * float2(37.1, 17.7));                      // film grain
        G *= 1 - smoothstep(R.y * .4, R.y * .92, y);                                        // fade to zero before the panel top
        G = clamp(G, 0.0, 1.0);
        return float4(G, G, G, G * .85);
    }
    """
}

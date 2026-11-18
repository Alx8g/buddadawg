/// Animation clocks for the overlay shader, with voice-warped phases.
///
/// The shafts and peaks speed up with voice level. Feeding the shader
/// `sin(elapsed * speed * (1 + k*level))` makes the phase jump per frame grow
/// with `elapsed`, so the glow degenerates into teleporting noise after enough
/// cumulative animation time. Integrating the warp here instead bounds each
/// frame's phase change to `rate * dt` forever.
public struct PhaseClock {
    public private(set) var time: Float = 0       // plain elapsed (wander, noise, grain)
    public private(set) var shaftTime: Float = 0  // advanced by (1 + 1.5 * level)
    public private(set) var bumpTime: Float = 0   // advanced by (0.7 + 0.8 * swell)

    public init() {}

    public mutating func advance(dt rawDt: Float, level: Float, swell: Float) {
        let dt = min(max(rawDt, 0), 0.05)
        time += dt
        shaftTime += dt * (1 + 1.5 * level)
        bumpTime += dt * (0.7 + 0.8 * swell)
    }

    /// Call while fully faded out: re-basing the phases is invisible then, and keeps
    /// the float arguments to `sin` in their precise range forever.
    public mutating func wrapIfNeeded() {
        guard time > 7200 else { return }
        time = time.truncatingRemainder(dividingBy: 600)
        shaftTime = shaftTime.truncatingRemainder(dividingBy: 600)
        bumpTime = bumpTime.truncatingRemainder(dividingBy: 600)
    }
}

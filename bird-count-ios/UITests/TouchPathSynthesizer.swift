import XCTest

/// Replays an arbitrary multi-point single-finger touch path with timing, via
/// XCTest's private XCPointerEventPath / XCSynthesizedEventRecord. The public
/// XCUICoordinate API only does straight-line drags; real fingers curl and
/// drift. Diagnostics only — private API, may break across Xcode versions.
enum TouchPathSynthesizer {
    struct Step { let dx: CGFloat; let dy: CGFloat; let t: TimeInterval }

    private typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
    private typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
    private typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
    private typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
    private typealias AddPath = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias Synthesize = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool

    private static func imp<T>(_ obj: AnyObject, _ name: String, as: T.Type) -> (T, Selector) {
        let sel = NSSelectorFromString(name)
        let m = (obj as! NSObject).method(for: sel)
        return (unsafeBitCast(m, to: T.self), sel)
    }

    /// `origin` in screen points; `steps` offsets relative to origin, `t` seconds from touch-down.
    static func perform(origin: CGPoint, steps: [Step], liftAfter: TimeInterval = 0) throws {
        guard let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type
        else { throw XCTSkip("XCTest private event synthesis unavailable") }

        let rawPath = pathClass.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let (initPath, initSel) = imp(rawPath, "initForTouchAtPoint:offset:", as: InitPath.self)
        let path = initPath(rawPath, initSel, origin, 0)
        let (move, moveSel) = imp(path, "moveToPoint:atOffset:", as: Move.self)
        var last: TimeInterval = 0
        for s in steps {
            move(path, moveSel, CGPoint(x: origin.x + s.dx, y: origin.y + s.dy), s.t)
            last = s.t
        }
        let (lift, liftSel) = imp(path, "liftUpAtOffset:", as: Lift.self)
        lift(path, liftSel, last + liftAfter)

        let rawRecord = recordClass.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let (initRecord, initRecSel) = imp(rawRecord, "initWithName:interfaceOrientation:", as: InitRecord.self)
        let record = initRecord(rawRecord, initRecSel, "path" as NSString, 1)
        let (add, addSel) = imp(record, "addPointerEventPath:", as: AddPath.self)
        add(record, addSel, path)
        let (synth, synthSel) = imp(record, "synthesizeWithError:", as: Synthesize.self)
        var error: NSError?
        if !synth(record, synthSel, &error) { throw error ?? NSError(domain: "TouchPathSynthesizer", code: 1) }
    }

    /// Linear interpolation helper: segments between waypoints at ~60Hz.
    static func interpolate(_ waypoints: [Step], hz: Double = 120) -> [Step] {
        guard var prev = waypoints.first else { return [] }
        var out: [Step] = [prev]
        for w in waypoints.dropFirst() {
            let n = max(1, Int(((w.t - prev.t) * hz).rounded()))
            for i in 1...n {
                let f = CGFloat(i) / CGFloat(n)
                out.append(Step(dx: prev.dx + (w.dx - prev.dx) * f,
                                dy: prev.dy + (w.dy - prev.dy) * f,
                                t: prev.t + (w.t - prev.t) * Double(f)))
            }
            prev = w
        }
        return out
    }
}

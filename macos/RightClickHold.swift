import AppKit

// One timer per press, with a token so a cancelled callback cannot affect a newer press.
final class RightClickHold {
  typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
  private let short: () -> Void
  private let long: () -> Void
  private let isHeld: () -> Bool
  private let schedule: Schedule
  private var cancelTimer: (() -> Void)?
  private var token: UInt64 = 0
  private var active = false
  private var fired = false

  init(
    short: @escaping () -> Void, long: @escaping () -> Void,
    isHeld: @escaping () -> Bool,
    schedule: @escaping Schedule = RightClickHold.scheduleTimer
  ) {
    self.short = short
    self.long = long
    self.isHeld = isHeld
    self.schedule = schedule
  }
  static func scheduleTimer(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
    let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }
  func begin() {
    guard !active else { return }
    active = true
    fired = false
    token &+= 1
    let current = token
    cancelTimer = schedule(0.5) { [weak self] in
      guard let self, self.active, self.token == current, !self.fired else { return }
      guard self.isHeld() else { self.cancel(); return }
      self.fired = true
      self.cancelTimer?()
      self.cancelTimer = nil
      self.long()
    }
  }
  func end() {
    guard active else { return }
    let performShort = !fired
    cancel()
    if performShort { short() }
  }
  func cancel() {
    token &+= 1
    active = false
    fired = false
    cancelTimer?()
    cancelTimer = nil
  }
  deinit { cancelTimer?() }
}

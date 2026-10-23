import AppKit

// Consume raw status-window right events before NSStatusBarButton starts control tracking.
// This is an app-local, event-driven hook; other windows and other applications are untouched.
final class StatusRightEventRouter {
  private weak var view: StatusFileDropView?
  private weak var trackingWindow: NSWindow?
  private var monitor: Any?
  private let pressedButtons: () -> Int
  private let pointerInside: () -> Bool
  private let schedule: RightClickHold.Schedule
  private var releaseCancel: (() -> Void)?
  private var releaseRevision: UInt64 = 0
  private var releaseChecksLeft = 0
  private var releaseDeadline: TimeInterval = 0

  init(
    view: StatusFileDropView, install: Bool = true,
    pressedButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons },
    pointerInside: (() -> Bool)? = nil,
    schedule: @escaping RightClickHold.Schedule = RightClickHold.scheduleTimer
  ) {
    self.view = view
    self.pressedButtons = pressedButtons
    self.pointerInside = pointerInside ?? { [weak view] in
      guard let view, let window = view.window else { return false }
      return view.bounds.contains(view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    self.schedule = schedule
    view.rightPress.onHoldRejected = { [weak self] in
      guard let self else { return }
      if self.pressedButtons() & 2 == 0 && self.pointerInside() {
        self.finishRelease()
      } else {
        self.cancel()
      }
    }
    if install {
      monitor = NSEvent.addLocalMonitorForEvents(
        matching: [.rightMouseDown, .rightMouseUp, .rightMouseDragged]
      ) { [weak self] event in
        guard let self else { return event }
        return self.handle(event)
      }
    }
  }
  var isTracking: Bool { trackingWindow != nil }

  func handle(_ event: NSEvent) -> NSEvent? {
    guard let view, let window = view.window else {
      cancel()
      return event
    }
    guard event.window === window else { return event }
    switch event.type {
    case .rightMouseDown:
      guard view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
      trackingWindow = window
      view.rightMouseDown(with: event)
      return nil
    case .rightMouseDragged:
      guard trackingWindow === window else { return event }
      if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
        cancel()
      } else {
        view.rightMouseDragged(with: event)
      }
      return nil
    case .rightMouseUp:
      guard trackingWindow === window else { return event }
      // Trackpads/status-window forwarding can synthesize an up while the physical button is down.
      if pressedButtons() & 2 != 0 {
        if releaseCancel == nil {
          releaseChecksLeft = 300
          releaseDeadline = ProcessInfo.processInfo.systemUptime + 10
          watchRelease(revision: releaseRevision)
        }
        return nil
      }
      clearReleaseWatch()
      trackingWindow = nil
      view.rightMouseUp(with: event)
      return nil
    default:
      return event
    }
  }
  private func watchRelease(revision: UInt64) {
    releaseCancel = schedule(1.0 / 30.0) { [weak self] in
      guard let self, self.releaseRevision == revision, self.trackingWindow != nil else { return }
      self.releaseCancel = nil
      guard ProcessInfo.processInfo.systemUptime < self.releaseDeadline,
        self.pointerInside(), self.view?.window === self.trackingWindow else {
        self.cancel()
        return
      }
      if self.pressedButtons() & 2 == 0 {
        self.finishRelease()
        return
      }
      self.releaseChecksLeft -= 1
      guard self.releaseChecksLeft > 0 else { self.cancel(); return }
      self.watchRelease(revision: revision)
    }
  }
  private func finishRelease() {
    clearReleaseWatch()
    trackingWindow = nil
    view?.rightPress.end()
  }
  private func clearReleaseWatch() {
    releaseRevision &+= 1
    releaseCancel?()
    releaseCancel = nil
  }
  func cancel() {
    clearReleaseWatch()
    trackingWindow = nil
    view?.rightPress.cancel()
  }
  func stop() {
    cancel()
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
  deinit { stop() }
}

import AppKit

// Consume raw status-window right events before NSStatusBarButton starts control tracking.
// This is an app-local, event-driven hook; other windows and other applications are untouched.
final class StatusRightEventRouter {
  private weak var view: StatusFileDropView?
  private weak var trackingWindow: NSWindow?
  private var monitor: Any?

  init(view: StatusFileDropView, install: Bool = true) {
    self.view = view
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
      view.rightMouseDragged(with: event)
      return nil
    case .rightMouseUp:
      guard trackingWindow === window else { return event }
      trackingWindow = nil
      view.rightMouseUp(with: event)
      return nil
    default:
      return event
    }
  }
  func cancel() {
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

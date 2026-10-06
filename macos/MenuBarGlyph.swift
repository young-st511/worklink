import AppKit

enum MenuBarGlyph {
  enum Mode: CaseIterable { case off, on, paused, problem }
  private static let images = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, make($0)) })
  static func image(for mode: Mode) -> NSImage { images[mode]! }
  private static func make(_ mode: Mode) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSGraphicsContext.saveGraphicsState()
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let transform = NSAffineTransform()
      transform.translateX(by: 9, yBy: 9)
      transform.rotate(byDegrees: 45)
      transform.translateX(by: -9, yBy: -9)
      transform.concat()
      if mode == .off {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: 7, y: 11.6))
        left.line(to: NSPoint(x: 4.35, y: 11.6))
        left.appendArc(
          withCenter: NSPoint(x: 4.35, y: 9), radius: 2.6, startAngle: 90, endAngle: 270)
        left.line(to: NSPoint(x: 7, y: 6.4))
        let right = NSBezierPath()
        right.move(to: NSPoint(x: 11, y: 6.4))
        right.line(to: NSPoint(x: 13.65, y: 6.4))
        right.appendArc(
          withCenter: NSPoint(x: 13.65, y: 9), radius: 2.6, startAngle: 270, endAngle: 450)
        right.line(to: NSPoint(x: 11, y: 11.6))
        for path in [left, right] {
          path.lineWidth = 1.65
          path.lineCapStyle = .round
          path.lineJoinStyle = .round
          path.stroke()
        }
      } else {
        for rect in [
          NSRect(x: 1.75, y: 6.4, width: 8.55, height: 5.2),
          NSRect(x: 7.7, y: 6.4, width: 8.55, height: 5.2),
        ] {
          let path = NSBezierPath(roundedRect: rect, xRadius: 2.6, yRadius: 2.6)
          path.lineWidth = 1.65
          path.stroke()
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      NSGraphicsContext.saveGraphicsState()
      NSColor.black.setStroke()
      NSColor.black.setFill()
      if mode == .paused {
        let bars = NSBezierPath()
        bars.lineWidth = 1.3
        bars.lineCapStyle = .round
        for x: CGFloat in [13.8, 16.2] {
          bars.move(to: NSPoint(x: x, y: 2))
          bars.line(to: NSPoint(x: x, y: 5))
        }
        bars.stroke()
      } else if mode == .problem {
        let mark = NSBezierPath()
        mark.lineWidth = 1.5
        mark.lineCapStyle = .round
        mark.move(to: NSPoint(x: 15, y: 3.4))
        mark.line(to: NSPoint(x: 15, y: 6))
        mark.stroke()
        NSBezierPath(ovalIn: NSRect(x: 14.3, y: 1, width: 1.4, height: 1.4)).fill()
      }
      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    image.isTemplate = true
    return image
  }
}

import AppKit

enum MenuBarGlyph {
  enum Mode: CaseIterable { case off, on, paused, problem }
  private static let images = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, make($0)) })
  private static let preservedImages = Dictionary(
    uniqueKeysWithValues: Mode.allCases.map { ($0, make($0, preservesImage: true)) })
  static func image(for mode: Mode, preservesImage: Bool = false) -> NSImage {
    (preservesImage ? preservedImages : images)[mode]!
  }
  private static func make(_ mode: Mode, preservesImage: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) {
      _ in
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
      NSGraphicsContext.saveGraphicsState()
      if preservesImage {
        let statusOffset = NSAffineTransform()
        statusOffset.translateX(by: -12.5, yBy: 11)
        statusOffset.concat()
      }
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
      if preservesImage {
        let frame = NSBezierPath(
          roundedRect: NSRect(x: 11, y: 0.75, width: 6.5, height: 5.5), xRadius: 0.7, yRadius: 0.7
        )
        frame.lineWidth = 0.85
        frame.stroke()
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: 12.2, y: 1.9))
        mountain.line(to: NSPoint(x: 14.2, y: 4.1))
        mountain.line(to: NSPoint(x: 16.3, y: 1.9))
        mountain.lineWidth = 0.85
        mountain.lineCapStyle = .round
        mountain.lineJoinStyle = .round
        mountain.stroke()
      }
      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    image.isTemplate = true
    return image
  }
}

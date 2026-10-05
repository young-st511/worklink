import AppKit

struct ClipboardImage {
  let bytes: Data
  let ext: String
  let count: Int
}
enum ClipboardFailure: Error { case denied, tooLarge, changed, unreadable }
enum ClipboardReader {
  static let types: [(NSPasteboard.PasteboardType, String)] = [
    (.png, "png"), (NSPasteboard.PasteboardType("public.jpeg"), "jpg"), (.tiff, "tiff"),
    (NSPasteboard.PasteboardType("public.heic"), "heic"),
    (NSPasteboard.PasteboardType("public.heif"), "heif"),
    (NSPasteboard.PasteboardType("org.webmproject.webp"), "webp"),
  ]
  static func read(_ board: NSPasteboard, maximum: Int64) throws -> ClipboardImage? {
    if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny {
      throw ClipboardFailure.denied
    }
    let count = board.changeCount
    guard let offered = board.types,
      let (type, ext) = types.first(where: { offered.contains($0.0) })
    else { return nil }
    guard let bytes = board.data(forType: type), !bytes.isEmpty else {
      throw ClipboardFailure.unreadable
    }
    guard board.changeCount == count else { throw ClipboardFailure.changed }
    guard bytes.count <= maximum else { throw ClipboardFailure.tooLarge }
    return ClipboardImage(bytes: bytes, ext: ext, count: count)
  }
  static func replaceWithPath(
    _ path: String, board: NSPasteboard, expectedCount: Int, allowed: Bool
  ) -> Bool {
    guard allowed, board.changeCount == expectedCount else { return false }
    board.clearContents()
    return board.setString(path, forType: .string)
  }
}

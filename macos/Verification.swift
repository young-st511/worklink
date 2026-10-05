import AppKit

func fixtureState(on: Bool = true) -> CoreState {
  let host = HostConfig(name: "office-test", helper: "~/.local/bin/worklink")
  let ep = EndpointConfig(
    scheme: "http", remoteHost: "127.0.0.1", remotePort: 5173, path: "/preview", rawPath: nil,
    query: nil, fragment: nil, rawFragment: nil)
  let ports = [
    PortConfig(
      id: String(repeating: "a", count: 32), name: "프론트엔드", host: host.name, endpoint: ep,
      localPort: 5173, enabled: true, title: "미리보기"),
    PortConfig(
      id: String(repeating: "b", count: 32), name: "관리자 미리보기", host: host.name,
      endpoint: EndpointConfig(
        scheme: "http", remoteHost: "127.0.0.1", remotePort: 4387, path: "/", rawPath: nil,
        query: nil, fragment: nil, rawFragment: nil), localPort: 14387, enabled: true, title: nil),
  ]
  let limits = LimitsConfig(
    imageBytes: 64 * 1_048_576, queueBytes: 256 * 1_048_576, queueCount: 8,
    inboxBytes: 2 * 1_073_741_824)
  let job = ImageJob(
    id: String(repeating: "c", count: 32), host: host.name, createdAt: "2026-10-06T05:20:00.000Z",
    path: "/tmp/fixture.png", size: 524_288, sha256: "fixture", extension: "png",
    status: "complete", error: nil, remotePath: "/tmp/worklink-capture-fixture.png",
    clipboardCount: 7, generation: 1)
  return CoreState(
    on: on, generation: 1,
    config: Config(revision: 1, hosts: [host], ports: ports, imageHost: host.name, limits: limits),
    hosts: on ? [HostStatus(host: host.name, status: "connected", error: nil)] : [],
    ports: on
      ? [
        PortStatus(id: ports[0].id, status: "ready", error: nil, reachable: true),
        PortStatus(id: ports[1].id, status: "waiting", error: nil, reachable: false),
      ] : [], jobs: on ? [job] : [], version: "0.1.0", error: nil)
}

func renderNative(_ view: NSView, to url: URL) throws {
  view.layoutSubtreeIfNeeded()
  guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  view.cacheDisplay(in: view.bounds, to: rep)
  guard let bytes = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "Worklink QA", code: 2)
  }
  try bytes.write(to: url)
}
func renderPreviews(_ directory: URL) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  for style in [NSAppearance.Name.aqua, .darkAqua] {
    let appearance = NSAppearance(named: style)!
    for name in ["off", "on", "error"] {
      let controller = DashboardController()
      controller.view.appearance = appearance
      var state = fixtureState(on: name != "off")
      if name == "error" {
        state.ports[0] = PortStatus(
          id: state.config.ports[0].id, status: "conflict",
          error: "로컬 포트 5173이 사용 중입니다. 다른 로컬 포트를 설정해 주세요.", reachable: false)
        controller.notice = "전송 완료 · 클립보드가 바뀌어 경로 복사를 생략했습니다."
      }
      if name == "on" { controller.copied.insert(state.jobs[0].id) }
      controller.expanded.insert(state.config.ports[0].id)
      appearance.performAsCurrentDrawingAppearance { controller.render(state) }
      let window = NSWindow(
        contentRect: controller.view.bounds, styleMask: .borderless, backing: .buffered,
        defer: false)
      window.contentView = controller.view
      window.appearance = appearance
      var renderError: Error?
      appearance.performAsCurrentDrawingAppearance {
        do {
          try renderNative(
            controller.view,
            to: directory.appendingPathComponent("\(name)-\(style == .aqua ? "light" : "dark").png")
          )
        } catch { renderError = error }
      }
      if let renderError { throw renderError }
      window.close()
    }
  }
  let bridge = CoreBridge()
  bridge.state = fixtureState()
  let settings = SettingsController(bridge: bridge, loginEnabled: false)
  if let content = settings.window?.contentView {
    try renderNative(content, to: directory.appendingPathComponent("settings.png"))
  }
  print("Rendered actual AppKit dashboard views and settings to \(directory.path)")
}
func nativeSelfTest() throws {
  func require(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(domain: "Worklink QA", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  let board = NSPasteboard(name: NSPasteboard.Name("dev.worklink.qa.\(UUID().uuidString)"))
  defer { board.releaseGlobally() }
  let original = Data([0, 255, 1, 2, 3, 128])
  board.clearContents()
  board.setData(original, forType: .png)
  let image = try ClipboardReader.read(board, maximum: 1024)
  try require(image?.bytes == original && image?.ext == "png", "clipboard bytes changed")
  let old = board.changeCount
  board.clearContents()
  board.setString("new user text", forType: .string)
  try require(
    !ClipboardReader.replaceWithPath(
      "/tmp/image.png", board: board, expectedCount: old, allowed: true),
    "new clipboard overwritten")
  let current = board.changeCount
  try require(
    !ClipboardReader.replaceWithPath(
      "/tmp/image.png", board: board, expectedCount: current, allowed: false),
    "OFF replaced clipboard")
  try require(
    ClipboardReader.replaceWithPath(
      "/tmp/image.png", board: board, expectedCount: current, allowed: true),
    "matching clipboard not updated")
  board.clearContents()
  board.setData(original, forType: .tiff)
  let tiff = try ClipboardReader.read(board, maximum: 1024)
  try require(tiff?.bytes == original && tiff?.ext == "tiff", "TIFF was reencoded")
  do {
    _ = try ClipboardReader.read(board, maximum: 1)
    throw NSError(domain: "Worklink QA", code: 9)
  } catch ClipboardFailure.tooLarge {}
  let ep = EndpointConfig(
    scheme: "https", remoteHost: "::1", remotePort: 8443, path: "/a/b", rawPath: "/a%2Fb",
    query: "q=a%20b", fragment: "view/item", rawFragment: "view%2Fitem")
  try require(
    ep.localURL(18443)?.absoluteString == "https://localhost:18443/a%2Fb?q=a%20b#view%2Fitem",
    "browser URL lost components")
  let encoded = try JSONSerialization.data(withJSONObject: jsonObject(fixtureState()))
  _ = try decoder().decode(CoreState.self, from: encoded)
  var unicode = ep
  unicode.path = "/안녕"
  unicode.rawPath = "/안녕"
  unicode.query = "q=안녕 world&x=%2F"
  try require(
    unicode.localURL(18443)?.absoluteString.contains("q=%EC%95%88%EB%85%95%20world&x=%2F") == true,
    "Unicode query or escaped query lost")
  var suspension = SuspensionTracker()
  suspension.pause("lock")
  suspension.pause("sleep")
  suspension.resume("sleep")
  try require(suspension.active, "wake resumed while locked")
  suspension.resume("lock")
  try require(!suspension.active, "unlock did not release final reason")
  let dashboard = DashboardController()
  dashboard.clipboardCount = { board.changeCount }
  dashboard.copied = ["old"]
  dashboard.copiedCount = board.changeCount
  board.clearContents()
  board.setString("other user text", forType: .string)
  dashboard.render(fixtureState())
  try require(dashboard.copied.isEmpty, "stale clipboard still shown ready")
  let bridge = CoreBridge()
  let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
    "worklink-eof-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporary) }
  try bridge.start(binary: URL(fileURLWithPath: "/usr/bin/true"), dataDirectory: temporary)
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
  try require(bridge.eofEvents <= 8 && !bridge.isRunning, "EOF handler spun after core termination")
  var failedReply = false
  bridge.send(
    "upload", ["path": "/tmp/never-send"], reply: { result in failedReply = result["error"] != nil }
  )
  try require(failedReply, "stopped core did not invoke failure cleanup callback")
  bridge.stop()
  print(
    "Native clipboard/counter/OFF/format/Unicode URL/lock overlap/ready state/EOF tests passed.")
}
func configureNativeTransferQA(_ delegate: AppDelegate) throws {
  guard let path = ProcessInfo.processInfo.environment["WORKLINK_QA_IMAGE_PATH"] else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  let board = NSPasteboard(
    name: NSPasteboard.Name("dev.worklink.qa.integration.\(UUID().uuidString)"))
  delegate.clipboardBoard = board
  var toggled = false
  var captured = false
  delegate.bridge.onState = { [weak delegate] state in
    guard let delegate else { return }
    delegate.update(state)
    if !toggled {
      toggled = true
      delegate.desiredOn = true
      delegate.bridge.send("toggle", ["on": true])
    }
    if state.on && state.hosts.contains(where: { $0.status == "connected" }) && !captured {
      captured = true
      board.clearContents()
      board.setData(data, forType: .png)
    }
  }
  delegate.bridge.onComplete = { [weak delegate] job in
    guard let delegate else { return }
    delegate.complete(job)
    let replaced = board.string(forType: .string) == job.remotePath
    let result: [String: Any] = [
      "native_clipboard": true, "path_replaced": replaced, "sha256": job.sha256,
      "remote_path": job.remotePath ?? "", "byte_count": job.size,
    ]
    if let bytes = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys) {
      FileHandle.standardOutput.write(bytes + Data([10]))
    }
    board.releaseGlobally()
    NSApp.terminate(nil)
  }
  Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
    fputs("Native QA timed out\n", stderr)
    NSApp.terminate(nil)
  }
}

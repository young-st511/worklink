import AppKit
import ImageIO

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
  view.displayIfNeeded()
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
    for name in ["off", "on", "error", "keep", "images"] {
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
      if name == "keep" || name == "images" {
        controller.preservesImage = name == "keep"
        state.config.ports = []
        state.jobs = Array(repeating: state.jobs[0], count: 5)
      }
      if let port = state.config.ports.first { controller.expanded.insert(port.id) }
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
  for style in [NSAppearance.Name.aqua, .darkAqua] {
    for count in [1, 5, 8] {
      let portsPanel = DashboardController()
      var state = fixtureState()
      let base = state.config.ports[0]
      state.config.ports = (0..<count).map { index in
        var port = base
        port.id = String(format: "%032x", index + 1)
        port.name = ["프론트엔드", "API", "관리자", "문서", "스토리북", "미리보기", "테스트", "대시보드"][index]
        port.localPort = 5190 + index
        port.endpoint.remotePort = 5190 + index
        return port
      }
      state.ports = state.config.ports.map {
        PortStatus(id: $0.id, status: "ready", error: nil, reachable: true)
      }
      portsPanel.view.appearance = NSAppearance(named: style)
      portsPanel.render(state)
      let window = NSWindow(
        contentRect: portsPanel.view.bounds, styleMask: .borderless, backing: .buffered,
        defer: false)
      window.contentView = portsPanel.view
      try renderNative(
        portsPanel.view,
        to: directory.appendingPathComponent(
          "ports-\(count)-\(style == .aqua ? "light" : "dark").png"))
      if count == 1 {
        portsPanel.expanded.insert(state.config.ports[0].id)
        portsPanel.render(state)
        try renderNative(
          portsPanel.view,
          to: directory.appendingPathComponent(
            "ports-expanded-\(style == .aqua ? "light" : "dark").png"))
      }
      window.close()
    }
  }
  // Capture the same view through appearance transitions without another state render.
  let live = DashboardController()
  var liveState = fixtureState()
  liveState.config.ports = []
  live.render(liveState)
  let liveWindow = NSWindow(
    contentRect: live.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
  liveWindow.contentView = live.view
  for (index, mode) in [NSAppearance.Name.aqua, .darkAqua, .aqua].enumerated() {
    liveWindow.appearance = NSAppearance(named: mode)
    try renderNative(
      live.view,
      to: directory.appendingPathComponent(
        "transition-\(index)-\(mode == .aqua ? "light" : "dark").png"))
  }
  liveWindow.close()
  let stableMode = DashboardController()
  stableMode.notice = "전송 완료 · 기존 상태를 유지합니다."
  var modeState = fixtureState()
  modeState.config.ports = []
  let modeWindow = NSWindow(
    contentRect: NSRect(origin: .zero, size: DashboardController.panelSize), styleMask: .borderless,
    backing: .buffered, defer: false)
  modeWindow.contentView = stableMode.view
  for (index, keep) in [false, true, false].enumerated() {
    stableMode.preservesImage = keep
    stableMode.render(modeState)
    try renderNative(
      stableMode.view,
      to: directory.appendingPathComponent("mode-\(index)-\(keep ? "keep" : "copy").png"))
  }
  modeWindow.close()
  for style in [NSAppearance.Name.aqua, .darkAqua] {
    let row = AppearanceBackgroundView(frame: NSRect(x: 0, y: 0, width: 330, height: 64))
    row.wantsLayer = true
    row.appearance = NSAppearance(named: style)
    var cells: [NSView] = []
    for (mode, title) in [
      (MenuBarGlyph.Mode.on, "ON"), (.off, "OFF"), (.paused, "일시 정지"), (.problem, "오류"),
    ] {
      let image = NSImageView(image: MenuBarGlyph.image(for: mode))
      image.contentTintColor = .labelColor
      image.alphaValue = mode == .off ? 0.65 : 1
      image.widthAnchor.constraint(equalToConstant: 18).isActive = true
      image.heightAnchor.constraint(equalToConstant: 18).isActive = true
      let cell = vertical([image, label(title, size: 10)], spacing: 6)
      cell.alignment = .centerX
      cell.widthAnchor.constraint(equalToConstant: 64).isActive = true
      cells.append(cell)
    }
    let strip = horizontal(cells, spacing: 16)
    strip.frame.origin = NSPoint(x: 10, y: 12)
    strip.setFrameSize(strip.fittingSize)
    row.addSubview(strip)
    try renderNative(
      row, to: directory.appendingPathComponent("glyphs-\(style == .aqua ? "light" : "dark").png"))
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
  if Bundle.main.url(forResource: "Assets", withExtension: "car") != nil {
    try require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "Worklink",
      "layered app icon is not registered")
  }
  try require(
    Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "Worklink",
    "app icon is not registered")
  guard let iconURL = Bundle.main.url(forResource: "Worklink", withExtension: "icns"),
    let icon = NSImage(contentsOf: iconURL)
  else {
    throw NSError(
      domain: "Worklink QA", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "legacy app icon missing or unreadable"])
  }
  try require(icon.size.width > 0, "app icon has no drawable size")
  guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil) else {
    throw NSError(
      domain: "Worklink QA", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "icns image source cannot be decoded"])
  }
  let widths = (0..<CGImageSourceGetCount(source)).compactMap { index -> Int? in
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    return properties?[kCGImagePropertyPixelWidth] as? Int
  }
  try require(widths.contains { $0 >= 1024 }, "app icon lacks high-resolution representation")
  let board = NSPasteboard(name: NSPasteboard.Name("dev.worklink.qa.\(UUID().uuidString)"))
  defer { board.releaseGlobally() }
  let original = Data([0, 255, 1, 2, 3, 128])
  board.clearContents()
  board.setData(original, forType: .png)
  let image = try ClipboardReader.read(board, maximum: 1024)
  try require(image?.bytes == original && image?.ext == "png", "clipboard bytes changed")
  let suite = "dev.worklink.qa.preferences.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let preferences = ClipboardPreferences(defaults: defaults)
  try require(!preferences.preservesImage, "new preference unexpectedly changed legacy mode")
  preferences.preservesImage = true
  let preservedCount = board.changeCount
  try require(
    preferences.complete(
      "/tmp/image.png", board: board, expectedCount: preservedCount, allowed: true)
      == .originalKept, "keep mode reported path copied")
  try require(
    board.data(forType: .png) == original && board.changeCount == preservedCount,
    "keep mode overwrote local capture")
  try require(ClipboardPreferences(defaults: defaults).preservesImage, "mode not persisted")
  preferences.preservesImage = false
  try require(board.changeCount == preservedCount, "switching mode wrote clipboard")
  try require(
    preferences.complete(
      "/tmp/image.png", board: board, expectedCount: preservedCount, allowed: true) == .pathCopied,
    "path mode failed")
  board.clearContents()
  board.setData(original, forType: .png)
  let restoreCount = board.changeCount
  try require(
    ClipboardReader.restore(
      original, extension: "png", board: board, expectedCount: restoreCount, allowed: true),
    "restore failed")
  try require(board.data(forType: .png) == original, "restore reencoded image")
  let outdated = board.changeCount
  board.clearContents()
  board.setString("newer content", forType: .string)
  try require(
    !ClipboardReader.restore(
      original, extension: "png", board: board, expectedCount: outdated, allowed: true),
    "restore overwrote newer clipboard")
  try require(board.string(forType: .string) == "newer content", "newer clipboard lost")
  board.clearContents()
  board.setData(original, forType: .png)
  let delegate = AppDelegate()
  delegate.clipboardBoard = board
  delegate.clipboardPreferences = preferences
  delegate.bridge.state = fixtureState()
  delegate.desiredOn = true
  var delayedJob = fixtureState().jobs[0]
  delayedJob.clipboardCount = board.changeCount
  preferences.preservesImage = true
  delegate.complete(delayedJob)
  try require(
    board.data(forType: .png) == original && board.changeCount == delayedJob.clipboardCount,
    "in-flight keep choice ignored")
  preferences.preservesImage = false
  delegate.complete(delayedJob)
  try require(
    board.string(forType: .string) == delayedJob.remotePath, "in-flight copy choice ignored")
  board.clearContents()
  board.setData(original, forType: .png)
  delegate.lastCount = board.changeCount
  delegate.observeClipboard()
  try require(!delegate.captureBusy, "app-restored image re-enqueued")
  for ext in ["png", "jpg", "jpeg", "tiff", "heic", "heif", "webp"] {
    let before = board.changeCount
    try require(
      ClipboardReader.restore(
        original, extension: ext, board: board, expectedCount: before, allowed: true),
      "original format restore failed")
    let type = ClipboardReader.types.first { $0.1 == (ext == "jpeg" ? "jpg" : ext) }!.0
    try require(board.data(forType: type) == original, "restore changed original format/bytes")
  }
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
  let fixedSize = NSSize(width: 380, height: 460)
  let panel = DashboardController()
  var crowded = fixtureState()
  crowded.config.ports = Array(repeating: crowded.config.ports[0], count: 12)
  var stoppedWithJobs = fixtureState()
  stoppedWithJobs.on = false
  for state in [fixtureState(on: false), fixtureState(), stoppedWithJobs, crowded] {
    panel.preservesImage.toggle()
    panel.render(state)
    try require(
      panel.view.frame.size == fixedSize && panel.preferredContentSize == fixedSize,
      "popover changed height on state transition")
    try require(
      panel.headerFrame.maxY <= fixedSize.height && panel.footerFrame.minY >= 0,
      "pinned controls clipped")
  }
  panel.bodyScroll?.contentView.scroll(to: NSPoint(x: 0, y: 120))
  panel.resetScroll()
  try require(
    panel.bodyScroll?.contentView.bounds.origin.y == 0, "reopened menu did not reset to top")
  let menuDelegate = AppDelegate()
  menuDelegate.clipboardBoard = board
  menuDelegate.clipboardPreferences = preferences
  menuDelegate.bridge.state = fixtureState()
  menuDelegate.dashboard.notice = "전송 완료 · 기존 상태"
  menuDelegate.dashboard.render(fixtureState())
  let menuPanel = menuDelegate.dashboard
  let geometry = [menuPanel.headerFrame, menuPanel.footerFrame, menuPanel.bodyScroll!.frame]
  let beforeCount = board.changeCount
  for keep in [true, false, true] {
    menuDelegate.setClipboardMode(keep)
    try require(menuPanel.notice == "전송 완료 · 기존 상태", "mode switch added or replaced notice")
    try require(
      [menuPanel.headerFrame, menuPanel.footerFrame, menuPanel.bodyScroll!.frame] == geometry,
      "mode switch moved layout")
    try require(menuPanel.view.fittingSize == fixedSize, "popover fitting size is not fixed")
    try require(board.changeCount == beforeCount, "mode switch changed clipboard")
  }
  func actionButtons(_ view: NSView) -> [ActionButton] {
    (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap { actionButtons($0) }
  }
  guard let keepControl = actionButtons(menuPanel.view).first(where: { $0.title == "캡처 원본 유지" }),
    let titleRow = keepControl.superview as? NSStackView
  else { throw NSError(domain: "Worklink QA", code: 1) }
  try require(
    titleRow.arrangedSubviews.contains { ($0 as? NSTextField)?.stringValue == "Worklink" }
      && menuPanel.headerFrame.height <= 30, "header controls are not in compact title row")
  func switches(_ root: NSView) -> [NSSwitch] {
    (root as? NSSwitch).map { [$0] } ?? root.subviews.flatMap { switches($0) }
  }
  guard let workSwitch = switches(menuPanel.view).first else {
    throw NSError(
      domain: "Worklink QA", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "work mode switch missing"])
  }
  try require(
    workSwitch.acceptsFirstMouse(for: nil) && workSwitch.accessibilityLabel() == "업무 모드",
    "header switch cannot handle first click or lacks accessibility label")
  var workToggles = 0
  menuPanel.toggle = { workToggles += 1 }
  workSwitch.sendAction(workSwitch.action!, to: workSwitch.target)
  try require(
    workToggles == 1 && workSwitch.state == .on,
    "header switch did not invoke existing toggle callback")
  try require(
    !actionButtons(menuPanel.view).contains { ["업무 시작", "업무 종료"].contains($0.title) },
    "duplicate footer work control remains")
  var disabledState = fixtureState()
  disabledState.on = false
  let disabledPanel = DashboardController()
  disabledPanel.render(disabledState)
  let copyButtons = actionButtons(disabledPanel.view).filter {
    ["경로 복사", "원본 복사"].contains($0.title)
  }
  try require(
    copyButtons.count == 2
      && copyButtons.allSatisfy { !$0.isEnabled && $0.toolTip == "업무 모드를 켜 주세요." },
    "OFF actions lack reason tooltips")
  disabledState.on = true
  disabledPanel.expired = [disabledState.jobs[0].id]
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).filter { ["경로 복사", "원본 복사"].contains($0.title) }.allSatisfy {
      !$0.isEnabled && $0.toolTip?.contains("만료") == true
    }, "expired action lacks reason")
  disabledPanel.expired.removeAll()
  disabledState.hosts[0].status = "connecting"
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).filter { ["경로 복사", "원본 복사"].contains($0.title) }.allSatisfy {
      !$0.isEnabled && $0.toolTip?.contains("연결") == true
    }, "waiting connection actions lack reason")
  disabledState.hosts[0].status = "connected"
  disabledPanel.restoring = disabledState.jobs[0].id
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).first { $0.title == "가져오는 중…" }?.toolTip?.contains("가져오는 중")
      == true, "busy restore lacks reason")
  try require(
    actionButtons(disabledPanel.view).first { $0.title == "경로 복사" }?.isEnabled == true,
    "busy restore blocked path copy")
  disabledPanel.restoring = nil
  disabledState.jobs[0].status = "sending"
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).first { $0.title == "재시도" }?.toolTip?.contains("전송 중")
      == true, "sending retry lacks reason")
  disabledState.jobs[0].status = "expired"
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).first { $0.title == "재시도" }?.toolTip?.contains("다시 캡처")
      == true, "expired retry lacks recovery hint")
  disabledState.jobs[0].status = "paused"
  disabledState.hosts[0].status = "connecting"
  disabledPanel.render(disabledState)
  try require(
    actionButtons(disabledPanel.view).first { $0.title == "재시도" }?.isEnabled == true,
    "retry disabled while connecting")
  var invokes = 0
  let disabledAction = ActionButton("test") { invokes += 1 }
  disabledAction.setDisabledReason("업무 모드를 켜 주세요.")
  try require(
    disabledAction.accessibilityHelp() == disabledAction.toolTip,
    "disabled reason lacks accessibility help")
  disabledAction.performClick(nil)
  try require(invokes == 0, "disabled action invoked")
  disabledAction.setDisabledReason(nil)
  disabledAction.performClick(nil)
  try require(
    invokes == 1 && disabledAction.toolTip == nil && disabledAction.accessibilityHelp() == nil,
    "reenabled action retained disabled help")
  let activeGlyph = MenuBarGlyph.image(for: .on)
  let inactiveGlyph = MenuBarGlyph.image(for: .off)
  try require(
    activeGlyph.isTemplate && inactiveGlyph.isTemplate
      && activeGlyph.size == NSSize(width: 18, height: 18)
      && inactiveGlyph.size == activeGlyph.size, "ON/OFF glyph size differs")
  try require(
    activeGlyph.tiffRepresentation != inactiveGlyph.tiffRepresentation,
    "OFF glyph is not visibly broken")
  func glyphBounds(_ image: NSImage) throws -> NSRect {
    guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else {
      throw NSError(domain: "Worklink QA", code: 1)
    }
    var pixels: [NSPoint] = []
    for y in 0..<rep.pixelsHigh {
      for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
        pixels.append(NSPoint(x: x, y: y))
      }
    }
    try require(
      !pixels.isEmpty && pixels.count < rep.pixelsWide * rep.pixelsHigh / 2,
      "glyph is empty or has a filled background")
    let xs = pixels.map { $0.x }
    let ys = pixels.map { $0.y }
    return NSRect(
      x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
  }
  try require(
    try glyphBounds(activeGlyph) == glyphBounds(inactiveGlyph), "ON/OFF actual chain bounds differ")
  func taggedViews(_ root: NSView, prefix: String) -> [NSView] {
    (root.identifier?.rawValue.hasPrefix(prefix) == true ? [root] : [])
      + root.subviews.flatMap { taggedViews($0, prefix: prefix) }
  }
  let compactPanel = DashboardController()
  compactPanel.notice = "전송 완료 · 캡처 원본 유지 중. 필요할 때 경로를 복사하세요."
  var compactState = fixtureState()
  let base = compactState.config.ports[0]
  compactState.config.ports = (0..<5).map { index in
    var port = base
    port.id = String(format: "%032x", index + 1)
    port.name = "개발 서버 \(index + 1)"
    port.localPort = 5200 + index
    port.endpoint.remotePort = 5200 + index
    port.endpoint.scheme = "https"
    port.endpoint.query = "q=1"
    port.endpoint.fragment = "view"
    return port
  }
  compactState.ports = compactState.config.ports.map {
    PortStatus(id: $0.id, status: "ready", error: nil, reachable: true)
  }
  compactPanel.render(compactState)
  let compactRows = taggedViews(compactPanel.view, prefix: "port-row-")
  try require(
    compactRows.count == 5 && compactRows.allSatisfy { abs($0.frame.height - 24) < 0.1 },
    "port rows are not compact single lines")
  let document = compactPanel.bodyScroll!.documentView!
  let viewport = compactPanel.bodyScroll!.contentView.bounds
  try require(
    compactRows.allSatisfy { viewport.contains($0.convert($0.bounds, to: document)) },
    "five ports do not fit in initial viewport")
  var opened: PortConfig?
  compactPanel.open = { opened = $0 }
  guard
    let firstRow = compactRows.first(where: {
      $0.identifier?.rawValue == "port-row-\(compactState.config.ports[0].id)"
    })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  guard
    let addressButton = actionButtons(firstRow).first(where: {
      $0.title.hasPrefix("localhost:")
    })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  try require(
    addressButton.toolTip == "https://localhost:5200/preview?q=1#view",
    "compact address lost full URL tooltip")
  addressButton.performClick(nil)
  try require(
    opened?.endpoint.localURL(5200)?.absoluteString == "https://localhost:5200/preview?q=1#view"
      && opened?.localPort == 5200,
    "compact browser action changed target")
  guard let disclosure = actionButtons(firstRow).first(where: { $0.title == "상세 보기" }) else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  disclosure.performClick(nil)
  try require(
    actionButtons(compactPanel.view).contains { $0.title == "주소 복사" }
      && actionButtons(compactPanel.view).contains { $0.title == "제목 확인" },
    "compact disclosure removed details actions")
  let live = DashboardController()
  live.render(fixtureState())
  let hostWindow = NSWindow(
    contentRect: live.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
  hostWindow.contentView = live.view
  defer { hostWindow.close() }
  live.bodyScroll?.contentView.scroll(to: NSPoint(x: 0, y: 40))
  let children = live.view.subviews.map { ObjectIdentifier($0) }
  let offset = live.bodyScroll?.contentView.bounds.origin
  var shades: [CGFloat] = []
  for mode in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
    let appearance = NSAppearance(named: mode)!
    hostWindow.appearance = appearance
    live.view.layoutSubtreeIfNeeded()
    live.view.displayIfNeeded()
    guard let rep = live.view.bitmapImageRepForCachingDisplay(in: live.view.bounds) else {
      throw NSError(domain: "Worklink QA", code: 1)
    }
    live.view.cacheDisplay(in: live.view.bounds, to: rep)
    guard let pixel = rep.colorAt(x: rep.pixelsWide - 10, y: 10)?.usingColorSpace(.sRGB) else {
      throw NSError(domain: "Worklink QA", code: 1)
    }
    var expected: NSColor!
    appearance.performAsCurrentDrawingAppearance {
      expected = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
    }
    try require(
      abs(pixel.redComponent - expected.redComponent) < 0.04,
      "live appearance background did not follow window")
    shades.append(pixel.redComponent)
    try require(
      live.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == mode,
      "view appearance did not follow window")
    try require(
      live.view.subviews.map { ObjectIdentifier($0) } == children
        && live.bodyScroll?.contentView.bounds.origin == offset
        && live.view.frame.size == fixedSize, "appearance switch rebuilt or moved menu")
  }
  try require(
    shades[0] - shades[1] > 0.3 && abs(shades[0] - shades[2]) < 0.04,
    "live light/dark/light transition failed")
  let quickRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "worklink-quick-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: quickRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: quickRoot) }
  try JSONSerialization.data(withJSONObject: jsonObject(fixtureState().config)).write(
    to: quickRoot.appendingPathComponent("config.json"))
  let quickDelegate = AppDelegate()
  guard let core = Bundle.main.url(forResource: "worklink", withExtension: nil) else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  try quickDelegate.bridge.start(binary: core, dataDirectory: quickRoot)
  defer { quickDelegate.bridge.stop() }
  func waitQuick(_ condition: () -> Bool) throws {
    let deadline = Date(timeIntervalSinceNow: 3)
    while !condition() && Date() < deadline {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    try require(condition(), "quick registration timed out")
  }
  try waitQuick { quickDelegate.bridge.state != nil }
  let quick = quickDelegate.dashboard
  quick.render(quickDelegate.bridge.state!)
  try require(
    quick.quickHost.titleOfSelectedItem == "office-test",
    "quick host default differs from image target")
  let draft = "Local: http://localhost:5188/preview?q=1#view"
  quick.quickAddress.stringValue = draft
  quick.render(quickDelegate.bridge.state!)
  try require(quick.quickAddress.stringValue == draft, "state render discarded quick draft")
  quick.registerQuick = { [weak quickDelegate] input, host in
    quickDelegate?.registerQuickPort(input, host: host)
  }
  quick.quickAddress.sendAction(quick.quickAddress.action!, to: quick.quickAddress.target)
  quickDelegate.registerQuickPort("5192", host: "office-test")
  try waitQuick { !quick.quickBusy && quickDelegate.bridge.state?.config.ports.count == 3 }
  let created = quickDelegate.bridge.state!.config.ports.last!
  try require(
    created.host == "office-test" && created.localPort == 5188
      && created.endpoint.remoteHost == "127.0.0.1"
      && created.endpoint.localURL(5188)?.absoluteString
        == "http://localhost:5188/preview?q=1#view",
    "quick port registration lost target or URL")
  try require(
    quick.quickAddress.stringValue.isEmpty && !quickDelegate.bridge.state!.on,
    "quick registration did not clear success or changed work mode")
  quick.quickAddress.stringValue = "5188"
  quickDelegate.registerQuickPort("5188", host: "office-test")
  try waitQuick { !quick.quickBusy }
  try require(
    quickDelegate.bridge.state!.config.ports.count == 3 && quick.quickAddress.stringValue == "5188"
      && quick.quickError, "duplicate quick registration changed config or cleared draft")
  quick.quickAddress.stringValue = "http://example.com:5189"
  quickDelegate.registerQuickPort(quick.quickAddress.stringValue, host: "office-test")
  try waitQuick { !quick.quickBusy }
  try require(
    quick.quickError && quickDelegate.bridge.state!.config.ports.count == 3
      && quick.quickAddress.stringValue.contains("example.com"),
    "non-loopback quick registration accepted")
  for bad in ["http://localhost:5190 http://localhost:5191", "http://localhost/preview"] {
    quick.quickAddress.stringValue = bad
    quickDelegate.registerQuickPort(bad, host: "office-test")
    try waitQuick { !quick.quickBusy }
    try require(
      quick.quickError && quickDelegate.bridge.state!.config.ports.count == 3
        && quick.quickAddress.stringValue == bad,
      "ambiguous/missing-port input changed config or lost draft")
  }
  let editingPanel = DashboardController()
  var editingState = fixtureState(on: false)
  editingState.config.hosts.append(
    HostConfig(name: "office-backup", helper: "~/.local/bin/worklink"))
  editingPanel.render(editingState)
  editingPanel.quickHost.selectItem(withTitle: "office-backup")
  editingPanel.quickHost.sendAction(
    editingPanel.quickHost.action!, to: editingPanel.quickHost.target)
  let editWindow = NSWindow(
    contentRect: editingPanel.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
  editWindow.contentView = editingPanel.view
  defer { editWindow.close() }
  editingPanel.quickAddress.stringValue = "5188"
  try require(
    editWindow.makeFirstResponder(editingPanel.quickAddress),
    "quick input cannot become first responder")
  guard let editor = editingPanel.quickAddress.currentEditor() as? NSTextView else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  editor.selectedRange = NSRange(location: 2, length: 0)
  let parents = [
    editingPanel.quickAddress.superview!, editingPanel.quickAddress.superview!.superview!,
    editingPanel.bodyScroll!.documentView!, editingPanel.bodyScroll!,
  ].map { ObjectIdentifier($0) }
  for _ in 0..<20 {
    editingPanel.render(editingState)
    try require(
      editingPanel.quickAddress.currentEditor() === editor && editor.string == "5188"
        && editor.selectedRange == NSRange(location: 2, length: 0),
      "state render interrupted input/cursor")
    try require(
      editingPanel.quickHost.titleOfSelectedItem == "office-backup",
      "state render changed explicit SSH target")
    try require(
      [
        editingPanel.quickAddress.superview!, editingPanel.quickAddress.superview!.superview!,
        editingPanel.bodyScroll!.documentView!, editingPanel.bodyScroll!,
      ].map { ObjectIdentifier($0) } == parents && editingPanel.view.constraints.count <= 14,
      "form ancestry changed or constraints accumulated")
  }
  editor.setMarkedText(
    "가", selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: 2, length: 0))
  let marked = editor.markedRange()
  editingPanel.render(editingState)
  try require(
    editor.hasMarkedText() && editor.markedRange() == marked
      && editingPanel.quickAddress.currentEditor() === editor,
    "state render interrupted IME composition")
  editor.unmarkText()
  var noHosts = editingState
  noHosts.config.hosts = []
  noHosts.config.ports = []
  noHosts.config.imageHost = ""
  let emptyPanel = DashboardController()
  emptyPanel.render(noHosts)
  try require(
    !emptyPanel.quickAddress.isEnabled
      && actionButtons(emptyPanel.view).first { $0.title == "등록" }?.toolTip?.contains("SSH")
        == true,
    "missing SSH target lacks registration hint")
  print(
    "Native clipboard/lifecycle/appearance/menu layout/tooltips/glyphs/quick registration/IME tests passed."
  )
}
func configureNativeTransferQA(_ delegate: AppDelegate) throws {
  guard let path = ProcessInfo.processInfo.environment["WORKLINK_QA_IMAGE_PATH"] else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  let board = NSPasteboard(
    name: NSPasteboard.Name("dev.worklink.qa.integration.\(UUID().uuidString)"))
  delegate.clipboardBoard = board
  let suite = "dev.worklink.qa.integration.preferences.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  delegate.clipboardPreferences = ClipboardPreferences(defaults: defaults)
  let preserve = ProcessInfo.processInfo.environment["WORKLINK_QA_PRESERVE"] == "1"
  delegate.clipboardPreferences.preservesImage = preserve
  delegate.dashboard.preservesImage = preserve
  var completed = false
  var capturedCount = 0
  var baselineJobs = Set<String>()
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
      baselineJobs = Set(state.jobs.map { $0.id })
      board.clearContents()
      board.setData(data, forType: .png)
      capturedCount = board.changeCount
    }
  }
  delegate.bridge.onComplete = { [weak delegate] job in
    guard let delegate else { return }
    guard !completed else { return }
    completed = true
    delegate.complete(job)
    let replaced = board.string(forType: .string) == job.remotePath
    let preserved = board.data(forType: .png) == data && board.changeCount == capturedCount
    // Exercise explicit path copy even when original preservation is selected.
    let beforeManualCopy = board.changeCount
    delegate.copy(job)
    var phase = 0
    var pathCopied = false
    var restoreCount = 0
    var restoreStarted = Date()
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
      if phase == 0 {
        guard board.string(forType: .string) == job.remotePath,
          board.changeCount != beforeManualCopy
        else { return }
        pathCopied = true
        phase = 1
        delegate.restore(job)
        restoreStarted = Date()
        return
      }
      if phase == 1 {
        guard delegate.dashboard.restoring == nil else { return }
        phase = 2
        restoreCount = board.changeCount
        restoreStarted = Date()
      }
      guard Date().timeIntervalSince(restoreStarted) >= 2 else { return }
      let noRepeat =
        delegate.bridge.state?.jobs.filter {
          $0.sha256 == job.sha256 && !baselineJobs.contains($0.id)
        }.count == 1
      let restored = board.data(forType: .png) == data && board.changeCount == restoreCount
      let result: [String: Any] = [
        "native_clipboard": true, "path_replaced": replaced, "original_preserved": preserved,
        "manual_path_copied": pathCopied, "original_restored": restored,
        "restore_no_reupload": noRepeat,
        "scratch_removed":
          (try? FileManager.default.contentsOfDirectory(
            atPath: delegate.root.appendingPathComponent("restores").path
          ).isEmpty) == true,
        "sha256": job.sha256, "byte_count": job.size,
      ]
      if let bytes = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys) {
        FileHandle.standardOutput.write(bytes + Data([10]))
      }
      timer.invalidate()
      defaults.removePersistentDomain(forName: suite)
      board.releaseGlobally()
      NSApp.terminate(nil)
    }
  }
  Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
    fputs("Native QA timed out\n", stderr)
    NSApp.terminate(nil)
  }
}

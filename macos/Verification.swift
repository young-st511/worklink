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
    for name in [
      "off", "on", "error", "keep", "images", "files", "cleanup", "offline", "low-power",
    ] {
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
      if name == "offline" { state.networkUnavailable = true }
      if name == "low-power" { state.lowPower = true }
      if name == "cleanup" {
        state.config.portCleanupEnabled = true
        state.config.portCleanupDays = 7
        var removed = state.config.ports[0]
        removed.id = identifier()
        removed.localPort = 4100
        state.config.portCleanupHistory = PortCleanupHistory(
          lastRun: "2026-10-22T01:00:00Z", removedAt: "2026-10-22T01:00:00Z", removed: [removed])
        state.config.ports[0].pinned = true
      }
      if name == "files" {
        state.files = [
          FileTransfer(
            id: identifier(), name: "디자인 원본 시안.pdf", host: state.config.imageHost, size: 204800,
            sent: 204800, status: "complete", error: nil),
          FileTransfer(
            id: identifier(), name: "테스트 데이터.csv", host: state.config.imageHost, size: 1_024_000,
            sent: 512000, status: "sending", error: nil),
        ]
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
      if count == 8 {
        state.jobs = (0..<5).map { index in
          var job = state.jobs[0]
          job.id = String(format: "%032x", index + 20)
          return job
        }
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
      if count == 8 {
        func imageButtons(_ root: NSView) -> [ActionButton] {
          (root as? ActionButton).map { [$0] } ?? root.subviews.flatMap { imageButtons($0) }
        }
        imageButtons(portsPanel.view).first { $0.title == "전체 5개 보기" }?.performClick(nil)
        try renderNative(
          portsPanel.view,
          to: directory.appendingPathComponent(
            "images-all-ports-8-\(style == .aqua ? "light" : "dark").png"))
      }
      if count == 1 {
        func buttons(_ root: NSView) -> [ActionButton] {
          (root as? ActionButton).map { [$0] } ?? root.subviews.flatMap { buttons($0) }
        }
        if let button = buttons(portsPanel.view).first(where: {
          $0.identifier?.rawValue.hasPrefix("port-open-") == true
        }),
          let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
        {
          button.mouseEntered(with: event)
          try renderNative(
            portsPanel.view,
            to: directory.appendingPathComponent(
              "ports-hover-\(style == .aqua ? "light" : "dark").png"))
          button.mouseExited(with: event)
        }

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
    let row = AppearanceBackgroundView(frame: NSRect(x: 0, y: 0, width: 600, height: 64))
    row.wantsLayer = true
    row.appearance = NSAppearance(named: style)
    var cells: [NSView] = []
    for keep in [false, true] {
      for (mode, title) in [
        (MenuBarGlyph.Mode.on, "ON"), (.off, "OFF"), (.paused, "일시 정지"), (.problem, "오류"),
      ] {
        let glyph = MenuBarGlyph.image(for: mode, preservesImage: keep)
        let image = NSImageView(image: glyph)
        image.contentTintColor = .labelColor
        image.alphaValue = mode == .off ? 0.65 : 1
        image.widthAnchor.constraint(equalToConstant: glyph.size.width).isActive = true
        image.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let cell = vertical([image, label("\(title)\(keep ? " 원본" : "")", size: 10)], spacing: 6)
        cell.alignment = .centerX
        cell.widthAnchor.constraint(equalToConstant: 64).isActive = true
        cells.append(cell)
      }
    }
    let strip = horizontal(cells, spacing: 10)
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
  try nativeRightHoldSelfTest()
  try nativeStatusRoutingSelfTest()
  try nativeSecondaryReleaseSelfTest()
  try nativeFileSelfTest()
  try nativeCleanupSelfTest()
  try nativeEnvironmentSelfTest()

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
  let readyCount = board.changeCount
  delegate.observeClipboard()
  try require(
    !delegate.dashboard.copied.isEmpty && delegate.dashboard.copiedCount == readyCount,
    "unchanged clipboard cleared ready marker")
  board.clearContents()
  board.setString("http://localhost:4000/", forType: .string)
  let changedCount = board.changeCount
  delegate.observeClipboard()
  try require(
    delegate.dashboard.copied.isEmpty && delegate.dashboard.copiedCount == nil,
    "no state heartbeat left stale ready marker")
  try require(
    board.changeCount == changedCount && board.string(forType: .string) == "http://localhost:4000/"
      && !delegate.captureBusy, "local clipboard marker refresh altered clipboard or uploaded text")
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
  for mode in MenuBarGlyph.Mode.allCases {
    let plain = MenuBarGlyph.image(for: mode)
    let preserved = MenuBarGlyph.image(for: mode, preservesImage: true)
    try require(
      preserved.isTemplate && preserved.size == NSSize(width: 18, height: 18),
      "photo indicator missing or clipped")
    func glyphPixels(_ image: NSImage) throws -> NSBitmapImageRep {
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: 36,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      rep.size = image.size
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      image.draw(in: NSRect(origin: .zero, size: image.size))
      NSGraphicsContext.restoreGraphicsState()
      return rep
    }
    let left = try glyphPixels(plain)
    let right = try glyphPixels(preserved)
    for y in 0..<36 {
      for x in 0..<36 {
        let photoRegion = x >= 21 && y >= 21
        let movedStatus = (mode == .paused || mode == .problem) && x < 12 && y < 14
        if !photoRegion && !movedStatus {
          try require(
            abs(
              (left.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                - (right.colorAt(x: x, y: y)?.alphaComponent ?? 0)) < 0.01,
            "badge changed chain outside corner")
        }
      }
    }
    var photoPixels = 0
    for y in 23..<36 {
      for x in 22..<36 where (right.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
        photoPixels += 1
      }
    }
    try require(
      photoPixels > 20 && photoPixels < 150,
      "small photo outline/mountain missing or filled: \(photoPixels)")
  }
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
    compactRows.first.map { viewport.intersects($0.convert($0.bounds, to: document)) } == true,
    "first server is not reachable below images")
  var opened: PortConfig?
  compactPanel.open = { opened = $0 }
  guard
    let firstRow = compactRows.first(where: {
      $0.identifier?.rawValue == "port-row-\(compactState.config.ports[0].id)"
    })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  guard
    let addressButton = actionButtons(firstRow).first(where: {
      $0.identifier?.rawValue.hasPrefix("port-open-") == true
    })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  try require(
    addressButton.toolTip == "https://localhost:5200/preview?q=1#view",
    "compact address lost full URL tooltip")
  for x: CGFloat in [3, 35, 160, 260, 310] {
    let hit = firstRow.hitTest(NSPoint(x: firstRow.frame.minX + x, y: firstRow.frame.midY))
    try require(hit === addressButton, "port row locations route to different actions")
  }
  guard
    let hoverEvent = NSEvent.otherEvent(
      with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, subtype: 0, data1: 0, data2: 0)
  else { throw NSError(domain: "Worklink QA", code: 1) }
  func buttonPixel(_ button: ActionButton) throws -> NSColor {
    guard let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
      throw NSError(domain: "Worklink QA", code: 1)
    }
    button.displayIfNeeded()
    button.cacheDisplay(in: button.bounds, to: rep)
    guard let pixel = rep.colorAt(x: rep.pixelsWide / 2, y: 2)?.usingColorSpace(.sRGB) else {
      throw NSError(domain: "Worklink QA", code: 1)
    }
    return pixel
  }
  let hoverBefore = try buttonPixel(addressButton)
  addressButton.mouseEntered(with: hoverEvent)
  try require(addressButton.isHovered, "active button did not respond to hover")
  let hoverAfter = try buttonPixel(addressButton)
  try require(
    abs(hoverBefore.alphaComponent - hoverAfter.alphaComponent) > 0.05
      || abs(hoverBefore.blueComponent - hoverAfter.blueComponent) > 0.02,
    "hover has no visible feedback")
  let otherHover = ActionButton("다른 버튼") {}
  compactPanel.view.addSubview(otherHover)
  otherHover.mouseEntered(with: hoverEvent)
  try require(otherHover.isHovered && !addressButton.isHovered, "multiple buttons retain hover")
  let independentRoot = NSView()
  let independentHover = ActionButton("별도 창") {}
  independentRoot.addSubview(independentHover)
  independentHover.mouseEntered(with: hoverEvent)
  try require(
    independentHover.isHovered && otherHover.isHovered, "independent roots steal hover ownership")
  otherHover.removeFromSuperview()
  try require(!otherHover.isHovered, "removed button retains hover")
  independentHover.mouseExited(with: hoverEvent)
  otherHover.mouseExited(with: hoverEvent)
  addressButton.mouseExited(with: hoverEvent)
  try require(!addressButton.isHovered, "hover did not clear")
  disabledAction.setDisabledReason("비활성")
  disabledAction.mouseEntered(with: hoverEvent)
  try require(!disabledAction.isHovered, "disabled button highlighted on hover")
  addressButton.performClick(nil)
  try require(
    opened?.endpoint.localURL(5200)?.absoluteString == "https://localhost:5200/preview?q=1#view"
      && opened?.localPort == 5200,
    "compact browser action changed target")
  guard let disclosure = actionButtons(firstRow).first(where: { $0.title == "상세 보기" }) else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  try require(
    firstRow.hitTest(NSPoint(x: firstRow.frame.maxX - 8, y: firstRow.frame.midY)) === disclosure,
    "disclosure hit area overlaps server open")
  opened = nil
  disclosure.performClick(nil)
  try require(
    actionButtons(compactPanel.view).contains { $0.title == "주소 복사" }
      && actionButtons(compactPanel.view).contains { $0.title == "제목 확인" },
    "compact disclosure removed details actions")
  try require(opened == nil, "disclosure opened browser")
  let detailRows = taggedViews(compactPanel.view, prefix: "port-detail-actions-")
  try require(
    detailRows.count == 1 && abs(detailRows[0].frame.height - 24) < 0.1,
    "detail URL and actions are not compact")
  try require(
    actionButtons(detailRows[0]).contains { $0.title == "주소 복사" && $0.imagePosition == .imageOnly },
    "detail copy is not an icon")
  for (on, status, reason) in [
    (false, "ready", "업무 OFF"), (true, "waiting", "서버 연결 대기"), (true, "conflict", "로컬 포트 충돌"),
  ] {
    var unavailable = compactState
    unavailable.on = on
    unavailable.ports[0] = PortStatus(
      id: unavailable.config.ports[0].id, status: status, error: nil, reachable: false)
    compactPanel.render(unavailable)
    guard
      let unavailableOpen = actionButtons(compactPanel.view).first(where: {
        $0.identifier?.rawValue == "port-open-\(unavailable.config.ports[0].id)"
      })
    else { throw NSError(domain: "Worklink QA", code: 1) }
    try require(
      !unavailableOpen.isEnabled && unavailableOpen.toolTip == reason,
      "unavailable port lacks disabled reason")
    unavailableOpen.mouseEntered(with: hoverEvent)
    unavailableOpen.performClick(nil)
    try require(
      !unavailableOpen.isHovered && opened == nil, "unavailable port hovered or opened browser")
    let unavailableRow = taggedViews(compactPanel.view, prefix: "port-row-").first {
      $0.identifier?.rawValue == "port-row-\(unavailable.config.ports[0].id)"
    }!
    try require(
      actionButtons(unavailableRow).contains { $0.title.hasPrefix("상세") && $0.isEnabled },
      "unavailable port lost details")
  }
  let imagePanel = DashboardController()
  var imageState = fixtureState()
  imageState.config.ports = []
  imageState.jobs = (0..<5).map { index in
    var job = imageState.jobs[0]
    job.id = String(format: "%032x", index + 10)
    return job
  }
  imagePanel.render(imageState)
  var imageRows = taggedViews(imagePanel.view, prefix: "image-row-")
  try require(
    imageRows.count == 3 && imageRows.allSatisfy { abs($0.frame.height - 28) < 0.1 },
    "image list is not compact")
  let imageDocument = imagePanel.bodyScroll!.documentView!
  try require(
    imageRows.allSatisfy {
      imagePanel.bodyScroll!.contentView.bounds.contains($0.convert($0.bounds, to: imageDocument))
    }, "default images do not fit")
  guard let showAll = actionButtons(imagePanel.view).first(where: { $0.title == "전체 5개 보기" }) else {
    throw NSError(domain: "Worklink QA", code: 1)
  }
  showAll.performClick(nil)
  try require(
    taggedViews(imagePanel.view, prefix: "image-row-").count == 5,
    "show all did not expose five images")
  imagePanel.render(imageState)
  try require(
    taggedViews(imagePanel.view, prefix: "image-row-").count == 5, "state refresh collapsed images")
  actionButtons(imagePanel.view).first(where: { $0.title == "접기" })?.performClick(nil)
  try require(
    taggedViews(imagePanel.view, prefix: "image-row-").count == 3,
    "collapse did not restore three images")
  actionButtons(imagePanel.view).first(where: { $0.title == "전체 5개 보기" })?.performClick(nil)
  imagePanel.resetScroll()
  try require(
    taggedViews(imagePanel.view, prefix: "image-row-").count == 3,
    "reopen did not restore three images")
  var manyPortsState = compactState
  manyPortsState.jobs = imageState.jobs
  imagePanel.render(manyPortsState)
  imageRows = taggedViews(imagePanel.view, prefix: "image-row-")
  let firstServer = taggedViews(imagePanel.view, prefix: "port-row-")[0]
  let imagesDocument = imagePanel.bodyScroll!.documentView!
  let imagesViewport = imagePanel.bodyScroll!.contentView.bounds
  try require(
    imageRows.count == 3
      && imageRows.allSatisfy {
        let frame = $0.convert($0.bounds, to: imagesDocument)
        return imagesViewport.contains(frame)
          && frame.maxY < firstServer.convert(firstServer.bounds, to: imagesDocument).minY
      }, "servers pushed images outside initial viewport")
  for count in [0, 1, 3] {
    var smallState = imageState
    smallState.jobs = Array(imageState.jobs.prefix(count))
    imagePanel.render(smallState)
    try require(
      taggedViews(imagePanel.view, prefix: "image-row-").count == count
        && !actionButtons(imagePanel.view).contains {
          $0.title.hasPrefix("전체") || $0.title == "접기"
        }, "unnecessary image disclosure")
  }
  var fourImages = imageState
  fourImages.jobs = Array(imageState.jobs.prefix(4))
  imagePanel.render(fourImages)
  guard let showFour = actionButtons(imagePanel.view).first(where: { $0.title == "전체 4개 보기" })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  showFour.performClick(nil)
  try require(
    taggedViews(imagePanel.view, prefix: "image-row-").count == 4, "four-image count is misleading")
  imagePanel.resetScroll()
  imagePanel.render(imageState)
  imageRows = taggedViews(imagePanel.view, prefix: "image-row-")
  var copiedID: String?
  var restoredID: String?
  imagePanel.copy = { copiedID = $0.id }
  imagePanel.restore = { restoredID = $0.id }
  guard let pathAction = actionButtons(imageRows[0]).first(where: { $0.title == "경로 복사" }),
    let originalAction = actionButtons(imageRows[0]).first(where: { $0.title == "원본 복사" })
  else { throw NSError(domain: "Worklink QA", code: 1) }
  pathAction.performClick(nil)
  originalAction.performClick(nil)
  try require(
    copiedID != nil && restoredID == copiedID && pathAction.toolTip == "경로 복사"
      && originalAction.toolTip == "원본 복사", "compact image callbacks or help missing")
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

func nativeFileSelfTest() throws {
  func check(_ good: Bool, _ message: String) throws {
    if !good {
      throw NSError(domain: "File QA", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  let board = NSPasteboard.withUniqueName()
  defer { board.releaseGlobally() }
  let urls = [
    URL(fileURLWithPath: "/tmp/Worklink fixture.txt"), URL(fileURLWithPath: "/tmp/한글.csv"),
  ]
  board.writeObjects(urls as [NSURL])
  try check(FileSelection.urls(board) == urls, "file URL selection lost filename")
  board.setData(Data([1, 2, 3]), forType: .png)
  let image = try ClipboardReader.read(board, maximum: 1024)
  try check(image == nil, "Finder thumbnail uploaded automatically")
  board.clearContents()
  board.setPropertyList(
    urls.map { $0.path }, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
  try check(FileSelection.urls(board) == urls, "legacy Finder selection lost filename")
  let delegate = AppDelegate()
  try check(
    delegate.responds(to: NSSelectorFromString("sendFiles:userData:error:")),
    "Finder service selector missing")
  let drop = StatusFileDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  try check(
    drop.registeredDraggedTypes.contains(.fileURL), "menu drop file URL registration missing")
  let controller = DashboardController()
  var state = fixtureState()
  state.files = (0..<8).map {
    FileTransfer(
      id: String($0), name: "fixture-\($0).pdf", host: state.config.imageHost, size: 2048,
      sent: 2048, status: "complete", error: nil)
  }
  var copied = ""
  controller.copyFile = { copied = $0.id }
  controller.render(state)
  let rows = controller.view.allFileRows()
  try check(
    rows.count == 3 && rows.allSatisfy { $0.frame.height == 28 || $0.frame.height == 0 },
    "recent file compact rows")
  controller.showsAllFiles = true
  controller.render(state)
  try check(controller.view.allFileRows().count == 8, "file history expansion lost batch entries")
  func buttons(_ view: NSView) -> [ActionButton] {
    (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
  }
  if let button = buttons(controller.view).first(where: { $0.title == "파일 경로 복사" }) {
    button.performClick(nil)
  }
  try check(!copied.isEmpty, "file path action unavailable")
}
extension NSView {
  fileprivate func allFileRows() -> [NSView] {
    subviews.flatMap { child in
      child.identifier?.rawValue.hasPrefix("file-row-") == true ? [child] : child.allFileRows()
    }
  }
}

func nativeCleanupSelfTest() throws {
  func check(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(domain: "Cleanup QA", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  var state = fixtureState()
  var object = jsonObject(state)
  var config = object["config"] as! [String: Any]
  config["port_cleanup_history"] = [
    "last_run": "2026-10-22T01:00:00Z", "removed_at": "0001-01-01T00:00:00Z", "removed": NSNull(),
  ]
  object["config"] = config
  let decoded = try decoder().decode(
    CoreState.self, from: JSONSerialization.data(withJSONObject: object))
  try check(
    decoded.config.portCleanupHistory?.removed.isEmpty == true,
    "null history blocked CoreState decoding")
  var history = config["port_cleanup_history"] as! [String: Any]
  history.removeValue(forKey: "removed")
  config["port_cleanup_history"] = history
  object["config"] = config
  _ = try decoder().decode(CoreState.self, from: JSONSerialization.data(withJSONObject: object))
  let bridge = CoreBridge()
  bridge.state = state
  let settings = SettingsController(bridge: bridge, loginEnabled: false)
  try check(
    settings.cleanupEnabled.state == .off && settings.cleanupDays.titleOfSelectedItem == "7일"
      && !settings.cleanupDays.isEnabled, "cleanup default not off/7 days")
  state.config.portCleanupEnabled = true
  state.config.portCleanupDays = 30
  state.config.revision += 1
  state.config.ports[0].pinned = true
  state.config.portCleanupHistory = PortCleanupHistory(
    lastRun: "2026-10-22T01:00:00Z", removedAt: "2026-10-22T01:00:00Z",
    removed: [state.config.ports[1]])
  bridge.state = state
  settings.refresh()
  try check(
    settings.cleanupDays.isEnabled && settings.cleanupDays.titleOfSelectedItem == "30일",
    "policy refresh lost period")
  try check(!settings.cleanupLastRun.stringValue.contains("아직"), "last cleanup time missing")
  let controller = DashboardController()
  var undo = false
  var pinned = false
  controller.undoPortCleanup = { undo = true }
  controller.pinPort = { _ in pinned = true }
  controller.expanded.insert(state.config.ports[0].id)
  controller.render(state)
  func buttons(_ view: NSView) -> [ActionButton] {
    (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
  }
  buttons(controller.view).first { $0.title == "되돌리기" }?.performClick(nil)
  buttons(controller.view).first { $0.title == "고정 해제" }?.performClick(nil)
  try check(undo && pinned, "undo/pin callback missing")
  try check(
    controller.view.frame.size == DashboardController.panelSize, "cleanup changed popup dimensions")
  settings.close()
}

func nativeEnvironmentSelfTest() throws {
  func check(_ value: Bool, _ text: String) throws {
    if !value {
      throw NSError(domain: "Environment QA", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
  }
  var gate = NetworkRecoveryGate()
  gate.start()
  let first = gate.receive(true)!
  for _ in 0..<100 { try check(gate.receive(true) == nil, "duplicate recovery scheduled") }
  _ = gate.receive(false)
  try check(!gate.complete(first) && !gate.available, "flap restored network")
  let next = gate.receive(true)!
  gate.stop()
  try check(!gate.complete(next), "OFF restored by stale callback")
  gate.start()
  try check(!gate.complete(next), "old monitor callback restored new session")
  let stable = gate.receive(true)!
  try check(gate.complete(stable) && gate.available, "stable path not accepted")
  var low = false
  var events: [String] = []
  let monitor = NetworkPowerMonitor(paths: false, lowPower: { low }) { available, power in
    events.append("\(available):\(power)")
  }
  monitor.start()
  monitor.handlePath(true)
  monitor.handlePath(true)
  try check(events == ["false:false"], "unstable path emitted available")
  monitor.stop()
  low = true
  monitor.publish()
  monitor.publish()
  try check(events == ["false:false", "false:true"], "power state not deduplicated")
  var state = fixtureState()
  state.networkUnavailable = true
  let controller = DashboardController()
  controller.render(state)
  func buttons(_ view: NSView) -> [ActionButton] {
    (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
  }
  try check(
    buttons(controller.view).first { $0.title == "서버 상태 새로고침" }?.isEnabled == false,
    "offline refresh enabled")
  state.networkUnavailable = false
  state.lowPower = true
  var refresh = false
  controller.refreshPorts = { refresh = true }
  controller.render(state)
  buttons(controller.view).first { $0.title == "서버 상태 새로고침" }?.performClick(nil)
  try check(
    refresh && controller.view.frame.size == DashboardController.panelSize,
    "power policy changed panel or refresh callback")
}


func nativeRightHoldSelfTest() throws {
  func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "Worklink QA", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }
  var short = 0, long = 0, held = true
  var callbacks: [() -> Void] = []
  var delays: [TimeInterval] = []
  let press = RightClickHold(
    short: { short += 1 }, long: { long += 1 }, isHeld: { held },
    schedule: { delay, action in delays.append(delay); callbacks.append(action); return {} })
  press.begin()
  press.begin()
  try require(callbacks.count == 1 && delays == [0.5], "hold timer duplicated/wrong threshold")
  press.end()
  callbacks[0]()
  try require(short == 1 && long == 0, "short press or stale timer failed")
  press.begin()
  callbacks[1]()
  callbacks[1]()
  try require(long == 1 && short == 1, "hold did not fire once before release")
  press.end()
  try require(short == 1, "long release toggled work")
  press.begin()
  press.cancel()
  callbacks[2]()
  press.end()
  try require(long == 1 && short == 1, "cancelled press executed")
  press.begin()
  held = false
  callbacks[3]()
  press.end()
  try require(long == 1 && short == 1, "lost release triggered action")
  held = true
  press.begin()
  callbacks[0]()
  try require(long == 1, "old timer affected new press")
  callbacks[4]()
  press.end()
  try require(long == 2 && short == 1, "new hold failed")

  var timedLong = 0, timedShort = 0
  let timed = RightClickHold(short: { timedShort += 1 }, long: { timedLong += 1 }, isHeld: { true })
  timed.begin()
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
  try require(timedLong == 0, "hold fired early")
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
  try require(timedLong == 1 && timedShort == 0, "real timer did not fire before up")
  timed.end()
  try require(timedShort == 0, "real long release toggled work")

  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
    styleMask: [.borderless], backing: .buffered, defer: false)
  let input = StatusFileDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  window.contentView = input
  var left = 0, right = 0
  input.clicked = { left += 1 }
  input.rightClicked = { right += 1 }
  func event(_ type: NSEvent.EventType, outside: Bool = false) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: outside ? 30 : 12, y: 12),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 0, clickCount: 1, pressure: 1)!
  }
  input.mouseDown(with: event(.leftMouseDown))
  input.mouseUp(with: event(.leftMouseUp))
  input.rightMouseDown(with: event(.rightMouseDown))
  input.rightMouseUp(with: event(.rightMouseUp))
  try require(left == 1 && right == 1, "input view lost left/short right click routing")
  input.rightMouseDown(with: event(.rightMouseDown))
  input.rightMouseDragged(with: event(.rightMouseDragged, outside: true))
  input.rightMouseUp(with: event(.rightMouseUp))
  try require(right == 1, "drag-out triggered short click")
  input.rightMouseDown(with: event(.rightMouseDown))
  input.viewWillMove(toWindow: nil)
  input.rightMouseUp(with: event(.rightMouseUp))
  try require(right == 1, "detached view retained press")
}


func nativeStatusRoutingSelfTest() throws {
  func check(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "Status routing QA", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]) }
  }
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
    styleMask: [.borderless], backing: .buffered, defer: false)
  let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
    styleMask: [.borderless], backing: .buffered, defer: false)
  let view = StatusFileDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  window.contentView = view
  var short = 0, long = 0
  var timers: [() -> Void] = []
  view.rightPress = RightClickHold(short: { short += 1 }, long: { long += 1 }, isHeld: { true },
    schedule: { _, action in timers.append(action); return {} })
  let router = StatusRightEventRouter(view: view, install: false)
  func event(_ type: NSEvent.EventType, outside: Bool = false, foreign: Bool = false) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: outside ? 30 : 12, y: 12),
      modifierFlags: [], timestamp: 0, windowNumber: foreign ? other.windowNumber : window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  }
  try check(router.handle(event(.rightMouseDown, foreign: true)) != nil, "foreign down consumed")
  try check(router.handle(event(.rightMouseDown, outside: true)) != nil, "outside down consumed")
  try check(router.handle(event(.leftMouseUp)) != nil, "left click consumed")
  try check(router.handle(event(.rightMouseDown)) == nil && short == 0 && long == 0,
    "raw down toggled work or escaped to button")
  timers[0]()
  try check(long == 1 && short == 0, "raw hold not fired before up")
  try check(router.handle(event(.rightMouseUp)) == nil && short == 0, "long up toggled work")
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  try check(short == 1 && long == 1, "short raw up not routed once")
  _ = router.handle(event(.rightMouseDown))
  try check(router.handle(event(.rightMouseDragged, outside: true)) == nil, "drag escaped")
  timers[2]()
  _ = router.handle(event(.rightMouseUp))
  try check(short == 1 && long == 1, "drag-out/return executed action")
  _ = router.handle(event(.rightMouseDown))
  router.cancel()
  timers[3]()
  _ = router.handle(event(.rightMouseUp))
  try check(short == 1 && long == 1, "cancel left action alive")
  router.stop()

  // Exercise the installed AppKit monitor, not only the extracted handler.
  let live = StatusRightEventRouter(view: view)
  let timerCount = timers.count
  NSApp.sendEvent(event(.rightMouseDown))
  try check(live.isTracking && timers.count == timerCount + 1 && short == 1,
    "AppKit raw down bypassed local router")
  timers.last?()
  NSApp.sendEvent(event(.rightMouseUp))
  try check(!live.isTracking && short == 1 && long == 2,
    "AppKit monitor did not consume long release")
  live.stop()
}


func nativeSecondaryReleaseSelfTest() throws {
  func check(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "Secondary release QA", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]) }
  }
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
    styleMask: [.borderless], backing: .buffered, defer: false)
  let view = StatusFileDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  window.contentView = view
  var buttons = 2, inside = true, short = 0, long = 0
  var hold: [() -> Void] = [], release: [() -> Void] = []
  view.rightPress = RightClickHold(short: { short += 1 }, long: { long += 1 },
    isHeld: { buttons & 2 != 0 && inside },
    schedule: { _, action in hold.append(action); return {} })
  let router = StatusRightEventRouter(view: view, install: false,
    pressedButtons: { buttons }, pointerInside: { inside },
    schedule: { delay, action in
      if delay != 1.0 / 30.0 { fatalError("wrong release interval") }
      release.append(action); return {}
    })
  func event(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: 12, y: 12), modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 0, clickCount: 1, pressure: 1)!
  }
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  try check(short == 0 && router.isTracking && release.count == 1, "synthetic up toggled work")
  hold[0]()
  try check(long == 1 && short == 0, "long did not fire while physical button held")
  buttons = 0
  release[0]()
  try check(!router.isTracking && short == 0 && long == 1, "long physical release toggled work")
  buttons = 2
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  buttons = 0
  release[1]()
  hold[1]()
  try check(short == 1 && long == 1, "short physical release/stale hold failed")
  buttons = 2
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  inside = false
  release[2]()
  hold[2]()
  try check(short == 1 && long == 1 && !router.isTracking, "pointer escape retained press")
  inside = true
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  router.cancel()
  release[3]()
  try check(release.count == 4 && !router.isTracking, "cancelled watcher rescheduled")
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  for _ in 0..<300 { release.last?() }
  try check(!router.isTracking && short == 1 && long == 1 && release.count <= 304,
    "stuck physical button did not stop bounded watcher")
  _ = router.handle(event(.rightMouseDown))
  _ = router.handle(event(.rightMouseUp))
  buttons = 0 // Released just before .5, but long timer is delivered before next release check.
  hold.last?()
  release.last?()
  try check(short == 2 && long == 1 && !router.isTracking,
    "release just before threshold lost short click")
  router.stop()
}

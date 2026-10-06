import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  let bridge = CoreBridge()
  let dashboard = DashboardController()
  let popover = NSPopover()
  var item: NSStatusItem!
  var settingsController: SettingsController?
  var desiredOn = false
  var suspension = SuspensionTracker()
  var suspended: Bool { suspension.active }
  var timer: Timer?
  var lastCount = 0
  var captureBusy = false
  var afterLaunch: (() -> Void)?
  var lastGeneration: UInt64 = 0
  var clipboardBlocked = false
  var clipboardBoard: NSPasteboard = .general
  let dev =
    (CommandLine.arguments.contains("--dev") || CommandLine.arguments.contains("--qa-transfer")
      || CommandLine.arguments.contains("--qa-idle"))
    || ProcessInfo.processInfo.environment["WORKLINK_DEV"] == "1"
    || Bundle.main.object(forInfoDictionaryKey: "WorklinkDevelopment") as? Bool == true
  var root: URL {
    if let path = ProcessInfo.processInfo.environment["WORKLINK_DATA_DIR"] ?? Bundle.main.object(
      forInfoDictionaryKey: "WorklinkDataDirectory") as? String
    {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      ".local/share/\(dev ? "worklink-dev" : "worklink")", isDirectory: true)
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.target = self
    item.button?.action = #selector(statusClicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    popover.contentViewController = dashboard
    popover.contentSize = DashboardController.panelSize
    popover.behavior = .transient
    dashboard.clipboardCount = { [weak self] in self?.clipboardBoard.changeCount ?? 0 }
    dashboard.toggle = { [weak self] in self?.toggle() }
    dashboard.settings = { [weak self] in self?.showSettings() }
    dashboard.quit = { NSApp.terminate(nil) }
    dashboard.open = { [weak self] port in self?.open(port) }
    dashboard.copy = { [weak self] job in self?.copy(job) }
    dashboard.retry = { [weak self] job in
      self?.bridge.send("retry", ["job_id": job.id], reply: { [weak self] r in self?.result(r) })
    }
    dashboard.titleRefresh = { [weak self] port in
      self?.bridge.send("title", ["port_id": port.id], reply: { [weak self] r in self?.result(r) })
    }
    bridge.onState = { [weak self] state in self?.update(state) }
    bridge.onError = { [weak self] error in
      guard let self else { return }
      if !bridge.isRunning {
        desiredOn = false
        stopTimer()
      }
      notice("오류 · \(error)")
    }
    bridge.onComplete = { [weak self] job in self?.complete(job) }
    do {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent("staging"), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      guard let binary = Bundle.main.url(forResource: "worklink", withExtension: nil) else {
        throw NSError(
          domain: "Worklink", code: 1, userInfo: [NSLocalizedDescriptionKey: "번들에 연결 코어가 없습니다"])
      }
      try bridge.start(binary: binary, dataDirectory: root)
    } catch { notice("오류 · \(error.localizedDescription)") }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(pause), name: NSWorkspace.willSleepNotification, object: nil)
    center.addObserver(
      self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(pause), name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(resume), name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(pause), name: NSNotification.Name("com.apple.screenIsLocked"),
      object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(resume), name: NSNotification.Name("com.apple.screenIsUnlocked"),
      object: nil)
    updateIcon()
    if !dev && UserDefaults.standard.object(forKey: "worklink.loginEnabled") as? Bool != false {
      setLogin(true, remember: false)
    }
    afterLaunch?()
  }
  @objc func statusClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp { toggle() } else { showMenu() }
  }
  func showMenu() {
    guard let button = item.button else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    if let state = bridge.state { dashboard.render(state) }
    dashboard.resetScroll()
    popover.contentSize = DashboardController.panelSize
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }
  func toggle() {
    desiredOn.toggle()
    clipboardBlocked = false
    if desiredOn && bridge.state?.config.imageHost.isEmpty != false {
      desiredOn = false
      notice("이미지 전송 SSH 대상을 먼저 등록해 주세요.")
      showSettings()
      return
    }
    bridge.send("toggle", ["on": desiredOn && !suspended])
    if !desiredOn { stopTimer() }
    updateIcon()
  }
  func update(_ state: CoreState) {
    if state.on && desiredOn && !suspended && !clipboardBlocked {
      if timer == nil || lastGeneration != state.generation {
        stopTimer()
        lastCount = clipboardBoard.changeCount
        lastGeneration = state.generation
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.observeClipboard() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
      }
    } else {
      stopTimer()
    }
    updateIcon()
    if popover.isShown { dashboard.render(state) }
    settingsController?.refresh()
  }
  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
  func updateIcon() {
    guard item != nil else { return }
    let state = bridge.state
    let problem =
      state?.hosts.contains(where: { $0.status == "blocked" || $0.status == "backoff" }) == true
      || state?.ports.contains(where: { $0.status == "conflict" }) == true
      || dashboard.notice.hasPrefix("오류")
    let symbol =
      !desiredOn
      ? "link" : suspended ? "moon.circle" : problem ? "exclamationmark.circle" : "link.circle.fill"
    let image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: "Worklink \(desiredOn ? "ON" : "OFF")")
    image?.isTemplate = true
    item.button?.image = image
    item.button?.alphaValue = desiredOn ? 1 : 0.65
    item.button?.toolTip =
      "Worklink · \(suspended ? "잠금/절전 일시 정지" : desiredOn ? "업무 ON" : "업무 OFF") · 좌클릭 목록 / 우클릭 전환"
  }
  func notice(_ text: String) {
    dashboard.notice = text
    updateIcon()
    if let state = bridge.state, popover.isShown { dashboard.render(state) }
    settingsController?.message(text)
  }
  func result(_ r: [String: Any]) {
    if let error = r["error"] as? String { notice("오류 · \(error)") }
  }
  func observeClipboard() {
    guard !captureBusy, desiredOn, !suspended, let state = bridge.state, state.on else { return }
    let board = clipboardBoard
    let count = board.changeCount
    if count == lastCount { return }
    lastCount = count
    autoreleasepool {
      do {
        guard
          let snapshot = try ClipboardReader.read(board, maximum: state.config.limits.imageBytes)
        else { return }
        let path = root.appendingPathComponent("staging/\(identifier()).\(snapshot.ext)")
        try snapshot.bytes.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        captureBusy = true
        bridge.send(
          "upload",
          ["path": path.path, "extension": snapshot.ext, "clipboard_count": snapshot.count],
          reply: { [weak self] r in
            try? FileManager.default.removeItem(at: path)
            self?.captureBusy = false
            self?.result(r)
          })
        notice("원본 이미지 전송 중…")
      } catch ClipboardFailure.denied {
        clipboardBlocked = true
        stopTimer()
        notice("오류 · 클립보드 접근이 거부됐습니다. 시스템 설정에서 Worklink의 붙여넣기 접근을 허용해 주세요.")
      } catch ClipboardFailure.changed { lastCount = board.changeCount - 1 } catch ClipboardFailure
        .tooLarge
      { notice("오류 · 원본 이미지 크기 제한을 초과했습니다. 설정에서 용량을 늘릴 수 있습니다.") } catch ClipboardFailure.unreadable
      {
        clipboardBlocked = true
        stopTimer()
        notice("오류 · 원본 클립보드를 읽지 못했습니다. 접근 허용 후 업무 OFF/ON으로 다시 확인해 주세요.")
      } catch { notice("오류 · 전송 준비 실패: \(error.localizedDescription)") }
    }
  }
  func complete(_ job: ImageJob) {
    guard let path = job.remotePath, let count = job.clipboardCount, let state = bridge.state else {
      return
    }
    let allowed =
      desiredOn && !suspended && state.on && state.generation == job.generation
      && state.config.imageHost == job.host
    if ClipboardReader.replaceWithPath(
      path, board: clipboardBoard, expectedCount: count, allowed: allowed)
    {
      lastCount = clipboardBoard.changeCount
      dashboard.copied = [job.id]
      dashboard.copiedCount = clipboardBoard.changeCount
      notice("붙여넣기 준비됨 · 원격 경로를 복사했습니다.")
    } else {
      notice("전송 완료 · 클립보드가 바뀌어 경로 복사를 생략했습니다.")
    }
  }
  func copy(_ job: ImageJob) {
    bridge.send(
      "copy_path", ["job_id": job.id],
      reply: { [weak self] r in
        guard let self else { return }
        if let error = r["error"] as? String {
          if error.contains("만료") { dashboard.expired.insert(job.id) }
          notice("오류 · \(error)")
          return
        }
        guard let path = r["result"] as? String else { return }
        clipboardBoard.clearContents()
        clipboardBoard.setString(path, forType: .string)
        lastCount = clipboardBoard.changeCount
        dashboard.copied = [job.id]
        dashboard.copiedCount = clipboardBoard.changeCount
        notice("붙여넣기 준비됨 · 경로를 다시 복사했습니다.")
      })
  }
  func open(_ port: PortConfig) {
    guard desiredOn, bridge.state?.on == true else {
      notice("업무 모드를 켜 주세요. 우클릭으로 전환할 수 있습니다.")
      return
    }
    guard let status = bridge.state?.ports.first(where: { $0.id == port.id }),
      status.status == "ready", let url = port.endpoint.localURL(port.localPort)
    else {
      notice("서버가 아직 준비되지 않았습니다. 포트 상태와 연결을 확인해 주세요.")
      return
    }
    NSWorkspace.shared.open(url)
  }
  func showSettings() {
    popover.performClose(nil)
    if settingsController == nil {
      let controller = SettingsController(
        bridge: bridge, loginEnabled: !dev && SMAppService.mainApp.status == .enabled)
      controller.loginChange = { [weak self] on in self?.setLogin(on) }
      controller.install = { [weak self] host in self?.installHelper(host) }
      settingsController = controller
    }
    settingsController?.present()
  }
  func installHelper(_ host: String) {
    bridge.send(
      "install_remote", ["input": host, "path": Bundle.main.resourceURL?.path ?? ""],
      reply: { [weak self] r in
        self?.result(r)
        if r["error"] == nil { self?.notice("원격 헬퍼와 일일 정리 작업을 설치했습니다.") }
      })
  }
  func setLogin(_ on: Bool, remember: Bool = true) {
    if dev {
      notice("개발 모드에서는 로그인 항목을 변경하지 않습니다.")
      return
    }
    if remember { UserDefaults.standard.set(on, forKey: "worklink.loginEnabled") }
    do {
      if on && SMAppService.mainApp.status == .notRegistered {
        try SMAppService.mainApp.register()
      } else if !on && SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      }
      if on && SMAppService.mainApp.status == .requiresApproval {
        notice("로그인 시작 · 시스템 설정의 로그인 항목에서 Worklink를 허용해 주세요.")
      }
    } catch { notice("로그인 시작 설정 · 앱을 Applications에 설치한 뒤 확인해 주세요: \(error.localizedDescription)") }
  }
  @objc func pause(_ notification: Notification) {
    let reason =
      notification.name == NSWorkspace.willSleepNotification
      ? "sleep"
      : notification.name == NSWorkspace.sessionDidResignActiveNotification ? "session" : "lock"
    suspension.pause(reason)
    stopTimer()
    if desiredOn { bridge.send("toggle", ["on": false]) }
    notice("잠금/절전 중 감시를 멈췄습니다.")
  }
  @objc func resume(_ notification: Notification) {
    let reason =
      notification.name == NSWorkspace.didWakeNotification
      ? "sleep"
      : notification.name == NSWorkspace.sessionDidBecomeActiveNotification ? "session" : "lock"
    let wasSuspended = suspended
    suspension.resume(reason)
    if wasSuspended && !suspended {
      lastCount = clipboardBoard.changeCount
      if desiredOn { bridge.send("toggle", ["on": true]) }
    }
    updateIcon()
  }
  func applicationWillTerminate(_ notification: Notification) {
    stopTimer()
    bridge.stop()
  }
}

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
  CommandLine.arguments.count > index + 1
{
  do {
    try renderPreviews(URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
    exit(0)
  } catch {
    fputs("\(error)\n", stderr)
    exit(1)
  }
} else if CommandLine.arguments.contains("--self-test") {
  do {
    try nativeSelfTest()
    exit(0)
  } catch {
    fputs("\(error)\n", stderr)
    exit(1)
  }
} else {
  let delegate = AppDelegate()
  app.delegate = delegate
  if CommandLine.arguments.contains("--qa-transfer") {
    delegate.afterLaunch = { [weak delegate] in
      guard let delegate else { return }
      do { try configureNativeTransferQA(delegate) } catch {
        fputs("QA setup failed: \(error)\n", stderr)
        NSApp.terminate(nil)
      }
    }
  }
  if CommandLine.arguments.contains("--qa-idle") {
    Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in NSApp.terminate(nil) }
  }
  withExtendedLifetime(delegate) { app.run() }
}

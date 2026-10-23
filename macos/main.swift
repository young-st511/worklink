import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  let bridge = CoreBridge()
  let dashboard = DashboardController()
  let popover = NSPopover()
  var item: NSStatusItem!
  var statusInput: StatusFileDropView?
  var settingsController: SettingsController?
  var desiredOn = false
  var suspension = SuspensionTracker()
  var suspended: Bool { suspension.active }
  var environmentMonitor: NetworkPowerMonitor?
  var timer: Timer?
  var lastCount = 0
  var captureBusy = false
  var afterLaunch: (() -> Void)?
  var lastGeneration: UInt64 = 0
  var clipboardBlocked = false
  lazy var clipboardPreferences = ClipboardPreferences(
    defaults: dev ? UserDefaults(suiteName: "dev.worklink.development")! : .standard)
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
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseDown, .rightMouseUp])
    if let button = item.button {
      let drop = StatusFileDropView(frame: button.bounds)
      drop.autoresizingMask = [.width, .height]
      drop.receive = { [weak self] urls in self?.sendFiles(urls) ?? false }
      drop.clicked = { [weak self] in self?.showMenu() }
      drop.rightClicked = { [weak self] in self?.toggle() }
      drop.rightHeld = { [weak self] in
        guard let self, !self.suspended else { return }
        self.setClipboardMode(!self.clipboardPreferences.preservesImage)
      }
      statusInput = drop
      button.addSubview(drop)
    }
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
    popover.contentViewController = dashboard
    popover.contentSize = DashboardController.panelSize
    popover.behavior = .transient
    dashboard.clipboardCount = { [weak self] in self?.clipboardBoard.changeCount ?? 0 }
    dashboard.sendFiles = { [weak self] in self?.chooseFiles() }
    dashboard.copyFile = { [weak self] f in self?.copyFile(f) }
    dashboard.cancelFiles = { [weak self] in self?.bridge.send("cancel_files") }
    dashboard.undoPortCleanup = { [weak self] in
      self?.bridge.send(
        "undo_port_cleanup",
        reply: { [weak self] r in
          if let error = r["error"] as? String {
            self?.notice("오류 · \(error)")
          } else {
            self?.notice("포트를 복원하고 고정했습니다. 상세에서 고정을 풀 수 있습니다.")
          }
        })
    }
    dashboard.pinPort = { [weak self] port in
      self?.bridge.send(
        "pin_port", ["port_id": port.id, "on": port.pinned != true],
        reply: { [weak self] r in self?.result(r) })
    }
    dashboard.refreshPorts = { [weak self] in
      self?.bridge.send("refresh_ports", reply: { [weak self] r in self?.result(r) })
    }
    dashboard.toggle = { [weak self] in self?.toggle() }
    dashboard.settings = { [weak self] in self?.showSettings() }
    dashboard.quit = { NSApp.terminate(nil) }
    dashboard.open = { [weak self] port in self?.open(port) }
    dashboard.preservesImage = clipboardPreferences.preservesImage
    dashboard.changeClipboardMode = { [weak self] on in self?.setClipboardMode(on) }
    dashboard.restore = { [weak self] job in self?.restore(job) }
    dashboard.copy = { [weak self] job in self?.copy(job) }
    dashboard.retry = { [weak self] job in
      self?.bridge.send("retry", ["job_id": job.id], reply: { [weak self] r in self?.result(r) })
    }
    dashboard.registerQuick = { [weak self] input, host in
      self?.registerQuickPort(input, host: host)
    }
    dashboard.titleRefresh = { [weak self] port in
      self?.bridge.send("title", ["port_id": port.id], reply: { [weak self] r in self?.result(r) })
    }
    bridge.onState = { [weak self] state in self?.update(state) }
    bridge.onError = { [weak self] error in
      guard let self else { return }
      if !bridge.isRunning {
        desiredOn = false
        environmentMonitor?.stop(notify: false)
        environmentMonitor = nil
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
      environmentMonitor = NetworkPowerMonitor { [weak self] available, lowPower in
        self?.bridge.send("environment", ["available": available, "low_power": lowPower])
      }
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
    switch NSApp.currentEvent?.type {
    case .rightMouseDown: statusInput?.rightPress.begin()
    case .rightMouseUp: statusInput?.rightPress.end()
    default: showMenu()
    }
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
  func setClipboardMode(_ on: Bool) {
    clipboardPreferences.preservesImage = on
    dashboard.preservesImage = on
    updateIcon()
    if let state = bridge.state { dashboard.render(state) }
    popover.contentSize = DashboardController.panelSize
  }
  func registerQuickPort(_ input: String, host: String) {
    guard !dashboard.quickBusy else { return }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      dashboard.finishQuickRegistration("포트 또는 URL을 입력해 주세요.", success: false)
      return
    }
    guard bridge.state?.config.hosts.contains(where: { $0.name == host }) == true else {
      dashboard.finishQuickRegistration("등록할 SSH 대상을 먼저 선택해 주세요.", success: false)
      return
    }
    dashboard.beginQuickRegistration()
    bridge.send(
      "parse", ["input": input],
      reply: { [weak self] reply in
        guard let self else { return }
        func fail(_ message: String) { dashboard.finishQuickRegistration(message, success: false) }
        if let error = reply["error"] as? String {
          fail(error)
          return
        }
        guard let parsed = reply["result"] as? [String: Any] else {
          fail("주소를 확인하지 못했습니다.")
          return
        }
        if let candidates = parsed["candidates"] as? [String], !candidates.isEmpty {
          fail("포트나 URL 하나만 입력해 주세요.")
          return
        }
        if let error = parsed["error"] as? String, !error.isEmpty {
          fail(error)
          return
        }
        if parsed["needs_port"] as? Bool == true {
          fail("포트 번호를 추가해 주세요. 예: localhost:5173")
          return
        }
        guard let endpoint = parsed["endpoint"],
          let bytes = try? JSONSerialization.data(withJSONObject: endpoint),
          let address = try? decoder().decode(EndpointConfig.self, from: bytes)
        else {
          fail("주소를 확인하지 못했습니다.")
          return
        }
        guard var config = bridge.state?.config, config.hosts.contains(where: { $0.name == host })
        else {
          fail("SSH 대상이 변경됐습니다. 다시 선택해 주세요.")
          return
        }
        config.ports.append(
          PortConfig(
            id: identifier(), name: "", host: host, endpoint: address,
            localPort: address.remotePort, enabled: true, title: nil))
        bridge.send(
          "save_config", ["config": jsonObject(config)],
          reply: { [weak self] result in
            guard let self else { return }
            if let error = result["error"] as? String {
              dashboard.finishQuickRegistration(error, success: false)
              return
            }
            let removed = (result["result"] as? [String: Any])?["removed_port"] as? [String: Any]
            let replaced = (removed?["local_port"] as? Int).map { " · 비활성 포트 \($0) 정리" } ?? ""
            dashboard.finishQuickRegistration(
              "\(host) · 원격 포트 \(address.remotePort) 등록 완료\(replaced)", success: true)
          })
      })
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
    if desiredOn && !suspended { environmentMonitor?.start() } else { environmentMonitor?.stop() }
    bridge.send("toggle", ["on": desiredOn && !suspended])
    if !desiredOn { stopTimer() }
    updateIcon()
  }
  func update(_ state: CoreState) {
    if desiredOn && !suspended { environmentMonitor?.start() } else { environmentMonitor?.stop() }
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
    let networkWaiting = state?.networkUnavailable == true
    let mode: MenuBarGlyph.Mode =
      !desiredOn ? .off : suspended || networkWaiting ? .paused : problem ? .problem : .on
    let preservesImage = clipboardPreferences.preservesImage
    item.button?.image = MenuBarGlyph.image(for: mode, preservesImage: preservesImage)
    item.button?.alphaValue = desiredOn ? 1 : 0.65
    let status =
      suspended
      ? "잠금/절전 일시 정지"
      : !desiredOn ? "업무 OFF" : networkWaiting ? "네트워크 연결 대기" : problem ? "연결 또는 전송 오류" : "업무 ON"
    let powerMode = state?.lowPower == true ? " · 저전력 모드" : ""
    let clipboardMode = preservesImage ? "캡처 원본 유지" : "원격 경로 자동 복사"
    item.button?.toolTip = "Worklink · \(status)\(powerMode) · \(clipboardMode) · 좌클릭 목록 / 우클릭 업무 전환 / 우클릭 0.5초 사진 모드"
    item.button?.setAccessibilityLabel("Worklink")
    item.button?.setAccessibilityValue("\(status) · \(clipboardMode)")
    item.button?.setAccessibilityHelp("좌클릭으로 목록을 열고 짧은 우클릭으로 업무 모드를 전환합니다. 우클릭을 0.5초 누르면 캡처 원본 유지 모드를 전환합니다.")
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
    if dashboard.clearCopiedIfChanged(count), popover.isShown { dashboard.render(state) }
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
    switch clipboardPreferences.complete(
      path, board: clipboardBoard, expectedCount: count, allowed: allowed)
    {
    case .pathCopied:
      lastCount = clipboardBoard.changeCount
      dashboard.copied = [job.id]
      dashboard.copiedCount = clipboardBoard.changeCount
      notice("붙여넣기 준비됨 · 원격 경로를 복사했습니다.")
    case .originalKept:
      notice("전송 완료 · 캡처 원본 유지 중. 필요할 때 경로를 복사하세요.")
    case .clipboardUnchanged:
      notice("전송 완료 · 클립보드나 업무 상태가 바뀌어 경로 복사를 생략했습니다.")
    }
  }
  func restore(_ job: ImageJob) {
    guard dashboard.restoring == nil, desiredOn, !suspended, let state = bridge.state, state.on
    else { return }
    let count = clipboardBoard.changeCount
    let generation = state.generation
    dashboard.restoring = job.id
    notice("원본 이미지 가져오는 중…")
    bridge.send(
      "restore_original", ["job_id": job.id],
      reply: { [weak self] response in
        let result = response["result"] as? [String: Any]
        let path = (result?["path"] as? String).map { URL(fileURLWithPath: $0) }
        defer { if let path { try? FileManager.default.removeItem(at: path) } }
        guard let self else { return }
        dashboard.restoring = nil
        if let error = response["error"] as? String {
          if error.contains("만료") { dashboard.expired.insert(job.id) }
          notice("오류 · \(error)")
          return
        }
        guard let path, let ext = result?["extension"] as? String else {
          notice("오류 · 원본 응답을 읽지 못했습니다.")
          return
        }
        do {
          let bytes = try Data(contentsOf: path, options: .mappedIfSafe)
          let allowed =
            desiredOn && !suspended && bridge.state?.on == true
            && bridge.state?.networkUnavailable != true
            && bridge.state?.generation == generation
          guard
            ClipboardReader.restore(
              bytes, extension: ext, board: clipboardBoard, expectedCount: count, allowed: allowed)
          else {
            notice("원본 복사 생략 · 클립보드나 업무 상태가 바뀌었습니다.")
            return
          }
          lastCount = clipboardBoard.changeCount
          dashboard.copied.removeAll()
          dashboard.copiedCount = nil
          notice("원본 이미지를 복사했습니다. 로컬 앱에 붙여넣을 수 있습니다.")
        } catch { notice("오류 · 원본 복사 실패: \(error.localizedDescription)") }
      })
  }
  func copy(_ job: ImageJob) {
    let count = clipboardBoard.changeCount
    let generation = bridge.state?.generation
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
        let allowed =
          desiredOn && !suspended && bridge.state?.on == true
          && bridge.state?.networkUnavailable != true
          && bridge.state?.generation == generation
        guard
          ClipboardReader.replaceWithPath(
            path, board: clipboardBoard, expectedCount: count, allowed: allowed)
        else {
          notice("경로 복사 생략 · 클립보드나 업무 상태가 바뀌었습니다.")
          return
        }
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
    guard bridge.state?.networkUnavailable != true,
      let status = bridge.state?.ports.first(where: { $0.id == port.id }),
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
    statusInput?.rightPress.cancel()
    suspension.pause(reason)
    stopTimer()
    if desiredOn { bridge.send("toggle", ["on": false]) }
    environmentMonitor?.stop()
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
      if desiredOn {
        environmentMonitor?.start()
        bridge.send("toggle", ["on": true])
      }
    }
    updateIcon()
  }
  func applicationWillTerminate(_ notification: Notification) {
    statusInput?.rightPress.cancel()
    environmentMonitor?.stop(notify: false)
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

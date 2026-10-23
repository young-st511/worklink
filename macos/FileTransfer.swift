import AppKit

// File URLs take precedence over Finder's optional thumbnail image representations.
enum FileSelection {
  static func urls(_ board: NSPasteboard) -> [URL] {
    if let values = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !values.isEmpty
    {
      return values.filter { $0.isFileURL }
    }
    let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    return (board.propertyList(forType: legacy) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
  }
}

final class StatusFileDropView: NSView {
  var receive: (([URL]) -> Bool)?
  var clicked: (() -> Void)?
  var rightClicked: (() -> Void)?
  var rightHeld: (() -> Void)?
  lazy var rightPress = RightClickHold(
    short: { [weak self] in self?.rightClicked?() },
    long: { [weak self] in self?.rightHeld?() },
    isHeld: { [weak self] in
      guard let self, let window = self.window, NSEvent.pressedMouseButtons & 2 != 0 else { return false }
      return self.bounds.contains(self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    })
  private var dragging = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func mouseDown(with event: NSEvent) { rightPress.cancel() }
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { clicked?() }
  }
  override func rightMouseDown(with event: NSEvent) { rightPress.begin() }
  override func rightMouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { rightPress.end() }
    else { rightPress.cancel() }
  }
  override func rightMouseDragged(with event: NSEvent) {
    if !bounds.contains(convert(event.locationInWindow, from: nil)) { rightPress.cancel() }
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { rightPress.cancel() }
    super.viewWillMove(toWindow: newWindow)
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    rightPress.cancel()
    dragging = !FileSelection.urls(sender.draggingPasteboard).isEmpty
    needsDisplay = true
    return dragging ? .copy : []
  }
  override func draggingExited(_ sender: NSDraggingInfo?) {
    dragging = false
    needsDisplay = true
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    dragging = false
    needsDisplay = true
    let urls = FileSelection.urls(sender.draggingPasteboard)
    return !urls.isEmpty && (receive?(urls) ?? false)
  }
  override func draw(_ dirtyRect: NSRect) {
    if dragging {
      NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
  }
}

extension AppDelegate {
  var fileSendProblem: String? {
    guard desiredOn, !suspended, let state = bridge.state, state.on else { return "업무 모드를 켜 주세요." }
    if state.networkUnavailable == true { return "네트워크 연결을 기다려 주세요." }
    guard
      state.hosts.contains(where: { $0.host == state.config.imageHost && $0.status == "connected" })
    else { return "전송 대상의 SSH 연결을 기다려 주세요." }
    return nil
  }
  func chooseFiles() {
    if let problem = fileSendProblem {
      notice("오류 · \(problem)")
      return
    }
    popover.performClose(nil)
    let panel = NSOpenPanel()
    panel.title = "Worklink로 파일 보내기"
    panel.prompt = "보내기"
    panel.message = "전송 대상에 일반 파일을 원본 그대로 보냅니다. 최대 8개 · 파일당 256 MiB"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = false
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] response in if response == .OK { _ = self?.sendFiles(panel.urls) } }
  }
  @objc(sendFiles:userData:error:)
  func sendFilesService(
    _ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) {
    let urls = FileSelection.urls(board)
    if let problem = fileSendProblem {
      error?.pointee = problem as NSString
      return
    }
    guard !urls.isEmpty else {
      error?.pointee = "일반 파일을 선택해 주세요."
      return
    }
    if !sendFiles(urls) { error?.pointee = "파일을 보내지 못했습니다. Worklink 메뉴에서 확인해 주세요." }
  }
  @discardableResult
  func sendFiles(_ urls: [URL]) -> Bool {
    if let problem = fileSendProblem {
      notice("오류 · \(problem)")
      return false
    }
    guard !urls.isEmpty, urls.count <= 8, urls.allSatisfy({ $0.isFileURL }) else {
      notice("오류 · 한 번에 일반 파일 1~8개를 선택해 주세요.")
      return false
    }
    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
    let count = clipboardBoard.changeCount
    let generation = bridge.state?.generation
    notice("파일 \(urls.count)개 전송 준비 중…")
    bridge.send("send_files", ["paths": urls.map { $0.path }]) { [weak self] reply in
      defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
      guard let self else { return }
      if let error = reply["error"] as? String {
        notice("오류 · \(error) · 완료한 파일은 최근 파일에서 경로를 복사할 수 있습니다.")
        return
      }
      let files = reply["result"] as? [[String: Any]] ?? []
      let paths = files.compactMap { $0["path"] as? String }
      guard !paths.isEmpty else { return }
      let allowed =
        desiredOn && !suspended && bridge.state?.on == true
        && bridge.state?.networkUnavailable != true
        && bridge.state?.generation == generation
      if ClipboardReader.replaceWithPath(
        paths.joined(separator: "\n"), board: clipboardBoard, expectedCount: count, allowed: allowed
      ) {
        lastCount = clipboardBoard.changeCount
        dashboard.copied.removeAll()
        dashboard.copiedCount = nil
        notice("파일 \(paths.count)개 완료 · 원격 경로를 복사했습니다.")
      } else {
        notice("파일 \(paths.count)개 완료 · 클립보드가 바뀌어 경로 복사를 생략했습니다.")
      }
    }
    return true
  }
  func copyFile(_ file: FileTransfer) {
    let count = clipboardBoard.changeCount
    let generation = bridge.state?.generation
    bridge.send("copy_file_path", ["job_id": file.id]) { [weak self] reply in
      guard let self else { return }
      if let error = reply["error"] as? String {
        notice("오류 · \(error)")
        return
      }
      guard let path = reply["result"] as? String else { return }
      let allowed =
        desiredOn && !suspended && bridge.state?.on == true
        && bridge.state?.networkUnavailable != true
        && bridge.state?.generation == generation
      if ClipboardReader.replaceWithPath(
        path, board: clipboardBoard, expectedCount: count, allowed: allowed)
      {
        lastCount = clipboardBoard.changeCount
        dashboard.copied.removeAll()
        dashboard.copiedCount = nil
        notice("붙여넣기 준비됨 · 파일 경로를 복사했습니다.")
      } else {
        notice("경로 복사 생략 · 클립보드나 업무 상태가 바뀌었습니다.")
      }
    }
  }
}

extension DashboardController {
  func fileSections(_ state: CoreState) -> [NSView] {
    let send = ActionButton("파일 보내기…") { [weak self] in self?.sendFiles?() }
    send.controlSize = .small
    send.font = .systemFont(ofSize: 10)
    send.toolTip = "메뉴바 아이콘에 드롭하거나 Finder → 서비스 → Worklink로 보내기도 사용할 수 있습니다."
    let active = (state.files ?? []).contains { $0.status == "sending" || $0.status == "preparing" }
    let connected = state.hosts.contains {
      $0.host == state.config.imageHost && $0.status == "connected"
    }
    send.setDisabledReason(
      !state.on
        ? "업무 모드를 켜 주세요." : !connected ? "전송 대상의 SSH 연결을 기다려 주세요." : active ? "파일 전송 중입니다." : nil)
    if send.isEnabled { send.toolTip = "최대 8개 · 파일당 256 MiB · 메뉴바 드롭 / Finder 서비스도 지원합니다." }
    var heading: [NSView] = [
      label("최근 파일", size: 11, color: .secondaryLabelColor, bold: true), NSView(), send,
    ]
    if (state.files?.count ?? 0) > 3 {
      let more = ActionButton(showsAllFiles ? "접기" : "전체 \(state.files?.count ?? 0)개") {
        [weak self] in
        guard let self else { return }
        self.showsAllFiles.toggle()
        self.refreshFileLayout()
      }
      more.font = .systemFont(ofSize: 10)
      heading.append(more)
    }
    if active { heading.append(ActionButton("취소") { [weak self] in self?.cancelFiles?() }) }
    let row = horizontal(heading)
    row.distribution = .fill
    row.widthAnchor.constraint(equalToConstant: 344).isActive = true
    row.heightAnchor.constraint(equalToConstant: 24).isActive = true
    var sections: [NSView] = [row]
    for file in (state.files ?? []).prefix(showsAllFiles ? 8 : 3) {
      let name = label(file.name, size: 10.5)
      name.maximumNumberOfLines = 1
      name.lineBreakMode = .byTruncatingMiddle
      name.widthAnchor.constraint(equalToConstant: 190).isActive = true
      name.toolTip = "\(file.name) · \(file.host) · \(fileSize(file.size))"
      let text =
        file.status == "sending"
        ? (file.size > 0 ? "\(min(100, file.sent * 100 / file.size))%" : "전송 중")
        : ["preparing": "준비 중", "complete": "완료", "cancelled": "중단", "failed": "실패"][file.status]
          ?? file.status
      let status = label(
        text, size: 10, color: file.error == nil ? .secondaryLabelColor : .systemRed)
      status.maximumNumberOfLines = 1
      status.widthAnchor.constraint(equalToConstant: 108).isActive = true
      status.toolTip = file.error ?? "\(text) · \(fileSize(file.size))"
      let copy = ActionButton("파일 경로 복사") { [weak self] in self?.copyFile?(file) }
      let available =
        state.on && state.hosts.contains { $0.host == file.host && $0.status == "connected" }
      copy.setDisabledReason(
        file.status != "complete"
          ? "전송이 완료되면 복사할 수 있습니다." : !available ? "업무 ON 후 파일의 SSH 대상에 연결해 주세요." : nil)
      if copy.isEnabled { copy.toolTip = "파일 경로 복사" }
      copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "파일 경로 복사")
      copy.imagePosition = .imageOnly
      copy.setAccessibilityLabel("\(file.name) 경로 복사")
      copy.widthAnchor.constraint(equalToConstant: 28).isActive = true
      copy.heightAnchor.constraint(equalToConstant: 24).isActive = true
      let row = horizontal([name, status, NSView(), copy], spacing: 4)
      row.widthAnchor.constraint(equalToConstant: 344).isActive = true
      row.heightAnchor.constraint(equalToConstant: 28).isActive = true
      row.identifier = NSUserInterfaceItemIdentifier("file-row-\(file.id)")
      sections.append(row)
    }
    sections.append(separator())
    return sections
  }
}

import AppKit

final class AppearanceBackgroundView: NSView {
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

final class MenuWorkSwitch: NSSwitch {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DashboardController: NSViewController, NSTextFieldDelegate {
  static let panelSize = NSSize(width: 380, height: 460)
  private(set) var bodyScroll: NSScrollView?
  private var pinnedHeader: NSView?
  private var pinnedFooter: NSView?
  var headerFrame: NSRect { pinnedHeader?.frame ?? .zero }
  var footerFrame: NSRect { pinnedFooter?.frame ?? .zero }
  func resetScroll() {
    bodyScroll?.contentView.scroll(to: .zero)
    if let bodyScroll { bodyScroll.reflectScrolledClipView(bodyScroll.contentView) }
  }

  var toggle: (() -> Void)?
  var settings: (() -> Void)?
  var quit: (() -> Void)?
  var restore: ((ImageJob) -> Void)?
  var restoring: String?
  var preservesImage = false
  var changeClipboardMode: ((Bool) -> Void)?
  var copy: ((ImageJob) -> Void)?
  var retry: ((ImageJob) -> Void)?
  var titleRefresh: ((PortConfig) -> Void)?
  var open: ((PortConfig) -> Void)?
  var notice = ""
  var copied: Set<String> = []
  var copiedCount: Int?
  var clipboardCount: () -> Int = { NSPasteboard.general.changeCount }
  var expired: Set<String> = []
  var expanded: Set<String> = []
  private var lastState: CoreState?
  private var layoutConstraints: [NSLayoutConstraint] = []
  private var bodyStack: NSStackView?
  private var bodyContent: FlippedView?
  let quickAddress = NSTextField()
  let quickHost = NSPopUpButton()
  var registerQuick: ((String, String) -> Void)?
  private(set) var quickBusy = false
  private(set) var quickError = false
  private var quickMessage = ""
  private var quickHostExplicit = false
  private lazy var quickAdd = ActionButton("등록") { [weak self] in self?.submitQuick() }
  private lazy var quickFeedback = label("", size: 10, color: .secondaryLabelColor)
  private lazy var quickForm: NSStackView = {
    quickAddress.placeholderString = "포트 · localhost URL"
    quickAddress.font = .systemFont(ofSize: 11)
    quickAddress.bezelStyle = .roundedBezel
    quickAddress.setAccessibilityLabel("원격 포트 또는 localhost URL")
    quickHost.setAccessibilityLabel("원격 SSH 대상")
    quickAdd.setAccessibilityLabel("개발 서버 등록")
    quickAddress.delegate = self
    quickAddress.target = self
    quickAddress.action = #selector(submitQuick)
    quickAddress.widthAnchor.constraint(equalToConstant: 166).isActive = true
    quickAddress.heightAnchor.constraint(equalToConstant: 22).isActive = true
    quickHost.font = .systemFont(ofSize: 11)
    quickHost.target = self
    quickHost.action = #selector(quickHostChanged)
    quickHost.widthAnchor.constraint(equalToConstant: 104).isActive = true
    quickHost.heightAnchor.constraint(equalToConstant: 22).isActive = true
    quickAdd.widthAnchor.constraint(equalToConstant: 54).isActive = true
    quickAdd.heightAnchor.constraint(equalToConstant: 22).isActive = true
    quickFeedback.maximumNumberOfLines = 1
    quickFeedback.lineBreakMode = .byTruncatingTail
    quickFeedback.heightAnchor.constraint(equalToConstant: 14).isActive = true
    return vertical([horizontal([quickAddress, quickHost, quickAdd]), quickFeedback], spacing: 4)
  }()
  private var quickInput: String {
    (quickAddress.currentEditor() as? NSTextView)?.string ?? quickAddress.stringValue
  }
  func controlTextDidChange(_ notification: Notification) {
    if (notification.object as? NSTextField) === quickAddress {
      if quickError {
        quickError = false
        quickMessage = ""
      }
      refreshQuickControls()
    }
  }
  @objc private func quickHostChanged() { quickHostExplicit = true }
  @objc private func submitQuick() {
    guard quickAdd.isEnabled, !quickBusy, let host = quickHost.titleOfSelectedItem else { return }
    registerQuick?(quickInput, host)
  }
  func beginQuickRegistration() {
    quickBusy = true
    quickError = false
    quickMessage = "주소 확인·등록 중…"
    refreshQuickControls()
  }
  func finishQuickRegistration(_ message: String, success: Bool) {
    quickBusy = false
    quickError = !success
    quickMessage = message
    if success { quickAddress.stringValue = "" }
    refreshQuickControls()
    if let window = quickAddress.window, window.isKeyWindow {
      window.makeFirstResponder(quickAddress)
    }
  }
  private func refreshQuickControls() {
    _ = quickForm
    let names = lastState?.config.hosts.map { $0.name } ?? []
    let selected = quickHost.titleOfSelectedItem
    let titles = names.isEmpty ? ["SSH 대상 없음"] : names
    if quickHost.itemTitles != titles {
      quickHost.removeAllItems()
      quickHost.addItems(withTitles: titles)
    }
    if quickHostExplicit, let selected, names.contains(selected) {
      quickHost.selectItem(withTitle: selected)
    } else {
      quickHostExplicit = false
      let preferred = lastState?.config.imageHost ?? ""
      if let name = names.contains(preferred) ? preferred : names.first {
        quickHost.selectItem(withTitle: name)
      }
    }
    let inputReason = names.isEmpty ? "SSH 대상을 먼저 등록해 주세요." : quickBusy ? "등록 중입니다." : nil
    quickAddress.isEnabled = inputReason == nil
    quickHost.isEnabled = inputReason == nil
    quickAddress.toolTip = inputReason ?? "예: 5173 또는 localhost:5173/preview"
    quickHost.toolTip = inputReason ?? "등록할 원격 SSH 대상"
    quickAddress.setAccessibilityHelp(inputReason)
    quickHost.setAccessibilityHelp(inputReason)
    let reason =
      inputReason
      ?? (quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "포트 또는 URL을 입력해 주세요." : nil)
    quickAdd.setDisabledReason(reason)
    quickFeedback.stringValue = quickMessage.isEmpty ? "선택한 SSH 대상의 원격 포트를 등록합니다." : quickMessage
    quickFeedback.textColor = quickError ? .systemRed : .secondaryLabelColor
    quickFeedback.toolTip = quickFeedback.stringValue
  }
  override func loadView() {
    view = AppearanceBackgroundView(frame: NSRect(origin: .zero, size: Self.panelSize))
    view.wantsLayer = true
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: Self.panelSize.width),
      view.heightAnchor.constraint(equalToConstant: Self.panelSize.height),
    ])
    preferredContentSize = Self.panelSize
  }
  func render(_ state: CoreState) {
    loadViewIfNeeded()
    lastState = state
    if let copiedCount, copiedCount != clipboardCount() {
      copied.removeAll()
      self.copiedCount = nil
    }
    let scrollOffset = bodyScroll?.contentView.bounds.origin.y ?? 0
    NSLayoutConstraint.deactivate(layoutConstraints)
    view.subviews.filter { $0 !== bodyScroll }.forEach { $0.removeFromSuperview() }
    refreshQuickControls()
    let title = label("Worklink", size: 16, bold: true)
    title.maximumNumberOfLines = 1
    let status = label(
      state.on ? "업무 ON" : "업무 OFF", size: 13, color: .labelColor,
      bold: true)
    status.maximumNumberOfLines = 1
    status.widthAnchor.constraint(equalToConstant: 56).isActive = true
    let workSwitch = MenuWorkSwitch(frame: .zero)
    workSwitch.state = state.on ? .on : .off
    workSwitch.isContinuous = false
    workSwitch.target = self
    workSwitch.action = #selector(toggleWork)
    workSwitch.toolTip =
      state.on ? "업무 모드를 끕니다. 이미지 전달과 서버 연결을 중지합니다." : "업무 모드를 켭니다. 이미지 전달과 등록 서버 연결을 시작합니다."
    workSwitch.setAccessibilityLabel("업무 모드")
    workSwitch.setAccessibilityHelp(workSwitch.toolTip)
    workSwitch.widthAnchor.constraint(equalToConstant: 54).isActive = true
    workSwitch.heightAnchor.constraint(equalToConstant: 24).isActive = true
    let keep = ActionButton("캡처 원본 유지") { [weak self] in
      guard let self else { return }
      self.changeClipboardMode?(!self.preservesImage)
    }
    keep.setButtonType(.switch)
    keep.state = preservesImage ? .on : .off
    keep.font = .systemFont(ofSize: 11)
    keep.heightAnchor.constraint(equalToConstant: 22).isActive = true
    keep.toolTip = "켜면 캡처 원본을 유지하고, 끄면 전송 완료 시 경로를 자동 복사합니다."
    keep.setAccessibilityHelp(keep.toolTip)
    let statusDot = NSImageView(
      image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage())
    statusDot.contentTintColor = state.on ? .systemGreen : .secondaryLabelColor
    statusDot.widthAnchor.constraint(equalToConstant: 6).isActive = true
    statusDot.heightAnchor.constraint(equalToConstant: 6).isActive = true
    let space = NSView()
    let header = horizontal(
      [title, space, keep, horizontal([statusDot, status, workSwitch], spacing: 4)], spacing: 8)
    header.distribution = .fill
    header.heightAnchor.constraint(equalToConstant: 28).isActive = true
    var sections: [NSView] = []
    if !notice.isEmpty {
      sections.append(
        label(
          notice, size: 11,
          color: notice.contains("실패") || notice.contains("오류") ? .systemRed : .secondaryLabelColor)
      )
    }
    if let error = state.error, !error.isEmpty {
      sections.append(label(error, size: 11, color: .systemRed))
    }
    for host in state.hosts {
      if let error = host.error, !error.isEmpty {
        sections.append(label("\(host.host) · \(error)", size: 11, color: .systemRed))
      }
    }
    sections.append(separator())
    let manage = ActionButton("관리…") { [weak self] in self?.settings?() }
    manage.isBordered = false
    manage.font = .systemFont(ofSize: 10)
    manage.contentTintColor = .secondaryLabelColor
    manage.toolTip = "서버 이름·로컬 포트·SSH 대상 설정"
    let headingSpace = NSView()
    let serverHeading = horizontal([
      label("개발 서버", size: 11, color: .secondaryLabelColor, bold: true), headingSpace, manage,
    ])
    serverHeading.distribution = .fill
    serverHeading.widthAnchor.constraint(equalToConstant: 344).isActive = true
    serverHeading.heightAnchor.constraint(equalToConstant: 18).isActive = true
    sections.append(serverHeading)
    sections.append(quickForm)
    if state.config.ports.isEmpty {
      sections.append(label("등록한 서버가 없습니다. URL이나 포트 번호를 붙여넣어 추가하세요.", color: .secondaryLabelColor))
    }
    if !state.config.ports.isEmpty {
      sections.append(
        vertical(state.config.ports.map { compactPortRow($0, state: state) }, spacing: 3))
    }
    sections.append(separator())
    sections.append(
      label(
        "최근 이미지 · \(state.config.imageHost.isEmpty ? "전송 대상 미선택" : state.config.imageHost)",
        size: 11, color: .secondaryLabelColor, bold: true))
    if state.jobs.isEmpty {
      sections.append(label("업무 ON 후 캡처하면 원본을 한 번 전송합니다.", size: 11, color: .secondaryLabelColor))
    }
    for job in state.jobs.prefix(5) {
      let stateText: String
      if expired.contains(job.id) {
        stateText = "원격 파일 만료"
      } else if copied.contains(job.id) {
        stateText = "붙여넣기 준비됨"
      } else {
        stateText =
          [
            "complete": "전송 완료", "sending": "전송 중", "queued": "전송 대기", "paused": "일시 중지",
            "failed": "전송 실패", "expired": "대기 만료",
          ][job.status] ?? job.status
      }
      let date = ISO8601DateFormatter()
      date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let time =
        date.date(from: job.createdAt).map {
          DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
        } ?? "최근"
      let info = label(
        "\(time) · \(job.host) · \(job.extension.uppercased()) · \(fileSize(job.size))", size: 11)
      let action = ActionButton(job.status == "complete" ? "경로 복사" : "재시도") { [weak self] in
        if job.status == "complete" { self?.copy?(job) } else { self?.retry?(job) }
      }
      action.setDisabledReason(disabledReason(job, state: state, original: false))
      var actions: [NSView] = [action]
      if job.status == "complete" {
        let original = ActionButton(restoring == job.id ? "가져오는 중…" : "원본 복사") { [weak self] in
          self?.restore?(job)
        }
        original.setDisabledReason(disabledReason(job, state: state, original: true))
        actions.append(original)
      }
      var row: [NSView] = [
        info, label(stateText, size: 11, color: .secondaryLabelColor), horizontal(actions),
      ]
      if let error = job.error, !error.isEmpty {
        row.append(label(error, size: 10, color: .systemRed))
      }
      sections.append(vertical(row, spacing: 2))
    }
    let footer = vertical(
      [
        separator(),
        horizontal([
          ActionButton("설정…") { [weak self] in self?.settings?() },
          ActionButton("종료") { [weak self] in self?.quit?() },
        ]),
      ], spacing: 10)
    // Keep the form's entire ancestry attached while updating dynamic rows.
    let stack = bodyStack ?? vertical([], spacing: 8)
    for previous in stack.arrangedSubviews where previous !== quickForm {
      stack.removeArrangedSubview(previous)
      previous.removeFromSuperview()
    }
    for (index, section) in sections.enumerated() {
      if section !== quickForm || !stack.arrangedSubviews.contains(where: { $0 === quickForm }) {
        stack.insertArrangedSubview(section, at: index)
      }
    }
    let content = bodyContent ?? FlippedView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
    if bodyContent == nil {
      stack.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(stack)
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
        stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
        stack.widthAnchor.constraint(equalToConstant: 344),
      ])
      bodyContent = content
      bodyStack = stack
    }
    content.layoutSubtreeIfNeeded()
    let height = max(40, stack.fittingSize.height + 16)
    content.setFrameSize(NSSize(width: 380, height: height))
    let scroll = bodyScroll ?? NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    if scroll.documentView !== content { scroll.documentView = content }
    for child in [header, scroll, footer] {
      child.translatesAutoresizingMaskIntoConstraints = false
      if child.superview !== view { view.addSubview(child) }
    }
    layoutConstraints = [
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
      footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
    ]
    NSLayoutConstraint.activate(layoutConstraints)
    bodyScroll = scroll
    pinnedHeader = header
    pinnedFooter = footer
    view.setFrameSize(Self.panelSize)
    preferredContentSize = Self.panelSize
    view.layoutSubtreeIfNeeded()
    let offset = min(scrollOffset, max(0, height - scroll.contentSize.height))
    scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
    scroll.reflectScrolledClipView(scroll.contentView)
    view.needsDisplay = true
  }
  @objc private func toggleWork() { toggle?() }
  private func compactPortRow(_ port: PortConfig, state: CoreState) -> NSView {
    let connection = state.ports.first { $0.id == port.id }
    let ready =
      state.on && port.enabled && connection?.status == "ready" && connection?.reachable == true
    let status =
      !state.on
      ? "OFF" : !port.enabled ? "중지" : connection?.status == "conflict" ? "충돌" : ready ? "연결" : "대기"
    let statusHelp =
      !state.on
      ? "업무 OFF"
      : !port.enabled
        ? "감시 중지" : connection?.status == "conflict" ? "로컬 포트 충돌" : ready ? "연결 가능" : "서버 연결 대기"
    let url = port.endpoint.localURL(port.localPort)?.absoluteString ?? "주소 확인 필요"
    let dot = NSImageView(
      image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: statusHelp)
        ?? NSImage())
    dot.contentTintColor = ready ? .systemGreen : status == "충돌" ? .systemRed : .secondaryLabelColor
    dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
    let name = ActionButton(port.displayName) { [weak self] in self?.open?(port) }
    name.isBordered = false
    name.alignment = .left
    name.font = .systemFont(ofSize: 12, weight: .medium)
    name.lineBreakMode = .byTruncatingTail
    name.toolTip = "\(port.displayName) · \(url)"
    name.widthAnchor.constraint(equalToConstant: 132).isActive = true
    name.heightAnchor.constraint(equalToConstant: 24).isActive = true
    let address = ActionButton("localhost:\(port.localPort)") { [weak self] in self?.open?(port) }
    address.isBordered = false
    address.alignment = .left
    address.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
    address.lineBreakMode = .byTruncatingMiddle
    address.toolTip = url
    address.setAccessibilityLabel(url)
    address.widthAnchor.constraint(equalToConstant: 120).isActive = true
    address.heightAnchor.constraint(equalToConstant: 24).isActive = true
    let stateLabel = label(
      status, size: 10, color: status == "충돌" ? .systemRed : .secondaryLabelColor)
    stateLabel.maximumNumberOfLines = 1
    stateLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
    stateLabel.heightAnchor.constraint(equalToConstant: 14).isActive = true
    stateLabel.toolTip = state.on && port.enabled ? (connection?.error ?? statusHelp) : statusHelp
    stateLabel.setAccessibilityHelp(stateLabel.toolTip)
    let isExpanded = expanded.contains(port.id)
    let details = ActionButton(isExpanded ? "상세 접기" : "상세 보기") { [weak self] in
      guard let self else { return }
      if expanded.contains(port.id) { expanded.remove(port.id) } else { expanded.insert(port.id) }
      if let state = lastState { render(state) }
    }
    details.isBordered = false
    details.image = NSImage(
      systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
      accessibilityDescription: details.title)
    details.imagePosition = .imageOnly
    details.contentTintColor = .secondaryLabelColor
    details.toolTip = details.title
    details.setAccessibilityLabel(details.title)
    details.widthAnchor.constraint(equalToConstant: 20).isActive = true
    details.heightAnchor.constraint(equalToConstant: 24).isActive = true
    let spacer = NSView()
    let primary = horizontal([dot, name, address, stateLabel, spacer, details], spacing: 4)
    primary.distribution = .fill
    primary.identifier = NSUserInterfaceItemIdentifier("port-row-\(port.id)")
    primary.widthAnchor.constraint(equalToConstant: 344).isActive = true
    primary.heightAnchor.constraint(equalToConstant: 24).isActive = true
    guard isExpanded else { return primary }
    let actualHost = connection?.remoteHost ?? port.endpoint.remoteHost
    let actualAddress =
      actualHost.contains(":")
      ? "[\(actualHost)]:\(port.endpoint.remotePort)" : "\(actualHost):\(port.endpoint.remotePort)"
    var rows: [NSView] = [
      primary, label(url, size: 10, color: .secondaryLabelColor),
      label(
        "원격 \(port.host) / \(actualAddress)",
        size: 10,
        color: .secondaryLabelColor),
    ]
    if let error = connection?.error, !error.isEmpty {
      rows.append(label(error, size: 10, color: .systemRed))
    }
    rows.append(
      horizontal([
        ActionButton("주소 복사") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(url, forType: .string)
        },
        ActionButton("제목 확인") { [weak self] in self?.titleRefresh?(port) },
      ]))
    return vertical(rows, spacing: 3)
  }
  private func disabledReason(_ job: ImageJob, state: CoreState, original: Bool) -> String? {
    if expired.contains(job.id) { return "원격 파일이 만료되었습니다." }
    if job.status == "expired" { return "대기 시간이 지났습니다. 다시 캡처해 주세요." }
    if !state.on { return "업무 모드를 켜 주세요." }
    if job.status == "sending" { return "전송 중입니다. 완료 후 사용하세요." }
    if original, let restoring {
      return restoring == job.id ? "원본 이미지를 가져오는 중입니다." : "다른 원본 이미지를 가져오는 중입니다."
    }
    if !state.config.hosts.contains(where: { $0.name == job.host }) {
      return "원래 전송 대상을 다시 등록해 주세요."
    }
    if job.status == "complete"
      && !state.hosts.contains(where: { $0.host == job.host && $0.status == "connected" })
    {
      return "원래 SSH 대상의 연결을 기다리는 중입니다."
    }
    return nil
  }

}

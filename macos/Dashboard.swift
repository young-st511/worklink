import AppKit

final class DashboardController: NSViewController {
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
  override func loadView() {
    view = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
    view.wantsLayer = true
  }
  func render(_ state: CoreState) {
    loadViewIfNeeded()
    lastState = state
    if let copiedCount, copiedCount != clipboardCount() {
      copied.removeAll()
      self.copiedCount = nil
    }
    let scrollOffset = bodyScroll?.contentView.bounds.origin.y ?? 0
    view.subviews.forEach { $0.removeFromSuperview() }
    let title = label("Worklink", size: 16, bold: true)
    let status = label(state.on ? "업무 ON" : "업무 OFF", size: 11, color: .secondaryLabelColor)
    let keep = ActionButton("캡처 원본 유지") { [weak self] in
      guard let self else { return }
      self.changeClipboardMode?(!self.preservesImage)
    }
    keep.setButtonType(.switch)
    keep.state = preservesImage ? .on : .off
    keep.font = .systemFont(ofSize: 11)
    let header = vertical(
      [
        horizontal([title, status]),
        label(
          state.on ? "이미지 전달과 등록한 서버 연결이 켜져 있습니다." : "우클릭으로 시작 · 좌클릭으로 목록 확인", size: 11,
          color: .secondaryLabelColor),
        keep,
        label(
          preservesImage ? "자동 전송 후에도 로컬 이미지를 유지합니다." : "전송 완료 시 원격 경로를 자동 복사합니다.", size: 10,
          color: .secondaryLabelColor),
      ], spacing: 6)
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
    sections.append(label("개발 서버", size: 11, color: .secondaryLabelColor, bold: true))
    if state.config.ports.isEmpty {
      sections.append(label("등록한 서버가 없습니다. URL이나 포트 번호를 붙여넣어 추가하세요.", color: .secondaryLabelColor))
    }
    for port in state.config.ports {
      let connection = state.ports.first { $0.id == port.id }
      let ready = connection?.reachable == true
      let text =
        !state.on
        ? "업무 OFF"
        : !port.enabled
          ? "감시 중지" : connection?.status == "conflict" ? "포트 충돌" : ready ? "연결 가능" : "서버 대기"
      let name = ActionButton(port.displayName) { [weak self] in self?.open?(port) }
      name.isBordered = false
      name.alignment = .left
      name.font = .systemFont(ofSize: 13, weight: .medium)
      let dot = NSImageView(
        image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: text) ?? NSImage()
      )
      dot.contentTintColor = ready && state.on ? .systemGreen : .secondaryLabelColor
      dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
      dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
      let url = port.endpoint.localURL(port.localPort)?.absoluteString ?? "주소 확인 필요"
      let address = ActionButton(url) { [weak self] in self?.open?(port) }
      address.isBordered = false
      address.alignment = .left
      address.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      address.lineBreakMode = .byTruncatingMiddle
      address.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
      let details = ActionButton(expanded.contains(port.id) ? "상세 접기" : "상세 보기") { [weak self] in
        guard let self else { return }
        if expanded.contains(port.id) { expanded.remove(port.id) } else { expanded.insert(port.id) }
        if let state = lastState { render(state) }
      }
      details.isBordered = false
      details.font = .systemFont(ofSize: 10)
      details.contentTintColor = .secondaryLabelColor
      var row: [NSView] = [
        horizontal([dot, name, label(text, size: 10, color: .secondaryLabelColor)]), address,
      ]
      if let error = connection?.error { row.append(label(error, size: 11, color: .systemRed)) }
      row.append(details)
      if expanded.contains(port.id) {
        row.append(
          label(
            "원격 \(port.host) / \(port.endpoint.remoteHost):\(port.endpoint.remotePort)", size: 11,
            color: .secondaryLabelColor))
        row.append(
          horizontal([
            ActionButton("주소 복사") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(url, forType: .string)
            }, ActionButton("제목 확인") { [weak self] in self?.titleRefresh?(port) },
          ]))
      }
      sections.append(vertical(row, spacing: 2))
    }
    sections.append(ActionButton("서버·SSH 대상 등록…") { [weak self] in self?.settings?() })
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
      action.isEnabled = state.on && !expired.contains(job.id) && job.status != "sending"
      var actions: [NSView] = [action]
      if job.status == "complete" {
        let original = ActionButton(restoring == job.id ? "가져오는 중…" : "원본 복사") { [weak self] in
          self?.restore?(job)
        }
        original.isEnabled = state.on && !expired.contains(job.id) && restoring == nil
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
          ActionButton(state.on ? "업무 종료" : "업무 시작") { [weak self] in self?.toggle?() },
          ActionButton("설정…") { [weak self] in self?.settings?() },
          ActionButton("종료") { [weak self] in self?.quit?() },
        ]),
      ], spacing: 10)
    let stack = vertical(sections, spacing: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
      stack.widthAnchor.constraint(equalToConstant: 344),
    ])
    content.layoutSubtreeIfNeeded()
    let height = max(40, stack.fittingSize.height + 16)
    content.setFrameSize(NSSize(width: 380, height: height))
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.documentView = content
    for child in [header, scroll, footer] {
      child.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(child)
    }
    NSLayoutConstraint.activate([
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
    ])
    bodyScroll = scroll
    pinnedHeader = header
    pinnedFooter = footer
    view.setFrameSize(Self.panelSize)
    preferredContentSize = Self.panelSize
    view.layoutSubtreeIfNeeded()
    let offset = min(scrollOffset, max(0, height - scroll.contentSize.height))
    scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
    scroll.reflectScrolledClipView(scroll.contentView)
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}

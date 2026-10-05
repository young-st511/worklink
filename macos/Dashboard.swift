import AppKit

final class DashboardController: NSViewController {
  var toggle: (() -> Void)?
  var settings: (() -> Void)?
  var quit: (() -> Void)?
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
    view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
    view.wantsLayer = true
  }
  func render(_ state: CoreState) {
    loadViewIfNeeded()
    lastState = state
    if let copiedCount, copiedCount != clipboardCount() {
      copied.removeAll()
      self.copiedCount = nil
    }
    view.subviews.forEach { $0.removeFromSuperview() }
    let title = label("Worklink", size: 16, bold: true)
    let status = label(state.on ? "업무 ON" : "업무 OFF", size: 11, color: .secondaryLabelColor)
    var sections: [NSView] = [
      horizontal([title, status]),
      label(
        state.on ? "이미지 전달과 등록한 서버 연결이 켜져 있습니다." : "우클릭으로 시작 · 좌클릭으로 목록 확인", size: 11,
        color: .secondaryLabelColor),
    ]
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
      var row: [NSView] = [
        info, horizontal([label(stateText, size: 11, color: .secondaryLabelColor), action]),
      ]
      if let error = job.error, !error.isEmpty {
        row.append(label(error, size: 10, color: .systemRed))
      }
      sections.append(vertical(row, spacing: 2))
    }
    sections.append(separator())
    sections.append(
      horizontal([
        ActionButton(state.on ? "업무 종료" : "업무 시작") { [weak self] in self?.toggle?() },
        ActionButton("설정…") { [weak self] in self?.settings?() },
        ActionButton("종료") { [weak self] in self?.quit?() },
      ]))
    let stack = vertical(sections, spacing: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 380, height: 600))
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
      stack.widthAnchor.constraint(equalToConstant: 344),
    ])
    content.layoutSubtreeIfNeeded()
    let height = max(160, stack.fittingSize.height + 32)
    content.setFrameSize(NSSize(width: 380, height: height))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: min(height, 620)))
    scroll.hasVerticalScroller = height > 620
    scroll.drawsBackground = false
    scroll.documentView = content
    view.setFrameSize(scroll.frame.size)
    view.addSubview(scroll)
    preferredContentSize = view.frame.size
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}

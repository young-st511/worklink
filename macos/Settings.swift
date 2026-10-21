import AppKit

final class SettingsController: NSWindowController, NSTextFieldDelegate {
  let bridge: CoreBridge
  var loginChange: ((Bool) -> Void)?
  var install: ((String) -> Void)?
  var removeCleanup: ((String) -> Void)?
  let hostName = NSTextField()
  let helperPath = NSTextField(string: "~/.local/bin/worklink")
  let addressInput = NSTextField()
  let serverName = NSTextField()
  let localPort = NSTextField()
  let hostPicker = NSPopUpButton()
  let imagePicker = NSPopUpButton()
  let choices = NSPopUpButton()
  let preview = label("URL 또는 포트 번호를 붙여넣으세요.", size: 11, color: .secondaryLabelColor)
  let errorLabel = label("", size: 11, color: .systemRed)
  let hostRows = vertical([])
  let serverRows = vertical([])
  let imageLimit = NSTextField()
  let queueLimit = NSTextField()
  let inboxLimit = NSTextField()
  var endpoint: EndpointConfig?
  var debounce: Timer?
  var parseSerial = 0
  var hostEditName: String?
  var editID: String?
  private var displayedRevision: UInt64?
  init(bridge: CoreBridge, loginEnabled: Bool) {
    self.bridge = bridge
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 570, height: 690),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Worklink 설정"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    hostName.placeholderString = "SSH 별칭 · 예: office-mac"
    addressInput.placeholderString = "5173 또는 localhost:5173/preview"
    serverName.placeholderString = "이름 · 예: 프론트엔드"
    localPort.placeholderString = "자동: 원격 포트와 동일"
    addressInput.delegate = self
    localPort.delegate = self
    for field in [
      hostName, helperPath, addressInput, serverName, localPort, imageLimit, queueLimit, inboxLimit,
    ] {
      field.font = .systemFont(ofSize: 12)
      field.widthAnchor.constraint(equalToConstant: 510).isActive = true
    }
    hostPicker.widthAnchor.constraint(equalToConstant: 510).isActive = true
    imagePicker.widthAnchor.constraint(equalToConstant: 510).isActive = true
    choices.widthAnchor.constraint(equalToConstant: 510).isActive = true
    choices.isHidden = true
    choices.target = self
    choices.action = #selector(candidateChanged)
    imagePicker.target = self
    imagePicker.action = #selector(imageHostChanged)
    let login = ActionButton("로그인할 때 메뉴바 앱 시작") { [weak self] in
      guard let self, let button = self.loginButton else { return }
      self.loginChange?(button.state == .on)
    }
    login.setButtonType(.switch)
    login.state = loginEnabled ? .on : .off
    loginButton = login
    let sections: [NSView] = [
      label("SSH 대상", size: 15, bold: true),
      label("기존 SSH 별칭과 키를 사용합니다. 처음 연결은 터미널에서 확인해 주세요.", size: 11, color: .secondaryLabelColor),
      hostRows, hostName, helperPath,
      horizontal([
        ActionButton("대상 추가 / 수정 저장") { [weak self] in self?.addHost() },
        ActionButton("선택한 대상에 헬퍼 설치") { [weak self] in
          guard let self, let host = self.hostPicker.titleOfSelectedItem else { return }
          self.install?(host)
        },
      ]),
      separator(), label("이미지 전송 대상", size: 13, bold: true), imagePicker,
      separator(), label("개발 서버 등록", size: 15, bold: true), hostPicker, addressInput, choices,
      serverName, localPort, preview,
      horizontal([
        ActionButton("등록 / 수정 저장") { [weak self] in self?.savePort() },
        ActionButton("입력 초기화") { [weak self] in self?.resetForm() },
      ]), serverRows,
      separator(), label("원본·대기·원격 용량 (MiB)", size: 13, bold: true),
      label(
        "원본 1개 / 로컬 대기 합계 / 원격 보관 합계 순서입니다. 화질을 줄이지 않습니다.", size: 11, color: .secondaryLabelColor),
      imageLimit, queueLimit, inboxLimit,
      ActionButton("용량 설정 저장") { [weak self] in self?.saveLimits() },
      login,
      ActionButton("OFF 상태의 대기 파일 정리") { [weak self] in
        self?.bridge.send(
          "clear_pending",
          reply: { [weak self] r in
            self?.showResult(r)
          })
      }, errorLabel,
    ]
    let stack = vertical(sections, spacing: 9)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 550, height: 1000))
    document.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
      stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
      stack.widthAnchor.constraint(equalToConstant: 510),
    ])
    document.layoutSubtreeIfNeeded()
    document.setFrameSize(NSSize(width: 550, height: max(900, stack.fittingSize.height + 40)))
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.hasVerticalScroller = true
    scroll.autoresizingMask = [.width, .height]
    scroll.documentView = document
    window.contentView!.addSubview(scroll)
    refresh()
  }
  var loginButton: ActionButton?
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  func present() {
    window?.center()
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    refresh()
  }
  func refresh() {
    guard let config = bridge.state?.config else { return }
    if displayedRevision == config.revision { return }
    displayedRevision = config.revision
    let selectedHost = hostPicker.titleOfSelectedItem
    hostPicker.removeAllItems()
    imagePicker.removeAllItems()
    hostPicker.addItems(withTitles: config.hosts.map(\.name))
    imagePicker.addItems(withTitles: config.hosts.map(\.name))
    imagePicker.selectItem(withTitle: config.imageHost)
    if let selectedHost { hostPicker.selectItem(withTitle: selectedHost) }
    hostRows.arrangedSubviews.forEach {
      hostRows.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    serverRows.arrangedSubviews.forEach {
      serverRows.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    for host in config.hosts {
      hostRows.addArrangedSubview(
        horizontal([
          label(host.name, bold: true),
          ActionButton("수정") { [weak self] in
            self?.hostEditName = host.name
            self?.hostName.stringValue = host.name
            self?.helperPath.stringValue = host.helper
          },
          ActionButton("삭제") { [weak self] in self?.removeHost(host.name) },
        ]))
    }
    for port in config.ports {
      serverRows.addArrangedSubview(
        horizontal([
          label("\(port.displayName) · \(port.localPort)", size: 11),
          ActionButton("수정") { [weak self] in self?.edit(port) },
          ActionButton(port.enabled ? "중지" : "켜기") { [weak self] in self?.togglePort(port.id) },
          ActionButton("삭제") { [weak self] in self?.removePort(port.id) },
        ]))
    }
    imageLimit.stringValue = String(config.limits.imageBytes / 1_048_576)
    queueLimit.stringValue = String(config.limits.queueBytes / 1_048_576)
    inboxLimit.stringValue = String(config.limits.inboxBytes / 1_048_576)
    if let scroll = window?.contentView?.subviews.first as? NSScrollView,
      let document = scroll.documentView, let stack = document.subviews.first as? NSStackView
    {
      document.layoutSubtreeIfNeeded()
      document.setFrameSize(NSSize(width: 550, height: max(900, stack.fittingSize.height + 40)))
    }
  }
  func message(_ text: String) { errorLabel.stringValue = text }
  private func showResult(_ result: [String: Any]) {
    if let error = result["error"] as? String {
      message(error)
    } else {
      let removed = (result["result"] as? [String: Any])?["removed_port"] as? [String: Any]
      let suffix = (removed?["local_port"] as? Int).map { " 비활성 포트 \($0)을 정리했습니다." } ?? ""
      message("저장했습니다.\(suffix)")
      refresh()
    }
  }
  private func save(_ config: Config, onSuccess: (() -> Void)? = nil) {
    bridge.send(
      "save_config", ["config": jsonObject(config)],
      reply: { [weak self] r in
        self?.showResult(r)
        if r["error"] == nil { onSuccess?() }
      }
    )
  }
  private func addHost() {
    guard var c = bridge.state?.config else { return }
    let name = hostName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let host = HostConfig(
      name: name, helper: helperPath.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    if let old = hostEditName, let index = c.hosts.firstIndex(where: { $0.name == old }) {
      c.hosts[index] = host
      for n in c.ports.indices { if c.ports[n].host == old { c.ports[n].host = name } }
      if c.imageHost == old { c.imageHost = name }
    } else {
      c.hosts.append(host)
    }
    if c.imageHost.isEmpty { c.imageHost = name }
    save(
      c,
      onSuccess: { [weak self] in
        self?.hostEditName = nil
        self?.hostName.stringValue = ""
        self?.helperPath.stringValue = "~/.local/bin/worklink"
      })
  }
  private func removeHost(_ name: String) {
    guard var c = bridge.state?.config else { return }
    if c.ports.contains(where: { $0.host == name }) {
      message("이 대상의 서버부터 삭제해 주세요.")
      return
    }
    c.hosts.removeAll { $0.name == name }
    if c.imageHost == name { c.imageHost = c.hosts.first?.name ?? "" }
    save(c)
  }
  @objc private func imageHostChanged() {
    guard var c = bridge.state?.config, let host = imagePicker.titleOfSelectedItem else { return }
    c.imageHost = host
    save(c)
  }
  func controlTextDidChange(_ obj: Notification) {
    guard
      (obj.object as? NSTextField) === addressInput || (obj.object as? NSTextField) === localPort
    else { return }
    endpoint = nil
    preview.stringValue = "주소 확인 중…"
    debounce?.invalidate()
    debounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
      self?.parse()
    }
  }
  @objc private func candidateChanged() {
    if let text = choices.titleOfSelectedItem {
      addressInput.stringValue = text
      parse()
    }
  }
  func parse() {
    parseSerial += 1
    let serial = parseSerial
    let input = addressInput.stringValue
    endpoint = nil
    bridge.send(
      "parse", ["input": input],
      reply: { [weak self] result in
        guard let self, serial == parseSerial, input == addressInput.stringValue,
          let r = result["result"] as? [String: Any]
        else { return }
        if let candidates = r["candidates"] as? [String], !candidates.isEmpty {
          choices.removeAllItems()
          choices.addItems(withTitles: candidates)
          choices.isHidden = false
          preview.stringValue = "여러 주소가 있습니다. 후보 하나를 선택해 주세요."
          return
        }
        choices.isHidden = true
        if let error = r["error"] as? String {
          preview.stringValue = error
          return
        }
        if r["needs_port"] as? Bool == true {
          preview.stringValue = "개발 서버 포트를 추가해 주세요. 예: localhost:5173"
          return
        }
        guard let e = r["endpoint"], let bytes = try? JSONSerialization.data(withJSONObject: e),
          let parsed = try? decoder().decode(EndpointConfig.self, from: bytes)
        else { return }
        endpoint = parsed
        let port = Int(localPort.stringValue) ?? parsed.remotePort
        preview.stringValue =
          "원격 \(parsed.remoteHost):\(parsed.remotePort) → \(parsed.localURL(port)?.absoluteString ?? "")"
      })
  }
  private func savePort() {
    guard var c = bridge.state?.config, let e = endpoint, let host = hostPicker.titleOfSelectedItem
    else {
      message("주소를 확인하고 SSH 대상을 선택해 주세요.")
      parse()
      return
    }
    let input = localPort.stringValue.trimmingCharacters(in: .whitespaces)
    let port = input.isEmpty ? e.remotePort : Int(input) ?? 0
    let entry = PortConfig(
      id: editID ?? identifier(), name: serverName.stringValue.trimmingCharacters(in: .whitespaces),
      host: host, endpoint: e, localPort: port,
      enabled: c.ports.first(where: { $0.id == editID })?.enabled ?? true,
      title: c.ports.first(where: { $0.id == editID })?.title)
    if let index = c.ports.firstIndex(where: { $0.id == entry.id }) {
      c.ports[index] = entry
    } else {
      c.ports.append(entry)
    }
    save(c)
  }
  private func resetForm() {
    editID = nil
    endpoint = nil
    addressInput.stringValue = ""
    serverName.stringValue = ""
    localPort.stringValue = ""
    preview.stringValue = "URL 또는 포트 번호를 붙여넣으세요."
  }
  private func edit(_ port: PortConfig) {
    editID = port.id
    endpoint = port.endpoint
    serverName.stringValue = port.name
    localPort.stringValue = String(port.localPort)
    hostPicker.selectItem(withTitle: port.host)
    if let url = port.endpoint.localURL(port.endpoint.remotePort),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    {
      components.host = port.endpoint.remoteHost
      addressInput.stringValue = components.url?.absoluteString ?? ""
    }
    parse()
  }
  private func removePort(_ id: String) {
    guard var c = bridge.state?.config else { return }
    c.ports.removeAll { $0.id == id }
    save(c)
  }
  private func togglePort(_ id: String) {
    guard var c = bridge.state?.config, let index = c.ports.firstIndex(where: { $0.id == id })
    else { return }
    c.ports[index].enabled.toggle()
    save(c)
  }
  private func saveLimits() {
    guard var c = bridge.state?.config, let image = Int64(imageLimit.stringValue),
      let queue = Int64(queueLimit.stringValue), let inbox = Int64(inboxLimit.stringValue),
      (1...256).contains(image), (1...1024).contains(queue), (1...16384).contains(inbox)
    else {
      message("원본 1–256, 대기 1–1024, 원격 1–16384 MiB 범위를 확인해 주세요.")
      return
    }
    c.limits.imageBytes = image * 1_048_576
    c.limits.queueBytes = queue * 1_048_576
    c.limits.inboxBytes = inbox * 1_048_576
    save(c)
  }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

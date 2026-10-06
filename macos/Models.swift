import AppKit

struct HostConfig: Codable {
  var name: String
  var helper: String
}
struct EndpointConfig: Codable {
  var scheme: String
  var remoteHost: String
  var remotePort: Int
  var path: String
  var rawPath: String?
  var query: String?
  var fragment: String?
  var rawFragment: String?
  func localURL(_ port: Int) -> URL? {
    var c = URLComponents()
    c.scheme = scheme
    c.host = "localhost"
    c.port = port
    c.percentEncodedPath =
      rawPath?.isEmpty == false
      ? percentEncoded(rawPath!, allowed: .urlPathAllowed)
      : path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "/"
    if c.percentEncodedPath.isEmpty { c.percentEncodedPath = "/" }
    c.percentEncodedQuery = query.map { percentEncoded($0, allowed: .urlQueryAllowed) }
    c.percentEncodedFragment =
      rawFragment?.isEmpty == false
      ? rawFragment.map { percentEncoded($0, allowed: .urlFragmentAllowed) }
      : fragment?.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    return c.url
  }
}
func percentEncoded(_ text: String, allowed: CharacterSet) -> String {
  var characters = allowed
  characters.insert(charactersIn: "%")
  return text.addingPercentEncoding(withAllowedCharacters: characters) ?? ""
}
struct SuspensionTracker {
  private(set) var reasons = Set<String>()
  var active: Bool { !reasons.isEmpty }
  mutating func pause(_ reason: String) { reasons.insert(reason) }
  mutating func resume(_ reason: String) { reasons.remove(reason) }
}
struct PortConfig: Codable {
  var id: String
  var name: String
  var host: String
  var endpoint: EndpointConfig
  var localPort: Int
  var enabled: Bool
  var title: String?
  var displayName: String {
    !name.isEmpty ? name : title?.isEmpty == false ? title! : "서버 \(endpoint.remotePort)"
  }
}
struct LimitsConfig: Codable {
  var imageBytes: Int64
  var queueBytes: Int64
  var queueCount: Int
  var inboxBytes: Int64
}
struct Config: Codable {
  var revision: UInt64
  var hosts: [HostConfig]
  var ports: [PortConfig]
  var imageHost: String
  var limits: LimitsConfig
}
struct HostStatus: Codable {
  var host: String
  var status: String
  var error: String?
}
struct PortStatus: Codable {
  var id: String
  var status: String
  var error: String?
  var reachable: Bool
}
struct ImageJob: Codable {
  var id: String
  var host: String
  var createdAt: String
  var path: String
  var size: Int64
  var sha256: String
  var `extension`: String
  var status: String
  var error: String?
  var remotePath: String?
  var clipboardCount: Int?
  var generation: UInt64?
}
struct CoreState: Codable {
  var on: Bool
  var generation: UInt64
  var config: Config
  var hosts: [HostStatus]
  var ports: [PortStatus]
  var jobs: [ImageJob]
  var version: String
  var error: String?
}
func decoder() -> JSONDecoder {
  let d = JSONDecoder()
  d.keyDecodingStrategy = .convertFromSnakeCase
  return d
}
func jsonObject<T: Encodable>(_ value: T) -> [String: Any] {
  let e = JSONEncoder()
  e.keyEncodingStrategy = .convertToSnakeCase
  return (try? JSONSerialization.jsonObject(with: e.encode(value))) as? [String: Any] ?? [:]
}
func identifier() -> String {
  UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}

final class CoreBridge {
  var state: CoreState?
  var onState: ((CoreState) -> Void)?
  var onComplete: ((ImageJob) -> Void)?
  var onError: ((String) -> Void)?
  private var process: Process?
  private var input: FileHandle?
  private var callbacks: [String: ([String: Any]) -> Void] = [:]
  private var buffer = Data()
  private let readQueue = DispatchQueue(label: "worklink.core-output")
  private var output: FileHandle?
  private var errorOutput: FileHandle?
  private var stopping = false
  private let eofLock = NSLock()
  private var eofCount = 0
  var eofEvents: Int {
    eofLock.lock()
    defer { eofLock.unlock() }
    return eofCount
  }
  private func recordEOF() {
    eofLock.lock()
    eofCount += 1
    eofLock.unlock()
  }
  var isRunning: Bool { process?.isRunning == true }
  func start(binary: URL, dataDirectory: URL) throws {
    let p = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    p.executableURL = binary
    p.arguments = ["ui", "--stdio"]
    var env = ProcessInfo.processInfo.environment
    env["WORKLINK_DATA_DIR"] = dataDirectory.path
    p.environment = env
    p.standardInput = stdin
    p.standardOutput = stdout
    p.standardError = stderr
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    errorOutput = stderr.fileHandleForReading
    process = p
    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let bytes = handle.availableData
      if bytes.isEmpty {
        self?.recordEOF()
        handle.readabilityHandler = nil
        return
      }
      self?.readQueue.async { [weak self] in self?.receive(bytes) }
    }
    stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let bytes = handle.availableData
      if bytes.isEmpty {
        self?.recordEOF()
        handle.readabilityHandler = nil
        return
      }
      if !bytes.isEmpty {
        let text = String(decoding: bytes.prefix(4096), as: UTF8.self)
        DispatchQueue.main.async { self?.onError?(text) }
      }
    }
    p.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        guard let self else { return }
        let pending = self.callbacks
        self.callbacks.removeAll()
        try? self.input?.close()
        self.input = nil
        if var state = self.state {
          state.on = false
          state.generation &+= 1
          self.state = state
          self.onState?(state)
        }
        for callback in pending.values { callback(["error": "연결 코어가 종료됐습니다"]) }
        if !self.stopping { self.onError?("연결 코어가 종료됐습니다. 앱을 다시 시작해 주세요.") }
      }
    }
    try p.run()
  }
  private func receive(_ bytes: Data) {
    if bytes.isEmpty { return }
    buffer.append(bytes)
    if buffer.count > 1_048_576 {
      buffer.removeAll()
      DispatchQueue.main.async { self.onError?("코어 응답이 너무 큽니다") }
      return
    }
    while let newline = buffer.firstIndex(of: 10) {
      let line = buffer.prefix(upTo: newline)
      buffer.removeSubrange(...newline)
      guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        continue
      }
      DispatchQueue.main.async { [weak self] in self?.handle(obj) }
    }
  }
  private func handle(_ obj: [String: Any]) {
    if let data = obj["state"], let bytes = try? JSONSerialization.data(withJSONObject: data) {
      do {
        let state = try decoder().decode(CoreState.self, from: bytes)
        self.state = state
        onState?(state)
      } catch { onError?("상태 응답을 읽지 못했습니다: \(error)") }
    }
    if obj["kind"] as? String == "upload_complete", let data = obj["job"],
      let bytes = try? JSONSerialization.data(withJSONObject: data),
      let job = try? decoder().decode(ImageJob.self, from: bytes)
    {
      onComplete?(job)
    }
    if let id = obj["id"] as? String, let callback = callbacks.removeValue(forKey: id) {
      callback(obj)
    } else if let error = obj["error"] as? String {
      onError?(error)
    }
  }
  func send(
    _ method: String, _ values: [String: Any] = [:], reply: (([String: Any]) -> Void)? = nil
  ) {
    var obj = values
    let id = identifier()
    obj["id"] = id
    obj["method"] = method
    if let reply { callbacks[id] = reply }
    guard let data = try? JSONSerialization.data(withJSONObject: obj), let input else {
      callbacks.removeValue(forKey: id)
      reply?(["error": "연결 코어가 실행 중이 아닙니다"])
      onError?("코어를 시작하지 못했습니다")
      return
    }
    do { try input.write(contentsOf: data + Data([10])) } catch {
      callbacks.removeValue(forKey: id)
      if let reply { reply(["error": error.localizedDescription]) }
      onError?(error.localizedDescription)
    }
  }
  func stop() {
    stopping = true
    output?.readabilityHandler = nil
    errorOutput?.readabilityHandler = nil
    try? input?.close()
    input = nil
  }
}

final class ActionButton: NSButton {
  var invoke: (() -> Void)?
  init(_ title: String, action: @escaping () -> Void) {
    super.init(frame: .zero)
    self.title = title
    self.invoke = action
    target = self
    self.action = #selector(runAction)
    bezelStyle = .rounded
    font = .systemFont(ofSize: 12)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  func setDisabledReason(_ reason: String?) {
    isEnabled = reason == nil
    toolTip = reason
    setAccessibilityHelp(reason)
  }
  @objc private func runAction() { if isEnabled { invoke?() } }
}
func label(_ text: String, size: CGFloat = 12, color: NSColor = .labelColor, bold: Bool = false)
  -> NSTextField
{
  let field = NSTextField(wrappingLabelWithString: text)
  field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
  field.textColor = color
  field.isSelectable = false
  field.maximumNumberOfLines = 3
  field.preferredMaxLayoutWidth = 340
  return field
}
func vertical(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
  let v = NSStackView(views: views)
  v.orientation = .vertical
  v.alignment = .leading
  v.spacing = spacing
  return v
}
func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
  let v = NSStackView(views: views)
  v.orientation = .horizontal
  v.alignment = .centerY
  v.spacing = spacing
  return v
}
func separator() -> NSBox {
  let b = NSBox()
  b.boxType = .separator
  b.widthAnchor.constraint(equalToConstant: 340).isActive = true
  return b
}
func fileSize(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
}

import AppKit
import Network

// Pure reducer: duplicate path events cannot postpone or multiply recovery work.
struct NetworkRecoveryGate {
  private(set) var active = false
  private(set) var available = false
  private(set) var pending = false
  private var revision = 0
  mutating func start() {
    guard !active else { return }
    active = true
    available = false
    pending = false
    revision += 1
  }
  mutating func stop() {
    active = false
    available = false
    pending = false
    revision += 1
  }
  mutating func receive(_ satisfied: Bool) -> Int? {
    guard active else { return nil }
    if !satisfied {
      available = false
      pending = false
      revision += 1
      return nil
    }
    guard !available, !pending else { return nil }
    pending = true
    revision += 1
    return revision
  }
  mutating func complete(_ token: Int) -> Bool {
    guard active, pending, token == revision else { return false }
    pending = false
    available = true
    return true
  }
}

final class NetworkPowerMonitor {
  private var gate = NetworkRecoveryGate()
  private var monitor: NWPathMonitor?
  private var recovery: DispatchWorkItem?
  private var session: UInt64 = 0
  private var powerObserver: NSObjectProtocol?
  private var lastPublished: String?
  private let emit: (Bool, Bool) -> Void
  private let lowPower: () -> Bool
  private let paths: Bool
  private let queue = DispatchQueue(label: "worklink.network-path", qos: .utility)
  init(
    paths: Bool = true,
    lowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
    emit: @escaping (Bool, Bool) -> Void
  ) {
    self.emit = emit
    self.lowPower = lowPower
    self.paths = paths
    powerObserver = NotificationCenter.default.addObserver(
      forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
    ) { [weak self] _ in self?.publish() }
    publish()
  }
  func start() {
    guard !gate.active else { return }
    gate.start()
    session &+= 1
    let current = session
    publish()
    guard paths else { return }
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      let satisfied = path.status == .satisfied
      DispatchQueue.main.async { [weak self] in
        guard let self, self.session == current else { return }
        self.handlePath(satisfied)
      }
    }
    monitor.start(queue: queue)
  }
  func handlePath(_ satisfied: Bool) {
    guard gate.active else { return }
    if !satisfied {
      recovery?.cancel()
      recovery = nil
    }
    if let token = gate.receive(satisfied) {
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.gate.complete(token) else { return }
        self.recovery = nil
        self.publish()
      }
      recovery = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    publish()
  }
  func stop(notify: Bool = true) {
    guard gate.active else { return }
    session &+= 1
    gate.stop()
    recovery?.cancel()
    recovery = nil
    monitor?.cancel()
    monitor = nil
    if notify { publish() }
  }
  func publish() {
    let available = gate.active && gate.available
    let power = lowPower()
    let value = "\(available):\(power)"
    guard value != lastPublished else { return }
    lastPublished = value
    emit(available, power)
  }
  deinit {
    recovery?.cancel()
    monitor?.cancel()
    if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
  }
}

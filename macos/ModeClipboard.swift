import AppKit

struct ModeClipboardRequest {
  let revision: UInt64
  let preservesImage: Bool
  let job: ImageJob
  let clipboardCount: Int
  let generation: UInt64

  // Core snapshots already order captures newest first. Do not skip a pending latest capture.
  static func latest(in state: CoreState) -> ImageJob? {
    guard !state.config.imageHost.isEmpty else { return nil }
    return state.jobs.first { $0.host == state.config.imageHost }
  }
  func matches(state: CoreState, revision: UInt64, preservesImage: Bool, count: Int) -> Bool {
    state.on && state.networkUnavailable != true && state.generation == generation
      && self.revision == revision && self.preservesImage == preservesImage
      && clipboardCount == count && state.config.imageHost == job.host
      && Self.latest(in: state)?.id == job.id && Self.latest(in: state)?.status == "complete"
  }
}

extension AppDelegate {
  func settleCaptureRegistration(in state: CoreState) {
    guard let count = unregisteredCaptureCount else { return }
    if clipboardBoard.changeCount != count
      || (captureAwaitingJobID != nil && state.jobs.contains(where: { $0.id == captureAwaitingJobID })) {
      unregisteredCaptureCount = nil
      captureAwaitingJobID = nil
    }
  }
  var hasPendingCapture: Bool {
    if captureBusy || unregisteredCaptureCount == clipboardBoard.changeCount || clipboardBlocked { return true }
    guard clipboardBoard.changeCount != lastCount else { return false }
    let offered = clipboardBoard.types ?? []
    if offered.contains(.fileURL) || offered.contains(.init("NSFilenamesPboardType")) { return false }
    return ClipboardReader.types.contains { offered.contains($0.0) }
  }
  func toggleClipboardModeFromStatusItem() {
    guard !suspended else { return }
    setClipboardMode(!clipboardPreferences.preservesImage)
    guard desiredOn, let state = bridge.state, state.on,
      state.networkUnavailable != true,
      state.hosts.contains(where: { $0.host == state.config.imageHost && $0.status == "connected" })
    else { return }
    // Let the existing observer/transfer finish a fresh capture instead of copying an older snapshot.
    guard !hasPendingCapture else { return }
    guard let job = ModeClipboardRequest.latest(in: state), job.status == "complete",
      job.remotePath != nil, !dashboard.expired.contains(job.id)
    else {
      notice("모드를 변경했습니다. 바로 복사할 최신 완료 캡처가 없습니다.")
      return
    }
    pendingModeClipboard = ModeClipboardRequest(
      revision: clipboardModeRevision, preservesImage: clipboardPreferences.preservesImage,
      job: job, clipboardCount: clipboardBoard.changeCount, generation: state.generation)
    processModeClipboard()
  }
  func modeClipboardIsCurrent(_ request: ModeClipboardRequest) -> Bool {
    guard desiredOn, !suspended, !hasPendingCapture, let state = bridge.state,
      !dashboard.expired.contains(request.job.id) else { return false }
    return request.matches(state: state, revision: clipboardModeRevision,
      preservesImage: clipboardPreferences.preservesImage, count: clipboardBoard.changeCount)
  }
  func processModeClipboard() {
    guard !modeClipboardBusy, dashboard.restoring == nil, let request = pendingModeClipboard else { return }
    pendingModeClipboard = nil
    guard modeClipboardIsCurrent(request) else { return }
    modeClipboardBusy = true
    let permitted = { [weak self] in self?.modeClipboardIsCurrent(request) == true }
    let finished: () -> Void = { [weak self] in self?.modeClipboardBusy = false }
    if request.preservesImage {
      restore(request.job, permitted: permitted, finished: finished)
    } else {
      copy(request.job, permitted: permitted, finished: finished)
    }
  }
}

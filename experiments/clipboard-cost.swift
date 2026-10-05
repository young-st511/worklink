// Finite macOS feasibility probe. Reads only the clipboard change counter.
// It never reads/writes clipboard contents, starts SSH, or sends network data.
import AppKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3,
      ["timer-only", "clipboard"].contains(arguments[0]),
      let duration = Double(arguments[1]), duration.isFinite, (1...3600).contains(duration),
      let interval = Double(arguments[2]), interval.isFinite, (0.5...60).contains(interval),
      interval <= duration else {
    fail("Usage: clipboard-cost <timer-only|clipboard> <duration-seconds:1...3600> <interval-seconds:0.5...60>")
}

func usage() -> rusage {
    var value = rusage()
    guard getrusage(RUSAGE_SELF, &value) == 0 else { fail("getrusage failed") }
    return value
}

func cpuSeconds(_ value: rusage) -> Double {
    Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
        + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
}

let mode = arguments[0]
// Warm up AppKit equally in both modes; reported CPU excludes initialization.
let pasteboard = NSPasteboard.general
var lastChange = pasteboard.changeCount
var observations = 0
var changes = 0
let before = usage()
let start = ProcessInfo.processInfo.systemUptime

let timer = Timer(timeInterval: interval, repeats: true) { _ in
    autoreleasepool {
        observations += 1
        if mode == "clipboard" {
            let current = pasteboard.changeCount
            if current != lastChange {
                changes += 1
                lastChange = current
            }
        }
    }
}
timer.tolerance = interval * 0.1
RunLoop.main.add(timer, forMode: .default)
// One run-loop wait; no busy loop and no process spawn on each observation.
RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
timer.invalidate()

let elapsed = ProcessInfo.processInfo.systemUptime - start
let after = usage()
let cpu = cpuSeconds(after) - cpuSeconds(before)
let result: [String: Any] = [
    "mode": mode,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
    "requested_duration_seconds": duration,
    "elapsed_seconds": elapsed,
    "interval_seconds": interval,
    "tolerance_seconds": timer.tolerance,
    "timer_callbacks": observations,
    "observed_change_events": changes,
    "process_cpu_seconds_excluding_startup": cpu,
    "process_cpu_percent_one_core": cpu / elapsed * 100,
    // Darwin reports ru_maxrss in bytes. This is process lifetime peak RSS.
    "process_peak_rss_bytes_including_startup": after.ru_maxrss,
    "scope": "Probe process only; excludes pasteboard server, SSH, Tailscale, image encoding and network."
]
do {
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("Could not encode measurement: \(error)")
}

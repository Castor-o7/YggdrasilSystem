// yggapps — the Yggdrasil System workspace daemon.
//
// Prints one JSON object per line at a fixed interval: every application
// with a Dock presence (activation policy "regular"), its window count,
// whether it is frontmost, and its CPU including every process it has
// spawned. Background services never appear; the OS is one node.
// Exits when its stdout closes (SIGPIPE on the next write). Foundation,
// AppKit and Darwin only; build with helper/build.sh.
//
//   yggapps [--interval 1000] [--once]

import Foundation
import AppKit
import Darwin

// MARK: - Arguments

var intervalMs = 1000
var once = false
var argIter = CommandLine.arguments.dropFirst().makeIterator()
while let a = argIter.next() {
    switch a {
    case "--interval": if let v = argIter.next(), let n = Int(v), n >= 250 { intervalMs = n }
    case "--once": once = true
    default: break
    }
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let parentPid = getppid()

// MARK: - Processes

/// Every process's parent, from the kernel's process table.
func processParents() -> [pid_t: pid_t] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [:] }
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
    size = procs.count * MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }
    var out: [pid_t: pid_t] = [:]
    for i in 0..<(size / MemoryLayout<kinfo_proc>.stride) {
        out[procs[i].kp_proc.p_pid] = procs[i].kp_eproc.e_ppid
    }
    return out
}

/// CPU time a process has used, in nanoseconds. The rusage clocks are in
/// mach time units, which are not nanoseconds on Apple silicon.
func cpuNanos(_ pid: pid_t) -> UInt64 {
    var info = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    guard r == 0 else { return 0 }
    let units = info.ri_user_time &+ info.ri_system_time
    return units * UInt64(timebase.numer) / UInt64(timebase.denom)
}

/// CPU nanoseconds of a process and everything descended from it.
func familyNanos(_ root: pid_t, children: [pid_t: [pid_t]]) -> UInt64 {
    var total: UInt64 = 0
    var stack = [root]
    var seen = Set<pid_t>()
    while let pid = stack.popLast() {
        guard seen.insert(pid).inserted else { continue }
        total &+= cpuNanos(pid)
        stack.append(contentsOf: children[pid] ?? [])
    }
    return total
}

// MARK: - Windows

/// Normal-layer windows per owning process, on every Space, minimized or
/// not: (all, on this screen right now). Bounds and owner need no
/// permission; titles would need Screen Recording, so none are read.
func windowCounts() -> [pid_t: (all: Int, visible: Int, rects: [[Double]])] {
    let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var out: [pid_t: (all: Int, visible: Int, rects: [[Double]])] = [:]
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
              let pid = w[kCGWindowOwnerPID as String] as? Int else { continue }
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let wd = b["Width"] as? Double ?? 0
        let ht = b["Height"] as? Double ?? 0
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        if wd < 40 || ht < 40 || alpha == 0 { continue }
        let on = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
        var e = out[pid_t(pid)] ?? (0, 0, [])
        e.all += 1
        if on {
            e.visible += 1
            // Screen points, origin at the top-left of the main display.
            e.rects.append([b["X"] as? Double ?? 0, b["Y"] as? Double ?? 0, wd, ht])
        }
        out[pid_t(pid)] = e
    }
    return out
}

// MARK: - Sample

var lastNanos: [pid_t: UInt64] = [:]
var lastTime = Date()

func sample() -> String {
    let now = Date()
    let dt = max(now.timeIntervalSince(lastTime), 0.001)
    lastTime = now
    let parents = processParents()
    var children: [pid_t: [pid_t]] = [:]
    for (pid, ppid) in parents { children[ppid, default: []].append(pid) }
    let windows = windowCounts()

    var apps: [[String: Any]] = []
    var seenNanos: [pid_t: UInt64] = [:]
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
        let pid = app.processIdentifier
        let nanos = familyNanos(pid, children: children)
        seenNanos[pid] = nanos
        var cpu = 0.0
        if let prev = lastNanos[pid], nanos >= prev {
            cpu = Double(nanos - prev) / 1e9 / dt  // fraction of one core
        }
        let name = app.localizedName ?? "pid \(pid)"
        apps.append([
            "id": app.bundleIdentifier ?? name,
            "name": name,
            "pid": Int(pid),
            "launched": app.launchDate?.timeIntervalSince1970 ?? 0,
            "windows": windows[pid]?.all ?? 0,
            "visible": windows[pid]?.visible ?? 0,
            "rects": windows[pid]?.rects ?? [],
            "cpu": (cpu * 1000).rounded() / 1000,
            "active": app.isActive,
            "hidden": app.isHidden,
            "self": pid == parentPid,
        ])
    }
    lastNanos = seenNanos
    let obj: [String: Any] = ["t": now.timeIntervalSince1970, "interval": intervalMs, "apps": apps]
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Fast window tracking

/// On-screen window rects per process, polled far faster than the full
/// sample so the cockpit's paint stays locked to a window being dragged.
/// Printed only when something changed: {"win": {"<pid>": [[x,y,w,h]]}}.
func onscreenRects() -> [Int: [[Double]]] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var out: [Int: [[Double]]] = [:]
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
              let pid = w[kCGWindowOwnerPID as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
        let wd = b["Width"] as? Double ?? 0
        let ht = b["Height"] as? Double ?? 0
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        if wd < 40 || ht < 40 || alpha == 0 { continue }
        out[pid, default: []].append([b["X"] as? Double ?? 0, b["Y"] as? Double ?? 0, wd, ht])
    }
    return out
}

var lastRects: [Int: [[Double]]] = [:]

func windowTick() {
    let now = onscreenRects()
    if now == lastRects { return }
    lastRects = now
    var byPid: [String: Any] = [:]
    for (pid, rects) in now { byPid[String(pid)] = rects }
    let data = try! JSONSerialization.data(withJSONObject: ["win": byPid], options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

// MARK: - Loop

setvbuf(stdout, nil, _IOLBF, 0)
if once {
    _ = sample()
    usleep(250_000)
    print(sample())
    exit(0)
}
_ = sample()
let timer = Timer(timeInterval: Double(intervalMs) / 1000.0, repeats: true) { _ in
    print(sample())
}
RunLoop.main.add(timer, forMode: .common)
let fast = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in windowTick() }
RunLoop.main.add(fast, forMode: .common)
RunLoop.main.run()

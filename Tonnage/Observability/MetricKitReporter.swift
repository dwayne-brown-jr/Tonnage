#if canImport(MetricKit)
import Foundation
import MetricKit
import os

/// Minimal MetricKit subscriber — Apple's built-in, privacy-preserving telemetry (no
/// third-party SDK, no data sent off-device). The OS delivers aggregated daily metrics and
/// diagnostic payloads (crashes, hangs, disk-write exceptions) on the NEXT launch; we log
/// concise summaries via os.Logger so they surface in Console / device logs.
///
/// This is the foundation for production observability: the payloads carry full call-stack
/// trees (`jsonRepresentation()`) that could later be forwarded to a backend for triage.
// Holds only an immutable Logger — safe to share across the MetricKit delivery queue.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitReporter()
    private let log = Logger(subsystem: "com.dwayne.tonnage", category: "metrics")

    /// Subscribe once, early in launch. Safe to call repeatedly.
    func start() { MXMetricManager.shared.add(self) }

    // Daily aggregated performance metrics (launch time, hang rate, memory, energy…).
    func didReceive(_ payloads: [MXMetricPayload]) {
        log.info("MetricKit: received \(payloads.count) metric payload(s)")
    }

    // Diagnostics: crashes, hangs, CPU/disk exceptions. Logged at error level so they stand out.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics?.count ?? 0
            let hangs = p.hangDiagnostics?.count ?? 0
            let cpu = p.cpuExceptionDiagnostics?.count ?? 0
            let disk = p.diskWriteExceptionDiagnostics?.count ?? 0
            if crashes + hangs + cpu + disk > 0 {
                log.error("MetricKit diagnostics — crashes: \(crashes), hangs: \(hangs), cpu: \(cpu), diskWrite: \(disk)")
            }
        }
    }
}
#endif

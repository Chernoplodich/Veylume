import SwiftUI

struct DiagnosticsContent: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var capabilities: CapabilityCoordinator
    @Environment(\.dismiss) private var dismiss
    @ViewState private var report = ""
    @ViewState private var showHelp = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(I18n.tr("Диагностика", "Diagnostics")).font(.title3)
            Text(I18n.tr("Предпросмотр отчёта. Тексты, аудио, буфер, нажатия, пути и документы других приложений не включены. Отчёт никуда не отправляется автоматически.", "Report preview. No text, audio, clipboard, keystrokes, paths, or other apps’ documents are included. Reports are never sent automatically.")).font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 220)
            #if DEBUG
            HStack {
                Button(I18n.tr("Проверить 100 коротких записей", "Test 100 short recordings")) { session.probeCaptureStops() }.disabled(session.busy || session.probeProgress != nil)
                if let progress = session.probeProgress { Text("\(progress) / 100").font(.caption).monospacedDigit() }
                Button(I18n.tr("Обновить отчёт", "Refresh report")) { report = makeReport() }
            }.controlSize(.small)
            #endif
            HStack {
                Button(I18n.tr("Сохранить отчёт…", "Save report…")) { FileActions.save(Data(report.utf8), name: "Veylume-diagnostics.txt", type: .plainText) }
                Button(I18n.tr("Скопировать", "Copy")) { session.copyText(report) }
                Button(I18n.tr("Справка", "Help")) { showHelp = true }
                Spacer(); Button(I18n.tr("Закрыть", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 540).onAppear { capabilities.refresh(); report = makeReport() }
            .sheet(isPresented: $showHelp) { HelpContent() }
    }
    private func makeReport() -> String {
        var lines = ["Veylume " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                     "OS: " + ProcessInfo.processInfo.operatingSystemVersionString, "Architecture: arm64", "RAM GiB: \(ProcessInfo.processInfo.physicalMemory / 1073741824)",
                     "Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"); signature/notarization verified separately", "Session: \(session.phase.rawValue)",
                     "Microphone: \(capabilities.microphone.rawValue)", "AX: \(capabilities.accessibility)", "Listen: \(capabilities.listen)", "Post: \(capabilities.post)",
                     "Secure Input: \(capabilities.secureInput)", "Event tap: \(session.shortcutsAvailable)",
                     "FluidAudio: c8b41f98eae668794dd0083bbe028fe7e6585051", "WhisperKit: 1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4", "Sparkle: 2.10.1",
                     "Model: \(session.models.active?.id ?? "none")", "Model revision: \(session.models.active?.revision ?? "none")", "Pending: \(session.unresolvedCount)"]
        if !session.stopLatencies.isEmpty {
            let values = session.stopLatencies.sorted(), p95 = values[min(values.count - 1, Int(Double(values.count) * 0.95))]
            lines.append(String(format: "Capture stop API p95: %.3f ms (%d samples; excludes key dispatch/external audio stack)", p95, values.count))
        } else { lines.append("Capture stop: not measured") }
        if let m = session.measurement { lines.append(String(format: "Load: %.3f s; ASR: %.3f s; captured: %.3f s; RTF: %.3f; cold: %@", m.loadSeconds, m.recognitionSeconds, m.capturedSeconds, m.rtf, m.cold.description)) }
        else { lines.append("ASR: not measured") }
        if let p = session.pipelineMeasurement {
            lines.append(String(format: "Capture preparation: %.1f ms; Stop-to-result: %.1f ms; Insertion: %.1f ms; Outcome: %@", p.capturePreparationMilliseconds, p.stopToResultMilliseconds, p.insertionMilliseconds, p.insertionOutcome))
            lines.append("Destination status: \(p.destinationDiagnostic); insertion status: \(p.insertionDiagnostic)")
        }
        if let data = try? Data(contentsOf: AppPaths.root.appendingPathComponent("recent-pipelines.json")), data.count <= 65536,
           let recent = try? JSONDecoder().decode([PipelineMeasurement].self, from: data) {
            lines.append("Recent pipeline codes (no text or app identity):")
            for p in recent.suffix(10) { lines.append(String(format: "%.1f ms; %@; %@; %@", p.stopToResultMilliseconds, p.insertionOutcome, p.destinationDiagnostic, p.insertionDiagnostic)) }
        }
        lines.append("Presentation: AppKit notch attachment on cutout displays; Mini fallback; ActivityKit unavailable for macOS")
        return lines.joined(separator: "\n")
    }
}

struct HelpContent: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Veylume").font(.title3)
            ScrollView {
                Text(helpText).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 280)
            Button(I18n.tr("Закрыть", "Close")) { dismiss() }
        }.padding(24).frame(width: 520)
    }
    private var helpText: String {
        guard let url = Bundle.module.url(forResource: "Help-" + I18n.languageCode, withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return I18n.tr("Справка недоступна.", "Help unavailable.") }; return text
    }
}

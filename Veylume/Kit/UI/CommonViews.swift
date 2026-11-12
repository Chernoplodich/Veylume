import SwiftUI
import UniformTypeIdentifiers
import VeylumeCore

// Use the macOS 14-compatible property wrapper explicitly. SDK 27 also declares
// a same-named State macro whose compiler plugin is absent from standalone CLT.
typealias ViewState<Value> = SwiftUI.State<Value>

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, models, shortcuts, appearance, dictionary, history, statistics
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return I18n.tr("Общее", "General")
        case .models: return I18n.tr("Модели", "Models")
        case .shortcuts: return I18n.tr("Клавиши", "Shortcuts")
        case .appearance: return I18n.tr("Оформление", "Appearance")
        case .dictionary: return I18n.tr("Словарь", "Dictionary")
        case .history: return I18n.tr("История", "History")
        case .statistics: return I18n.tr("Статистика", "Statistics")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .models: return "square.stack.3d.up"
        case .shortcuts: return "keyboard"
        case .appearance: return "circle.lefthalf.filled"
        case .dictionary: return "book"
        case .history: return "clock.arrow.circlepath"
        case .statistics: return "chart.bar"
        }
    }
}
/// Native sidebar selection includes the full row, keyboard navigation, focus
/// and VoiceOver. It does not rely on the glyphs of a plain Button for hit tests.
struct SettingsSidebar: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Binding var selection: SettingsSection
    var updateAvailable = false
    var installUpdate: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandAvatar(size: 30)
                Text("Veylume").font(.system(size: 13, weight: .semibold))
            }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
            List(SettingsSection.allCases, selection: Binding<SettingsSection?>(get: { selection }, set: { if let value = $0 { selection = value } })) { section in
                sidebarLabel(section)
                    .font(.system(size: 13)).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).tag(section)
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .accessibilityLabel(I18n.tr("Разделы настроек", "Settings sections"))
            if updateAvailable {
                Button(I18n.tr("Обновить", "Update"), action: installUpdate).controlSize(.small).padding(.horizontal, 16).padding(.bottom, 8)
            }
            PrivacyInfoButton().padding(.horizontal, 16).padding(.bottom, 10)
        }.frame(width: 176).frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
    @ViewBuilder private func sidebarLabel(_ section: SettingsSection) -> some View {
        if selection == section && controlActiveState != .inactive {
            // The native emphasized selection supplies its own contrast color.
            Label(section.title, systemImage: section.symbol)
        } else {
            Label { Text(section.title).foregroundStyle(.primary) } icon: {
                Image(systemName: section.symbol).foregroundStyle(selection == section ? Color.accentColor : Color.secondary)
            }
        }
    }
}

struct SidebarDivider: View {
    var body: some View { Divider().ignoresSafeArea(.container, edges: .top) }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }.frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }
}
struct AppRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) { Text(title).fixedSize(horizontal: false, vertical: true); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
            Spacer(minLength: 8); content
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }
}
struct PageHeading: View {
    let title: String, subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 20, weight: .semibold)); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(.bottom, 4) }
}
struct RatingView: View {
    let title: String, value: Int
    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 2) { ForEach(1...5, id: \.self) { i in Capsule().fill(i <= value ? Color.accentColor : Color.secondary.opacity(0.2)).frame(width: 10, height: 4) } }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title): \(value) / 5")
    }
}
struct ProviderBadge: View {
    let publisher: String
    var body: some View {
        Text(["NVIDIA":"N", "OpenAI":"AI", "Cohere":"C"][publisher] ?? "≈")
            .font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 20)
            .foregroundStyle(Color.accentColor).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}
@MainActor enum FileActions {
    static func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        if panel.runModal() == .OK, let url = panel.url { do { try data.write(to: url, options: .atomic) } catch { showFailure() } }
    }
    static func confirm(_ title: String, explanation: String, action: () -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = explanation; alert.alertStyle = .warning
        alert.addButton(withTitle: I18n.tr("Удалить", "Delete")); alert.addButton(withTitle: I18n.tr("Отменить", "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
    static func showFailure() { let alert = NSAlert(); alert.messageText = I18n.tr("Не удалось прочитать или сохранить файл.", "Couldn’t read or save the file."); alert.runModal() }
}

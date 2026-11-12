import SwiftUI
import AppKit
import VeylumeCore

struct IndicatorSettings: View {
    @Binding var value: Preferences
    @ViewState private var screens = NSScreen.screens
    private var selectedScreen: NSScreen? {
        value.screenID.flatMap { id in screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id } }
            ?? NSScreen.main ?? screens.first
    }
    private var cameraAvailable: Bool {
        guard let screen = selectedScreen else { return false }
        return IndicatorGeometry.cameraRect(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea) != nil
    }
    var body: some View {
        GlassGroup {
            AppRow(title: I18n.tr("Вид индикатора", "Indicator style")) {
                NativePopup(selection: Binding(get: { value.indicator == .mini ? IndicatorStyle.mini : .notch }, set: { value.indicator = $0 }),
                    choices: [(I18n.tr("У чёлки", "Camera cutout"), .notch), (I18n.tr("Компактный", "Compact"), .mini)],
                    label: I18n.tr("Вид индикатора", "Indicator style")).frame(width: 200)
            }
            if value.indicator == .mini || !cameraAvailable {
                Divider()
                AppRow(title: I18n.tr("Положение", "Position")) {
                    NativePopup(selection: Binding(get: { value.resolvedIndicatorPosition }, set: { value.indicatorPosition = $0 }),
                        choices: [(I18n.tr("Сверху", "Top"), IndicatorPosition.top), (I18n.tr("Снизу", "Bottom"), .bottom)],
                        label: I18n.tr("Положение индикатора", "Indicator position")).frame(width: 200)
                }
            }
            Divider()
            AppRow(title: I18n.tr("Экран", "Screen")) {
                NativePopup(selection: Binding(get: { value.screenID ?? 0 }, set: { value.screenID = $0 == 0 ? nil : $0 }),
                    choices: [(I18n.tr("Активный экран", "Active screen"), UInt32(0))] + screens.map { ($0.localizedName, ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0) },
                    label: I18n.tr("Экран", "Screen")).frame(width: 200)
            }
        }
        IndicatorSettingsPreview(style: value.indicator, position: value.resolvedIndicatorPosition, cameraAvailable: cameraAvailable)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        if value.indicator != .mini {
            Text(cameraAvailable
                ? I18n.tr("Индикатор соединяется с чёлкой. Если рядом свободно, он расширяется по бокам.", "The indicator joins the camera cutout and extends to its sides when there is room.")
                : I18n.tr("macOS не сообщает о вырезе на этом экране. Будет показан компактный индикатор.", "macOS is not reporting a camera cutout on this display. The compact indicator will be used."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct IndicatorSettingsPreview: View {
    let style: IndicatorStyle
    let position: IndicatorPosition
    let cameraAvailable: Bool
    @ViewState private var meter = AudioMeter()
    private var integrated: Bool { style != .mini && cameraAvailable }
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: integrated || position == .top ? .top : .bottom) {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.25))
                if integrated {
                    IndicatorSurface(phase: .preparing, meter: meter, layout: .attached(width: 192, cutoutHeight: 32), openControls: {})
                } else {
                    IndicatorSurface(phase: .preparing, meter: meter, layout: .mini, openControls: {}).padding(.vertical, 10)
                }
            }.frame(width: 320, height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false).accessibilityHidden(true)
            Text(I18n.tr("Предпросмотр", "Preview")).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 4)
    }
}

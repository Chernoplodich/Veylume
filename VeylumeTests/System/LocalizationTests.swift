import Testing
import Foundation
@testable import VeylumeKit

@Suite(.serialized) struct LocalizationTests {
    @Test func systemLanguageMatchesSupportedRegionalPreferencesAndFallsBackSafely() {
        #expect(I18n.resolveLanguage("system", preferred: ["es-MX", "en-US"]) == "es")
        #expect(I18n.resolveLanguage("system", preferred: ["de-DE", "fr-CA"]) == "fr")
        #expect(I18n.resolveLanguage("system", preferred: ["ja-JP"]) == "en")
        #expect(I18n.resolveLanguage("ru_RU", preferred: ["en-US"]) == "ru")
        #expect(I18n.resolveLanguage("fr", preferred: ["ru-RU"]) == "fr")
        #expect(I18n.resolveLanguage("unknown", preferred: ["ru-RU"]) == "en")
    }
    @Test @MainActor func nativeBundlesResolveFourLanguagesAndTheirNumberFormats() {
        let old = I18n.language; defer { I18n.language = old }
        for (code, expected) in [("en", "Ready to record"), ("ru", "Готово к записи"), ("es", "Listo para grabar"), ("fr", "Prêt à enregistrer")] {
            I18n.language = code
            #expect(I18n.tr("Готово к записи", "Ready to record") == expected)
            #expect(!I18n.duration(75).isEmpty)
            let value = I18n.format("Загрузка %.2f с · ASR %.2f с · RTF %.3f", "Load %.2f s · ASR %.2f s · RTF %.3f", 1.25, 2.5, 0.125)
            #expect(value.contains(code == "en" ? "1.25" : "1,25"))
        }
    }
}

import XCTest
@testable import KotoroUI
import QuantTern

final class KotoroUITests: XCTestCase {

    func testOnboardingFlowShape() {
        let pages = OnboardingPage.all(engineID: "apple")
        XCTAssertEqual(pages.count, 6)
        XCTAssertEqual(pages.first?.title, "Welcome to \(KotoroAppInfo.name)")
        XCTAssertEqual(pages.last?.title, "You're set")
        // Exactly one page owns the engine picker, and it links nowhere.
        XCTAssertEqual(pages.filter(\.enginePicker).count, 1)
        // The Shortcut page points at the guided setup.
        XCTAssertTrue(pages.contains { $0.guide == KotoroAppInfo.setupGuide })
    }

    func testEngineChoicesAreStable() {
        XCTAssertFalse(KotoroEngineChoice.all.isEmpty)
        XCTAssertEqual(KotoroEngineChoice.named("apple").id, "apple")
        // Unknown ids fall back to the first choice rather than crashing.
        XCTAssertEqual(KotoroEngineChoice.named("nope").id, KotoroEngineChoice.all[0].id)
    }

    func testAppInfoURLsParse() {
        XCTAssertEqual(KotoroAppInfo.setupGuide.absoluteString, KotoroAppInfo.setupGuideURL)
        XCTAssertEqual(KotoroAppInfo.version, "0.5.0")
    }

    func testLocalesCoverGoalLanguages() {
        let ids = Set(KotoroLocale.all.map(\.id))
        for tag in ["en-US", "ja-JP", "zh-CN", "zh-TW", "nan-TW"] {
            XCTAssertTrue(ids.contains(tag), "missing locale \(tag)")
        }
        XCTAssertEqual(KotoroLocale.named("ja-JP").name, "日本語")
        // Unknown tags fall back to the first locale rather than crashing.
        XCTAssertEqual(KotoroLocale.named("xx-XX").id, KotoroLocale.all[0].id)
    }

    func testDefaultIsProAndAllowsLongTakes() {
        XCTAssertTrue(KotoroAppInfo.defaultPro)
        XCTAssertGreaterThanOrEqual(KotoroAppInfo.maxTakeSeconds, 1800)
    }

    func testTimecodeFormatting() {
        XCTAssertEqual(KotoroAppInfo.timecode(0), "0:00")
        XCTAssertEqual(KotoroAppInfo.timecode(60), "1:00")
        XCTAssertEqual(KotoroAppInfo.timecode(1815), "30:15")
        XCTAssertEqual(KotoroAppInfo.timecode(3661), "1:01:01")
    }
}

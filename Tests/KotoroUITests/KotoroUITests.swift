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
        XCTAssertEqual(KotoroAppInfo.version, "0.2.0")
    }
}

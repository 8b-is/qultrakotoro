import XCTest
@testable import QuantTern
@testable import KotoroCore

final class QuantTernTests: XCTestCase {

    func testTritThresholds() {
        XCTAssertEqual(Trit(0.9), .plus)
        XCTAssertEqual(Trit(-0.9), .minus)
        XCTAssertEqual(Trit(0.1), .zero)          // a real "don't know"
        XCTAssertEqual(Trit(0.33), .plus)         // boundary is inclusive
    }

    func testPackRoundTrip() {
        let trits: [Trit] = [.plus, .zero, .minus, .plus, .minus, .zero, .zero, .plus, .minus]
        let code = QuantTern.pack(trits)
        XCTAssertEqual(code.bytes.count, 3)       // 9 trits → 3 bytes (4 per byte, zero-padded)
        XCTAssertTrue(code.hex.hasPrefix("qt:"))
        XCTAssertEqual(QuantTern.unpack(code.bytes, count: trits.count), trits)
    }

    func testEncodeNeutralIsZero() {
        let code = QuantTern.encode(.neutral)
        XCTAssertTrue(code.isNeutral)
        XCTAssertEqual(code.magnitude, 0)
        XCTAssertEqual(code.bytes, [0b01010101])  // every trit = zero (code 1)
    }

    func testEncodePositiveWords() {
        let tagger = EmotionTagger()
        let v = tagger.vad(for: "I love this warm good hope")
        XCTAssertGreaterThan(v.valence, 0.5)
        let code = tagger.code(for: "I love this warm good hope")
        XCTAssertEqual(code.trits.first, .plus)   // valence trit fires
    }

    func testAgreementIdentity() {
        let a = QuantTern.encode(VAD(valence: 0.8, arousal: 0.5, dominance: 0)).trits
        XCTAssertEqual(QuantTern.agreement(a, a), 1.0)
    }
}

final class AccessTests: XCTestCase {

    func testFreeCeiling() {
        let e = Entitlement.free
        XCTAssertTrue(e.allows(seconds: 60))
        XCTAssertFalse(e.allows(seconds: 60.1))
        XCTAssertFalse(e.isPro)
        XCTAssertFalse(e.betaManuscripts)
    }

    func testProIsUnlimitedAndGetsManuscripts() {
        let e = Entitlement.pro()
        XCTAssertTrue(e.isPro)
        XCTAssertTrue(e.allows(seconds: 3600))
        XCTAssertTrue(e.betaManuscripts)
        XCTAssertEqual(Entitlement.proMonthlyEUR, Decimal(string: "4.20"))
    }

    func testSessionThrowsOverFreeLimit() {
        let s = KotoroSession(entitlement: .free)
        XCTAssertNoThrow(try s.check(seconds: 30))
        XCTAssertThrowsError(try s.check(seconds: 61)) { err in
            XCTAssertEqual(err as? KotoroError, .freeLimitReached(limit: 60))
        }
    }
}

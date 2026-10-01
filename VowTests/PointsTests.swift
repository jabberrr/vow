import XCTest
@testable import Vow

final class PointsTests: XCTestCase {

    private let minus: String = "\u{2212}"

    func testUnsigned() {
        XCTAssertEqual(Points.format(5), "5 pts")
        XCTAssertEqual(Points.format(2.0 / 3.0), "0.67 pts")
        XCTAssertEqual(Points.format(1.5), "1.5 pts")
        XCTAssertEqual(Points.format(10), "10 pts")
        XCTAssertEqual(Points.format(0), "0 pts")
        XCTAssertEqual(Points.format(1.999), "2 pts")
        XCTAssertEqual(Points.format(-2), "\(minus)2 pts")
        XCTAssertEqual(Points.format(-0.001), "0 pts")
    }

    func testSigned() {
        XCTAssertEqual(Points.format(4.0 / 3.0, signed: true), "+1.33 pts")
        XCTAssertEqual(Points.format(0, signed: true), "+0 pts")
        XCTAssertEqual(Points.format(-0.004, signed: true), "+0 pts")
        XCTAssertEqual(Points.format(-2, signed: true), "\(minus)2 pts")
        XCTAssertEqual(Points.format(-2.5, signed: true), "\(minus)2.5 pts")
        XCTAssertEqual(Points.format(15, signed: true), "+15 pts")
    }

    func testStakeOptions() {
        XCTAssertEqual(Points.stakeOptions, [1, 2, 5, 10])
    }

    func testVowTextSplit() {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split("I will train for 30 minutes")
        XCTAssertEqual(parts.prefix, "I will ")
        XCTAssertEqual(parts.verb, "train")
        XCTAssertEqual(parts.suffix, " for 30 minutes")
    }
}

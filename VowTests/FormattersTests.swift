import XCTest
@testable import Vow

final class FormattersTests: XCTestCase {
    func testShortNamesDisambiguateOnlyDuplicates() {
        XCTAssertEqual(NameFormat.shortNames(["Sam Lee", "Maya", "sam Park", "Sam"]), ["Sam L.", "Maya", "sam P.", "Sam"])
        XCTAssertEqual(NameFormat.shortNames(["Jonathan Doe", ""]), ["Jonathan", "Someone"])
    }

    func testBalancePartsNeverShowsPlusZero() {
        XCTAssertEqual(PointsText.balanceParts(0).number, "0")
        XCTAssertEqual(PointsText.balanceParts(0.004).number, "0")
        XCTAssertEqual(PointsText.balanceParts(14.5).number, "+14.5")
        XCTAssertEqual(PointsText.balanceParts(-3).number, "\u{2212}3")
        XCTAssertEqual(PointsText.balanceParts(1).unit, "pt")
    }

    func testMilestoneText() {
        XCTAssertEqual(MilestoneText.title(.milestone(7)), "One week")
        XCTAssertEqual(MilestoneText.title(.milestone(50)), "50 days")
        XCTAssertEqual(MilestoneText.title(.newBest(22)), "New best")
        XCTAssertEqual(MilestoneText.announcement(streak: 7, event: .milestone(7)), "Checked in. 7-day streak. One week.")
        XCTAssertEqual(MilestoneText.announcement(streak: 1, event: nil), "Checked in. 1-day streak.")
    }

    func testVoteRuleText() {
        XCTAssertEqual(VoteRuleText.title(.majority), "More than half")
        XCTAssertEqual(VoteRuleText.title(.twoThirds), "Two thirds")
        XCTAssertEqual(VoteRuleText.title(.everyone), "Everyone")
        let tail: String = " they don't, by the end of the next day."
        XCTAssertEqual(VoteRuleText.summary(.majority),
                       "Check-ins and excuses count unless more than half of the others say" + tail)
        XCTAssertEqual(VoteRuleText.summary(.twoThirds),
                       "Check-ins and excuses count unless two thirds of the others say" + tail)
        XCTAssertEqual(VoteRuleText.summary(.everyone), "Check-ins and excuses count unless everyone else says" + tail)
    }
}

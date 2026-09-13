import XCTest
import HealthKit
@testable import Veyra

final class HealthUnitTests: XCTestCase {
    func testVO2UnitHasTimeInDenominator() throws {
        let definition = try XCTUnwrap(HealthCatalog.quantities.first { $0.key == "vo2" })
        let canonical = HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
        let sample = HKQuantity(unit: canonical, doubleValue: 42)
        let unit = HealthCatalog.unit(for: definition)
        XCTAssertTrue(sample.is(compatibleWith: unit))
        XCTAssertEqual(sample.doubleValue(for: unit), 42, accuracy: 0.001)
    }
    func testPercentIsConvertedFromFraction() throws {
        let definition = try XCTUnwrap(HealthCatalog.quantities.first { $0.key == "oxygen" })
        let sample = HKQuantity(unit: .percent(), doubleValue: 0.98)
        XCTAssertEqual(sample.doubleValue(for: HealthCatalog.unit(for: definition)) * 100, 98, accuracy: 0.001)
    }
}

import XCTest
@testable import Due

final class PaymentTests: XCTestCase {
    private func month(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }
    func testDueDateClampsToFebruary() {
        let payment = Payment(name: "Rent", amount: 100, day: 31, category: "Housing", reminderDays: 2)
        XCTAssertEqual(Calendar.current.component(.day, from: payment.date(in: month(2026, 2))), 28)
        XCTAssertEqual(Calendar.current.component(.day, from: payment.date(in: month(2028, 2))), 29)
        XCTAssertEqual(Calendar.current.component(.day, from: payment.date(in: month(2026, 4))), 30)
    }
    func testPaymentRoundTripPreservesMoneyAndPaidHistory() throws {
        var payment = Payment(name: "Internet", amount: Decimal(string: "59.99")!, day: 15, category: "Bills", reminderDays: 3)
        payment.paidMonths.insert("2026-10")
        let restored = try JSONDecoder().decode(Payment.self, from: JSONEncoder().encode(payment))
        XCTAssertEqual(restored.id, payment.id)
        XCTAssertEqual(restored.amount, Decimal(string: "59.99"))
        XCTAssertTrue(restored.paidMonths.contains("2026-10"))
        XCTAssertFalse(restored.paidMonths.contains("2026-11"))
        XCTAssertEqual(restored.reminderDays, 3)
    }
}

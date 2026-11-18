import XCTest

final class FLSDemoUITests: XCTestCase {
    @MainActor
    func testAllExamplesAndCancellation() throws {
        let app = XCUIApplication()
        app.launch()
        let get = app.buttons["action-get"]
        XCTAssertTrue(get.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: get)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: get)], timeout: 10) == .completed)

        let cases = [
            ("get", "完成：GET 请求", "Hello FLSNetworking"),
            ("post", "完成：JSON POST", "method: POST"),
            ("payload", "完成：业务响应解析", "业务数据解析成功"),
            ("upload", "完成：文件上传", "receivedBytes: 262144"),
            ("download", "完成：文件下载", "已校验 262144 bytes"),
            ("httpError", "预期错误：HTTP 503", "演示服务暂时不可用"),
            ("businessError", "预期错误：业务 401", "演示业务错误")
        ]
        for (action, status, result) in cases {
            app.buttons["action-\(action)"].tap()
            let completed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", status), object: app.staticTexts["status"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 10), .completed, action)
            XCTAssertTrue(app.staticTexts["result"].label.contains(result), action)
        }

        app.buttons["action-slow"].tap()
        let cancel = app.buttons["cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        // Let the request reach the local HTTP server before cancelling the in-flight task.
        let running = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "执行中"), object: app.staticTexts["status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 2), .completed)
        cancel.tap()
        let cancelled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已取消"), object: app.staticTexts["status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["result"].label.contains("CancellationError"))
    }
}

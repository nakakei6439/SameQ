import XCTest

/// evaluator（eval-7）が追加した実 e2e テスト。
/// 実機 1 台の UI 操作 + URLSession による「もう 1 台」の実クライアントで、
/// spec.md 受け入れ条件 1・3 を本番 Supabase に対して直接確かめる。
///
/// - 条件1: 端末Aの投稿が「もう1台」(URLSession) の world_timeline に他人の回答として出る
/// - 条件3: 「もう1台」が端末Aの回答にいいねすると、端末Aの today.receivedLikes が 1 になる
final class SprintTwelveEvalE2ETests: XCTestCase {

    private let baseURL = URL(string: "https://loqumzfgnahtclnvnrzb.supabase.co")!
    private let apiKey = "sb_publishable_-N3uUwv7XYfRIdr4WI_39Q_23swTNEL"

    private let emoji = "🌙"
    private let nickname = "EvalAlice"

    @MainActor
    func test_condition1_and_3_realDeviceB() async throws {
        let marker = "EVAL7-\(UUID().uuidString.prefix(8))"
        let body = "空がしずかだった \(marker)"

        // --- 端末A: アプリを Supabase 経路で起動しオンボーディング完了 → 投稿 ---
        let app = XCUIApplication()
        app.launchArguments = [
            "-SameQScenario", "live",
            "-SameQFakePlus",
            "-SameQTimeOffsetMinutes", "0",
            "-SameQResetState",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 15))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()
        let field = app.textFields["onboarding.nickname"]
        field.tap()
        field.typeText(nickname)
        app.buttons["onboarding.next"].tap()
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["onboarding.notification.later"].tap()

        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "オンボーディング後に today.input に到達できない")
        editor.tap()
        editor.typeText(body)
        if app.buttons["today.doneEditing"].exists { app.buttons["today.doneEditing"].tap() }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["today.submit"].tap()

        XCTAssertTrue(app.staticTexts["today.myAnswer"].waitForExistence(timeout: 20), "投稿後に today.myAnswer が出ない")
        XCTAssertFalse(app.staticTexts["today.receivedLikes"].exists, "投稿直後に受信いいねが表示されている")

        // --- 「もう1台」(URLSession) : サインアップ → users 行 → prompt_001 に回答（F05 の解放条件）---
        let (tokenB, uidB) = try await signUp()
        try await postJSON(path: "/rest/v1/users",
                           body: ["id": uidB, "emoji": "🐼", "nickname": "EvalBob", "status": "active"],
                           token: tokenB)
        try await postJSON(path: "/rest/v1/posts",
                           body: ["prompt_id": "prompt_001", "author_id": uidB,
                                  "body": "Bの回答 \(marker)", "body_language": "ja"],
                           token: tokenB)

        // --- 条件1: 「もう1台」の world_timeline に端末Aの投稿が出る ---
        let timeline = try await get(path: "/rest/v1/world_timeline",
                                    query: "select=id,author_id,author_nickname,body&prompt_id=eq.prompt_001",
                                    token: tokenB)
        let rows = try JSONSerialization.jsonObject(with: timeline) as? [[String: Any]] ?? []
        let aPost = rows.first { ($0["body"] as? String)?.contains(marker) == true
            && ($0["body"] as? String)?.contains("空が") == true }
        XCTAssertNotNil(aPost, "条件1違反: 端末Aの投稿(\(marker))が『もう1台』のworld_timelineに出てこない。返却 \(rows.count) 件")
        guard let aPostID = aPost?["id"] as? String else {
            XCTFail("A の投稿 id を取得できない")
            return
        }

        // --- 条件3: 「もう1台」が A の投稿にいいね → 端末Aの受信いいねが 1 になる ---
        try await postJSON(path: "/rest/v1/likes",
                           body: ["user_id": uidB, "post_id": aPostID],
                           token: tokenB)

        let likesLabel = app.staticTexts["today.receivedLikes"]
        let appeared = likesLabel.waitForExistence(timeout: 20)
        XCTAssertTrue(appeared,
            "条件3違反: 『もう1台』が端末Aの回答にいいねしたのに、端末Aの today.receivedLikes が表示されない（受信いいね 0 のまま）")
        if appeared {
            XCTAssertTrue(likesLabel.label.contains("1"),
                "条件3: 受信いいねラベルが「1 件のいいね」でない: \(likesLabel.label)")
        }
    }

    // MARK: - Supabase REST ヘルパー（URLSession 直叩き）

    private func signUp() async throws -> (token: String, uid: String) {
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "eval", code: 1, userInfo: [NSLocalizedDescriptionKey: "signup failed: \(String(data: data, encoding: .utf8) ?? "")"])
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = j["access_token"] as? String ?? ""
        let user = j["user"] as? [String: Any] ?? [:]
        let uid = user["id"] as? String ?? ""
        return (token, uid)
    }

    private func postJSON(path: String, body: [String: Any], token: String) async throws {
        var req = URLRequest(url: URL(string: baseURL.absoluteString + path)!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) || code == 409 else {
            throw NSError(domain: "eval", code: code, userInfo: [NSLocalizedDescriptionKey: "POST \(path) -> \(code): \(String(data: data, encoding: .utf8) ?? "")"])
        }
    }

    private func get(path: String, query: String, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: baseURL.absoluteString + path + "?" + query)!)
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw NSError(domain: "eval", code: code, userInfo: [NSLocalizedDescriptionKey: "GET \(path) -> \(code): \(String(data: data, encoding: .utf8) ?? "")"])
        }
        return data
    }
}

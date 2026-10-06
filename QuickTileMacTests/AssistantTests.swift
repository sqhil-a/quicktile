import XCTest
import QuickTileCore

final class AssistantTests: XCTestCase {
    private let safari = AppEntry(id: "com.apple.Safari", name: "Safari")
    private func response(_ commands: [String], question: String = "") throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["commands":commands,"question":question]), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject:["choices":[["finish_reason":"stop", "message":["content":content]]]])
    }
    @MainActor func testStructuredRequestExcludesIdentifiersAndUsesRequiredModel() throws {
        let context = AssistantCommandContext(apps:[safari], shortcuts:[.init(id:UUID().uuidString,name:"Review")])
        let body = try GroqAssistant.requestBody(text:"Open Safari",context:context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any])
        XCTAssertEqual(json["model"] as? String,"openai/gpt-oss-120b")
        XCTAssertEqual(json["reasoning_effort"] as? String,"low")
        XCTAssertFalse(String(decoding:body,as:UTF8.self).contains(safari.id))
        let format = try XCTUnwrap(json["response_format"] as? [String:Any])
        XCTAssertEqual(format["type"] as? String,"json_schema")
    }
    @MainActor func testLargeCatalogIsBoundedAndRelevantAppSurvives() throws {
        var apps = (0..<1500).map { AppEntry(id: "test.\($0)", name: "Application \($0)") }
        apps.append(safari)
        let data = try GroqAssistant.requestBody(text:"Please open Safari",context:.init(apps:apps))
        XCTAssertLessThan(data.count, 14_000)
        XCTAssertTrue(String(decoding:data,as:UTF8.self).contains("Safari"))
    }
    @MainActor func testRateLimitFallsBackOnceAndKeepsSmallerModel() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistantFallbackTransportStub.self]
        let store = GroqAssistant(testingKey:"fake-test-key-never-live",sessionConfiguration:config)
        for _ in 0..<2 {
            let plans = try await store.resolve("Please open Safari",context:.init(apps:[safari]))
            XCTAssertEqual(plans.first?.action,.launchApp(bundleID:safari.id))
        }
    }
    @MainActor func testLiveConfiguredGroqInterpretationWithoutExecution() async throws {
        guard ProcessInfo.processInfo.environment["QUICKTILE_TEST_GROQ"] == "1" else { throw XCTSkip("Live cloud request is opt-in") }
        let store = GroqAssistant()
        XCTAssertTrue(store.configured)
        let plans = try await store.resolve("Please open Safari",context:.init(apps:[safari]))
        XCTAssertEqual(plans.first?.action,.launchApp(bundleID:safari.id))
    }
    @MainActor func testValidProviderResponseResolvesOnlyInstalledApp() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistantSuccessTransportStub.self]
        let store = GroqAssistant(testingKey:"fake-test-key-never-live",sessionConfiguration:config)
        let plans = try await store.resolve("Please open Safari",context:.init(apps:[safari]))
        XCTAssertEqual(plans.count,1); XCTAssertEqual(plans.first?.action,.launchApp(bundleID:safari.id))
    }
    @MainActor func testWebsiteCannotBeInferredFromSubstringOfAnotherAddress() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistantWebsiteTransportStub.self]
        let store = GroqAssistant(testingKey:"fake-test-key-never-live",sessionConfiguration:config)
        do { _ = try await store.resolve("open https://example.com.evil.com",context:.init()); XCTFail("Should ask for the full address") }
        catch { guard case GroqAssistantError.clarification = error else { return XCTFail("Expected clarification") } }
    }
    @MainActor func testMixedUnsafeResponseDoesNotReturnPartialPlans() throws {
        let data = try response(["Open Safari","run shell rm -rf files"])
        XCTAssertThrowsError(try GroqAssistant.plans(from:data,context:.init(apps:[safari])))
    }
    @MainActor func testAmbiguousInstalledAppProducesClarification() throws {
        let data = try response(["Open Editor"])
        XCTAssertThrowsError(try GroqAssistant.plans(from:data,context:.init(apps:[.init(id:"one.Editor",name:"Editor"),.init(id:"two.Editor",name:"Editor")]))) { error in
            guard case GroqAssistantError.clarification = error else { return XCTFail("Expected clarification") }
        }
    }
    @MainActor func testModelQuestionNeverExecutesItsCommands() throws {
        XCTAssertThrowsError(try GroqAssistant.plans(from:response(["Open Safari"],question:"Which app?"),context:.init(apps:[safari])))
    }
    @MainActor func testUnsupportedLastStepBlocksFirstStepBeforeExecution() throws {
        let context = AssistantCommandContext(apps:[safari],controls:.init(volume:0.4,brightness:0.5,displayID:1,displayName:"Built-in"))
        let plans = try GroqAssistant.plans(from:response(["Open Safari","Set brightness to 50%"]),context:context)
        XCTAssertThrowsError(try AssistantPlanValidation.validate(plans,capabilities:.init(),apps:[safari],shortcuts:[]))
    }
    @MainActor func testTransportRateLimitIsSafeAndNoProviderBodyEscapes() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistantTransportStub.self]
        let store = GroqAssistant(testingKey:"fake-test-key-never-live",sessionConfiguration:config)
        do { _ = try await store.resolve("Open Safari",context:.init(apps:[safari])); XCTFail("Should fail") }
        catch { XCTAssertEqual(error as? GroqAssistantError,.rateLimited) }
        XCTAssertFalse(store.status.contains("private provider body"))
    }
    @MainActor func testInvalidRequestsAndCancelledKeyCannotReachProvider() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistantTransportStub.self]
        let store = GroqAssistant(testingKey:"fake-test-key-never-live",sessionConfiguration:config)
        do { _ = try await store.resolve("",context:.init()); XCTFail("Should fail") }
        catch { XCTAssertEqual(error as? GroqAssistantError,.invalidRequest) }
        try store.removeKey()
        do { _ = try await store.resolve("Open Safari",context:.init()); XCTFail("Should fail") }
        catch { XCTAssertEqual(error as? GroqAssistantError,.notConfigured) }
    }
    func testAssistantRequestRejectsEmptyOversizedAndNulText() throws {
        for text in ["",String(repeating:"a",count:2001),"open\0app"] {
            XCTAssertThrowsError(try AssistantRequest(sessionID:UUID(),createdAt:Date(),text:text).validate())
        }
    }
}
final class AssistantTransportStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.groq.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url:request.url!,statusCode:429,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("private provider body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private class AssistantSuccessTransportStub: URLProtocol {
    var command: String { "Open Safari" }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.groq.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let content = String(decoding:try! JSONSerialization.data(withJSONObject:["commands":[command],"question":""]),as:UTF8.self)
        let body = try! JSONSerialization.data(withJSONObject:["choices":[["finish_reason":"stop","message":["content":content]]]])
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class AssistantWebsiteTransportStub: AssistantSuccessTransportStub {
    override var command: String { "Open website https://example.com" }
}

private final class AssistantFallbackTransportStub: AssistantSuccessTransportStub {
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer,maxLength:buffer.count); if count <= 0 { break }; data.append(buffer,count:count) }
            return data
        } ?? Data()
        let object = (try? JSONSerialization.jsonObject(with:body)) as? [String:Any]
        if object?["model"] as? String == "openai/gpt-oss-20b" { super.startLoading() }
        else {
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:429,httpVersion:"HTTP/1.1",headerFields:[:])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

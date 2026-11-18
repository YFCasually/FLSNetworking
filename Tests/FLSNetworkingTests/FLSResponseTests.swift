import Foundation
import Testing
@testable import FLSNetworking

private struct FLSItem: Codable, Sendable, Equatable { let name: String }

private struct FLSStubClient: FLSHTTPClient {
    let data: Data
    func execute(_ endpoint: any FLSEndpoint) async throws -> FLSHTTPResponse {
        FLSHTTPResponse(data: data, statusCode: 200)
    }
}

struct FLSResponseTests {
    @Test func decodesDirectPayload() async throws {
        let client = FLSStubClient(data: Data(#"{"name":"sample"}"#.utf8))
        let value = try await client.request(FLSRequest(path: "x"), as: FLSItem.self)
        #expect(value.name == "sample")
    }

    @Test(arguments: [#"{"code":0,"data":{"name":"sample"}}"#, #"{"code":"0","data":{"name":"sample"}}"#])
    func decodesExplicitEnvelope(_ json: String) async throws {
        let client = FLSStubClient(data: Data(json.utf8))
        let value = try await client.requestPayload(FLSRequest(path: "x"), as: FLSItem.self, successCodes: ["0"])
        #expect(value.name == "sample")
    }

    @Test func preservesBusinessFailureBeforeDecodingPayload() async throws {
        let client = FLSStubClient(data: Data(#"{"code":401,"msg":"Expired","data":"unexpected shape"}"#.utf8))
        do {
            _ = try await client.requestPayload(FLSRequest(path: "x"), as: FLSItem.self, successCodes: ["0"])
            Issue.record("Expected business failure")
        } catch FLSNetworkError.business(let code, let message) {
            #expect(code == "401")
            #expect(message == "Expired")
        }
    }

    @Test func rejectsMissingPayloadAndMalformedSuccess() async throws {
        let missing = FLSStubClient(data: Data(#"{"code":0,"data":null}"#.utf8))
        do {
            _ = try await missing.requestPayload(FLSRequest(path: "x"), as: FLSItem.self, successCodes: ["0"])
            Issue.record("Expected empty response")
        } catch FLSNetworkError.emptyResponse { }
        let malformed = FLSStubClient(data: Data(#"{"code":0,"data":"wrong"}"#.utf8))
        do {
            _ = try await malformed.requestPayload(FLSRequest(path: "x"), as: FLSItem.self, successCodes: ["0"])
            Issue.record("Expected decoding error")
        } catch FLSNetworkError.decoding { }
    }

    @Test func supportsCustomDecoderAndCaseInsensitiveHeaders() throws {
        struct FLSModel: Decodable, Sendable { let displayName: String }
        let response = FLSHTTPResponse(data: Data(#"{"display_name":"test"}"#.utf8), statusCode: 200, headers: ["X-ID": "123"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        #expect(try response.decode(FLSModel.self, decoder: decoder).displayName == "test")
        #expect(response.header(named: "x-id") == "123")
    }

    @Test func emptyRawResponseRejectsTypedDecoding() throws {
        let response = FLSHTTPResponse(data: Data(), statusCode: 204)
        do {
            _ = try response.decode(FLSItem.self)
            Issue.record("Expected empty response")
        } catch FLSNetworkError.emptyResponse { }
    }
}

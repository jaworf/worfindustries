
import Foundation
final class FixtureLogoProtocol: URLProtocol, @unchecked Sendable {
    static let bytes = Data([137,80,78,71,13,10,26,10])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
        precondition(request.value(forHTTPHeaderField: "apikey") == "fixture-publishable-key")
        let path = request.url!.path
        precondition(path.hasSuffix("/abcdefab-1234-4567-89ab-abcdefabcdef/logo"))
        let responseBody: Data
        if request.httpMethod == "POST" {
            precondition(path.hasPrefix("/storage/v1/object/church-logos/"))
            precondition(request.value(forHTTPHeaderField: "x-upsert") == "true")
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
            responseBody = Data("{}".utf8)
        } else {
            precondition(path.hasPrefix("/storage/v1/object/authenticated/church-logos/"))
            responseBody = Self.bytes
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main enum LogoStorageSmoke {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureLogoProtocol.self]
        let id = UUID(uuidString:"ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF")!
        let session = SupabaseSession(accessToken:"fixture-access-token",refreshToken:"fixture-refresh",expiresAt:nil,user:SupabaseUser(id:id,email:nil))
        let client = SupabaseRESTClient(configuration:SupabaseConfiguration(projectURL:"https://fixture.invalid",publishableKey:"fixture-publishable-key"),session:session,urlSession:URLSession(configuration:configuration))
        try await client.uploadChurchLogo(churchId:id,png:FixtureLogoProtocol.bytes)
        let downloaded = try await client.churchLogo(churchId:id)
        precondition(downloaded == FixtureLogoProtocol.bytes)
        print("Logo storage smoke passed: church-scoped paths, bearer authorization, private download, PNG upload, and replacement headers.")
    }
}


import Foundation
import PDFKit
import CoreGraphics
struct LocalRuntime: Decodable { let url: String; let publishableKey: String }
struct LocalAccount: Decodable { let email: String; let password: String }
@main enum FullStackLogoSmoke {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtime = try JSONDecoder().decode(LocalRuntime.self, from: Data(contentsOf: root.appendingPathComponent(".local-runtime.json")))
        precondition(runtime.url == "http://127.0.0.1:54321")
        let accounts = try JSONDecoder().decode([String:LocalAccount].self, from: Data(contentsOf: root.appendingPathComponent(".local-test-accounts.json")))
        let configuration = SupabaseConfiguration(projectURL: runtime.url, publishableKey: runtime.publishableKey)
        let client = SupabaseRESTClient(configuration: configuration)
        let alpha = accounts["applicant"]!
        _ = try await client.signIn(email: alpha.email, password: alpha.password)
        let profile = try await client.loadCurrentProfile()
        let church = try await client.loadChurch(id: profile.churchId)
        let logo = try Data(contentsOf: root.deletingLastPathComponent().appendingPathComponent("fictional-church-logo.png"))
        try await client.uploadChurchLogo(churchId: church.id, png: logo)
        let stored = try await client.churchLogo(churchId: church.id)
        precondition(stored == logo, "Native private Storage round trip failed")
        let other = SupabaseRESTClient(configuration: configuration)
        let beta = accounts["beta"]!
        _ = try await other.signIn(email: beta.email, password: beta.password)
        let forbidden = try await other.churchLogo(churchId: church.id)
        precondition(forbidden == nil, "Another church could download this logo")
        let snapshot = try await client.loadSnapshot()
        let pdf = try ReportGenerator.makePDF(assignments:snapshot.assignments,filterDescription:"Local full-stack test",churchName:church.name,churchLogoData:stored)
        let document = PDFDocument(data: pdf)!
        precondition(document.string?.contains(church.name) == true)
        for index in 0..<document.pageCount {
            let dictionary = document.page(at:index)!.pageRef!.dictionary!
            var resources: CGPDFDictionaryRef?; var images: CGPDFDictionaryRef?
            precondition(CGPDFDictionaryGetDictionary(dictionary,"Resources",&resources))
            precondition(CGPDFDictionaryGetDictionary(resources!,"XObject",&images))
            precondition(CGPDFDictionaryGetCount(images!) > 0)
        }
        try pdf.write(to: root.deletingLastPathComponent().appendingPathComponent("real-local-church-report.pdf"))
        print("PASS: Native real Auth sign-in, own-church logo upload/download, cross-church denial, and PDF church name/image resources.")
    }
}

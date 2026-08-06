import Foundation

@main
enum PlanningCenterSyncSmoke {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let projectURL = environment["SUPABASE_URL"],
            let publishableKey = environment["SUPABASE_PUBLISHABLE_KEY"],
            let email = environment["RIVERVIEW_TEST_EMAIL"],
            let password = environment["RIVERVIEW_TEST_PASSWORD"]
        else {
            throw SmokeError.missingEnvironment
        }

        let client = SupabaseRESTClient(
            configuration: SupabaseConfiguration(
                projectURL: projectURL,
                publishableKey: publishableKey
            )
        )
        _ = try await client.signIn(email: email, password: password)

        do {
            let result = try await client.runPlanningCenterSync()
            print(
                "Planning Center sync completed with status \(result.status) " +
                "and \(result.counts.values.reduce(0, +)) outcomes."
            )
        } catch {
            let message = error.localizedDescription
            guard message.contains("Missing required secret: PCO_CLIENT_ID") else {
                throw error
            }
            print(
                "Planning Center sync endpoint and editor authorization passed; " +
                "the expected PCO_CLIENT_ID configuration is still missing."
            )
        }
    }
}

private enum SmokeError: Error {
    case missingEnvironment
}

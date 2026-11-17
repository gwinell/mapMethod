import SwiftUI
import SwiftData
#if os(macOS)
import Security
#endif

@main
struct MapMethodApp: App {
    private let modelContainer = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}

enum PersistenceController {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavingsGoal.self])
        let cloudDatabase: ModelConfiguration.CloudKitDatabase = hasCloudKitEntitlement
            ? .private("iCloud.com.gwinell.mapmethod")
            : .none
        let cloudConfiguration = ModelConfiguration(cloudKitDatabase: cloudDatabase)
        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            let localConfiguration = ModelConfiguration(cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [localConfiguration])
        }
    }

    private static var hasCloudKitEntitlement: Bool {
#if LOCAL_INSTALL
        return false
#elseif targetEnvironment(simulator)
        return false
#elseif os(iOS)
        return true
#else
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String] else { return false }
        return value.contains("iCloud.com.gwinell.mapmethod")
#endif
    }
}

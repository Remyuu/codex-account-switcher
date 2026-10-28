import Foundation
import Testing
@testable import SwitcherCore

@MainActor
struct AccountOrderTests {
    @Test func movingAccountsInBothDirectionsPersistsAcrossRestart() async throws {
        let fixture = try OrderFixture()
        defer { fixture.clean() }
        _ = try await fixture.prepare()
        await fixture.model.start()
        let profiles = fixture.model.accounts
        let active = fixture.model.activeAccountID
        let usage = try await fixture.store.loadUsageCache()
        let credentials = try await fixture.credentials(profiles)

        await fixture.model.moveAccount(id: profiles[3].id, relativeTo: profiles[0].id, after: false)
        #expect(fixture.model.accounts == [profiles[3], profiles[0], profiles[1], profiles[2]])
        await fixture.model.moveAccount(id: profiles[3].id, relativeTo: profiles[2].id, after: true)
        #expect(fixture.model.accounts == profiles)
        await fixture.model.moveAccount(id: profiles[1].id, relativeTo: profiles[2].id, after: true)
        let expected = [profiles[0], profiles[2], profiles[1], profiles[3]]
        #expect(fixture.model.accounts == expected)
        #expect(fixture.model.activeAccountID == active)
        #expect(fixture.model.activeIdentityConfirmed)
        #expect(fixture.model.visibleError == nil)
        #expect(try await fixture.credentials(profiles) == credentials)
        #expect(try await fixture.store.loadUsageCache() == usage)

        let reopened = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        let restarted = AccountController(store: reopened, codex: OrderClient(), switchService: OrderSwitch())
        await restarted.start()
        #expect(restarted.accounts.map(\.id) == expected.map(\.id))
        #expect(restarted.activeAccountID == active)
        #expect(restarted.visibleError == nil)
        #expect(try await reopened.syncActiveCredential().accounts.map(\.id) == expected.map(\.id))
    }

    @Test func invalidAndRedundantMovesNeverDropOrDuplicateAccounts() async throws {
        let fixture = try OrderFixture()
        defer { fixture.clean() }
        let profiles = try await fixture.prepare()
        let registryURL = fixture.base.appending(path: "accounts.json")
        let original = try Data(contentsOf: registryURL)
        for after in [false, true] {
            #expect(try await fixture.store.moveAccount(id: profiles[0].id,
                relativeTo: profiles[0].id, after: after).accounts == profiles)
            await #expect(throws: AccountStoreError.profileNotFound) {
                try await fixture.store.moveAccount(id: UUID(), relativeTo: profiles[0].id, after: after)
            }
            await #expect(throws: AccountStoreError.profileNotFound) {
                try await fixture.store.moveAccount(id: profiles[0].id, relativeTo: UUID(), after: after)
            }
        }
        #expect(try await fixture.store.moveAccount(id: profiles[0].id,
            relativeTo: profiles[1].id, after: false).accounts == profiles)
        #expect(try await fixture.store.moveAccount(id: profiles[1].id,
            relativeTo: profiles[0].id, after: true).accounts == profiles)
        #expect(try Data(contentsOf: registryURL) == original)
    }

    @Test func failedSaveKeepsDisplayedOrderAndReportsTheError() async throws {
        let fixture = try OrderFixture()
        defer { fixture.clean() }
        _ = try await fixture.prepare()
        await fixture.model.start()
        let profiles = fixture.model.accounts
        let active = fixture.model.activeAccountID
        let credentials = try await fixture.credentials(profiles)
        let registryURL = fixture.base.appending(path: "accounts.json")
        // A directory cannot be replaced by the registry's atomic file rename.
        try FileManager.default.removeItem(at: registryURL)
        try FileManager.default.createDirectory(at: registryURL, withIntermediateDirectories: false)
        await fixture.model.moveAccount(id: profiles[0].id, relativeTo: profiles[3].id, after: true)
        #expect(fixture.model.visibleError != nil)
        #expect(!fixture.model.isMutating)
        #expect(fixture.model.accounts == profiles)
        #expect(fixture.model.activeAccountID == active)
        #expect(try await fixture.store.loadRegistry().accounts == profiles)
        #expect(try await fixture.credentials(profiles) == credentials)
    }
}

@MainActor
private struct OrderFixture {
    let root: URL
    let base: URL
    let active: URL
    let store: AccountStore
    let model: AccountController

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "account-order-\(UUID())")
        base = root.appending(path: "store")
        active = root.appending(path: "active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: base, activeHomeURL: active)
        model = AccountController(store: store, codex: OrderClient(), switchService: OrderSwitch())
    }

    func prepare() async throws -> [AccountProfile] {
        var profiles: [AccountProfile] = []
        for index in 0..<4 {
            let profile = AccountProfile(id: UUID(), displayName: "Account \(index)",
                email: "order\(index)@example.test", accountID: "order-\(index)", createdAt: Date())
            let home = try await store.createProfileDirectory(id: profile.id)
            let bytes = try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "order-\(index)"]])
            try bytes.write(to: home.appending(path: "auth.json"))
            if index == 0 { try bytes.write(to: active.appending(path: "auth.json")) }
            try await store.addProfile(profile)
            try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 70 + index,
                resetsAt: Date().addingTimeInterval(86_400)), profileID: profile.id)
            profiles.append(profile)
        }
        return profiles
    }

    func credentials(_ profiles: [AccountProfile]) async throws -> [Data] {
        var bytes = [try Data(contentsOf: active.appending(path: "auth.json"))]
        for profile in profiles {
            let home = await store.profileHome(id: profile.id)
            bytes.append(try Data(contentsOf: home.appending(path: "auth.json")))
        }
        return bytes
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
}

private struct OrderClient: AccountClient {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity { throw CodexClientError.connectionClosed }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage { throw CodexClientError.connectionClosed }
    func login(profileHome: URL) async throws -> AccountIdentity { throw CodexClientError.connectionClosed }
}

private struct OrderSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws { throw CodexClientError.connectionClosed }
}

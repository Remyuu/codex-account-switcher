import AppKit
import SwiftUI
import Testing
import SwitcherCore
@testable import CodexAccountSwitcher

@MainActor
struct MenuBarPopoverTests {
    @Test(arguments: [false, true])
    func accountHeightIsIndependentOfPreviousPageAndCappedAtThreeRows(
        expandedUsage: Bool
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "popover-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "popover-layout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var heights: [Int: CGFloat] = [:]
        for count in [0, 1, 2, 3, 4, 20] {
            let model = try await makeModel(root: root.appending(path: "\(count)"), accountCount: count)
            await model.setShowsFiveHourUsage(expandedUsage)
            let updater = AppUpdater()
            let host = NSHostingController(rootView: MenuBarPopover(
                model: model, updater: updater, tiboForecast: TiboForecastModel(), defaults: defaults
            ))
            let maximumSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            let manageSize = NSHostingController(rootView: ManageAccountsView(model: model, onBack: {}))
                .sizeThatFits(in: maximumSize)
            let settingsSize = NSHostingController(rootView: SettingsView(model: model, updater: updater, onBack: {}))
                .sizeThatFits(in: maximumSize)

            // Exercise the first minimum-size probe, then heights left by both subpages.
            let firstSize = host.sizeThatFits(in: NSSize(width: 400, height: 0))
            heights[count] = firstSize.height
            for proposal in [manageSize, settingsSize, maximumSize] {
                let size = host.sizeThatFits(in: proposal)
                #expect(abs(size.height - firstSize.height) < 1)
                #expect(size.width == 400)
            }
        }
        let empty = try #require(heights[0])
        let one = try #require(heights[1])
        let two = try #require(heights[2])
        let three = try #require(heights[3])
        #expect(one > empty)
        #expect(two > one)
        #expect(three > two)
        #expect(heights[4] == three)
        #expect(heights[20] == three)
    }

    @Test(arguments: [0, 1, 20])
    func savedHeightSurvivesReopeningAndDoesNotDependOnAccountCount(accountCount: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "popover-resize-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "popover-resize-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try await makeModel(root: root, accountCount: accountCount)
        let maximum = PopoverSizing.maximumHeight()
        for requested in [220.0, 520.0, 660.0, 100_000.0] {
            defaults.set(requested, forKey: "popoverHeight")
            // A new host represents dismissing and reopening the menu bar popover.
            let host = NSHostingController(rootView: MenuBarPopover(
                model: model, updater: AppUpdater(), tiboForecast: TiboForecastModel(), defaults: defaults
            ))
            let expected = min(requested, maximum)
            for proposal in [0.0, 300.0, 900.0] {
                let size = host.sizeThatFits(in: NSSize(width: 400, height: proposal))
                #expect(abs(size.height - expected) < 1)
                #expect(size.width == 400)
            }
        }
    }

    @Test func resizeHandleKeepsFooterInsideTheScreenAndCanReset() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let screen = try #require(window.screen)
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY))
        let handle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 400, height: 14))
        window.contentView?.addSubview(handle)
        var height: CGFloat = 400
        handle.onResize = { value, _ in height = value }
        #expect(handle.accessibilityPerformIncrement())
        #expect(height == 440)
        window.setContentSize(NSSize(width: 400, height: 240))
        #expect(handle.accessibilityPerformDecrement())
        #expect(height == 220)
        window.setContentSize(NSSize(width: 400, height: 400))
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 40,
                                           y: screen.visibleFrame.minY + 300))
        #expect(handle.accessibilityPerformIncrement())
        #expect(height <= 292)
        var didReset = false
        handle.onReset = { didReset = true }
        let doubleClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        handle.mouseDown(with: doubleClick)
        #expect(didReset)
    }

    @Test func dragUsesEachEventsPositionForGrowingAndShrinking() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let screen = try #require(window.screen)
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY))
        let handle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 400, height: 14))
        window.contentView?.addSubview(handle)
        var height: CGFloat = 400
        handle.onResize = { value, _ in height = value }
        func event(_ type: CGEventType, y: CGFloat) throws -> NSEvent {
            let quartzEvent = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: 200, y: y), mouseButton: .left))
            return try #require(NSEvent(cgEvent: quartzEvent))
        }
        handle.mouseDown(with: try event(.leftMouseDown, y: 100))
        handle.mouseDragged(with: try event(.leftMouseDragged, y: 180))
        #expect(height == 480)
        let queuedDrag = try event(.leftMouseDragged, y: 0)
        // A resize moves the window's origin before the next queued event is handled.
        window.setContentSize(NSSize(width: 400, height: 480))
        handle.mouseDragged(with: queuedDrag)
        #expect(height == 300)
        handle.mouseUp(with: try event(.leftMouseUp, y: 0))
        handle.mouseDragged(with: try event(.leftMouseDragged, y: -100))
        #expect(height == 300)
    }

    private func makeModel(root: URL, accountCount: Int) async throws -> AppModel {
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "home"))
        for index in 0..<accountCount {
            let profile = AccountProfile(id: UUID(), displayName: "Account \(index)",
                                         email: "account\(index)@example.test", accountID: "account-\(index)",
                                         createdAt: Date())
            let home = try await store.createProfileDirectory(id: profile.id)
            try Data("fixture".utf8).write(to: home.appending(path: "auth.json"))
            try await store.addProfile(profile)
            try await store.cacheWeeklyUsage(
                WeeklyUsage(remainingPercent: 72, resetsAt: Date().addingTimeInterval(86_400),
                            fiveHourRemainingPercent: 85, fiveHourResetsAt: Date().addingTimeInterval(3_600)),
                profileID: profile.id
            )
        }
        let model = AppModel(store: store, codex: LayoutClient(), switchService: LayoutSwitch())
        await model.start()
        #expect(model.accounts.count == accountCount)
        #expect(model.visibleError == nil)
        return model
    }
}

private struct LayoutClient: AccountClient {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Layout test must not read an identity")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        throw CodexClientError.loginFailed("Layout test must not request usage")
    }
    func login(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Layout test must not log in")
    }
}

private struct LayoutSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws {
        throw CodexClientError.loginFailed("Layout test must not switch accounts")
    }
}

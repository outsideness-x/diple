//
//  dipleApp.swift
//  diple
//
//  Created by chemical_pink on 01.08.2026.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct dipleApp: App {
    // A static var change (`DipleAccent.current`) invalidates nothing on its own — SwiftUI
    // only re-renders what it observes. Observing the manager here and tagging the root with
    // `.id(accent)` forces the whole tree to rebuild when the accent changes, which is what
    // makes the computed colour tokens actually repaint. This resets tab/sidebar selection on
    // an accent change; that is the accepted price of not threading an environment value
    // through 28 files for something the user changes rarely and deliberately.
    @StateObject private var settingsManager = AppSettingsManager.shared
    /// Watched for one reason: iOS only lets an app change its Home Screen icon while it is
    /// active. See the `onChange` below.
    @Environment(\.scenePhase) private var scenePhase
    /// Settings is presented **here**, above the `.id` that rebuilds the interface on an accent
    /// change, rather than by the screen whose gear was tapped. See the `sheet` below.
    @State private var isShowingSettings = false

    init() {
        // The delegate must be installed before the root view appears, otherwise a tap on a
        // notification that cold-launches the app can be delivered before RootTabView starts
        // observing the routing event.
        UNUserNotificationCenter.current().delegate = DailyResurfacingNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if targetEnvironment(macCatalyst)
                FirstLaunchGate {
                    MacRootView()
                        .frame(minWidth: 980, minHeight: 680)
                }
                #else
                // A library that would not open used to crash the app on launch. Now the
                // reader gets told immediately, and a celebratory intro never covers the
                // failure with five seconds of unrelated animation.
                if let failure = AppDatabase.startupFailure {
                    DatabaseUnavailableView(failure: failure)
                } else {
                    FirstLaunchGate {
                        RootTabView()
                    }
                }
                #endif
            }
            // Deliberately not `.preferredColorScheme`. That modifier stamps its own
            // `overrideUserInterfaceStyle` on the root hosting controller, and a sheet
            // captures that value when it is presented — so changing the appearance while
            // the Settings sheet was open turned the screen behind it and left the sheet,
            // which is where the control lives, on the old theme. The window override below
            // is the single mechanism; with nothing competing, it cascades live into anything
            // presented in the window.
            .id(settingsManager.settings.accent)
            // Every screen under that `.id` is discarded and rebuilt when the accent changes,
            // and a sheet presented by one of them goes with it — so choosing an accent threw
            // the reader out of the screen they chose it on, and trying a second one meant
            // reopening Settings first. This modifier is applied *after* the `.id`, so its own
            // identity is stable and the sheet survives the rebuild underneath it. Screens ask
            // by notification because there are three of them (Home, the shelf, the Mac
            // sidebar) and none of them can hold this state themselves.
            .sheet(isPresented: $isShowingSettings) {
                AppSettingsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dipleOpenSettings)) { _ in
                isShowingSettings = true
            }
            .onChange(of: settingsManager.settings.appearance, initial: true) { _, appearance in
                DipleAppearance.apply(appearance)
            }
            // **Not** in the `.task` below, where this used to sit and never once worked.
            // iOS refuses to change an app icon while the app is anything but active, and at the
            // moment the root view first appears the scene is still `.inactive` — so the
            // reconciliation that exists to carry an accent chosen on another device onto this
            // one silently failed on every launch, leaving the icon on whatever was last set by
            // a direct tap in Settings. Activation is the earliest moment the call is allowed,
            // and running it on every activation costs nothing: `apply` returns immediately when
            // the icon already matches.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                AppIconManager.apply(settingsManager.settings.accent)
            }
            .task {
                // The window exists by now, which it did not when the settings manager was
                // built. Sheets and the keyboard take the window's style rather than the
                // SwiftUI preference, so this is what makes the choice cover all of them.
                DipleAppearance.apply(settingsManager.settings.appearance)

                // Notifications and sync both read the library; with no library to read,
                // starting them would only mean uploading an empty one over the real thing.
                guard AppDatabase.startupFailure == nil else { return }

                await DailyResurfacingService.shared.reconcileNotifications()
                // iCloud sync is opt-in (device-local flag, off by default — see CLAUDE.md).
                // Silent CloudKit pushes don't require notification permission, but the app
                // must register with APNs so CKSyncEngine can fetch while it is running.
                if CloudSyncService.isEnabled {
                    UIApplication.shared.registerForRemoteNotifications()
                    await CloudSyncService.shared.start()
                }
            }
        }
    }
}

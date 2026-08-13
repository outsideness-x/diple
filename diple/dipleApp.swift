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
                MacRootView()
                    .frame(minWidth: 980, minHeight: 680)
                #else
                // A library that would not open used to crash the app on launch. Now the
                // reader gets told, and nothing that queries the database is put on screen.
                if let failure = AppDatabase.startupFailure {
                    DatabaseUnavailableView(failure: failure)
                } else {
                    RootTabView()
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
            .onChange(of: settingsManager.settings.appearance, initial: true) { _, appearance in
                DipleAppearance.apply(appearance)
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
                // Reconciles the icon against whatever accent is already in `settings` before
                // touching the network: this is a local operation and has no reason to wait on
                // a CloudKit round trip. If an accent arrives later over iCloud, `AppSettingsManager`
                // updates `settings` itself and the next launch reconciles again.
                AppIconManager.apply(settingsManager.settings.accent)
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

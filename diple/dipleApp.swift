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
                    .preferredColorScheme(.dark)
                #else
                RootTabView()
                    .preferredColorScheme(.dark)
                #endif
            }
            .id(settingsManager.settings.accent)
            .task {
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

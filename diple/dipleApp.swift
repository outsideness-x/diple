//
//  dipleApp.swift
//  diple
//
//  Created by chemical_pink on 01.08.2026.
//

import SwiftUI
import UIKit

@main
struct dipleApp: App {
    // A static var change (`DipleAccent.current`) invalidates nothing on its own — SwiftUI
    // only re-renders what it observes. Observing the manager here and tagging the root with
    // `.id(accent)` forces the whole tree to rebuild when the accent changes, which is what
    // makes the computed colour tokens actually repaint. This resets tab/sidebar selection on
    // an accent change; that is the accepted price of not threading an environment value
    // through 28 files for something the user changes rarely and deliberately.
    @StateObject private var settingsManager = AppSettingsManager.shared

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
                // Silent CloudKit pushes don't require notification permission, but the app
                // must register with APNs so CKSyncEngine can fetch while it is running.
                UIApplication.shared.registerForRemoteNotifications()
                await CloudSyncService.shared.start()
                // Reconciles the icon against whatever accent CloudKit already applied to
                // `settings` during/before this launch, so a change made on another device
                // while this one was closed still moves the icon here.
                AppIconManager.apply(settingsManager.settings.accent)
            }
        }
    }
}

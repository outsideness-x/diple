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
            .task {
                // Silent CloudKit pushes don't require notification permission, but the app
                // must register with APNs so CKSyncEngine can fetch while it is running.
                UIApplication.shared.registerForRemoteNotifications()
                await CloudSyncService.shared.start()
            }
        }
    }
}

//
//  dipleApp.swift
//  diple
//
//  Created by chemical_pink on 01.08.2026.
//

import SwiftUI

@main
struct dipleApp: App {
    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(macCatalyst)
            MacRootView()
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
            #else
            RootTabView()
                .preferredColorScheme(.dark)
            #endif
        }
    }
}

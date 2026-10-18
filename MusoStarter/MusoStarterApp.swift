//
//  MusoStarterApp.swift
//  MusoStarter
//
//  Created by Nicholas Wong on 5/19/26.
//

import SwiftUI
import AppIntents
import GoogleSignIn

@main
struct MusoStarterApp: App {
    init() {
        AudioSessionManager.configureForPlayback()
        MusoAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

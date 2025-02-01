//
//  benodoroMacAppApp.swift
//  benodoroMacApp
//
//  Created by Bryan de Bourbon on 1/28/25.
//

import SwiftUI

@main
struct benodoroMacAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private var manager = PomodoroManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let statusButton = statusItem.button {
            statusButton.action = #selector(togglePopover)
            statusButton.target = self
            updateMenuBarTitle()
        }

        // Create and configure the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 200, height: 160)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        // Start the timer to update the menu bar text (keeps the countdown ticking).
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }

        // Start checking iCloud for updates
        Task {
            await PomodoroManager.shared.loadFromCloud()
        }


        // Also subscribe to state-change notifications.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMenuBarTitle),
                                               name: PomodoroManager.pomodoroStateDidChange,
                                               object: nil)
    }

    @objc private func updateMenuBarTitle() {
        if let button = statusItem.button {
            let timeString = formatTime(manager.timeRemaining)
            button.title = manager.timeRemaining > 0 ? timeString : "00:00"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}


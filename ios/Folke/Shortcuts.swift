import AppIntents

/// Siri og Genveje (milepæl 7). Sætningerne skal nævne appens navn.
struct FolkeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSleepIntent(), phrases: ["Start søvn i \(.applicationName)",
                                                          "\(.applicationName) sover"],
                    shortTitle: "Start søvn", systemImageName: "moon.zzz")
        AppShortcut(intent: StopSleepIntent(), phrases: ["Stop søvn i \(.applicationName)",
                                                         "\(.applicationName) er vågen"],
                    shortTitle: "Stop søvn", systemImageName: "sun.max")
        AppShortcut(intent: LogPumpingIntent(), phrases: ["Log udpumpning i \(.applicationName)"],
                    shortTitle: "Log udpumpning", systemImageName: "drop")
        AppShortcut(intent: LogBottleIntent(), phrases: ["Log flaske i \(.applicationName)"],
                    shortTitle: "Log flaske", systemImageName: "waterbottle")
    }
}

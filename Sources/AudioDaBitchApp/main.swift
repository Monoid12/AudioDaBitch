import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

let ADBAppVersion = "0.4.5"
let ADBRepoOwner = "Monoid12"
let ADBRepoName = "AudioDaBitch"
let ADBControlPort = 49372

struct AudioDeviceInfo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let maxInputChannels: Int
    let maxOutputChannels: Int
    let defaultSampleRate: Double
}

struct SourceConfig: Codable, Equatable {
    var enabled: Bool
    var deviceName: String
    var channels: [Int]
    var gainDb: Double
    var pan: Double
}

struct LimiterConfig: Codable, Equatable {
    var enabled: Bool
    var ceilingDb: Double
    var releaseMs: Double
}

struct DuckingConfig: Codable, Equatable {
    var mode: String
    var thresholdDb: Double
    var depthDb: Double
    var attackMs: Double
    var releaseMs: Double
}

struct XpilotAutoLevelConfig: Codable, Equatable {
    var enabled: Bool
    var targetRmsDb: Double
    var maxBoostDb: Double
    var maxCutDb: Double
    var attackMs: Double
    var releaseMs: Double
    var peakCeilingDb: Double
    var gateDb: Double
}

struct AudioConfig: Codable, Equatable {
    var sampleRate: Double
    var blockSize: Int
    var discord: SourceConfig
    var xpilot: SourceConfig
    var outputDeviceName: String
    var masterGainDb: Double
    var limiter: LimiterConfig
    var ducking: DuckingConfig
    var xpilotAutoLevel: XpilotAutoLevelConfig

    static let defaults = AudioConfig(
        sampleRate: 48000,
        blockSize: 480,
        discord: SourceConfig(enabled: true, deviceName: "BlackHole 2ch", channels: [1,2], gainDb: 0, pan: -0.75),
        xpilot: SourceConfig(enabled: true, deviceName: "BlackHole 16ch", channels: [1,2], gainDb: 0, pan: 0.75),
        outputDeviceName: "",
        masterGainDb: 0,
        limiter: LimiterConfig(enabled: true, ceilingDb: -1.0, releaseMs: 120),
        ducking: DuckingConfig(mode: "xpilot_ducks_discord", thresholdDb: -36, depthDb: -12, attackMs: 20, releaseMs: 220),
        xpilotAutoLevel: XpilotAutoLevelConfig(enabled: true, targetRmsDb: -18, maxBoostDb: 12, maxCutDb: 18, attackMs: 18, releaseMs: 160, peakCeilingDb: -3, gateDb: -55)
    )
}

struct EngineState: Codable {
    var ok: Bool
    var message: String
    var running: Bool
    var discordRmsDb: Double
    var xpilotRmsDb: Double
    var outputPeakDb: Double
    var xpilotAutoGainDb: Double
    var duckGainDb: Double
    var limiterGainDb: Double
}

struct GitHubAsset: Codable, Identifiable {
    var id: Int
    var name: String
    var browser_download_url: String
}

struct GitHubRelease: Codable {
    var tag_name: String
    var name: String?
    var body: String?
    var html_url: String
    var assets: [GitHubAsset]
}

final class AppLog {
    static let shared = AppLog()
    let logDir: URL
    let appLog: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDir = home.appendingPathComponent("Library/Logs/AudioDaBitch", isDirectory: true)
        appLog = logDir.appendingPathComponent("app.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: appLog.path), let handle = try? FileHandle(forWritingTo: appLog) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch { }
        } else {
            try? data.write(to: appLog)
        }
    }
}

@MainActor
final class AppState: NSObject, ObservableObject {
    @Published var config: AudioConfig = .defaults
    @Published var devices: [AudioDeviceInfo] = []
    @Published var engineState = EngineState(ok: false, message: "Engine startet...", running: false, discordRmsDb: -120, xpilotRmsDb: -120, outputPeakDb: -120, xpilotAutoGainDb: 0, duckGainDb: 0, limiterGainDb: 0)
    @Published var setupGuide: String = ""
    @Published var localChangelog: String = ""
    @Published var remoteChangelog: String = ""
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var updateAssetURL: String = ""
    @Published var updateStatus: String = "Noch nicht geprüft."
    @Published var setupStatus: String = ""
    @Published var showAbout = false

    private var engineProcess: Process?
    private var stateTimer: Timer?
    private var updateTimer: Timer?
    private let baseURL = URL(string: "http://127.0.0.1:\(ADBControlPort)")!

    func start() {
        AppLog.shared.write("AudioDaBitch \(ADBAppVersion) started")
        loadBundledText()
        startEngineIfNeeded()
        stateTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshEngineStateTimerFired), userInfo: nil, repeats: true)
        checkForUpdates()
        updateTimer = Timer.scheduledTimer(timeInterval: 60 * 30, target: self, selector: #selector(updateTimerFired), userInfo: nil, repeats: true)
    }

    @objc private func refreshEngineStateTimerFired() {
        fetchState()
        fetchDevices()
    }

    @objc private func updateTimerFired() {
        checkForUpdates()
    }

    func loadBundledText() {
        if let url = Bundle.main.url(forResource: "SetupGuide", withExtension: "md"), let text = try? String(contentsOf: url) { setupGuide = text }
        else { setupGuide = "SetupGuide.md nicht im Bundle gefunden." }
        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"), let text = try? String(contentsOf: url) { localChangelog = text }
        else { localChangelog = "CHANGELOG.md nicht im Bundle gefunden." }
    }

    func startEngineIfNeeded() {
        guard engineProcess == nil else { return }
        guard let engineDir = Bundle.main.resourceURL?.appendingPathComponent("engine", isDirectory: true) else {
            setupStatus = "Engine-Ressourcen nicht gefunden."
            AppLog.shared.write(setupStatus)
            return
        }
        let script = engineDir.appendingPathComponent("bootstrap_engine.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.currentDirectoryURL = engineDir
        var env = ProcessInfo.processInfo.environment
        env["AUDIODABITCH_VERSION"] = ADBAppVersion
        env["AUDIODABITCH_PORT"] = String(ADBControlPort)
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            AppLog.shared.write("engine-bootstrap: \(s.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        process.terminationHandler = { p in AppLog.shared.write("engine exited with status \(p.terminationStatus)") }
        do {
            try process.run()
            engineProcess = process
            setupStatus = "Audio-Engine wird im Hintergrund gestartet."
        } catch {
            setupStatus = "Audio-Engine konnte nicht gestartet werden: \(error.localizedDescription)"
            AppLog.shared.write(setupStatus)
        }
    }

    func stopEngine() {
        stateTimer?.invalidate()
        updateTimer?.invalidate()
        if let process = engineProcess, process.isRunning {
            process.terminate()
            AppLog.shared.write("engine termination requested")
        }
        engineProcess = nil
    }

    func fetchState() {
        URLSession.shared.dataTask(with: baseURL.appendingPathComponent("state")) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.engineState.message = "Engine nicht erreichbar: \(error.localizedDescription)"
                    self.engineState.ok = false
                }
                return
            }
            guard let data = data else { return }
            do {
                struct Payload: Codable { let state: EngineState; let config: AudioConfig }
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                DispatchQueue.main.async {
                    self.engineState = payload.state
                    if self.config != payload.config { self.config = payload.config }
                }
            } catch { AppLog.shared.write("state decode error: \(error)") }
        }.resume()
    }

    func fetchDevices() {
        URLSession.shared.dataTask(with: baseURL.appendingPathComponent("devices")) { data, _, _ in
            guard let data = data else { return }
            do {
                struct Payload: Codable { let devices: [AudioDeviceInfo] }
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                DispatchQueue.main.async { self.devices = payload.devices }
            } catch { }
        }.resume()
    }

    func applyConfig() {
        guard let body = try? JSONEncoder().encode(config) else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("config"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error { AppLog.shared.write("apply config failed: \(error)") }
        }.resume()
    }

    func resetDefaults() { config = .defaults; applyConfig() }
    func openLogs() { try? FileManager.default.createDirectory(at: AppLog.shared.logDir, withIntermediateDirectories: true); NSWorkspace.shared.open(AppLog.shared.logDir) }

    func exportDiagnosticZip() {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd_HHmmss"
        let panel = NSSavePanel(); panel.nameFieldStringValue = "AudioDaBitch_Logs_\(formatter.string(from: Date())).zip"; panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let destination = panel.url {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.arguments = ["-r", destination.path, "."]; process.currentDirectoryURL = AppLog.shared.logDir
            do { try process.run(); process.waitUntilExit(); AppLog.shared.write("exported diagnostic zip to \(destination.path)") }
            catch { AppLog.shared.write("zip export failed: \(error)") }
        }
    }

    func checkForUpdates() {
        updateStatus = "Prüfe GitHub Releases..."
        let url = URL(string: "https://api.github.com/repos/\(ADBRepoOwner)/\(ADBRepoName)/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error { DispatchQueue.main.async { self.updateStatus = "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)" }; return }
            guard let http = response as? HTTPURLResponse, let data = data else { return }
            if http.statusCode == 404 { DispatchQueue.main.async { self.updateStatus = "Noch kein public GitHub Release gefunden." }; return }
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latest = release.tag_name.replacingOccurrences(of: "v", with: "")
                let isNewer = Self.compareVersions(latest, ADBAppVersion) == .orderedDescending
                let pkgAsset = release.assets.first { $0.name.lowercased().hasSuffix(".pkg") }
                DispatchQueue.main.async {
                    self.latestVersion = latest
                    self.remoteChangelog = release.body ?? "Kein Release-Changelog vorhanden."
                    self.updateAvailable = isNewer && pkgAsset != nil
                    self.updateAssetURL = pkgAsset?.browser_download_url ?? ""
                    self.updateStatus = isNewer ? "Neue Version \(latest) verfügbar." : "AudioDaBitch ist aktuell."
                }
            } catch {
                DispatchQueue.main.async { self.updateStatus = "GitHub-Antwort konnte nicht gelesen werden." }
                AppLog.shared.write("release decode error: \(error)")
            }
        }.resume()
    }

    func downloadAndOpenUpdate() {
        guard let url = URL(string: updateAssetURL) else { return }
        let versionForFilename = latestVersion.isEmpty ? ADBAppVersion : latestVersion
        updateStatus = "Lade Update von GitHub..."
        URLSession.shared.downloadTask(with: url) { temp, _, error in
            if let error = error { DispatchQueue.main.async { self.updateStatus = "Download fehlgeschlagen: \(error.localizedDescription)" }; return }
            guard let temp = temp else { return }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dest = downloads.appendingPathComponent("AudioDaBitch_\(versionForFilename).pkg")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: temp, to: dest)
                DispatchQueue.main.async { self.updateStatus = "Update geladen. Installer wird geöffnet."; NSWorkspace.shared.open(dest) }
            } catch { DispatchQueue.main.async { self.updateStatus = "Update konnte nicht gespeichert werden: \(error.localizedDescription)" } }
        }.resume()
    }

    nonisolated static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aa = a.split(separator: ".").map { Int($0) ?? 0 }; let bb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(aa.count, bb.count) { let x = i < aa.count ? aa[i] : 0; let y = i < bb.count ? bb[i] : 0; if x > y { return .orderedDescending }; if x < y { return .orderedAscending } }
        return .orderedSame
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TabView {
            MixerView().tabItem { Label("Mixer", systemImage: "slider.horizontal.3") }
            RoutingHelpView().tabItem { Label("Setup", systemImage: "questionmark.circle") }
            UpdatesView().tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            LogsView().tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }
            AboutView().tabItem { Label("About", systemImage: "heart") }
        }.frame(minWidth: 980, minHeight: 720).sheet(isPresented: $state.showAbout) { AboutView().frame(width: 520, height: 420) }
    }
}

struct MixerView: View {
    @EnvironmentObject var state: AppState
    var inputDevices: [AudioDeviceInfo] { state.devices.filter { $0.maxInputChannels > 0 } }
    var outputDevices: [AudioDeviceInfo] { state.devices.filter { $0.maxOutputChannels > 0 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) { Text("AudioDaBitch").font(.largeTitle).bold(); Text("Status: \(state.engineState.message)").foregroundColor(state.engineState.ok ? .secondary : .red); Text(state.setupStatus).font(.caption).foregroundColor(.secondary) }
                Spacer(); Button("Geräte aktualisieren") { state.fetchDevices() }; Button("Übernehmen") { state.applyConfig() }.keyboardShortcut(.return); Button("Defaults") { state.resetDefaults() }
            }
            Divider()
            HStack(alignment: .top, spacing: 18) { SourcePanel(title: "Discord", levelDb: state.engineState.discordRmsDb, source: $state.config.discord, devices: inputDevices); SourcePanel(title: "xPilot", levelDb: state.engineState.xpilotRmsDb, source: $state.config.xpilot, devices: inputDevices) }
            GroupBox("Output / Master") { VStack(alignment: .leading) { DevicePicker(title: "Output", selection: $state.config.outputDeviceName, devices: outputDevices); SliderRow(title: "Master Gain", value: $state.config.masterGainDb, range: -24...12, suffix: " dB"); Toggle("Master Limiter aktiv", isOn: $state.config.limiter.enabled); SliderRow(title: "Limiter Ceiling", value: $state.config.limiter.ceilingDb, range: -12...0, suffix: " dBFS"); SliderRow(title: "Limiter Release", value: $state.config.limiter.releaseMs, range: 20...600, suffix: " ms"); MeterRow(title: "Output Peak", db: state.engineState.outputPeakDb); Text("Limiter Gain: \(state.engineState.limiterGainDb, specifier: "%.1f") dB").font(.caption).foregroundColor(.secondary) }.padding(8) }
            HStack(alignment: .top, spacing: 18) {
                GroupBox("Ducking") { VStack(alignment: .leading) { Picker("Mode", selection: $state.config.ducking.mode) { Text("xPilot duckt Discord").tag("xpilot_ducks_discord"); Text("Discord duckt xPilot").tag("discord_ducks_xpilot"); Text("Aus").tag("off") }; SliderRow(title: "Threshold", value: $state.config.ducking.thresholdDb, range: -60...(-12), suffix: " dBFS"); SliderRow(title: "Ducking-Tiefe", value: $state.config.ducking.depthDb, range: -30...0, suffix: " dB"); SliderRow(title: "Attack", value: $state.config.ducking.attackMs, range: 5...200, suffix: " ms"); SliderRow(title: "Release", value: $state.config.ducking.releaseMs, range: 50...1000, suffix: " ms"); Text("Aktuelles Ducking: \(state.engineState.duckGainDb, specifier: "%.1f") dB").font(.caption).foregroundColor(.secondary) }.padding(8) }
                GroupBox("xPilot Auto-Level") { VStack(alignment: .leading) { Toggle("xPilot Auto-Level aktiv", isOn: $state.config.xpilotAutoLevel.enabled); SliderRow(title: "Ziel-RMS", value: $state.config.xpilotAutoLevel.targetRmsDb, range: -30...(-10), suffix: " dBFS"); SliderRow(title: "Max Boost", value: $state.config.xpilotAutoLevel.maxBoostDb, range: 0...24, suffix: " dB"); SliderRow(title: "Max Cut", value: $state.config.xpilotAutoLevel.maxCutDb, range: 0...30, suffix: " dB"); SliderRow(title: "Fast Attack", value: $state.config.xpilotAutoLevel.attackMs, range: 5...120, suffix: " ms"); SliderRow(title: "Release", value: $state.config.xpilotAutoLevel.releaseMs, range: 50...800, suffix: " ms"); SliderRow(title: "Peak Ceiling", value: $state.config.xpilotAutoLevel.peakCeilingDb, range: -12...0, suffix: " dBFS"); Text("Auto-Gain: \(state.engineState.xpilotAutoGainDb, specifier: "%.1f") dB").font(.caption).foregroundColor(.secondary) }.padding(8) }
            }
        }.padding(18).onAppear { state.fetchDevices(); state.fetchState() }
    }
}

struct SourcePanel: View {
    let title: String; let levelDb: Double; @Binding var source: SourceConfig; let devices: [AudioDeviceInfo]
    var body: some View { GroupBox(title) { VStack(alignment: .leading, spacing: 10) { Toggle("Aktiv", isOn: $source.enabled); DevicePicker(title: "Input", selection: $source.deviceName, devices: devices); Picker("Channels", selection: Binding(get: { source.channels == [3,4] ? "3/4" : "1/2" }, set: { source.channels = $0 == "3/4" ? [3,4] : [1,2] })) { Text("1/2").tag("1/2"); Text("3/4").tag("3/4") }; SliderRow(title: "Gain", value: $source.gainDb, range: -30...18, suffix: " dB"); SliderRow(title: "Pan", value: $source.pan, range: -1...1, suffix: ""); MeterRow(title: "Level", db: levelDb); Text(source.pan < -0.2 ? "links" : (source.pan > 0.2 ? "rechts" : "mitte")).font(.caption).foregroundColor(.secondary) }.padding(8) } }
}
struct DevicePicker: View { let title: String; @Binding var selection: String; let devices: [AudioDeviceInfo]; var body: some View { Picker(title, selection: $selection) { Text(selection.isEmpty ? "Bitte auswählen" : selection).tag(selection); ForEach(devices) { device in Text("\(device.name)  (#\(device.id))").tag(device.name) } } } }
struct SliderRow: View { let title: String; @Binding var value: Double; let range: ClosedRange<Double>; let suffix: String; var body: some View { HStack { Text(title).frame(width: 130, alignment: .leading); Slider(value: $value, in: range); Text("\(value, specifier: "%.1f")\(suffix)").frame(width: 84, alignment: .trailing).monospacedDigit() } } }
struct MeterRow: View { let title: String; let db: Double; var normalized: Double { min(max((db + 60) / 60, 0), 1) }; var body: some View { HStack { Text(title).frame(width: 130, alignment: .leading); ProgressView(value: normalized).frame(width: 220); Text("\(db, specifier: "%.1f") dB").frame(width: 78, alignment: .trailing).monospacedDigit() } } }
struct RoutingHelpView: View { @EnvironmentObject var state: AppState; var body: some View { VStack(alignment: .leading) { Text("Einrichtung / Routing").font(.title).bold(); Text("Wichtig: Kein Multi-Output-Direktweg zum Kopfhörer, sonst wirkt der Limiter nicht vollständig.").foregroundColor(.orange); ScrollView { Text(state.setupGuide).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } }.padding(18) } }
struct UpdatesView: View { @EnvironmentObject var state: AppState; var body: some View { VStack(alignment: .leading, spacing: 14) { HStack { VStack(alignment: .leading) { Text("Updates").font(.title).bold(); Text("Repository: \(ADBRepoOwner)/\(ADBRepoName)"); Text("Installierte Version: \(ADBAppVersion)"); Text(state.updateStatus).foregroundColor(state.updateAvailable ? .green : .secondary) }; Spacer(); Button("Jetzt prüfen") { state.checkForUpdates() }; if state.updateAvailable { Button("Update installieren") { state.downloadAndOpenUpdate() }.buttonStyle(.borderedProminent) } }; Divider(); Text("GitHub Release Changelog").font(.headline); ScrollView { Text(state.remoteChangelog.isEmpty ? "Noch kein Remote-Changelog geladen." : state.remoteChangelog).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }; Divider(); Text("Lokales Changelog").font(.headline); ScrollView { Text(state.localChangelog).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } }.padding(18) } }
struct LogsView: View { @EnvironmentObject var state: AppState; var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Logs & Diagnose").font(.title).bold(); Text("Log-Verzeichnis: ~/Library/Logs/AudioDaBitch/").textSelection(.enabled); HStack { Button("Logs im Finder öffnen") { state.openLogs() }; Button("Diagnose-ZIP erstellen") { state.exportDiagnosticZip() } }; Text("Bitte bei Problemen die Diagnose-ZIP schicken. Darin liegen App-Log, Engine-Log und Setup-Informationen.").foregroundColor(.secondary); Spacer() }.padding(18) } }
struct AboutView: View { var body: some View { VStack(spacing: 16) { if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().frame(width: 96, height: 96).cornerRadius(20) }; Text("AudioDaBitch").font(.largeTitle).bold(); Text("Version \(ADBAppVersion)"); Text("Made with ♥ in Berlin - by Michel Damhorst").font(.headline); Text("Discord + xPilot Audio-Ducking, Auto-Leveling und Master-Limiter für macOS.").multilineTextAlignment(.center).foregroundColor(.secondary); Spacer() }.padding(32) } }

@main
struct AudioDaBitchApplication: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onAppear { state.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    state.stopEngine()
                }
        }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .appInfo) { Button("Über AudioDaBitch") { state.showAbout = true } } }
    }
}

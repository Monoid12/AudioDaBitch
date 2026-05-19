import Cocoa
import Foundation

let ADBVersion = "0.5.9"
let ADBPort = 49372
let ADBBaseURL = URL(string: "http://127.0.0.1:\(ADBPort)")!
let ADBLatestReleaseURL = URL(string: "https://api.github.com/repos/Monoid12/AudioDaBitch/releases/latest")!
let ADBReleasePageURL = URL(string: "https://github.com/Monoid12/AudioDaBitch/releases")!
let ADBUpdateAssetName = "AudioDaBitch.pkg"

func appSupportDir() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AudioDaBitch", isDirectory: true) }
func logDir() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AudioDaBitch", isDirectory: true) }
func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
func ensureDir(_ url: URL) { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
func log(_ message: String) {
    ensureDir(logDir())
    let url = logDir().appendingPathComponent("app.log")
    guard let data = "[\(nowISO())] \(message)\n".data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

struct Device: Codable { let id: Int; let name: String; let inputs: Int?; let outputs: Int? }
struct DevicesResponse: Codable { let inputs: [Device]; let outputs: [Device]; let error: String? }
struct HealthResponse: Codable { let ok: Bool; let version: String?; let sounddevice: Bool?; let error: String? }
struct Meters: Codable { let discord: Double?; let xpilot: Double?; let output: Double? }
struct Diagnostics: Codable { let sampleRate: Int?; let blockSize: Int?; let latency: String?; let callbackErrors: Int?; let lastError: String? }
struct StateResponse: Codable { let ok: Bool; let version: String?; let running: Bool?; let meters: Meters?; let levelerGainDb: Double?; let diagnostics: Diagnostics? }
struct GitHubAsset: Codable { let name: String; let browserDownloadURL: String; enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" } }
struct GitHubRelease: Codable { let tagName: String; let htmlURL: String?; let assets: [GitHubAsset]; enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case htmlURL = "html_url"; case assets } }

func normalizedVersion(_ text: String) -> [Int] {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^v", with: "", options: .regularExpression)
    return cleaned.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
}

func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
    let left = normalizedVersion(lhs)
    let right = normalizedVersion(rhs)
    let count = max(left.count, right.count)
    for idx in 0..<count {
        let a = idx < left.count ? left[idx] : 0
        let b = idx < right.count ? right[idx] : 0
        if a != b { return a > b }
    }
    return false
}

final class EngineManager {
    static let shared = EngineManager()
    private var process: Process?
    private var engineURL: URL? { Bundle.main.url(forResource: "engine", withExtension: "py") }
    let pidFile = appSupportDir().appendingPathComponent("engine.pid")

    func cleanupStale() {
        ensureDir(appSupportDir())
        ensureDir(logDir())
        if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
            kill(pid, SIGTERM)
            usleep(250_000)
            kill(pid, SIGKILL)
            try? FileManager.default.removeItem(at: pidFile)
        }
        _ = shell("/usr/bin/pkill", ["-f", "/Applications/AudioDaBitch.app/Contents/Resources/engine.py"])
        _ = shell("/usr/bin/pkill", ["-f", "Resources/engine.py"])
    }

    func start() {
        ensureDir(appSupportDir())
        ensureDir(logDir())
        if process?.isRunning == true { return }
        guard let engineURL else { log("engine.py missing in bundle"); return }
        cleanupStale()
        let python = findPython()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [engineURL.path]
        let err = logDir().appendingPathComponent("engine.stderr.log")
        FileManager.default.createFile(atPath: err.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: err) {
            process.standardError = handle
            process.standardOutput = handle
        }
        do {
            try process.run()
            self.process = process
            log("engine launched: \(python) \(engineURL.path)")
        } catch {
            log("engine launch failed: \(error)")
        }
    }

    func stop() {
        post("/shutdown", body: [:]) { _ in }
        if let process, process.isRunning {
            usleep(300_000)
            let deadline = Date().addingTimeInterval(1.2)
            while process.isRunning && Date() < deadline {
                usleep(100_000)
            }
            if process.isRunning {
                process.terminate()
                usleep(300_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process = nil
        cleanupStale()
    }

    func findPython() -> String {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3", "/usr/bin/python3"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        return "/usr/bin/python3"
    }

    func shell(_ executable: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { return "" }
    }

    func get(_ path: String, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: ADBBaseURL.appendingPathComponent(String(path.dropFirst()))) { data, _, _ in completion(data) }.resume()
    }

    func post(_ path: String, body: [String: Any], completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: ADBBaseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in completion(data) }.resume()
    }
}

final class MeterView: NSView {
    var valueDb: Double = -120 { didSet { needsDisplay = true } }
    var title = ""
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 48) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let text = "\(title)  \(Int(valueDb)) dB"
        text.draw(at: NSPoint(x: 0, y: 27), withAttributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        let rect = NSRect(x: 0, y: 9, width: bounds.width, height: 12)
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        let norm = max(0, min(1, (valueDb + 60) / 60))
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * norm, height: rect.height)
        (valueDb > -6 ? NSColor.systemRed : valueDb > -18 ? NSColor.systemOrange : NSColor.systemGreen).setFill()
        fill.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: rect).stroke()
    }
}

final class BlockView: NSBox {
    let popup = NSPopUpButton()
    let meter = MeterView()
    let gain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let pan = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)

    init(title: String, hasPan: Bool) {
        super.init(frame: .zero)
        self.title = title
        boxType = .custom
        borderColor = .separatorColor
        cornerRadius = 10
        contentViewMargins = NSSize(width: 12, height: 12)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor)
        ])
        meter.title = title
        stack.addArrangedSubview(meter)
        stack.addArrangedSubview(label("Gerät"))
        stack.addArrangedSubview(popup)
        stack.addArrangedSubview(label("Lautstärke"))
        stack.addArrangedSubview(gain)
        if hasPan {
            stack.addArrangedSubview(label("Panorama"))
            stack.addArrangedSubview(pan)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }
}

final class AppController: NSViewController {
    let tabs = NSTabView()
    let status = NSTextField(labelWithString: "Starte...")
    let diagnosticsLabel = NSTextField(labelWithString: "")
    let discord = BlockView(title: "Discord", hasPan: true)
    let xpilot = BlockView(title: "xPilot", hasPan: true)
    let output = BlockView(title: "Output", hasPan: false)
    let deviceError = NSTextField(labelWithString: "")
    let levelerInfo = NSTextField(labelWithString: "")
    let updateStatus = NSTextField(labelWithString: "Installiert: \(ADBVersion)")
    let updateButton = NSButton(title: "Update installieren", target: nil, action: nil)
    let helpText = NSTextView()
    let changeText = NSTextView()
    var updateTabItem: NSTabViewItem?
    var latestRelease: GitHubRelease?
    var latestAssetURL: URL?
    var timer: Timer?

    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 640)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        EngineManager.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.refreshAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.checkForUpdates(silent: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in self.pollState() }
    }

    func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])

        let top = NSStackView()
        top.orientation = .horizontal
        top.spacing = 8
        top.alignment = .centerY
        status.stringValue = "AudioDaBitch \(ADBVersion)"
        top.addArrangedSubview(status)
        top.addArrangedSubview(button("Geräte aktualisieren", #selector(loadDevices)))
        top.addArrangedSubview(button("Audio starten", #selector(startAudio)))
        top.addArrangedSubview(button("Audio stoppen", #selector(stopAudio)))
        top.addArrangedSubview(button("Audio stabilisieren", #selector(stabilizeAudio)))
        top.addArrangedSubview(button("Engine reparieren", #selector(repairEngine)))
        root.addArrangedSubview(top)

        diagnosticsLabel.textColor = .secondaryLabelColor
        diagnosticsLabel.font = .systemFont(ofSize: 11)
        root.addArrangedSubview(diagnosticsLabel)

        tabs.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(tabs)
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 530).isActive = true
        addTab("Audio", audioView())
        addTab("xPilot Leveler", levelerView())
        updateTabItem = addTab("Updates", updatesView())
        addTab("Changelog", textView(changeText, loadResource("CHANGELOG", fallback: fallbackChangelog())))
        addTab("Hilfe", textView(helpText, loadResource("HELP_BLACKHOLE_DE", fallback: fallbackHelp())))
        addTab("Logs", logsView())

        for popup in [discord.popup, xpilot.popup, output.popup] {
            popup.target = self
            popup.action = #selector(configChanged)
        }
        for slider in [discord.gain, xpilot.gain, output.gain, discord.pan, xpilot.pan] {
            slider.target = self
            slider.action = #selector(configChanged)
        }
        discord.pan.doubleValue = -1
        xpilot.pan.doubleValue = 1
    }

    @discardableResult
    func addTab(_ name: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: name)
        item.label = name
        item.view = view
        tabs.addTabViewItem(item)
        return item
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    func audioView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10)
        ])
        deviceError.textColor = .systemRed
        stack.addArrangedSubview(deviceError)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        for block in [discord, xpilot, output] {
            block.translatesAutoresizingMaskIntoConstraints = false
            block.widthAnchor.constraint(equalToConstant: 300).isActive = true
            row.addArrangedSubview(block)
        }
        stack.addArrangedSubview(row)
        let note = NSTextField(wrappingLabelWithString: "Qualität: Standard ist stabiler 48-kHz-Safe-Mode mit größerem Puffer. Bei Stottern bitte zuerst 'Audio stabilisieren' klicken und in Audio-MIDI-Setup alle Geräte auf 48.000 Hz stellen.")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        return view
    }

    func levelerView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18)
        ])
        let title = NSTextField(labelWithString: "xPilot Funk-Ausgleich")
        title.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(title)
        let body = NSTextField(wrappingLabelWithString: "Gleicht nur den xPilot-Kanal automatisch aus. Zu laute VATSIM-Stationen werden schnell abgesenkt, zu leise Stationen vorsichtig angehoben. Der Master-Limiter bleibt zusätzlich aktiv.")
        stack.addArrangedSubview(body)
        levelerInfo.stringValue = "Aktueller xPilot-Pegel: -120 dB    Auto-Korrektur: 0 dB"
        stack.addArrangedSubview(levelerInfo)
        let recommendation = NSTextField(wrappingLabelWithString: "Empfehlung: Standard aktiv lassen. Bei Funk-Rauschen Gate nicht zu niedrig setzen. Technische Werte werden später in 'Erweitert' verschoben.")
        recommendation.textColor = .secondaryLabelColor
        stack.addArrangedSubview(recommendation)
        return view
    }

    func updatesView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        updateStatus.stringValue = "Installiert: \(ADBVersion)."
        updateStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(updateStatus)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(button("Jetzt auf GitHub prüfen", #selector(checkUpdatesClicked)))
        updateButton.target = self
        updateButton.action = #selector(installUpdateClicked)
        updateButton.bezelStyle = .rounded
        updateButton.isEnabled = false
        row.addArrangedSubview(updateButton)
        row.addArrangedSubview(button("Release-Seite öffnen", #selector(openReleases)))
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(textView(NSTextView(), loadResource("CHANGELOG", fallback: fallbackChangelog())))
        return view
    }

    func logsView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18)
        ])
        stack.addArrangedSubview(button("Logs öffnen", #selector(openLogs)))
        stack.addArrangedSubview(button("Log-ZIP erstellen", #selector(exportLogs)))
        stack.addArrangedSubview(button("Hängende Prozesse beenden", #selector(killStale)))
        return view
    }

    func textView(_ textView: NSTextView, _ text: String) -> NSScrollView {
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = text
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        return scroll
    }

    func loadResource(_ name: String, fallback: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        return fallback
    }

    func fallbackHelp() -> String { "BlackHole Routing:\n\n1. Discord Output -> BlackHole 2ch\n2. xPilot Headset/Speaker -> BlackHole 16ch\n3. AudioDaBitch Output -> Kopfhörer/Audiointerface\n\nKein Multi-Output mit Kopfhörer verwenden, sonst läuft Audio am Limiter vorbei.\n\nAlle Geräte sollten in Audio-MIDI-Setup auf 48.000 Hz stehen." }
    func fallbackChangelog() -> String { "# Changelog\n\n## 0.5.9\n- PKG-Installation nach /Applications repariert\n- Audio-Basis aus 0.5.6 bleibt erhalten\n- Update- und Installer-Prüfungen bleiben aktiv" }

    @objc func loadDevices() { refreshAll() }
    @objc func startAudio() { EngineManager.shared.post("/start", body: [:]) { _ in self.pollState() } }
    @objc func stopAudio() { EngineManager.shared.post("/stop", body: [:]) { _ in } }
    @objc func repairEngine() { EngineManager.shared.stop(); EngineManager.shared.start(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refreshAll() } }
    @objc func stabilizeAudio() { EngineManager.shared.post("/config", body: ["safeMode": true, "sampleRate": 48000, "blockSize": 1024, "latency": "high"]) { _ in EngineManager.shared.post("/stop", body: [:]) { _ in EngineManager.shared.post("/start", body: [:]) { _ in self.pollState() } } } }
    @objc func checkUpdatesClicked() { checkForUpdates(silent: false) }
    @objc func installUpdateClicked() { installUpdate() }
    @objc func openReleases() { NSWorkspace.shared.open(ADBReleasePageURL) }
    @objc func openLogs() { ensureDir(logDir()); NSWorkspace.shared.open(logDir()) }
    @objc func exportLogs() { ensureDir(logDir()); let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/AudioDaBitch_Logs_\(Int(Date().timeIntervalSince1970)).zip"); _ = EngineManager.shared.shell("/usr/bin/zip", ["-r", dest.path, logDir().path, appSupportDir().path]); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
    @objc func killStale() { EngineManager.shared.cleanupStale(); status.stringValue = "Hängende Prozesse bereinigt" }

    func setUpdateBadge(_ enabled: Bool) {
        updateTabItem?.label = enabled ? "🔵 Updates" : "Updates"
        updateStatus.textColor = enabled ? .systemBlue : .secondaryLabelColor
        updateButton.isEnabled = enabled
    }

    func checkForUpdates(silent: Bool) {
        if !silent {
            updateStatus.stringValue = "Suche nach neuem Release..."
            updateStatus.textColor = .secondaryLabelColor
        }
        var request = URLRequest(url: ADBLatestReleaseURL)
        request.setValue("AudioDaBitch/\(ADBVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    if !silent {
                        self.updateStatus.stringValue = "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)"
                    }
                    self.setUpdateBadge(false)
                    return
                }
                guard let data, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    if !silent { self.updateStatus.stringValue = "GitHub-Release konnte nicht gelesen werden." }
                    self.setUpdateBadge(false)
                    return
                }
                self.latestRelease = release
                let version = release.tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
                guard isVersion(version, newerThan: ADBVersion) else {
                    self.latestAssetURL = nil
                    self.updateStatus.stringValue = "Installiert: \(ADBVersion). Kein neueres Release gefunden."
                    self.setUpdateBadge(false)
                    return
                }
                guard let asset = release.assets.first(where: { $0.name == ADBUpdateAssetName }), let url = URL(string: asset.browserDownloadURL) else {
                    self.latestAssetURL = nil
                    self.updateStatus.stringValue = "Release \(release.tagName) gefunden, aber \(ADBUpdateAssetName) fehlt."
                    self.setUpdateBadge(false)
                    return
                }
                self.latestAssetURL = url
                self.updateStatus.stringValue = "Update verfügbar: \(release.tagName)."
                self.setUpdateBadge(true)
            }
        }.resume()
    }

    func installUpdate() {
        guard let assetURL = latestAssetURL else {
            checkForUpdates(silent: false)
            return
        }
        updateButton.isEnabled = false
        updateStatus.stringValue = "Download läuft..."
        let updateDir = appSupportDir().appendingPathComponent("Updates", isDirectory: true)
        ensureDir(updateDir)
        let version = latestRelease?.tagName ?? "latest"
        let destination = updateDir.appendingPathComponent("AudioDaBitch-\(version).pkg")
        URLSession.shared.downloadTask(with: assetURL) { tempURL, _, error in
            if let error {
                DispatchQueue.main.async {
                    self.updateStatus.stringValue = "Download fehlgeschlagen: \(error.localizedDescription)"
                    self.updateButton.isEnabled = true
                }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async {
                    self.updateStatus.stringValue = "Download fehlgeschlagen: keine Datei erhalten."
                    self.updateButton.isEnabled = true
                }
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                DispatchQueue.main.async { self.startInstallerAndQuit(pkgURL: destination) }
            } catch {
                DispatchQueue.main.async {
                    self.updateStatus.stringValue = "Download konnte nicht gespeichert werden: \(error.localizedDescription)"
                    self.updateButton.isEnabled = true
                }
            }
        }.resume()
    }

    func startInstallerAndQuit(pkgURL: URL) {
        updateStatus.stringValue = "Engine wird gestoppt, Installer startet..."
        EngineManager.shared.stop()
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = ["-lc", """
pkg="$1"
/bin/sleep 1
/usr/bin/open "$pkg"
/bin/sleep 2
while /usr/bin/pgrep -x Installer >/dev/null 2>&1; do /bin/sleep 2; done
/bin/sleep 1
if [ -d "/Applications/AudioDaBitch.app" ]; then
  /usr/bin/open -a "/Applications/AudioDaBitch.app"
fi
""", "audiodabitch-updater", pkgURL.path]
        do {
            try helper.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        } catch {
            updateStatus.stringValue = "Installer konnte nicht gestartet werden: \(error.localizedDescription)"
            updateButton.isEnabled = true
        }
    }

    func refreshAll() { pollHealth(); fetchDevices(); pollState() }

    func pollHealth() {
        EngineManager.shared.get("/health") { data in
            DispatchQueue.main.async {
                guard let data, let health = try? JSONDecoder().decode(HealthResponse.self, from: data) else { self.status.stringValue = "Engine nicht erreichbar"; return }
                if health.sounddevice == false { self.status.stringValue = "Audio-Komponenten fehlen: \(health.error ?? "")" } else { self.status.stringValue = "Engine bereit \(health.version ?? "")" }
            }
        }
    }

    func fetchDevices() {
        EngineManager.shared.get("/devices") { data in
            DispatchQueue.main.async {
                guard let data, let response = try? JSONDecoder().decode(DevicesResponse.self, from: data) else { self.deviceError.stringValue = "/devices konnte nicht gelesen werden"; return }
                self.populate(self.discord.popup, response.inputs)
                self.populate(self.xpilot.popup, response.inputs)
                self.populate(self.output.popup, response.outputs)
                if let error = response.error, !error.isEmpty { self.deviceError.stringValue = "Gerätefehler: \(error)" } else { self.deviceError.stringValue = response.inputs.isEmpty || response.outputs.isEmpty ? "Keine Audio-Geräte gefunden" : "" }
            }
        }
    }

    func populate(_ popup: NSPopUpButton, _ devices: [Device]) {
        let old = popup.selectedItem?.representedObject as? Int
        popup.removeAllItems()
        popup.addItem(withTitle: "Bitte auswählen")
        popup.lastItem?.representedObject = -1
        for device in devices {
            popup.addItem(withTitle: "\(device.name)  (#\(device.id))")
            popup.lastItem?.representedObject = device.id
        }
        if let old, let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == old }) { popup.select(item) }
    }

    func pollState() {
        EngineManager.shared.get("/state") { data in
            DispatchQueue.main.async {
                guard let data, let state = try? JSONDecoder().decode(StateResponse.self, from: data) else { return }
                self.discord.meter.valueDb = state.meters?.discord ?? -120
                self.xpilot.meter.valueDb = state.meters?.xpilot ?? -120
                self.output.meter.valueDb = state.meters?.output ?? -120
                self.levelerInfo.stringValue = "Aktueller xPilot-Pegel: \(Int(state.meters?.xpilot ?? -120)) dB    Auto-Korrektur: \(Int(state.levelerGainDb ?? 0)) dB"
                if let diag = state.diagnostics {
                    self.diagnosticsLabel.stringValue = "Audio: \(diag.sampleRate ?? 0) Hz · Block \(diag.blockSize ?? 0) · Latenz \(diag.latency ?? "-") · Callback-Fehler \(diag.callbackErrors ?? 0)"
                }
            }
        }
    }

    @objc func configChanged() {
        var body: [String: Any] = [:]
        let did = discord.popup.selectedItem?.representedObject as? Int ?? -1
        let xid = xpilot.popup.selectedItem?.representedObject as? Int ?? -1
        let oid = output.popup.selectedItem?.representedObject as? Int ?? -1
        if did >= 0 { body["discordInput"] = did }
        if xid >= 0 { body["xpilotInput"] = xid }
        if oid >= 0 { body["outputDevice"] = oid }
        body["discordGainDb"] = discord.gain.doubleValue
        body["xpilotGainDb"] = xpilot.gain.doubleValue
        body["masterGainDb"] = output.gain.doubleValue
        body["discordPan"] = discord.pan.doubleValue
        body["xpilotPan"] = xpilot.pan.doubleValue
        body["safeMode"] = true
        body["sampleRate"] = 48000
        body["blockSize"] = 1024
        body["latency"] = "high"
        EngineManager.shared.post("/config", body: body) { _ in }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AudioDaBitch \(ADBVersion) started")
        let vc = AppController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.center()
        window.title = "AudioDaBitch"
        window.contentViewController = vc
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "AudioDaBitch beenden?"
        alert.informativeText = "Beenden stoppt die Audio-Engine. Minimieren lässt AudioDaBitch geöffnet."
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Minimieren")
        alert.addButton(withTitle: "Abbrechen")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { EngineManager.shared.stop(); NSApp.terminate(nil); return false }
        if response == .alertSecondButtonReturn { sender.miniaturize(nil); return false }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { EngineManager.shared.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

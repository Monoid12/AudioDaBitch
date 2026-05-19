import Cocoa
import Foundation

let ADBVersion = "0.5.3"
let controlURL = URL(string: "http://127.0.0.1:49372")!

final class ADBContainerView: NSView { override var isFlipped: Bool { true } }

final class MeterView: NSView {
    var levelDb: Double = -120 { didSet { needsDisplay = true } }
    var labelText: String = "" { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 240, height: 18) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let bg = bounds.insetBy(dx: 0, dy: 3)
        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        bg.fill()
        let clamped = max(-60.0, min(0.0, levelDb))
        let fraction = CGFloat((clamped + 60.0) / 60.0)
        var fill = bg
        fill.size.width *= fraction
        NSColor.controlAccentColor.setFill()
        fill.fill()
        let text = String(format: "%@  %.1f dB", labelText, levelDb)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        text.draw(in: bounds.insetBy(dx: 4, dy: 1), withAttributes: attrs)
    }
}

final class EngineManager {
    private var process: Process?
    private let fm = FileManager.default
    private var supportDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioDaBitch", isDirectory: true)
    }
    private var logDir: URL {
        fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/AudioDaBitch", isDirectory: true)
    }
    private var pidFile: URL { supportDir.appendingPathComponent("engine.pid") }

    func prepareFolders() {
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    func cleanupStaleEngines() {
        prepareFolders()
        if let pidString = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), let pid = Int32(pidString), pid > 0 {
            kill(pid, SIGTERM)
            usleep(250_000)
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        try? fm.removeItem(at: pidFile)
        _ = runShell("/usr/bin/pkill -f '/AudioDaBitch.app/.*/engine.py' || true")
        _ = runShell("/usr/bin/pkill -f 'Resources/engine.py' || true")
        _ = runShell("/usr/sbin/lsof -tiTCP:49372 -sTCP:LISTEN | /usr/bin/xargs -r /bin/kill -TERM 2>/dev/null || true")
        usleep(200_000)
        _ = runShell("/usr/sbin/lsof -tiTCP:49372 -sTCP:LISTEN | /usr/bin/xargs -r /bin/kill -KILL 2>/dev/null || true")
    }

    func start() {
        prepareFolders()
        if process?.isRunning == true { return }
        cleanupStaleEngines()
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("engine.py") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [engine.path]
        p.environment = [
            "ADB_SUPPORT": supportDir.path,
            "ADB_LOG_DIR": logDir.path,
            "PYTHONUNBUFFERED": "1"
        ]
        let log = logDir.appendingPathComponent("engine-launch.log")
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        if let fh = try? FileHandle(forWritingTo: log) {
            fh.seekToEndOfFile()
            p.standardOutput = fh
            p.standardError = fh
        }
        do {
            try p.run()
            process = p
            try? String(p.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
        } catch {
            appendAppLog("Engine start failed: \(error)")
        }
    }

    func stop() {
        call("/stop", method: "POST", body: nil) { _ in }
        usleep(350_000)
        if let p = process, p.isRunning { p.terminate(); usleep(250_000); if p.isRunning { p.interrupt() } }
        process = nil
        cleanupStaleEngines()
    }

    func restart() { stop(); usleep(300_000); start() }

    func call(_ path: String, method: String = "GET", body: Data? = nil, completion: @escaping (Data?) -> Void) {
        var req = URLRequest(url: controlURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        req.httpMethod = method
        req.timeoutInterval = 1.5
        if let body = body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        URLSession.shared.dataTask(with: req) { data, _, _ in completion(data) }.resume()
    }

    func supportPath() -> String { supportDir.path }
    func logsPath() -> String { logDir.path }

    private func appendAppLog(_ message: String) {
        prepareFolders()
        let line = "\(Date()) \(message)\n"
        let path = logDir.appendingPathComponent("app.log")
        if !fm.fileExists(atPath: path.path) { fm.createFile(atPath: path.path, contents: nil) }
        if let fh = try? FileHandle(forWritingTo: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8) ?? Data()); try? fh.close()
        }
    }
}

@discardableResult
func runShell(_ command: String) -> String {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", command]
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run(); p.waitUntilExit() } catch { return "" }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = EngineManager()
    var window: NSWindow!
    let status = NSTextField(labelWithString: "Engine startet...")
    let discordMeter = MeterView()
    let xpilotMeter = MeterView()
    let outputMeter = MeterView()
    let discordPopup = NSPopUpButton()
    let xpilotPopup = NSPopUpButton()
    let outputPopup = NSPopUpButton()
    let discordGain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let xpilotGain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let discordPan = NSSlider(value: -0.8, minValue: -1, maxValue: 1, target: nil, action: nil)
    let xpilotPan = NSSlider(value: 0.8, minValue: -1, maxValue: 1, target: nil, action: nil)
    let masterGain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let duckingDepth = NSSlider(value: -12, minValue: -36, maxValue: 0, target: nil, action: nil)
    let targetLevel = NSSlider(value: -21, minValue: -35, maxValue: -12, target: nil, action: nil)
    let gateLevel = NSSlider(value: -55, minValue: -80, maxValue: -30, target: nil, action: nil)
    let fastDown = NSSlider(value: 18, minValue: 5, maxValue: 80, target: nil, action: nil)
    let updateStatus = NSTextField(labelWithString: "Noch nicht geprüft")
    let updateButton = NSButton(title: "Update laden", target: nil, action: nil)
    let changelogView = NSTextView()
    let helpView = NSTextView()
    var devices: [[String: Any]] = []
    var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        engine.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.pollState() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.loadDevices() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.loadDevices() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        engine.stop()
        return .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "AudioDaBitch schließen?"
        alert.informativeText = "Beenden stoppt die Audio-Engine. Minimieren lässt AudioDaBitch im Dock weiterlaufen."
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Minimieren")
        alert.addButton(withTitle: "Abbrechen")
        let r = alert.runModal()
        if r == .alertFirstButtonReturn { NSApp.terminate(nil); return false }
        if r == .alertSecondButtonReturn { sender.miniaturize(nil); return false }
        return false
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AudioDaBitch \(ADBVersion)"
        window.center()
        window.delegate = self
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = tabs
        tabs.addTabViewItem(tab("Audio", audioTab()))
        tabs.addTabViewItem(tab("xPilot Leveler", levelerTab()))
        tabs.addTabViewItem(tab("Updates", updatesTab()))
        tabs.addTabViewItem(tab("Hilfe", helpTab()))
        tabs.addTabViewItem(tab("Logs", logsTab()))
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 8),
            tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -8),
            tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 8),
            tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -8)
        ])
        window.makeKeyAndOrderFront(nil)
    }

    func tab(_ title: String, _ view: NSView) -> NSTabViewItem { let i = NSTabViewItem(identifier: title); i.label = title; i.view = view; return i }
    func vstack() -> NSStackView { let s = NSStackView(); s.orientation = .vertical; s.spacing = 10; s.alignment = .leading; s.translatesAutoresizingMaskIntoConstraints = false; return s }
    func hstack() -> NSStackView { let s = NSStackView(); s.orientation = .horizontal; s.spacing = 10; s.alignment = .centerY; s.translatesAutoresizingMaskIntoConstraints = false; return s }
    func label(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField { let l = NSTextField(labelWithString: text); l.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size); l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 0; return l }
    func button(_ title: String, _ action: Selector) -> NSButton { let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b }
    func row(_ title: String, _ control: NSView, value: NSView? = nil) -> NSStackView { let r = hstack(); let l = label(title); l.widthAnchor.constraint(equalToConstant: 150).isActive = true; r.addArrangedSubview(l); control.widthAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true; r.addArrangedSubview(control); if let value = value { value.widthAnchor.constraint(equalToConstant: 75).isActive = true; r.addArrangedSubview(value) }; return r }
    func value(_ suffix: String, slider: NSSlider) -> NSTextField { let l = NSTextField(labelWithString: String(format: "%.1f %@", slider.doubleValue, suffix)); return l }

    func container(_ stack: NSStackView) -> NSView {
        let view = ADBContainerView(); view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22)
        ])
        return view
    }

    func audioTab() -> NSView {
        let root = vstack()
        let title = label("Audio", size: 22, bold: true); root.addArrangedSubview(title)
        status.textColor = .secondaryLabelColor; root.addArrangedSubview(status)
        discordMeter.labelText = "Discord"; xpilotMeter.labelText = "xPilot"; outputMeter.labelText = "Output"
        let meters = hstack(); meters.addArrangedSubview(discordMeter); meters.addArrangedSubview(xpilotMeter); meters.addArrangedSubview(outputMeter); root.addArrangedSubview(meters)
        root.addArrangedSubview(row("Discord Input", discordPopup))
        root.addArrangedSubview(row("xPilot Input", xpilotPopup))
        root.addArrangedSubview(row("Output", outputPopup))
        for p in [discordPopup, xpilotPopup, outputPopup] { p.target = self; p.action = #selector(applyConfig) }
        for s in [discordGain, xpilotGain, discordPan, xpilotPan, masterGain, duckingDepth] { s.target = self; s.action = #selector(applyConfig) }
        root.addArrangedSubview(row("Discord Lautstärke", discordGain, value: value("dB", slider: discordGain)))
        root.addArrangedSubview(row("xPilot Lautstärke", xpilotGain, value: value("dB", slider: xpilotGain)))
        root.addArrangedSubview(row("Discord Panorama", discordPan, value: value("", slider: discordPan)))
        root.addArrangedSubview(row("xPilot Panorama", xpilotPan, value: value("", slider: xpilotPan)))
        root.addArrangedSubview(row("Master", masterGain, value: value("dB", slider: masterGain)))
        root.addArrangedSubview(row("Ducking-Tiefe", duckingDepth, value: value("dB", slider: duckingDepth)))
        let buttons = hstack(); buttons.addArrangedSubview(button("Geräte aktualisieren", #selector(loadDevicesAction))); buttons.addArrangedSubview(button("Audio starten", #selector(startAudio))); buttons.addArrangedSubview(button("Audio stoppen", #selector(stopAudio))); buttons.addArrangedSubview(button("Engine neu starten", #selector(restartAudio))); buttons.addArrangedSubview(button("Panning testen", #selector(testPanning)))
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(label("Merksatz: Discord und xPilot gehen zuerst nach BlackHole, AudioDaBitch gibt erst danach auf deinen Kopfhörer aus.", size: 12))
        return container(root)
    }

    func levelerTab() -> NSView {
        let root = vstack(); root.addArrangedSubview(label("xPilot Leveler", size: 22, bold: true)); root.addArrangedSubview(label("Gleicht zu laute oder zu leise VATSIM-Stationen aus. Schnelle Absenkung schützt vor lauten Peaks; langsameres Anheben vermeidet Pumpen."))
        for s in [targetLevel, gateLevel, fastDown] { s.target = self; s.action = #selector(applyConfig) }
        root.addArrangedSubview(row("Zielpegel", targetLevel, value: value("dBFS", slider: targetLevel)))
        root.addArrangedSubview(row("Gate", gateLevel, value: value("dBFS", slider: gateLevel)))
        root.addArrangedSubview(row("Reaktion zu laut", fastDown, value: value("ms", slider: fastDown)))
        root.addArrangedSubview(label("Empfehlung: Zielpegel -21 dBFS, Gate -55 dBFS, schnelle Absenkung 18 ms. Das schützt bei falsch eingestellten VATSIM-Pegeln."))
        return container(root)
    }

    func updatesTab() -> NSView {
        let root = vstack(); root.addArrangedSubview(label("Updates & Changelog", size: 22, bold: true)); root.addArrangedSubview(updateStatus); let b = button("Jetzt prüfen", #selector(checkUpdates)); root.addArrangedSubview(b); updateButton.target = self; updateButton.action = #selector(downloadUpdate); updateButton.isHidden = true; root.addArrangedSubview(updateButton)
        changelogView.isEditable = false; changelogView.string = loadResourceText("CHANGELOG", fallback: "AudioDaBitch 0.5.3\n- Build-/Installer-Cleanup\n- Engine-Version-Prüfung\n- Kompakte Oberfläche\n- Pegelanzeigen\n- stabilerer Engine-Prozess\n- besserer Update- und Release-Ablauf")
        let scroll = NSScrollView(); scroll.documentView = changelogView; scroll.hasVerticalScroller = true; scroll.widthAnchor.constraint(equalToConstant: 980).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 430).isActive = true; root.addArrangedSubview(scroll); return container(root)
    }

    func helpTab() -> NSView {
        let root = vstack(); root.addArrangedSubview(label("Hilfe / BlackHole Routing", size: 22, bold: true)); helpView.isEditable = false; helpView.string = loadResourceText("HELP_BLACKHOLE_DE", fallback: fallbackHelp())
        let scroll = NSScrollView(); scroll.documentView = helpView; scroll.hasVerticalScroller = true; scroll.widthAnchor.constraint(equalToConstant: 980).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 540).isActive = true; root.addArrangedSubview(scroll); return container(root)
    }

    func logsTab() -> NSView {
        let root = vstack(); root.addArrangedSubview(label("Logs & Diagnose", size: 22, bold: true)); root.addArrangedSubview(label("Log-Verzeichnis: \(engine.logsPath())")); let row1 = hstack(); row1.addArrangedSubview(button("Logs öffnen", #selector(openLogs))); row1.addArrangedSubview(button("Log-ZIP erstellen", #selector(zipLogs))); row1.addArrangedSubview(button("Hängende Prozesse beenden", #selector(killStale))); root.addArrangedSubview(row1); root.addArrangedSubview(label("Die Log-ZIP enthält keine Passwörter. Sie enthält AudioDaBitch-Logs, Setup-Ausgaben und Prozessdiagnose.")); return container(root)
    }

    func loadResourceText(_ name: String, fallback: String) -> String { if let url = Bundle.main.url(forResource: name, withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) { return text }; return fallback }
    func fallbackHelp() -> String { "Discord Output: BlackHole 2ch\nxPilot Headset/Speaker: BlackHole 16ch\nAudioDaBitch Output: Kopfhörer oder Audiointerface\nKein Multi-Output-Gerät mit Kopfhörer verwenden, sonst läuft Audio am Limiter vorbei." }

    @objc func loadDevicesAction() { loadDevices() }
    func loadDevices() {
        engine.call("/devices") { data in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self.status.stringValue = "Engine nicht erreichbar - Neustart läuft"
                    self.engine.restart()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.loadDevices() }
                }
                return
            }
            DispatchQueue.main.async { self.devices = json; self.populateDevices(); self.status.stringValue = "Engine bereit" }
        }
    }
    func populateDevices() {
        for p in [discordPopup, xpilotPopup, outputPopup] { p.removeAllItems() }
        discordPopup.addItem(withTitle: "Bitte auswählen"); xpilotPopup.addItem(withTitle: "Bitte auswählen"); outputPopup.addItem(withTitle: "Bitte auswählen")
        for d in devices {
            let name = d["name"] as? String ?? "Device"
            let id = String(d["id"] as? Int ?? -1)
            if (d["max_input_channels"] as? Int ?? 0) > 0 { discordPopup.addItem(withTitle: name); discordPopup.lastItem?.representedObject = id; xpilotPopup.addItem(withTitle: name); xpilotPopup.lastItem?.representedObject = id }
            if (d["max_output_channels"] as? Int ?? 0) > 0 { outputPopup.addItem(withTitle: name); outputPopup.lastItem?.representedObject = id }
        }
        selectContaining(discordPopup, "BlackHole 2ch"); selectContaining(xpilotPopup, "BlackHole 16ch")
    }
    func selectContaining(_ popup: NSPopUpButton, _ text: String) { for item in popup.itemArray { if item.title.localizedCaseInsensitiveContains(text) { popup.select(item); break } } }

    @objc func applyConfig() {
        let cfg: [String: Any] = [
            "discordDevice": Int(discordPopup.selectedItem?.representedObject as? String ?? "-1") ?? -1,
            "xpilotDevice": Int(xpilotPopup.selectedItem?.representedObject as? String ?? "-1") ?? -1,
            "outputDevice": Int(outputPopup.selectedItem?.representedObject as? String ?? "-1") ?? -1,
            "discordGainDb": discordGain.doubleValue,
            "xpilotGainDb": xpilotGain.doubleValue,
            "discordPan": discordPan.doubleValue,
            "xpilotPan": xpilotPan.doubleValue,
            "masterGainDb": masterGain.doubleValue,
            "duckingDepthDb": duckingDepth.doubleValue,
            "targetDb": targetLevel.doubleValue,
            "gateDb": gateLevel.doubleValue,
            "fastDownMs": fastDown.doubleValue
        ]
        let body = try? JSONSerialization.data(withJSONObject: cfg)
        engine.call("/config", method: "POST", body: body) { _ in }
    }

    @objc func startAudio() { applyConfig(); engine.call("/start", method: "POST") { _ in } }
    @objc func stopAudio() { engine.call("/audio_stop", method: "POST") { _ in } }
    @objc func restartAudio() { engine.restart(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.loadDevices() } }
    @objc func testPanning() { applyConfig(); engine.call("/test_pan", method: "POST") { _ in } }
    @objc func killStale() { engine.cleanupStaleEngines(); status.stringValue = "Hängende Prozesse beendet" }

    func pollState() {
        engine.call("/state") { data in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { DispatchQueue.main.async { self.status.stringValue = "Engine nicht erreichbar" }; return }
            DispatchQueue.main.async {
                self.status.stringValue = json["running"] as? Bool == true ? "Audio läuft" : "Engine bereit"
                if let lv = json["levels"] as? [String: Any] {
                    self.discordMeter.levelDb = lv["discord"] as? Double ?? -120
                    self.xpilotMeter.levelDb = lv["xpilot"] as? Double ?? -120
                    self.outputMeter.levelDb = lv["output"] as? Double ?? -120
                }
            }
        }
    }

    @objc func checkUpdates() {
        updateStatus.stringValue = "Prüfe GitHub..."
        let url = URL(string: "https://api.github.com/repos/Monoid12/AudioDaBitch/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { DispatchQueue.main.async { self.updateStatus.stringValue = "Updateprüfung fehlgeschlagen" }; return }
            let tag = (json["tag_name"] as? String ?? "").replacingOccurrences(of: "v", with: "")
            DispatchQueue.main.async {
                if tag.compare(ADBVersion, options: .numeric) == .orderedDescending { self.updateStatus.stringValue = "Update verfügbar: \(tag)"; self.updateButton.isHidden = false } else { self.updateStatus.stringValue = "Aktuell: \(ADBVersion)"; self.updateButton.isHidden = true }
            }
        }.resume()
    }

    @objc func downloadUpdate() {
        let url = URL(string: "https://github.com/Monoid12/AudioDaBitch/releases/latest/download/AudioDaBitch.pkg")!
        updateStatus.stringValue = "Lade Update..."
        URLSession.shared.downloadTask(with: url) { tmp, _, _ in
            guard let tmp = tmp else { DispatchQueue.main.async { self.updateStatus.stringValue = "Download fehlgeschlagen" }; return }
            let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioDaBitch_Update.pkg")
            try? FileManager.default.removeItem(at: dest); try? FileManager.default.moveItem(at: tmp, to: dest)
            DispatchQueue.main.async { self.runInstallerAndQuit(pkg: dest) }
        }.resume()
    }

    func runInstallerAndQuit(pkg: URL) {
        engine.stop()
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("audiodabitch_update_restart.sh")
        let content = "#!/bin/zsh\n/usr/bin/pkill -f '/AudioDaBitch.app/.*/engine.py' 2>/dev/null || true\n/usr/bin/open -W '\(pkg.path)'\nsleep 2\n/usr/bin/open -a AudioDaBitch\n"
        try? content.write(to: script, atomically: true, encoding: .utf8)
        _ = runShell("/bin/chmod +x '\(script.path)' && /usr/bin/nohup '\(script.path)' >/tmp/audiodabitch_update.log 2>&1 &")
        NSApp.terminate(nil)
    }

    @objc func openLogs() { NSWorkspace.shared.open(URL(fileURLWithPath: engine.logsPath())) }
    @objc func zipLogs() { let dest = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioDaBitch_Logs.zip"); _ = runShell("/usr/bin/zip -r '\(dest.path)' '\(engine.logsPath())' >/dev/null 2>&1"); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
}

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()

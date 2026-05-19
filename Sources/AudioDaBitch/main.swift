import Cocoa
import Foundation
import Darwin

let appVersion = "0.5.4"
let port = 49372
let baseURL = URL(string: "http://127.0.0.1:\(port)")!

func supportDir() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioDaBitch", isDirectory: true)
}
func logDir() -> URL {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/AudioDaBitch", isDirectory: true)
}
func ensureDirs() {
    try? FileManager.default.createDirectory(at: supportDir(), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: logDir(), withIntermediateDirectories: true)
}
func postJSON(_ path: String, _ obj: [String: Any] = [:], completion: ((Bool) -> Void)? = nil) {
    var req = URLRequest(url: baseURL.appendingPathComponent(path))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: obj)
    URLSession.shared.dataTask(with: req) { _, resp, _ in
        completion?((resp as? HTTPURLResponse)?.statusCode == 200)
    }.resume()
}
func getJSON(_ path: String, completion: @escaping ([String: Any]?) -> Void) {
    URLSession.shared.dataTask(with: baseURL.appendingPathComponent(path)) { data, _, _ in
        guard let data = data else { completion(nil); return }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        completion(obj)
    }.resume()
}

final class EngineManager {
    var proc: Process?
    let pidFile = supportDir().appendingPathComponent("engine.pid")

    func cleanupStale() {
        ensureDirs()
        if let s = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
            kill(pid, SIGTERM)
            usleep(250_000)
            kill(pid, SIGKILL)
            try? FileManager.default.removeItem(at: pidFile)
        }
        _ = shell("/usr/sbin/lsof -tiTCP:\(port) -sTCP:LISTEN | /usr/bin/xargs -r kill -TERM")
    }

    func start() {
        if proc?.isRunning == true { return }
        ensureDirs()
        cleanupStale()
        guard let engineURL = Bundle.main.url(forResource: "engine", withExtension: "py") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", engineURL.path]
        let out = logDir().appendingPathComponent("engine.stdout.log")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: out) {
            h.seekToEndOfFile()
            p.standardOutput = h
            p.standardError = h
        }
        do { try p.run(); proc = p } catch { NSLog("Engine start failed: \(error)") }
    }

    func stop() {
        postJSON("shutdown") { _ in }
        usleep(200_000)
        proc?.terminate()
        proc = nil
        cleanupStale()
    }

    func shell(_ cmd: String) -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", cmd]
        p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

final class MeterView: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var db: Double = -120 { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 24) }
    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor(calibratedWhite: 0.22, alpha: 1)
        bg.setFill(); bounds.fill()
        let norm = max(0.0, min(1.0, (db + 60.0) / 60.0))
        let w = bounds.width * CGFloat(norm)
        let color: NSColor = db > -6 ? .systemRed : (db > -18 ? .systemYellow : .systemGreen)
        color.setFill(); NSRect(x: 0, y: 0, width: w, height: bounds.height).fill()
        let text = "\(title)  \(String(format: "%.1f", db)) dB"
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        text.draw(at: NSPoint(x: 8, y: 4), withAttributes: attrs)
    }
}

final class AudioBlock: NSBox {
    let meter = MeterView(frame: .zero)
    let popup = NSPopUpButton()
    let gain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let pan = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let gainLabel = NSTextField(labelWithString: "0.0 dB")
    let panLabel = NSTextField(labelWithString: "0.0")
    init(title: String, showPan: Bool) {
        super.init(frame: .zero)
        self.title = title
        self.boxType = .custom
        self.borderType = .lineBorder
        self.cornerRadius = 10
        self.contentViewMargins = NSSize(width: 14, height: 14)
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 10; root.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 12), root.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -12), root.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 12), root.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor, constant: -12)])
        meter.title = title; root.addArrangedSubview(meter)
        root.addArrangedSubview(row("Gerät", popup, nil))
        root.addArrangedSubview(row("Lautstärke", gain, gainLabel))
        if showPan { root.addArrangedSubview(row("Panorama", pan, panLabel)) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func row(_ label: String, _ control: NSView, _ value: NSTextField?) -> NSView {
        let h = NSStackView(); h.orientation = .horizontal; h.spacing = 8
        let l = NSTextField(labelWithString: label); l.widthAnchor.constraint(equalToConstant: 86).isActive = true
        h.addArrangedSubview(l); h.addArrangedSubview(control)
        if let value { value.alignment = .right; value.widthAnchor.constraint(equalToConstant: 62).isActive = true; h.addArrangedSubview(value) }
        return h
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = EngineManager()
    var window: NSWindow!
    let tabs = NSTabView()
    let status = NSTextField(labelWithString: "Engine startet...")
    let discord = AudioBlock(title: "Discord", showPan: true)
    let xpilot = AudioBlock(title: "xPilot", showPan: true)
    let output = AudioBlock(title: "Output", showPan: false)
    let startButton = NSButton(title: "Audio starten", target: nil, action: nil)
    let stopButton = NSButton(title: "Audio stoppen", target: nil, action: nil)
    let refreshButton = NSButton(title: "Geräte aktualisieren", target: nil, action: nil)
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.start()
        buildUI()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refreshDevices(); self.poll() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in self.poll() }
    }
    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { engine.stop(); NSApp.terminate(nil); return false }

    func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.center(); window.title = "AudioDaBitch \(appVersion)"; window.delegate = self
        tabs.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = tabs
        addAudioTab(); addLevelerTab(); addUpdatesTab(); addHelpTab(); addLogsTab()
        window.makeKeyAndOrderFront(nil)
    }
    func tab(_ title: String, _ view: NSView) {
        let item = NSTabViewItem(identifier: title); item.label = title; item.view = view; tabs.addTabViewItem(item)
    }
    func padded() -> NSStackView {
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 14; root.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28); return root
    }
    func addAudioTab() {
        let root = padded()
        let title = NSTextField(labelWithString: "Audio"); title.font = .systemFont(ofSize: 28, weight: .bold); root.addArrangedSubview(title)
        status.font = .systemFont(ofSize: 16, weight: .semibold); root.addArrangedSubview(status)
        let blocks = NSStackView(); blocks.orientation = .horizontal; blocks.spacing = 14; blocks.distribution = .fillEqually
        blocks.addArrangedSubview(discord); blocks.addArrangedSubview(xpilot); blocks.addArrangedSubview(output); root.addArrangedSubview(blocks)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        for b in [refreshButton, startButton, stopButton, NSButton(title: "Engine neu starten", target: self, action: #selector(restartEngine)), NSButton(title: "Panning testen", target: self, action: #selector(testPan))] { buttons.addArrangedSubview(b) }
        root.addArrangedSubview(buttons)
        root.addArrangedSubview(NSTextField(labelWithString: "Merksatz: Discord und xPilot gehen zuerst nach BlackHole. AudioDaBitch gibt erst danach auf deinen Kopfhörer aus."))
        refreshButton.target = self; refreshButton.action = #selector(refreshDevicesAction)
        startButton.target = self; startButton.action = #selector(startAudio)
        stopButton.target = self; stopButton.action = #selector(stopAudio)
        for s in [discord.gain, discord.pan, xpilot.gain, xpilot.pan, output.gain] { s.target = self; s.action = #selector(controlChanged) }
        for p in [discord.popup, xpilot.popup, output.popup] { p.target = self; p.action = #selector(controlChanged) }
        tab("Audio", root)
    }
    func addLevelerTab() {
        let root = padded(); let t = NSTextField(labelWithString: "xPilot Leveler"); t.font = .systemFont(ofSize: 26, weight: .bold); root.addArrangedSubview(t)
        root.addArrangedSubview(NSTextField(labelWithString: "Gleicht zu laute oder zu leise VATSIM-Stationen aus. Schnelle Absenkung schützt vor lauten Peaks."))
        root.addArrangedSubview(NSTextField(labelWithString: "Empfohlener Startwert: Zielpegel -21 dBFS, Gate -55 dBFS."))
        tab("xPilot Leveler", root)
    }
    func textTab(_ title: String, resource: String, fallback: String) -> NSView {
        let root = padded(); let h = NSTextField(labelWithString: title); h.font = .systemFont(ofSize: 26, weight: .bold); root.addArrangedSubview(h)
        let tv = NSTextView(); tv.isEditable = false; tv.string = loadText(resource, fallback)
        tv.font = .systemFont(ofSize: 14)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = tv; scroll.heightAnchor.constraint(equalToConstant: 520).isActive = true
        root.addArrangedSubview(scroll); return root
    }
    func addUpdatesTab() { tab("Updates", textTab("Updates & Changelog", resource: "CHANGELOG", fallback: "Changelog nicht gefunden.")) }
    func addHelpTab() { tab("Hilfe", textTab("Hilfe / BlackHole Routing", resource: "HELP_BLACKHOLE_DE", fallback: "Hilfe nicht gefunden.")) }
    func addLogsTab() {
        let root = padded(); let t = NSTextField(labelWithString: "Logs & Diagnose"); t.font = .systemFont(ofSize: 26, weight: .bold); root.addArrangedSubview(t)
        root.addArrangedSubview(NSTextField(labelWithString: "Log-Verzeichnis: \(logDir().path)"))
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        buttons.addArrangedSubview(NSButton(title: "Logs öffnen", target: self, action: #selector(openLogs)))
        buttons.addArrangedSubview(NSButton(title: "Hängende Prozesse beenden", target: self, action: #selector(killStale)))
        root.addArrangedSubview(buttons); tab("Logs", root)
    }
    func loadText(_ name: String, _ fallback: String) -> String {
        if let u = Bundle.main.url(forResource: name, withExtension: "md"), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return fallback
    }

    func fill(_ popup: NSPopUpButton, devices: [[String: Any]], selected: String?) {
        popup.removeAllItems(); popup.addItem(withTitle: "Bitte auswählen"); popup.lastItem?.representedObject = ""
        for d in devices {
            let id = String(describing: d["id"] ?? "")
            let name = String(describing: d["label"] ?? d["name"] ?? id)
            popup.addItem(withTitle: name); popup.lastItem?.representedObject = id
            if selected == id { popup.select(popup.lastItem) }
        }
    }
    @objc func refreshDevicesAction() { refreshDevices() }
    func refreshDevices() {
        getJSON("devices") { obj in
            DispatchQueue.main.async {
                guard let obj else { self.status.stringValue = "Engine nicht erreichbar"; return }
                let inputs = obj["inputs"] as? [[String: Any]] ?? []
                let outputs = obj["outputs"] as? [[String: Any]] ?? []
                self.fill(self.discord.popup, devices: inputs, selected: nil)
                self.fill(self.xpilot.popup, devices: inputs, selected: nil)
                self.fill(self.output.popup, devices: outputs, selected: nil)
                self.status.stringValue = inputs.isEmpty && outputs.isEmpty ? "Keine Geräte von Engine erhalten" : "Engine bereit"
            }
        }
    }
    @objc func controlChanged() {
        discord.gainLabel.stringValue = String(format: "%.1f dB", discord.gain.doubleValue)
        xpilot.gainLabel.stringValue = String(format: "%.1f dB", xpilot.gain.doubleValue)
        output.gainLabel.stringValue = String(format: "%.1f dB", output.gain.doubleValue)
        discord.panLabel.stringValue = String(format: "%.1f", discord.pan.doubleValue)
        xpilot.panLabel.stringValue = String(format: "%.1f", xpilot.pan.doubleValue)
        let cfg: [String: Any] = [
            "discordInput": discord.popup.selectedItem?.representedObject as? String ?? "",
            "xpilotInput": xpilot.popup.selectedItem?.representedObject as? String ?? "",
            "outputDevice": output.popup.selectedItem?.representedObject as? String ?? "",
            "discordGain": discord.gain.doubleValue,
            "xpilotGain": xpilot.gain.doubleValue,
            "discordPan": discord.pan.doubleValue,
            "xpilotPan": xpilot.pan.doubleValue,
            "masterGain": output.gain.doubleValue
        ]
        postJSON("config", cfg)
    }
    @objc func startAudio() { controlChanged(); postJSON("start") { ok in DispatchQueue.main.async { self.status.stringValue = ok ? "Audio läuft" : "Audio konnte nicht gestartet werden" } } }
    @objc func stopAudio() { postJSON("stop") { _ in DispatchQueue.main.async { self.status.stringValue = "Audio gestoppt" } } }
    @objc func restartEngine() { engine.stop(); engine.start(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refreshDevices() } }
    @objc func testPan() { NSSound.beep() }
    @objc func openLogs() { NSWorkspace.shared.open(logDir()) }
    @objc func killStale() { engine.cleanupStale(); status.stringValue = "Hängende Prozesse bereinigt" }
    func poll() {
        getJSON("state") { obj in
            DispatchQueue.main.async {
                guard let m = (obj?["meters"] as? [String: Any]) else { return }
                self.discord.meter.db = m["discordDb"] as? Double ?? -120
                self.xpilot.meter.db = m["xpilotDb"] as? Double ?? -120
                self.output.meter.db = m["outputDb"] as? Double ?? -120
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

import Cocoa
import Foundation

let appName = "AudioDaBitch"
let appVersion = "0.5.1"
let repoOwner = "Monoid12"
let repoName = "AudioDaBitch"
let updateAssetName = "AudioDaBitch.pkg"
let controlBaseURL = "http://127.0.0.1:49342"

struct Device: Codable {
    let index: Int
    let name: String
    let channels: Int
    let hostapi: String?
    let default_sr: Double?
}

struct DeviceList: Codable {
    let ok: Bool
    let inputs: [Device]?
    let outputs: [Device]?
    let default_input: Int?
    let default_output: Int?
    let error: String?
}

struct SourceConfig: Codable {
    var name: String
    var device_index: Int?
    var channels: [Int]
    var gain_db: Double
    var pan: Double
}

struct XpilotAGC: Codable {
    var enabled: Bool = true
    var target_db: Double = -21.0
    var gate_db: Double = -55.0
    var min_gain_db: Double = -14.0
    var max_gain_db: Double = 14.0
    var fast_down_ms: Double = 18.0
    var fast_up_ms: Double = 130.0
    var idle_release_ms: Double = 900.0
    var peak_guard_db: Double = -3.0
}

struct Config: Codable {
    var output_index: Int?
    var sample_rate: Int = 48000
    var block_size: Int = 512
    var ducking: Bool = true
    var trigger: Int = 1
    var threshold_db: Double = -35.0
    var duck_depth_db: Double = 18.0
    var attack_ms: Double = 20.0
    var release_ms: Double = 350.0
    var master_gain_db: Double = 0.0
    var limiter_ceiling_db: Double = -1.0
    var xpilot_agc: XpilotAGC = XpilotAGC()
    var inputs: [SourceConfig] = [
        SourceConfig(name: "Discord", device_index: nil, channels: [0,1], gain_db: 0.0, pan: -1.0),
        SourceConfig(name: "xPilot", device_index: nil, channels: [0,1], gain_db: 0.0, pan: 1.0)
    ]
}

final class EngineManager {
    let fm = FileManager.default
    let resources: URL
    let supportDir: URL
    let logDir: URL
    let configURL: URL
    let levelsURL: URL
    let pidURL: URL
    let adbctlURL: URL

    init() {
        resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let home = fm.homeDirectoryForCurrentUser
        supportDir = home.appendingPathComponent("Library/Application Support/AudioDaBitch", isDirectory: true)
        logDir = home.appendingPathComponent("Library/Logs/AudioDaBitch", isDirectory: true)
        configURL = supportDir.appendingPathComponent("config.json")
        levelsURL = supportDir.appendingPathComponent("levels.json")
        pidURL = supportDir.appendingPathComponent("engine.pid")
        adbctlURL = resources.appendingPathComponent("adbctl.sh")
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    func defaultConfig() -> Config { Config() }

    func loadConfig() -> Config {
        if let data = try? Data(contentsOf: configURL), let cfg = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
        return defaultConfig()
    }

    func saveConfig(_ cfg: Config) {
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) { try? data.write(to: configURL, options: .atomic) }
    }

    func runCtl(_ args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [self.adbctlURL.path] + args
            var env = ProcessInfo.processInfo.environment
            env["ADB_RESOURCES"] = self.resources.path
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                if p.terminationStatus == 0 { completion(.success(out.trimmingCharacters(in: .whitespacesAndNewlines))) }
                else { completion(.failure(NSError(domain: appName, code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out]))) }
            } catch { completion(.failure(error)) }
        }
    }

    func loadLevels() -> [String: Any]? {
        guard let data = try? Data(contentsOf: levelsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func exportLogs(completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
            let dest = self.logDir.appendingPathComponent("AudioDaBitch-Logs-\(df.string(from: Date())).zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = ["-r", dest.path, "."]
            p.currentDirectoryURL = self.logDir
            do { try p.run(); p.waitUntilExit(); completion(p.terminationStatus == 0 ? dest : nil) }
            catch { completion(nil) }
        }
    }
}

func versionParts(_ s: String) -> [Int] {
    let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    return t.split(separator: ".").map { part in
        let digits = part.prefix { ch in ch.isNumber }
        return Int(digits) ?? 0
    }
}
func isNewer(_ remote: String, than local: String) -> Bool {
    let a = versionParts(remote), b = versionParts(local)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x > y { return true }
        if x < y { return false }
    }
    return false
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let manager = EngineManager()
    var window: NSWindow!
    var cfg = Config()
    var inputDevices: [Device] = []
    var outputDevices: [Device] = []
    var latestDownloadURL: URL?
    var latestReleaseURL: URL?

    let statusLabel = NSTextField(labelWithString: "Bereit")
    let discordMeter = NSLevelIndicator()
    let xpilotMeter = NSLevelIndicator()
    let discordMeterText = NSTextField(labelWithString: "Discord: -inf dB")
    let xpilotMeterText = NSTextField(labelWithString: "xPilot: -inf dB")
    let duckText = NSTextField(labelWithString: "Ducking: 0.0 dB")
    let limitText = NSTextField(labelWithString: "Limiter: 0.0 dB")
    let agcText = NSTextField(labelWithString: "xPilot Auto-Level: 0.0 dB")

    let discordInput = NSPopUpButton()
    let xpilotInput = NSPopUpButton()
    let outputPopup = NSPopUpButton()
    let discordGain = NSSlider(value: 0, minValue: -24, maxValue: 24, target: nil, action: nil)
    let xpilotGain = NSSlider(value: 0, minValue: -24, maxValue: 24, target: nil, action: nil)
    let discordPan = NSSlider(value: -1, minValue: -1, maxValue: 1, target: nil, action: nil)
    let xpilotPan = NSSlider(value: 1, minValue: -1, maxValue: 1, target: nil, action: nil)
    let duckingButton = NSButton(checkboxWithTitle: "Ducking aktiv", target: nil, action: nil)
    let triggerPopup = NSPopUpButton()
    let thresholdSlider = NSSlider(value: -35, minValue: -70, maxValue: -10, target: nil, action: nil)
    let duckDepthSlider = NSSlider(value: 18, minValue: 0, maxValue: 40, target: nil, action: nil)
    let masterSlider = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
    let ceilingSlider = NSSlider(value: -1, minValue: -12, maxValue: 0, target: nil, action: nil)

    let agcButton = NSButton(checkboxWithTitle: "xPilot Auto-Leveler aktiv", target: nil, action: nil)
    let targetSlider = NSSlider(value: -21, minValue: -32, maxValue: -12, target: nil, action: nil)
    let gateSlider = NSSlider(value: -55, minValue: -80, maxValue: -30, target: nil, action: nil)
    let fastDownSlider = NSSlider(value: 18, minValue: 5, maxValue: 200, target: nil, action: nil)
    let fastUpSlider = NSSlider(value: 130, minValue: 20, maxValue: 600, target: nil, action: nil)

    let updateStatus = NSTextField(labelWithString: "Noch nicht geprueft")
    let updateButton = NSButton(title: "Update laden", target: nil, action: nil)
    let changelogText = NSTextView()

    var meterTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        cfg = manager.loadConfig()
        buildMenu()
        buildWindow()
        manager.saveConfig(cfg)
        loadDevices()
        checkForUpdates(silent: true)
        meterTimer = Timer.scheduledTimer(timeInterval: 0.12, target: self, selector: #selector(refreshMeters), userInfo: nil, repeats: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.runCtl(["stop", manager.pidURL.path]) { _ in }
    }

    func buildMenu() {
        let menubar = NSMenu()
        let appItem = NSMenuItem()
        menubar.addItem(appItem)
        NSApp.mainMenu = menubar
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About AudioDaBitch", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Fenster anzeigen", action: #selector(showMainWindow), keyEquivalent: "1")
        appMenu.addItem(withTitle: "Fenster minimieren", action: #selector(minimizeMainWindow), keyEquivalent: "m")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "AudioDaBitch beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 940, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AudioDaBitch \(appVersion)"
        window.minSize = NSSize(width: 820, height: 560)
        window.delegate = self
        let tabs = NSTabView(frame: window.contentView!.bounds)
        tabs.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tabs)
        tabs.addTabViewItem(tab(title: "Audio", view: audioView()))
        tabs.addTabViewItem(tab(title: "xPilot Leveler", view: agcView()))
        tabs.addTabViewItem(tab(title: "Updates & Changelog", view: updateView()))
        tabs.addTabViewItem(tab(title: "Hilfe / BlackHole", view: helpView()))
        tabs.addTabViewItem(tab(title: "Logs", view: logsView()))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func tab(title: String, view: NSView) -> NSTabViewItem { let t = NSTabViewItem(identifier: title); t.label = title; t.view = view; return t }

    func stack(_ orientation: NSUserInterfaceLayoutOrientation = .vertical) -> NSStackView {
        let s = NSStackView(); s.orientation = orientation; s.spacing = 10; s.alignment = .leading; s.translatesAutoresizingMaskIntoConstraints = false; return s
    }
    func label(_ text: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 0
        if bold { l.font = NSFont.boldSystemFont(ofSize: 14) }
        return l
    }
    func button(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }
    func row(_ title: String, _ control: NSView, value: NSTextField? = nil) -> NSStackView {
        let r = stack(.horizontal)
        let l = label(title); l.widthAnchor.constraint(equalToConstant: 190).isActive = true
        r.addArrangedSubview(l); r.addArrangedSubview(control)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        if let v = value { v.widthAnchor.constraint(equalToConstant: 130).isActive = true; r.addArrangedSubview(v) }
        return r
    }
    func container() -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        let root = stack(.vertical); root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        scroll.documentView = root
        root.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40).isActive = true
        return scroll
    }

    func audioView() -> NSView {
        let scroll = container(); let root = scroll.documentView as! NSStackView
        root.addArrangedSubview(label("Audio-Routing", bold: true))
        root.addArrangedSubview(label("Discord sollte auf BlackHole 2ch und xPilot auf BlackHole 16ch zeigen. AudioDaBitch gibt danach nur auf deinen echten Kopfhoerer oder dein Audiointerface aus."))
        root.addArrangedSubview(row("Discord Input", discordInput))
        root.addArrangedSubview(row("xPilot Input", xpilotInput))
        root.addArrangedSubview(row("Output", outputPopup))
        root.addArrangedSubview(separator())
        root.addArrangedSubview(row("Discord Gain", discordGain, value: valueLabel("dB", slider: discordGain)))
        root.addArrangedSubview(row("xPilot Gain", xpilotGain, value: valueLabel("dB", slider: xpilotGain)))
        root.addArrangedSubview(row("Discord Pan", discordPan, value: valueLabel("pan", slider: discordPan)))
        root.addArrangedSubview(row("xPilot Pan", xpilotPan, value: valueLabel("pan", slider: xpilotPan)))
        root.addArrangedSubview(separator())
        duckingButton.target = self; duckingButton.action = #selector(controlChanged(_:)); root.addArrangedSubview(duckingButton)
        triggerPopup.addItems(withTitles: ["xPilot duckt Discord", "Discord duckt xPilot", "Aus"]); triggerPopup.target = self; triggerPopup.action = #selector(controlChanged(_:)); root.addArrangedSubview(row("Ducking-Modus", triggerPopup))
        root.addArrangedSubview(row("Trigger Threshold", thresholdSlider, value: valueLabel("dB", slider: thresholdSlider)))
        root.addArrangedSubview(row("Ducking-Tiefe", duckDepthSlider, value: valueLabel("dB", slider: duckDepthSlider)))
        root.addArrangedSubview(row("Master Gain", masterSlider, value: valueLabel("dB", slider: masterSlider)))
        root.addArrangedSubview(row("Limiter Ceiling", ceilingSlider, value: valueLabel("dB", slider: ceilingSlider)))
        root.addArrangedSubview(separator())
        let btnRow = stack(.horizontal); btnRow.addArrangedSubview(button("Geraete laden", action: #selector(loadDevicesAction))); btnRow.addArrangedSubview(button("Audio starten", action: #selector(startAudio))); btnRow.addArrangedSubview(button("Audio stoppen", action: #selector(stopAudio))); btnRow.addArrangedSubview(button("Engine neu starten", action: #selector(restartAudio))); root.addArrangedSubview(btnRow)
        root.addArrangedSubview(statusLabel)
        setupMeter(discordMeter); setupMeter(xpilotMeter)
        root.addArrangedSubview(row("Discord Level", discordMeter, value: discordMeterText))
        root.addArrangedSubview(row("xPilot Level", xpilotMeter, value: xpilotMeterText))
        root.addArrangedSubview(duckText); root.addArrangedSubview(limitText); root.addArrangedSubview(agcText)
        for s in [discordGain, xpilotGain, discordPan, xpilotPan, thresholdSlider, duckDepthSlider, masterSlider, ceilingSlider] { s.target = self; s.action = #selector(controlChanged(_:)) }
        applyConfigToControls()
        return scroll
    }

    func agcView() -> NSView {
        let scroll = container(); let root = scroll.documentView as! NSStackView
        root.addArrangedSubview(label("xPilot Auto-Leveler / AGC", bold: true))
        root.addArrangedSubview(label("Der Leveler reagiert schnell nach unten, wenn eine VATSIM-Station viel zu laut ist, und hebt leise Stationen kontrolliert an. Ein Gate verhindert, dass Stille und Rauschen hochgezogen werden."))
        agcButton.target = self; agcButton.action = #selector(controlChanged(_:)); root.addArrangedSubview(agcButton)
        root.addArrangedSubview(row("Zielpegel", targetSlider, value: valueLabel("dBFS", slider: targetSlider)))
        root.addArrangedSubview(row("Gate", gateSlider, value: valueLabel("dBFS", slider: gateSlider)))
        root.addArrangedSubview(row("Zu laut: Reaktion", fastDownSlider, value: valueLabel("ms", slider: fastDownSlider)))
        root.addArrangedSubview(row("Zu leise: Reaktion", fastUpSlider, value: valueLabel("ms", slider: fastUpSlider)))
        root.addArrangedSubview(label("Empfehlung: Zielpegel -21 dBFS, Gate -55 dBFS, Abwaerts 18 ms, Aufwaerts 130 ms."))
        for s in [targetSlider, gateSlider, fastDownSlider, fastUpSlider] { s.target = self; s.action = #selector(controlChanged(_:)) }
        applyConfigToControls()
        return scroll
    }

    func updateView() -> NSView {
        let v = NSView()
        let root = stack(.vertical); root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        v.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: v.leadingAnchor), root.trailingAnchor.constraint(equalTo: v.trailingAnchor), root.topAnchor.constraint(equalTo: v.topAnchor), root.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        root.addArrangedSubview(label("Updates & Changelog", bold: true))
        root.addArrangedSubview(updateStatus)
        let row = stack(.horizontal); row.addArrangedSubview(button("Jetzt pruefen", action: #selector(checkUpdatesAction))); updateButton.target = self; updateButton.action = #selector(downloadUpdate); updateButton.isHidden = true; row.addArrangedSubview(updateButton); root.addArrangedSubview(row)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true
        changelogText.isEditable = false; changelogText.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = changelogText; root.addArrangedSubview(scroll)
        loadLocalChangelog()
        return v
    }

    func helpView() -> NSView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        let tv = NSTextView(); tv.isEditable = false; tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let url = Bundle.main.resourceURL?.appendingPathComponent("HELP_BLACKHOLE_DE.md")
        tv.string = (try? String(contentsOf: url ?? URL(fileURLWithPath: ""), encoding: .utf8)) ?? "Hilfe nicht gefunden."
        scroll.documentView = tv
        return scroll
    }

    func logsView() -> NSView {
        let scroll = container(); let root = scroll.documentView as! NSStackView
        root.addArrangedSubview(label("Logs & Diagnose", bold: true))
        root.addArrangedSubview(label("Log-Verzeichnis: \(manager.logDir.path)"))
        let row = stack(.horizontal); row.addArrangedSubview(button("Logs oeffnen", action: #selector(openLogs))); row.addArrangedSubview(button("Log-ZIP erstellen", action: #selector(exportLogs))); row.addArrangedSubview(button("Audio-Setup zuruecksetzen", action: #selector(resetAudioSetup))); root.addArrangedSubview(row)
        root.addArrangedSubview(label("Bitte sende bei Fehlern die erzeugte ZIP-Datei. Sie enthaelt keine Passwoerter, sondern nur AudioDaBitch-Logs und Setup-Ausgaben."))
        return scroll
    }

    func setupMeter(_ m: NSLevelIndicator) { m.minValue = 0; m.maxValue = 1; m.warningValue = 0.75; m.criticalValue = 0.95; m.levelIndicatorStyle = .continuousCapacity; m.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true }
    func separator() -> NSBox { let b = NSBox(); b.boxType = .separator; b.widthAnchor.constraint(greaterThanOrEqualToConstant: 780).isActive = true; return b }
    func valueLabel(_ suffix: String, slider: NSSlider) -> NSTextField { let l = NSTextField(labelWithString: ""); l.tag = 9000; slider.toolTip = suffix; return l }

    func applyConfigToControls() {
        duckingButton.state = cfg.ducking ? .on : .off
        agcButton.state = cfg.xpilot_agc.enabled ? .on : .off
        discordGain.doubleValue = cfg.inputs[0].gain_db; xpilotGain.doubleValue = cfg.inputs[1].gain_db
        discordPan.doubleValue = cfg.inputs[0].pan; xpilotPan.doubleValue = cfg.inputs[1].pan
        thresholdSlider.doubleValue = cfg.threshold_db; duckDepthSlider.doubleValue = cfg.duck_depth_db; masterSlider.doubleValue = cfg.master_gain_db; ceilingSlider.doubleValue = cfg.limiter_ceiling_db
        targetSlider.doubleValue = cfg.xpilot_agc.target_db; gateSlider.doubleValue = cfg.xpilot_agc.gate_db; fastDownSlider.doubleValue = cfg.xpilot_agc.fast_down_ms; fastUpSlider.doubleValue = cfg.xpilot_agc.fast_up_ms
        if !cfg.ducking { triggerPopup.selectItem(at: 2) } else { triggerPopup.selectItem(at: cfg.trigger == 0 ? 1 : 0) }
    }

    @objc func controlChanged(_ sender: Any?) {
        cfg.ducking = duckingButton.state == .on
        cfg.xpilot_agc.enabled = agcButton.state == .on
        if triggerPopup.indexOfSelectedItem == 2 { cfg.ducking = false; duckingButton.state = .off }
        else { cfg.ducking = true; duckingButton.state = .on; cfg.trigger = triggerPopup.indexOfSelectedItem == 0 ? 1 : 0 }
        cfg.inputs[0].gain_db = discordGain.doubleValue; cfg.inputs[1].gain_db = xpilotGain.doubleValue
        cfg.inputs[0].pan = discordPan.doubleValue; cfg.inputs[1].pan = xpilotPan.doubleValue
        cfg.threshold_db = thresholdSlider.doubleValue; cfg.duck_depth_db = duckDepthSlider.doubleValue; cfg.master_gain_db = masterSlider.doubleValue; cfg.limiter_ceiling_db = ceilingSlider.doubleValue
        cfg.xpilot_agc.target_db = targetSlider.doubleValue; cfg.xpilot_agc.gate_db = gateSlider.doubleValue; cfg.xpilot_agc.fast_down_ms = fastDownSlider.doubleValue; cfg.xpilot_agc.fast_up_ms = fastUpSlider.doubleValue
        if let d = selectedDevice(discordInput) { cfg.inputs[0].device_index = d }
        if let x = selectedDevice(xpilotInput) { cfg.inputs[1].device_index = x }
        if let o = selectedDevice(outputPopup) { cfg.output_index = o }
        manager.saveConfig(cfg)
    }

    func selectedDevice(_ popup: NSPopUpButton) -> Int? { popup.selectedItem?.representedObject as? Int }

    @objc func loadDevicesAction() { loadDevices() }
    func loadDevices() {
        statusLabel.stringValue = "Lade Audio-Geraete und richte bei Bedarf Audio-Komponenten ein..."
        manager.runCtl(["list"]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let out):
                    guard let data = out.data(using: .utf8), let list = try? JSONDecoder().decode(DeviceList.self, from: data), list.ok else { self.statusLabel.stringValue = "Geraeteliste konnte nicht gelesen werden: \(out)"; return }
                    self.inputDevices = list.inputs ?? []; self.outputDevices = list.outputs ?? []
                    self.fillDevicePopups()
                    self.statusLabel.stringValue = "Geraete geladen."
                case .failure(let error): self.statusLabel.stringValue = "Fehler beim Laden: \(error.localizedDescription)"
                }
            }
        }
    }

    func fillDevicePopups() {
        func fill(_ p: NSPopUpButton, devices: [Device], selected: Int?) {
            p.removeAllItems()
            for d in devices { let item = NSMenuItem(title: "#\(d.index)  \(d.name)  (\(d.channels) ch)", action: nil, keyEquivalent: ""); item.representedObject = d.index; p.menu?.addItem(item) }
            if let sel = selected, let item = p.menu?.items.first(where: { ($0.representedObject as? Int) == sel }) { p.select(item) }
        }
        if cfg.inputs[0].device_index == nil, let d = inputDevices.first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole 2ch") }) { cfg.inputs[0].device_index = d.index }
        if cfg.inputs[1].device_index == nil, let d = inputDevices.first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole 16ch") }) { cfg.inputs[1].device_index = d.index }
        if cfg.output_index == nil, let d = outputDevices.first(where: { !$0.name.localizedCaseInsensitiveContains("BlackHole") }) { cfg.output_index = d.index }
        fill(discordInput, devices: inputDevices, selected: cfg.inputs[0].device_index)
        fill(xpilotInput, devices: inputDevices, selected: cfg.inputs[1].device_index)
        fill(outputPopup, devices: outputDevices, selected: cfg.output_index)
        discordInput.target = self; discordInput.action = #selector(controlChanged(_:)); xpilotInput.target = self; xpilotInput.action = #selector(controlChanged(_:)); outputPopup.target = self; outputPopup.action = #selector(controlChanged(_:))
        manager.saveConfig(cfg)
    }

    @objc func startAudio() {
        controlChanged(nil)
        statusLabel.stringValue = "Starte Audio-Engine..."
        manager.runCtl(["start", manager.configURL.path, manager.levelsURL.path, manager.pidURL.path]) { result in
            DispatchQueue.main.async {
                switch result { case .success(let out): self.statusLabel.stringValue = "Audio gestartet: \(out)"; case .failure(let error): self.statusLabel.stringValue = "Start fehlgeschlagen: \(error.localizedDescription)" }
            }
        }
    }
    @objc func stopAudio() { manager.runCtl(["stop", manager.pidURL.path]) { _ in DispatchQueue.main.async { self.statusLabel.stringValue = "Audio gestoppt." } } }
    @objc func restartAudio() {
        statusLabel.stringValue = "Engine wird neu gestartet..."
        manager.runCtl(["stop", manager.pidURL.path]) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.startAudio() }
        }
    }

    func meterValue(_ rms: Double) -> Double { let db = 20.0 * log10(max(rms, 1e-12)); return min(1.0, max(0.0, (db + 70.0) / 70.0)) }
    func dbText(_ rms: Double) -> String { let db = 20.0 * log10(max(rms, 1e-12)); return db < -119 ? "-inf" : String(format: "%.1f dB", db) }
    @objc func refreshMeters() {
        guard let levels = manager.loadLevels() else { return }
        let rms = levels["rms"] as? [Double] ?? [0,0]
        if rms.count >= 2 {
            discordMeter.doubleValue = meterValue(rms[0]); xpilotMeter.doubleValue = meterValue(rms[1])
            discordMeterText.stringValue = "Discord: \(dbText(rms[0]))"; xpilotMeterText.stringValue = "xPilot: \(dbText(rms[1]))"
        }
        if let d = levels["duck_db"] as? Double { duckText.stringValue = String(format: "Ducking: %.1f dB", d) }
        if let l = levels["limiter_db"] as? Double { limitText.stringValue = String(format: "Limiter: %.1f dB", l) }
        if let a = levels["xpilot_agc_gain_db"] as? Double { agcText.stringValue = String(format: "xPilot Auto-Level: %.1f dB", a) }
        if let st = levels["status"] as? String { statusLabel.stringValue = st }
    }

    func loadLocalChangelog() {
        let url = Bundle.main.resourceURL?.appendingPathComponent("CHANGELOG.md")
        changelogText.string = (try? String(contentsOf: url ?? URL(fileURLWithPath: ""), encoding: .utf8)) ?? "Changelog nicht gefunden."
    }
    @objc func checkUpdatesAction() { checkForUpdates(silent: false) }
    func checkForUpdates(silent: Bool) {
        if !silent { updateStatus.stringValue = "Pruefe GitHub Releases..." }
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error = error { if !silent { self.updateStatus.stringValue = "Update-Pruefung fehlgeschlagen: \(error.localizedDescription)" }; return }
                guard let data = data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { if !silent { self.updateStatus.stringValue = "GitHub Antwort konnte nicht gelesen werden." }; return }
                let tag = obj["tag_name"] as? String ?? ""
                let body = obj["body"] as? String ?? ""
                let html = obj["html_url"] as? String ?? "https://github.com/\(repoOwner)/\(repoName)/releases/latest"
                self.latestReleaseURL = URL(string: html)
                if let assets = obj["assets"] as? [[String: Any]] {
                    for a in assets where (a["name"] as? String) == updateAssetName { if let u = a["browser_download_url"] as? String { self.latestDownloadURL = URL(string: u) } }
                }
                if self.latestDownloadURL == nil { self.latestDownloadURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest/download/\(updateAssetName)") }
                if isNewer(tag, than: appVersion) { self.updateStatus.stringValue = "Neue Version verfuegbar: \(tag)"; self.updateButton.isHidden = false }
                else { if !silent { self.updateStatus.stringValue = "Du nutzt die aktuelle Version (\(appVersion))." }; self.updateButton.isHidden = true }
                if !body.isEmpty {
                    let remoteText = """
# Latest GitHub Release: \(tag)

\(body)

---

"""
                    self.changelogText.string = remoteText + self.changelogText.string
                }
            }
        }.resume()
    }

    @objc func downloadUpdate() {
        guard let url = latestDownloadURL else { return }
        updateStatus.stringValue = "Lade Update..."
        URLSession.shared.downloadTask(with: url) { temp, _, error in
            DispatchQueue.main.async {
                if let error = error { self.updateStatus.stringValue = "Download fehlgeschlagen: \(error.localizedDescription)"; return }
                guard let temp = temp else { self.updateStatus.stringValue = "Download fehlgeschlagen."; return }
                let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/AudioDaBitch.pkg")
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.copyItem(at: temp, to: dest); self.updateStatus.stringValue = "Update geladen. Installer wird geoeffnet..."; NSWorkspace.shared.open(dest) }
                catch { self.updateStatus.stringValue = "Konnte Update nicht speichern: \(error.localizedDescription)" }
            }
        }.resume()
    }

    @objc func openLogs() { NSWorkspace.shared.open(manager.logDir) }
    @objc func exportLogs() {
        manager.exportLogs { url in DispatchQueue.main.async { if let url = url { NSWorkspace.shared.activateFileViewerSelecting([url]); self.statusLabel.stringValue = "Log-ZIP erstellt: \(url.lastPathComponent)" } else { self.statusLabel.stringValue = "Log-ZIP konnte nicht erstellt werden." } } }
    }
    @objc func resetAudioSetup() { manager.runCtl(["reset"]) { _ in DispatchQueue.main.async { self.statusLabel.stringValue = "Audio-Setup zurueckgesetzt. Beim naechsten Geraeteladen wird es neu eingerichtet." } } }

    @objc func minimizeMainWindow() { window?.miniaturize(nil) }
    @objc func showMainWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "AudioDaBitch beenden?"
        alert.informativeText = "Beenden stoppt die Audio-Engine. Minimieren legt das Fenster nur ab, die App bleibt aktiv."
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Minimieren")
        alert.addButton(withTitle: "Abbrechen")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn { NSApp.terminate(nil); return false }
        if result == .alertSecondButtonReturn { sender.miniaturize(nil); return false }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        meterTimer?.invalidate()
        manager.runCtl(["stop", manager.pidURL.path]) { _ in }
        return .terminateNow
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "AudioDaBitch \(appVersion)"
        alert.informativeText = "Made with ♥ in Berlin - by Michel Damhorst"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

import Cocoa
import Foundation

let ADBVersion = "0.5.5"
let ADBPort = 49372
let ADBBaseURL = URL(string: "http://127.0.0.1:\(ADBPort)")!

func appSupportDir() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AudioDaBitch", isDirectory: true) }
func logDir() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AudioDaBitch", isDirectory: true) }
func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
func ensureDir(_ url: URL) { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
func log(_ s: String) { ensureDir(logDir()); let u = logDir().appendingPathComponent("app.log"); if let d = "[\(nowISO())] \(s)\n".data(using: .utf8) { if FileManager.default.fileExists(atPath: u.path), let h = try? FileHandle(forWritingTo: u) { try? h.seekToEnd(); try? h.write(contentsOf: d); try? h.close() } else { try? d.write(to: u) } } }

struct Device: Codable { let id: Int; let name: String; let inputs: Int?; let outputs: Int? }
struct DevicesResponse: Codable { let inputs: [Device]; let outputs: [Device]; let error: String? }
struct HealthResponse: Codable { let ok: Bool; let version: String?; let sounddevice: Bool?; let error: String? }
struct Meters: Codable { let discord: Double?; let xpilot: Double?; let output: Double? }
struct StateResponse: Codable { let ok: Bool; let version: String?; let running: Bool?; let meters: Meters?; let levelerGainDb: Double? }

final class EngineManager {
 static let shared = EngineManager()
 private var process: Process?
 private var engineURL: URL? { Bundle.main.url(forResource: "engine", withExtension: "py") }
 let pidFile = appSupportDir().appendingPathComponent("engine.pid")

 func cleanupStale() {
 ensureDir(appSupportDir()); ensureDir(logDir())
 if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 { kill(pid, SIGTERM); usleep(250_000); kill(pid, SIGKILL); try? FileManager.default.removeItem(at: pidFile) }
 _ = shell("/usr/bin/pkill", ["-f", "/Applications/AudioDaBitch.app/Contents/Resources/engine.py"])
 _ = shell("/usr/bin/pkill", ["-f", "Resources/engine.py"])
 _ = shell("/usr/sbin/lsof", ["-tiTCP:\(ADBPort)", "-sTCP:LISTEN"])
 }

 func start() {
 ensureDir(appSupportDir()); ensureDir(logDir())
 if process?.isRunning == true { return }
 guard let engineURL else { log("engine.py missing in bundle"); return }
 cleanupStale()
 let py = findPython()
 let p = Process(); p.executableURL = URL(fileURLWithPath: py); p.arguments = [engineURL.path]
 let err = logDir().appendingPathComponent("engine.stderr.log"); FileManager.default.createFile(atPath: err.path, contents: nil)
 if let h = try? FileHandle(forWritingTo: err) { p.standardError = h; p.standardOutput = h }
 do { try p.run(); process = p; log("engine launched: \(py) \(engineURL.path)") } catch { log("engine launch failed: \(error)") }
 }

 func stop() {
 post("/shutdown", body: [:]) { _ in }
 if let p = process, p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now()+0.5) { if p.isRunning { p.interrupt(); p.terminate() } } }
 process = nil
 cleanupStale()
 }

 func findPython() -> String {
 let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3", "/usr/bin/python3"]
 for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
 return "/usr/bin/python3"
 }

 func shell(_ exe: String, _ args: [String]) -> String { let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args; let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; do { try p.run(); p.waitUntilExit(); return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding:.utf8) ?? "" } catch { return "" } }
 func get(_ path: String, completion: @escaping (Data?) -> Void) { URLSession.shared.dataTask(with: ADBBaseURL.appendingPathComponent(String(path.dropFirst()))) { d,_,_ in completion(d) }.resume() }
 func post(_ path: String, body: [String:Any], completion: @escaping (Data?) -> Void) { var req = URLRequest(url: ADBBaseURL.appendingPathComponent(String(path.dropFirst()))); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField:"Content-Type"); req.httpBody = try? JSONSerialization.data(withJSONObject: body); URLSession.shared.dataTask(with:req){ d,_,_ in completion(d)}.resume() }
}

final class MeterView: NSView {
 var valueDb: Double = -120 { didSet { needsDisplay = true } }
 var title = ""
 override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 52) }
 override func draw(_ dirtyRect: NSRect) {
 NSColor.clear.setFill(); dirtyRect.fill()
 let rect = NSRect(x: 0, y: 10, width: bounds.width, height: 12)
 NSColor.windowBackgroundColor.setFill(); rect.fill()
 let norm = max(0, min(1, (valueDb + 60) / 60))
 let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * norm, height: rect.height)
 (valueDb > -6 ? NSColor.systemRed : valueDb > -18 ? NSColor.systemOrange : NSColor.systemGreen).setFill(); fill.fill()
 NSColor.separatorColor.setStroke(); NSBezierPath(rect: rect).stroke()
 let text = "\(title) \(Int(valueDb)) dB"
 text.draw(at: NSPoint(x: 0, y: 28), withAttributes: [.foregroundColor:NSColor.labelColor, .font:NSFont.systemFont(ofSize: 12, weight: .medium)])
 }
}

final class BlockView: NSBox {
 let popup = NSPopUpButton()
 let meter = MeterView()
 let gain = NSSlider(value: 0, minValue: -24, maxValue: 12, target: nil, action: nil)
 let pan = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
 init(title: String, hasPan: Bool) {
 super.init(frame: .zero); self.title = title; boxType = .custom; borderColor = .separatorColor; cornerRadius = 10; contentViewMargins = NSSize(width: 12, height: 12)
 let st = NSStackView(); st.orientation = .vertical; st.spacing = 8; st.translatesAutoresizingMaskIntoConstraints = false; contentView?.addSubview(st); NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor), st.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor), st.topAnchor.constraint(equalTo: contentView!.topAnchor), st.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor)])
 meter.title = title; st.addArrangedSubview(meter); st.addArrangedSubview(label("Gerät")); st.addArrangedSubview(popup); st.addArrangedSubview(label("Lautstärke")); st.addArrangedSubview(gain)
 if hasPan { st.addArrangedSubview(label("Panorama")); st.addArrangedSubview(pan) }
 }
 required init?(coder: NSCoder) { fatalError() }
 func label(_ s:String)->NSTextField{ let l = NSTextField(labelWithString:s); l.font = .systemFont(ofSize:11); l.textColor = .secondaryLabelColor; return l }
}

final class AppController: NSViewController {
 let tabs = NSTabView(); let status = NSTextField(labelWithString:"Starte...")
 let discord = BlockView(title: "Discord", hasPan: true)
 let xpilot = BlockView(title: "xPilot", hasPan: true)
 let output = BlockView(title: "Output", hasPan: false)
 let deviceError = NSTextField(labelWithString: "")
 let levelerInfo = NSTextField(labelWithString: "")
 let helpText = NSTextView(); let changeText = NSTextView(); let updateStatus = NSTextField(labelWithString: "")
 var timer: Timer?

 override func loadView() { view = NSView(frame: NSRect(x:0,y:0,width:980,height:620)) }
 override func viewDidLoad() { super.viewDidLoad(); buildUI(); EngineManager.shared.start(); DispatchQueue.main.asyncAfter(deadline:.now()+1.0){ self.refreshAll() }; timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true){ _ in self.pollState() } }

 func buildUI() {
 let root = NSStackView(); root.orientation = .vertical; root.spacing = 8; root.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(root); NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:view.leadingAnchor, constant:14), root.trailingAnchor.constraint(equalTo:view.trailingAnchor, constant:-14), root.topAnchor.constraint(equalTo:view.topAnchor, constant:14), root.bottomAnchor.constraint(equalTo:view.bottomAnchor, constant:-14)])
 let top = NSStackView(); top.orientation = .horizontal; top.spacing = 8; status.stringValue = "AudioDaBitch \(ADBVersion)"; top.addArrangedSubview(status); top.addArrangedSubview(button("Geräte aktualisieren", #selector(loadDevices))); top.addArrangedSubview(button("Audio starten", #selector(startAudio))); top.addArrangedSubview(button("Audio stoppen", #selector(stopAudio))); top.addArrangedSubview(button("Engine reparieren", #selector(repairEngine))); root.addArrangedSubview(top)
 tabs.translatesAutoresizingMaskIntoConstraints = false; root.addArrangedSubview(tabs); tabs.heightAnchor.constraint(greaterThanOrEqualToConstant:540).isActive = true
 addTab("Audio", audioView()); addTab("xPilot Leveler", levelerView()); addTab("Updates ●", updatesView()); addTab("Hilfe", textView(helpText, loadResource("HELP_BLACKHOLE_DE", fallback: fallbackHelp()))); addTab("Logs", logsView())
 for p in [discord.popup,xpilot.popup,output.popup] { p.target = self; p.action = #selector(configChanged) }
 for s in [discord.gain,xpilot.gain,output.gain,discord.pan,xpilot.pan] { s.target = self; s.action = #selector(configChanged) }
 discord.pan.doubleValue = -1; xpilot.pan.doubleValue = 1
 }
 func addTab(_ name:String,_ v:NSView){ let i = NSTabViewItem(identifier:name); i.label = name; i.view = v; tabs.addTabViewItem(i) }
 func button(_ t:String,_ a:Selector)->NSButton{ let b = NSButton(title:t, target:self, action:a); b.bezelStyle = .rounded; return b }
 func audioView()->NSView{ let v = NSView(); let st = NSStackView(); st.orientation = .vertical; st.spacing = 10; st.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(st); NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo:v.leadingAnchor, constant:10),st.trailingAnchor.constraint(equalTo:v.trailingAnchor, constant:-10),st.topAnchor.constraint(equalTo:v.topAnchor, constant:10)])
 deviceError.textColor = .systemRed; st.addArrangedSubview(deviceError); let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12; [discord,xpilot,output].forEach{ $0.translatesAutoresizingMaskIntoConstraints = false; $0.widthAnchor.constraint(equalToConstant:290).isActive = true; row.addArrangedSubview($0)}; st.addArrangedSubview(row); return v }
 func levelerView()->NSView{ let v = NSView(); let st = NSStackView(); st.orientation = .vertical; st.spacing = 12; st.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(st); NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo:v.leadingAnchor, constant:18),st.trailingAnchor.constraint(equalTo:v.trailingAnchor, constant:-18),st.topAnchor.constraint(equalTo:v.topAnchor, constant:18)])
 let title = NSTextField(labelWithString:"xPilot Funk-Ausgleich"); title.font = .boldSystemFont(ofSize:18); st.addArrangedSubview(title); let body = NSTextField(wrappingLabelWithString:"Gleicht nur den xPilot-Kanal automatisch aus. Zu laute VATSIM-Stationen werden schnell abgesenkt, zu leise Stationen vorsichtig angehoben. Der Master-Limiter bleibt zusätzlich aktiv."); st.addArrangedSubview(body); levelerInfo.stringValue = "Aktueller xPilot-Pegel: -120 dB Auto-Korrektur: 0 dB"; st.addArrangedSubview(levelerInfo); return v }
 func updatesView()->NSView{ let v = NSView(); let st = NSStackView(); st.orientation = .vertical; st.spacing = 10; st.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(st); NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo:v.leadingAnchor, constant:18),st.trailingAnchor.constraint(equalTo:v.trailingAnchor, constant:-18),st.topAnchor.constraint(equalTo:v.topAnchor, constant:18),st.bottomAnchor.constraint(equalTo:v.bottomAnchor, constant:-18)]); updateStatus.stringValue = "Installiert: \(ADBVersion). Update-Check läuft automatisch."; updateStatus.textColor = .systemBlue; st.addArrangedSubview(updateStatus); st.addArrangedSubview(button("GitHub Releases öffnen", #selector(openReleases))); st.addArrangedSubview(textView(changeText, loadResource("CHANGELOG", fallback: fallbackChangelog()))); return v }
 func logsView()->NSView{ let v = NSView(); let st = NSStackView(); st.orientation = .vertical; st.spacing = 10; st.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(st); NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo:v.leadingAnchor, constant:18),st.topAnchor.constraint(equalTo:v.topAnchor, constant:18)]); st.addArrangedSubview(button("Logs öffnen", #selector(openLogs))); st.addArrangedSubview(button("Log-ZIP erstellen", #selector(exportLogs))); st.addArrangedSubview(button("Hängende Prozesse beenden", #selector(killStale))); return v }
 func textView(_ tv:NSTextView,_ txt:String)->NSScrollView{ tv.isEditable = false; tv.string = txt; tv.textColor = .labelColor; tv.backgroundColor = .textBackgroundColor; tv.font = .systemFont(ofSize:13); let sc = NSScrollView(); sc.hasVerticalScroller = true; sc.documentView = tv; sc.heightAnchor.constraint(greaterThanOrEqualToConstant:420).isActive = true; return sc }
 func loadResource(_ n:String,fallback:String)->String{ if let u = Bundle.main.url(forResource:n, withExtension:"md"), let s = try? String(contentsOf:u, encoding:.utf8), !s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return s }; return fallback }
 func fallbackHelp()->String{"BlackHole Routing:\nDiscord Output -> BlackHole 2ch\nxPilot Headset/Speaker -> BlackHole 16ch\nAudioDaBitch Output -> Kopfhörer/Audiointerface\nKein Multi-Output mit Kopfhörer verwenden."}
 func fallbackChangelog()->String{"# Changelog\n\n## 0.5.5\n- Audio-Abhängigkeiten werden automatisch repariert\n- Geräteauswahl, Hilfe, Changelog, Log-ZIP und Icon fixiert"}

 @objc func loadDevices(){ refreshAll() }
 @objc func startAudio(){ EngineManager.shared.post("/start", body: [:]){ _ in self.pollState() } }
 @objc func stopAudio(){ EngineManager.shared.post("/stop", body: [:]){ _ in } }
 @objc func repairEngine(){ EngineManager.shared.stop(); EngineManager.shared.start(); DispatchQueue.main.asyncAfter(deadline:.now()+2){ self.refreshAll() } }
 @objc func openReleases(){ NSWorkspace.shared.open(URL(string:"https://github.com/Monoid12/AudioDaBitch/releases")!) }
 @objc func openLogs(){ ensureDir(logDir()); NSWorkspace.shared.open(logDir()) }
 @objc func exportLogs(){ ensureDir(logDir()); let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/AudioDaBitch_Logs_\(Int(Date().timeIntervalSince1970)).zip"); _ = EngineManager.shared.shell("/usr/bin/zip", ["-r", dest.path, logDir().path, appSupportDir().path]); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
 @objc func killStale(){ EngineManager.shared.cleanupStale(); status.stringValue = "Hängende Prozesse bereinigt" }

 func refreshAll(){ pollHealth(); fetchDevices(); pollState() }
 func pollHealth(){ EngineManager.shared.get("/health"){ d in DispatchQueue.main.async { guard let d, let h = try? JSONDecoder().decode(HealthResponse.self, from:d) else { self.status.stringValue = "Engine nicht erreichbar"; return }; if h.sounddevice == false { self.status.stringValue = "Audio-Komponenten werden eingerichtet oder fehlen: \(h.error ?? "")" } else { self.status.stringValue = "Engine bereit \(h.version ?? "")" } } } }
 func fetchDevices(){ EngineManager.shared.get("/devices"){ d in DispatchQueue.main.async { guard let d, let r = try? JSONDecoder().decode(DevicesResponse.self, from:d) else { self.deviceError.stringValue = "/devices konnte nicht gelesen werden"; return }; self.populate(self.discord.popup, r.inputs); self.populate(self.xpilot.popup, r.inputs); self.populate(self.output.popup, r.outputs); if let e = r.error, !e.isEmpty { self.deviceError.stringValue = "Gerätefehler: \(e)" } else { self.deviceError.stringValue = r.inputs.isEmpty || r.outputs.isEmpty ? "Keine Audio-Geräte gefunden" : "" } } } }
 func populate(_ p:NSPopUpButton,_ devices:[Device]){ let old = p.selectedItem?.representedObject as? Int; p.removeAllItems(); p.addItem(withTitle:"Bitte auswählen"); p.lastItem?.representedObject = -1; for d in devices { p.addItem(withTitle:"\(d.name) (#\(d.id))"); p.lastItem?.representedObject = d.id }; if let old, let item = p.itemArray.first(where:{($0.representedObject as? Int)==old}) { p.select(item) } }
 func pollState(){ EngineManager.shared.get("/state"){ d in DispatchQueue.main.async { guard let d, let s = try? JSONDecoder().decode(StateResponse.self, from:d) else { return }; self.discord.meter.valueDb = s.meters?.discord ?? -120; self.xpilot.meter.valueDb = s.meters?.xpilot ?? -120; self.output.meter.valueDb = s.meters?.output ?? -120; self.levelerInfo.stringValue = "Aktueller xPilot-Pegel: \(Int(s.meters?.xpilot ?? -120)) dB Auto-Korrektur: \(Int(s.levelerGainDb ?? 0)) dB" } } }
 @objc func configChanged(){ var b:[String:Any] = [:]; let did = discord.popup.selectedItem?.representedObject as? Int ?? -1; let xid = xpilot.popup.selectedItem?.representedObject as? Int ?? -1; let oid = output.popup.selectedItem?.representedObject as? Int ?? -1; if did >= 0 { b["discordInput"] = did }; if xid >= 0 { b["xpilotInput"] = xid }; if oid >= 0 { b["outputDevice"] = oid }; b["discordGainDb"] = discord.gain.doubleValue; b["xpilotGainDb"] = xpilot.gain.doubleValue; b["masterGainDb"] = output.gain.doubleValue; b["discordPan"] = discord.pan.doubleValue; b["xpilotPan"] = xpilot.pan.doubleValue; EngineManager.shared.post("/config", body:b){ _ in } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
 var window: NSWindow!
 func applicationDidFinishLaunching(_ notification: Notification) { log("AudioDaBitch \(ADBVersion) started"); let vc = AppController(); window = NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:640), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false); window.center(); window.title = "AudioDaBitch"; window.contentViewController = vc; window.delegate = self; window.makeKeyAndOrderFront(nil) }
 func windowShouldClose(_ sender: NSWindow) -> Bool { let a = NSAlert(); a.messageText = "AudioDaBitch beenden?"; a.informativeText = "Beenden stoppt die Audio-Engine. Minimieren lässt AudioDaBitch geöffnet."; a.addButton(withTitle:"Beenden"); a.addButton(withTitle:"Minimieren"); a.addButton(withTitle:"Abbrechen"); let r = a.runModal(); if r == .alertFirstButtonReturn { EngineManager.shared.stop(); NSApp.terminate(nil); return false }; if r == .alertSecondButtonReturn { sender.miniaturize(nil); return false }; return false }
 func applicationWillTerminate(_ notification: Notification) { EngineManager.shared.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.activate(ignoringOtherApps:true); app.run()

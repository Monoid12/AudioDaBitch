import Cocoa
import Foundation

let ADBVersion = "0.5.15"
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
struct BufferDiagnostics: Codable { let queuedMs: Double?; let droppedMs: Double?; let highWaterMs: Double? }
struct Diagnostics: Codable { let sampleRate: Int?; let blockSize: Int?; let latency: String?; let callbackErrors: Int?; let lastError: String?; let discord: BufferDiagnostics?; let xpilot: BufferDiagnostics? }
struct StateResponse: Codable { let ok: Bool; let version: String?; let running: Bool?; let meters: Meters?; let levelerGainDb: Double?; let discordLevelerGainDb: Double?; let xpilotLevelerGainDb: Double?; let discordDuckGainDb: Double?; let xpilotDuckGainDb: Double?; let diagnostics: Diagnostics? }
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
    override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 128) }

    func point(center: NSPoint, radius: CGFloat, degrees: CGFloat) -> NSPoint {
        let radians = (degrees - 90) * .pi / 180
        return NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let outer = bounds.insetBy(dx: 3, dy: 4)
        let body = NSBezierPath(roundedRect: outer, xRadius: 9, yRadius: 9)
        NSGradient(colors: [NSColor(calibratedWhite: 0.05, alpha: 1), NSColor(calibratedWhite: 0.18, alpha: 1)])?.draw(in: body, angle: 90)
        NSColor(calibratedWhite: 0.0, alpha: 0.75).setStroke()
        body.lineWidth = 1.5
        body.stroke()

        let face = outer.insetBy(dx: 13, dy: 16)
        let facePath = NSBezierPath(roundedRect: face, xRadius: 6, yRadius: 6)
        NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.58, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.57, blue: 0.35, alpha: 1)])?.draw(in: facePath, angle: 90)
        NSColor(calibratedWhite: 0.05, alpha: 0.9).setStroke()
        facePath.lineWidth = 2
        facePath.stroke()

        NSGraphicsContext.saveGraphicsState()
        facePath.addClip()

        let safeFace = face.insetBy(dx: 16, dy: 12)
        let center = NSPoint(x: safeFace.midX, y: safeFace.minY + 10)
        let radius = min(safeFace.width * 0.37, safeFace.height * 0.70)
        let minAngle: CGFloat = 232
        let maxAngle: CGFloat = 128
        let labels: [(Double, String)] = [(-60, "-60"), (-40, "-40"), (-20, "-20"), (-10, "-10"), (-6, "-6"), (0, "0")]
        for item in labels {
            let norm = CGFloat(max(0, min(1, (item.0 + 60) / 60)))
            let angle = minAngle + (maxAngle - minAngle) * norm
            let p1 = point(center: center, radius: radius * 0.80, degrees: angle)
            let p2 = point(center: center, radius: radius * 0.92, degrees: angle)
            let tick = NSBezierPath()
            tick.move(to: p1)
            tick.line(to: p2)
            (item.0 >= -6 ? NSColor.systemRed : NSColor(calibratedWhite: 0.14, alpha: 1)).setStroke()
            tick.lineWidth = item.0 == -60 || item.0 == 0 ? 1.5 : 1
            tick.stroke()
            let lp = point(center: center, radius: radius * 0.63, degrees: angle)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: item.0 >= -6 ? NSColor.systemRed : NSColor(calibratedWhite: 0.12, alpha: 1),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            ]
            let size = item.1.size(withAttributes: attrs)
            item.1.draw(at: NSPoint(x: lp.x - size.width / 2, y: lp.y - size.height / 2), withAttributes: attrs)
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1), .font: NSFont.systemFont(ofSize: 13, weight: .heavy)]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1), .font: NSFont.systemFont(ofSize: 10, weight: .bold)]
        let titleText = title.uppercased()
        let titleSize = titleText.size(withAttributes: titleAttrs)
        titleText.draw(at: NSPoint(x: face.midX - titleSize.width / 2, y: face.minY + 39), withAttributes: titleAttrs)
        "VU".draw(at: NSPoint(x: face.midX - 8, y: face.minY + 27), withAttributes: subtitleAttrs)

        let norm = CGFloat(max(0, min(1, (valueDb + 60) / 60)))
        let angle = minAngle + (maxAngle - minAngle) * norm
        let needleEnd = point(center: center, radius: radius * 0.80, degrees: angle)
        let shadow = NSBezierPath()
        shadow.move(to: NSPoint(x: center.x + 1, y: center.y - 1))
        shadow.line(to: NSPoint(x: needleEnd.x + 1, y: needleEnd.y - 1))
        NSColor(calibratedWhite: 0, alpha: 0.35).setStroke()
        shadow.lineWidth = 2.2
        shadow.stroke()
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: needleEnd)
        NSColor.systemRed.setStroke()
        needle.lineWidth = 1.7
        needle.stroke()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)).fill()

        let valueText = "\(Int(valueDb.rounded())) dB"
        let valueAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1), .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)]
        let valueSize = valueText.size(withAttributes: valueAttrs)
        valueText.draw(at: NSPoint(x: face.midX - valueSize.width / 2, y: face.minY + 3), withAttributes: valueAttrs)

        NSGraphicsContext.restoreGraphicsState()
    }
}

final class KnobControl: NSControl {
    let minValue: Double
    let maxValue: Double
    var unit = ""
    var step: Double = 0.0
    private var value: Double
    private var startPoint = NSPoint.zero
    private var startValue: Double = 0
    private var hovering = false

    init(value: Double, minValue: Double, maxValue: Double, unit: String = "") {
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.unit = unit
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 86, height: 96) }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var doubleValue: Double {
        get { value }
        set { setValue(newValue, notify: false) }
    }

    func setValue(_ newValue: Double, notify: Bool) {
        var next = max(minValue, min(maxValue, newValue))
        if step > 0 {
            next = (next / step).rounded() * step
        }
        guard abs(next - value) > 0.0001 else { return }
        value = next
        needsDisplay = true
        if notify {
            sendAction(action, to: target)
        }
    }

    func valueAngle() -> CGFloat {
        let norm = CGFloat((value - minValue) / (maxValue - minValue))
        return -135 + 270 * max(0, min(1, norm))
    }

    func point(center: NSPoint, radius: CGFloat, degrees: CGFloat) -> NSPoint {
        let radians = (degrees - 90) * .pi / 180
        return NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = convert(event.locationInWindow, from: nil)
        startValue = value
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let range = max(0.0001, maxValue - minValue)
        let delta = Double((point.y - startPoint.y) + (point.x - startPoint.x) * 0.35) * range / 170.0
        setValue(startValue + delta, notify: true)
    }

    override func scrollWheel(with event: NSEvent) {
        let range = max(0.0001, maxValue - minValue)
        let direction = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        setValue(value + Double(direction) * range / 450.0, notify: true)
    }

    func valueText() -> String {
        if minValue == -1 && maxValue == 1 {
            if abs(value) < 0.05 { return "C" }
            return value < 0 ? "L \(Int(abs(value) * 100))" : "R \(Int(value * 100))"
        }
        let rounded = Int(value.rounded())
        if unit == "dB" && rounded > 0 { return "+\(rounded) \(unit)" }
        return unit.isEmpty ? "\(rounded)" : "\(rounded) \(unit)"
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let side = min(bounds.width, bounds.height - 14)
        let rect = NSRect(x: bounds.midX - side / 2, y: bounds.maxY - side - 6, width: side, height: side).insetBy(dx: 5, dy: 5)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        for index in 0...10 {
            let angle = CGFloat(-135 + index * 27)
            let p1 = point(center: center, radius: radius + 2, degrees: angle)
            let p2 = point(center: center, radius: radius + (index % 5 == 0 ? 10 : 7), degrees: angle)
            let tick = NSBezierPath()
            tick.move(to: p1)
            tick.line(to: p2)
            NSColor.secondaryLabelColor.setStroke()
            tick.lineWidth = index % 5 == 0 ? 1.4 : 0.9
            tick.stroke()
        }

        let shadow = NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: -2))
        NSColor(calibratedWhite: 0, alpha: 0.38).setFill()
        shadow.fill()
        let body = NSBezierPath(ovalIn: rect)
        let top = hovering ? NSColor(calibratedWhite: 0.26, alpha: 1) : NSColor(calibratedWhite: 0.18, alpha: 1)
        NSGradient(colors: [top, NSColor(calibratedWhite: 0.03, alpha: 1)])?.draw(in: body, angle: 90)
        NSColor(calibratedWhite: 0.0, alpha: 0.95).setStroke()
        body.lineWidth = 1.5
        body.stroke()

        let cap = NSBezierPath(ovalIn: rect.insetBy(dx: radius * 0.26, dy: radius * 0.26))
        NSGradient(colors: [NSColor(calibratedWhite: 0.1, alpha: 1), NSColor(calibratedWhite: 0.24, alpha: 1)])?.draw(in: cap, angle: 90)
        NSColor(calibratedWhite: 0, alpha: 0.7).setStroke()
        cap.lineWidth = 1
        cap.stroke()

        let angle = valueAngle()
        let p = point(center: center, radius: radius * 0.66, degrees: angle)
        let pointer = NSBezierPath()
        pointer.move(to: center)
        pointer.line(to: p)
        NSColor(calibratedRed: 0.9, green: 0.94, blue: 0.98, alpha: 1).setStroke()
        pointer.lineWidth = 3.2
        pointer.lineCapStyle = .round
        pointer.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        ]
        let text = valueText()
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 1), withAttributes: attrs)
    }
}

final class BlockView: NSBox {
    let popup = NSPopUpButton()
    let meter = MeterView()
    let gain = KnobControl(value: 0, minValue: -24, maxValue: 12, unit: "dB")
    let pan = KnobControl(value: 0, minValue: -1, maxValue: 1)

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
        meter.heightAnchor.constraint(equalToConstant: 128).isActive = true
        stack.addArrangedSubview(meter)
        stack.addArrangedSubview(label("Device"))
        stack.addArrangedSubview(popup)
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 18
        controls.addArrangedSubview(knobColumn("Volume", gain))
        if hasPan {
            controls.addArrangedSubview(knobColumn("Pan", pan))
        }
        stack.addArrangedSubview(controls)
    }

    required init?(coder: NSCoder) { fatalError() }

    func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    func knobColumn(_ title: String, _ knob: KnobControl) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        knob.widthAnchor.constraint(equalToConstant: 86).isActive = true
        knob.heightAnchor.constraint(equalToConstant: 96).isActive = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(knob)
        return stack
    }
}

final class LevelerPanel: NSBox {
    let enabled = NSButton(checkboxWithTitle: "Enable leveling", target: nil, action: nil)
    let target = KnobControl(value: -20, minValue: -36, maxValue: -12, unit: "dB")
    let maxBoost = KnobControl(value: 15, minValue: 0, maxValue: 18, unit: "dB")
    let maxCut = KnobControl(value: -24, minValue: -30, maxValue: 0, unit: "dB")
    let speed = KnobControl(value: 65, minValue: 1, maxValue: 100, unit: "%")
    let targetValue = NSTextField(labelWithString: "")
    let boostValue = NSTextField(labelWithString: "")
    let cutValue = NSTextField(labelWithString: "")
    let speedValue = NSTextField(labelWithString: "")

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        self.title = title
        boxType = .custom
        borderColor = .separatorColor
        cornerRadius = 8
        contentViewMargins = NSSize(width: 14, height: 14)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor)
        ])
        let detail = NSTextField(wrappingLabelWithString: subtitle)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        enabled.state = .on
        stack.addArrangedSubview(detail)
        stack.addArrangedSubview(enabled)
        stack.addArrangedSubview(controlRow("Target loudness", target, targetValue))
        stack.addArrangedSubview(controlRow("Maximum boost", maxBoost, boostValue))
        stack.addArrangedSubview(controlRow("Maximum cut", maxCut, cutValue))
        stack.addArrangedSubview(controlRow("Response speed", speed, speedValue))
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError() }

    var controls: [NSControl] { [enabled, target, maxBoost, maxCut, speed] }

    func controlRow(_ title: String, _ knob: KnobControl, _ value: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 118).isActive = true
        knob.widthAnchor.constraint(equalToConstant: 68).isActive = true
        knob.heightAnchor.constraint(equalToConstant: 78).isActive = true
        value.alignment = .right
        value.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.widthAnchor.constraint(equalToConstant: 64).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(knob)
        row.addArrangedSubview(value)
        return row
    }

    func updateLabels() {
        targetValue.stringValue = "\(Int(target.doubleValue.rounded())) dB"
        boostValue.stringValue = "+\(Int(maxBoost.doubleValue.rounded())) dB"
        cutValue.stringValue = "\(Int(maxCut.doubleValue.rounded())) dB"
        speedValue.stringValue = "\(Int(speed.doubleValue.rounded()))%"
    }
}

final class DuckingPanel: NSBox {
    let enabled = NSButton(checkboxWithTitle: "Enable xPilot priority ducking", target: nil, action: nil)
    let threshold = KnobControl(value: -46, minValue: -70, maxValue: -20, unit: "dB")
    let depth = KnobControl(value: -24, minValue: -36, maxValue: -6, unit: "dB")
    let attack = KnobControl(value: 4, minValue: 1, maxValue: 80, unit: "ms")
    let release = KnobControl(value: 180, minValue: 60, maxValue: 600, unit: "ms")
    let thresholdValue = NSTextField(labelWithString: "")
    let depthValue = NSTextField(labelWithString: "")
    let attackValue = NSTextField(labelWithString: "")
    let releaseValue = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title = "xPilot priority ducking"
        boxType = .custom
        borderColor = .systemBlue
        cornerRadius = 8
        contentViewMargins = NSSize(width: 14, height: 14)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor)
        ])
        let detail = NSTextField(wrappingLabelWithString: "When xPilot audio is detected, Discord is reduced quickly so ATC stays clear. Release controls how fast Discord fades back in.")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        enabled.state = .on
        stack.addArrangedSubview(detail)
        stack.addArrangedSubview(enabled)
        stack.addArrangedSubview(controlRow("Trigger threshold", threshold, thresholdValue))
        stack.addArrangedSubview(controlRow("Discord reduction", depth, depthValue))
        stack.addArrangedSubview(controlRow("Attack", attack, attackValue))
        stack.addArrangedSubview(controlRow("Release", release, releaseValue))
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError() }

    var controls: [NSControl] { [enabled, threshold, depth, attack, release] }

    func controlRow(_ title: String, _ knob: KnobControl, _ value: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        knob.widthAnchor.constraint(equalToConstant: 68).isActive = true
        knob.heightAnchor.constraint(equalToConstant: 78).isActive = true
        value.alignment = .right
        value.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(knob)
        row.addArrangedSubview(value)
        return row
    }

    func updateLabels() {
        thresholdValue.stringValue = "\(Int(threshold.doubleValue.rounded())) dB"
        depthValue.stringValue = "\(Int(depth.doubleValue.rounded())) dB"
        attackValue.stringValue = "\(Int(attack.doubleValue.rounded())) ms"
        releaseValue.stringValue = "\(Int(release.doubleValue.rounded())) ms"
    }
}

final class AppController: NSViewController {
    let tabs = NSTabView()
    let status = NSTextField(labelWithString: "Starting...")
    let diagnosticsLabel = NSTextField(labelWithString: "")
    let discord = BlockView(title: "Discord", hasPan: true)
    let xpilot = BlockView(title: "xPilot", hasPan: true)
    let output = BlockView(title: "Output", hasPan: false)
    let deviceError = NSTextField(labelWithString: "")
    let levelerInfo = NSTextField(labelWithString: "")
    let discordLeveler = LevelerPanel(title: "Discord channel 1", subtitle: "Keeps Discord voices steady before ducking, panning and limiting.")
    let xpilotLeveler = LevelerPanel(title: "xPilot channel 2", subtitle: "Balances VATSIM stations before the master limiter.")
    let duckingPanel = DuckingPanel()
    let updateStatus = NSTextField(labelWithString: "Installed: \(ADBVersion)")
    let updateButton = NSButton(title: "Install Update", target: nil, action: nil)
    let helpText = NSTextView()
    let changeText = NSTextView()
    var updateTabItem: NSTabViewItem?
    var latestRelease: GitHubRelease?
    var latestAssetURL: URL?
    var stateTimer: Timer?
    var updateTimer: Timer?
    var savedConfig: [String: Any] = [:]
    var inputDevices: [Device] = []
    var outputDevices: [Device] = []

    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 1240, height: 820)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        EngineManager.shared.start()
        updateStatus.stringValue = "Checking for updates automatically..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.loadConfigIntoUI() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.checkForUpdates(silent: false, allowRetry: true) }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in self.pollState() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in self.checkForUpdates(silent: true, allowRetry: false) }
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
        top.addArrangedSubview(button("Refresh Devices", #selector(loadDevices)))
        top.addArrangedSubview(button("Start Audio", #selector(startAudio)))
        top.addArrangedSubview(button("Stop Audio", #selector(stopAudio)))
        top.addArrangedSubview(button("Stabilize Audio", #selector(stabilizeAudio)))
        top.addArrangedSubview(button("Repair Engine", #selector(repairEngine)))
        root.addArrangedSubview(top)

        diagnosticsLabel.textColor = .secondaryLabelColor
        diagnosticsLabel.font = .systemFont(ofSize: 11)
        root.addArrangedSubview(diagnosticsLabel)

        tabs.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(tabs)
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 650).isActive = true
        addTab("Audio", audioView())
        addTab("Leveling", levelerView())
        updateTabItem = addTab("Updates", updatesView())
        addTab("Changelog", textView(changeText, loadResource("CHANGELOG", fallback: fallbackChangelog())))
        addTab("Help", textView(helpText, loadResource("HELP_BLACKHOLE_DE", fallback: fallbackHelp())))
        addTab("Logs", logsView())

        for popup in [discord.popup, xpilot.popup, output.popup] {
            popup.target = self
            popup.action = #selector(configChanged)
        }
        for slider in [discord.gain, xpilot.gain, output.gain, discord.pan, xpilot.pan] {
            slider.target = self
            slider.action = #selector(configChanged)
        }
        for control in discordLeveler.controls + xpilotLeveler.controls + duckingPanel.controls {
            control.target = self
            control.action = #selector(levelerChanged)
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
            block.widthAnchor.constraint(equalToConstant: 360).isActive = true
            row.addArrangedSubview(block)
        }
        stack.addArrangedSubview(row)
        let note = NSTextField(wrappingLabelWithString: "Quality: the default profile uses a stable 48 kHz safe mode with a larger buffer. If audio crackles, click 'Stabilize Audio' first and set all involved devices to 48,000 Hz in Audio MIDI Setup.")
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
        let title = NSTextField(labelWithString: "Channel Leveling")
        title.font = .boldSystemFont(ofSize: 20)
        title.alignment = .center
        stack.addArrangedSubview(title)
        let body = NSTextField(wrappingLabelWithString: "Automatic leveling works on both Discord channel 1 and xPilot channel 2. xPilot priority ducking now has its own controls so ATC can cut through Discord immediately.")
        body.alignment = .center
        stack.addArrangedSubview(body)
        let panels = NSStackView()
        panels.orientation = .horizontal
        panels.spacing = 12
        panels.distribution = .fillEqually
        panels.addArrangedSubview(discordLeveler)
        panels.addArrangedSubview(xpilotLeveler)
        stack.addArrangedSubview(panels)
        stack.addArrangedSubview(duckingPanel)
        levelerInfo.stringValue = "Discord: -120 dB / 0 dB correction    xPilot: -120 dB / 0 dB correction"
        levelerInfo.alignment = .center
        stack.addArrangedSubview(levelerInfo)
        let recommendation = NSTextField(wrappingLabelWithString: "Tip: keep the target around -20 dB for clear speech. Use faster response for busy radio, slower response for smoother Discord voices.")
        recommendation.textColor = .secondaryLabelColor
        recommendation.alignment = .center
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
        let title = NSTextField(labelWithString: "Update Center")
        title.font = .systemFont(ofSize: 20, weight: .heavy)
        title.textColor = .systemBlue
        stack.addArrangedSubview(title)
        let intro = NSTextField(wrappingLabelWithString: "✓ Checks the official GitHub release feed automatically on launch.\n→ A newer release turns this tab blue and enables Install Update.\n! If this version is current, no update needs to be installed.")
        intro.textColor = .labelColor
        intro.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(intro)
        updateStatus.stringValue = "Installed: \(ADBVersion)."
        updateStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(updateStatus)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(button("Check GitHub", #selector(checkUpdatesClicked)))
        updateButton.target = self
        updateButton.action = #selector(installUpdateClicked)
        updateButton.bezelStyle = .rounded
        updateButton.isEnabled = false
        row.addArrangedSubview(updateButton)
        row.addArrangedSubview(button("Open Release Page", #selector(openReleases)))
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
        stack.addArrangedSubview(button("Open Logs", #selector(openLogs)))
        stack.addArrangedSubview(button("Create Log ZIP", #selector(exportLogs)))
        stack.addArrangedSubview(button("Stop Stale Processes", #selector(killStale)))
        return view
    }

    func textView(_ textView: NSTextView, _ text: String) -> NSScrollView {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textStorage?.setAttributedString(styledDocument(text))
        textView.textColor = .labelColor
        textView.backgroundColor = .controlBackgroundColor
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        return scroll
    }

    func styledDocument(_ text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8
        let bulletParagraph = NSMutableParagraphStyle()
        bulletParagraph.lineSpacing = 3
        bulletParagraph.paragraphSpacing = 5
        bulletParagraph.firstLineHeadIndent = 0
        bulletParagraph.headIndent = 18
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespaces)
            var attributes = base
            if line.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                continue
            }
            if line.hasPrefix("### ") {
                line = "◼ " + String(line.dropFirst(4))
                attributes[.font] = NSFont.systemFont(ofSize: 15, weight: .bold)
                attributes[.foregroundColor] = NSColor.systemPurple
            } else if line.hasPrefix("## ") {
                line = "◆ " + String(line.dropFirst(3))
                attributes[.font] = NSFont.systemFont(ofSize: 17, weight: .bold)
                attributes[.foregroundColor] = NSColor.systemTeal
            } else if line.hasPrefix("# ") {
                line = "● " + String(line.dropFirst(2))
                attributes[.font] = NSFont.systemFont(ofSize: 21, weight: .heavy)
                attributes[.foregroundColor] = NSColor.systemBlue
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "  • " + String(line.dropFirst(2))
                attributes[.font] = NSFont.systemFont(ofSize: 14)
                attributes[.foregroundColor] = NSColor.labelColor
                attributes[.paragraphStyle] = bulletParagraph
            } else if line.hasPrefix("! ") {
                line = "⚠ " + String(line.dropFirst(2))
                attributes[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold)
                attributes[.foregroundColor] = NSColor.systemOrange
            } else if line.hasPrefix("✓ ") {
                line = "✓ " + String(line.dropFirst(2))
                attributes[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold)
                attributes[.foregroundColor] = NSColor.systemGreen
            } else if line.hasPrefix("→ ") {
                line = "→ " + String(line.dropFirst(2))
                attributes[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold)
                attributes[.foregroundColor] = NSColor.systemBlue
            }
            output.append(NSAttributedString(string: line + "\n", attributes: attributes))
        }
        return output
    }

    func loadResource(_ name: String, fallback: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        return fallback
    }

    func fallbackHelp() -> String { "# BlackHole Routing\n\n## Signal Flow\n1. Discord Output -> BlackHole 2ch\n2. xPilot Headset/Speaker -> BlackHole 16ch\n3. AudioDaBitch Output -> headphones or audio interface\n\n! Do not use a Multi-Output device with headphones, otherwise audio bypasses the limiter.\n\n## Audio MIDI Setup\nSet all involved devices to 48,000 Hz." }
    func fallbackChangelog() -> String { "# AudioDaBitch Changelog\n\n## 0.5.15\n- VU needles use a shorter inset path\n- VU ticks and labels use a safer internal drawing area\n- Live dB readouts stay inside the meter face\n- Audio engine behavior unchanged" }

    @objc func loadDevices() { refreshAll() }
    @objc func startAudio() { EngineManager.shared.post("/start", body: [:]) { _ in self.pollState() } }
    @objc func stopAudio() { EngineManager.shared.post("/stop", body: [:]) { _ in } }
    @objc func repairEngine() { EngineManager.shared.stop(); EngineManager.shared.start(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refreshAll() } }
    @objc func stabilizeAudio() { EngineManager.shared.post("/config", body: ["safeMode": true, "sampleRate": 48000, "blockSize": 1024, "latency": "high", "bufferMaxMs": 120.0, "bufferTargetMs": 45.0]) { _ in EngineManager.shared.post("/stop", body: [:]) { _ in EngineManager.shared.post("/start", body: [:]) { _ in self.pollState() } } } }
    @objc func checkUpdatesClicked() { checkForUpdates(silent: false) }
    @objc func installUpdateClicked() { installUpdate() }
    @objc func openReleases() { NSWorkspace.shared.open(ADBReleasePageURL) }
    @objc func openLogs() { ensureDir(logDir()); NSWorkspace.shared.open(logDir()) }
    @objc func exportLogs() { ensureDir(logDir()); let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/AudioDaBitch_Logs_\(Int(Date().timeIntervalSince1970)).zip"); _ = EngineManager.shared.shell("/usr/bin/zip", ["-r", dest.path, logDir().path, appSupportDir().path]); NSWorkspace.shared.activateFileViewerSelecting([dest]) }
    @objc func killStale() { EngineManager.shared.cleanupStale(); status.stringValue = "Stale processes stopped" }
    @objc func levelerChanged() {
        discordLeveler.updateLabels()
        xpilotLeveler.updateLabels()
        duckingPanel.updateLabels()
        EngineManager.shared.post("/config", body: levelerConfigBody()) { _ in }
    }

    func levelerConfigBody() -> [String: Any] {
        [
            "discordLevelerEnabled": discordLeveler.enabled.state == .on,
            "discordLevelerTargetDb": discordLeveler.target.doubleValue,
            "discordLevelerMaxBoostDb": discordLeveler.maxBoost.doubleValue,
            "discordLevelerMaxCutDb": discordLeveler.maxCut.doubleValue,
            "discordLevelerSpeed": discordLeveler.speed.doubleValue,
            "xpilotLevelerEnabled": xpilotLeveler.enabled.state == .on,
            "xpilotLevelerTargetDb": xpilotLeveler.target.doubleValue,
            "xpilotLevelerMaxBoostDb": xpilotLeveler.maxBoost.doubleValue,
            "xpilotLevelerMaxCutDb": xpilotLeveler.maxCut.doubleValue,
            "xpilotLevelerSpeed": xpilotLeveler.speed.doubleValue,
            "duckingEnabled": duckingPanel.enabled.state == .on,
            "duckingMode": "xpilot_ducks_discord",
            "thresholdDb": duckingPanel.threshold.doubleValue,
            "duckDepthDb": duckingPanel.depth.doubleValue,
            "duckAttackMs": duckingPanel.attack.doubleValue,
            "duckReleaseMs": duckingPanel.release.doubleValue,
            "bufferMaxMs": 120.0,
            "bufferTargetMs": 45.0
        ]
    }

    func configInt(_ key: String) -> Int? {
        if let value = savedConfig[key] as? Int { return value }
        if let value = savedConfig[key] as? Double { return Int(value) }
        if let value = savedConfig[key] as? String { return Int(value) }
        return nil
    }

    func configDouble(_ key: String) -> Double? {
        if let value = savedConfig[key] as? Double { return value }
        if let value = savedConfig[key] as? Int { return Double(value) }
        if let value = savedConfig[key] as? String { return Double(value) }
        return nil
    }

    func configString(_ key: String) -> String? {
        guard let value = savedConfig[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    func normalizedDeviceName(_ name: String) -> String {
        name.lowercased().split(separator: " ").joined(separator: " ")
    }

    func loadConfigIntoUI() {
        EngineManager.shared.get("/config") { data in
            DispatchQueue.main.async {
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cfg = obj["config"] as? [String: Any] else { return }
                self.savedConfig = cfg
                self.applyAudioConfig()
                self.applyLevelerConfig(cfg)
                self.applySavedDeviceSelections()
            }
        }
    }

    func applyAudioConfig() {
        if let value = configDouble("discordGainDb") { discord.gain.doubleValue = value }
        if let value = configDouble("xpilotGainDb") { xpilot.gain.doubleValue = value }
        if let value = configDouble("masterGainDb") { output.gain.doubleValue = value }
        if let value = configDouble("discordPan") { discord.pan.doubleValue = value }
        if let value = configDouble("xpilotPan") { xpilot.pan.doubleValue = value }
    }

    func applyLevelerConfig(_ cfg: [String: Any]) {
        applyLevelerPanel(discordLeveler, prefix: "discord", cfg: cfg)
        applyLevelerPanel(xpilotLeveler, prefix: "xpilot", cfg: cfg)
        if let enabled = cfg["duckingEnabled"] as? Bool { duckingPanel.enabled.state = enabled ? .on : .off }
        if let threshold = cfg["thresholdDb"] as? Double { duckingPanel.threshold.doubleValue = threshold }
        if let depth = cfg["duckDepthDb"] as? Double { duckingPanel.depth.doubleValue = depth }
        if let attack = cfg["duckAttackMs"] as? Double { duckingPanel.attack.doubleValue = attack }
        if let release = cfg["duckReleaseMs"] as? Double { duckingPanel.release.doubleValue = release }
        duckingPanel.updateLabels()
    }

    func applyLevelerPanel(_ panel: LevelerPanel, prefix: String, cfg: [String: Any]) {
        if let enabled = cfg["\(prefix)LevelerEnabled"] as? Bool { panel.enabled.state = enabled ? .on : .off }
        if let target = cfg["\(prefix)LevelerTargetDb"] as? Double { panel.target.doubleValue = target }
        if let boost = cfg["\(prefix)LevelerMaxBoostDb"] as? Double { panel.maxBoost.doubleValue = boost }
        if let cut = cfg["\(prefix)LevelerMaxCutDb"] as? Double { panel.maxCut.doubleValue = cut }
        if let speed = cfg["\(prefix)LevelerSpeed"] as? Double { panel.speed.doubleValue = speed }
        panel.updateLabels()
    }

    func setUpdateBadge(_ enabled: Bool) {
        updateTabItem?.label = enabled ? "🔵 Updates" : "Updates"
        updateStatus.textColor = enabled ? .systemBlue : .secondaryLabelColor
        updateButton.isEnabled = enabled
    }

    func checkForUpdates(silent: Bool, allowRetry: Bool = false, attempt: Int = 0) {
        if !silent {
            updateStatus.stringValue = attempt == 0 ? "Checking GitHub releases automatically..." : "Retrying update check..."
            updateStatus.textColor = .secondaryLabelColor
        }
        var request = URLRequest(url: ADBLatestReleaseURL)
        request.setValue("AudioDaBitch/\(ADBVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    if allowRetry && attempt < 4 {
                        if !silent {
                            self.updateStatus.stringValue = "Update check failed. Retrying automatically..."
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(2 + attempt * 2)) {
                            self.checkForUpdates(silent: silent, allowRetry: allowRetry, attempt: attempt + 1)
                        }
                    } else {
                        if !silent {
                            self.updateStatus.stringValue = "Update check failed: \(error.localizedDescription)"
                        }
                        self.setUpdateBadge(false)
                    }
                    return
                }
                guard let data, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    if allowRetry && attempt < 4 {
                        if !silent { self.updateStatus.stringValue = "Could not read the release yet. Retrying automatically..." }
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(2 + attempt * 2)) {
                            self.checkForUpdates(silent: silent, allowRetry: allowRetry, attempt: attempt + 1)
                        }
                    } else {
                        if !silent { self.updateStatus.stringValue = "Could not read the GitHub release." }
                        self.setUpdateBadge(false)
                    }
                    return
                }
                self.latestRelease = release
                let version = release.tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
                guard isVersion(version, newerThan: ADBVersion) else {
                    self.latestAssetURL = nil
                    self.updateStatus.stringValue = "Installed: \(ADBVersion). No newer release found."
                    self.setUpdateBadge(false)
                    return
                }
                guard let asset = release.assets.first(where: { $0.name == ADBUpdateAssetName }), let url = URL(string: asset.browserDownloadURL) else {
                    self.latestAssetURL = nil
                    self.updateStatus.stringValue = "Release \(release.tagName) was found, but \(ADBUpdateAssetName) is missing."
                    self.setUpdateBadge(false)
                    return
                }
                self.latestAssetURL = url
                self.updateStatus.stringValue = "Update available: \(release.tagName)."
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
        updateStatus.stringValue = "Downloading update..."
        let updateDir = appSupportDir().appendingPathComponent("Updates", isDirectory: true)
        ensureDir(updateDir)
        let version = latestRelease?.tagName ?? "latest"
        let destination = updateDir.appendingPathComponent("AudioDaBitch-\(version).pkg")
        URLSession.shared.downloadTask(with: assetURL) { tempURL, _, error in
            if let error {
                DispatchQueue.main.async {
                    self.updateStatus.stringValue = "Download failed: \(error.localizedDescription)"
                    self.updateButton.isEnabled = true
                }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async {
                    self.updateStatus.stringValue = "Download failed: no file was received."
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
                    self.updateStatus.stringValue = "Could not save the download: \(error.localizedDescription)"
                    self.updateButton.isEnabled = true
                }
            }
        }.resume()
    }

    func startInstallerAndQuit(pkgURL: URL) {
        updateStatus.stringValue = "Stopping engine and opening installer..."
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
            updateStatus.stringValue = "Could not open the installer: \(error.localizedDescription)"
            updateButton.isEnabled = true
        }
    }

    func refreshAll() { pollHealth(); fetchDevices(retry: true); pollState() }

    func pollHealth() {
        EngineManager.shared.get("/health") { data in
            DispatchQueue.main.async {
                guard let data, let health = try? JSONDecoder().decode(HealthResponse.self, from: data) else { self.status.stringValue = "Engine unavailable"; return }
                if health.sounddevice == false { self.status.stringValue = "Audio components missing: \(health.error ?? "")" } else { self.status.stringValue = "Engine ready \(health.version ?? "")" }
            }
        }
    }

    func fetchDevices(retry: Bool = false, attempt: Int = 0) {
        EngineManager.shared.get("/devices") { data in
            DispatchQueue.main.async {
                guard let data, let response = try? JSONDecoder().decode(DevicesResponse.self, from: data) else {
                    if retry && attempt < 8 {
                        self.deviceError.stringValue = "Waiting for audio devices..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.fetchDevices(retry: retry, attempt: attempt + 1) }
                    } else {
                        self.deviceError.stringValue = "Could not read /devices"
                    }
                    return
                }
                if retry && attempt < 8 && (response.inputs.isEmpty || response.outputs.isEmpty) {
                    self.deviceError.stringValue = "Waiting for audio devices..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.fetchDevices(retry: retry, attempt: attempt + 1) }
                    return
                }
                self.inputDevices = response.inputs
                self.outputDevices = response.outputs
                self.applySavedDeviceSelections()
                if let error = response.error, !error.isEmpty { self.deviceError.stringValue = "Device error: \(error)" } else { self.deviceError.stringValue = response.inputs.isEmpty || response.outputs.isEmpty ? "No audio devices found" : "" }
            }
        }
    }

    @discardableResult
    func populate(_ popup: NSPopUpButton, _ devices: [Device], idKey: String, nameKey: String) -> Device? {
        let currentId = popup.selectedItem?.representedObject as? Int
        let savedId = configInt(idKey)
        let savedName = configString(nameKey)
        popup.removeAllItems()
        popup.addItem(withTitle: "Select a device")
        popup.lastItem?.representedObject = -1
        for device in devices {
            popup.addItem(withTitle: "\(device.name)  (#\(device.id))")
            popup.lastItem?.representedObject = device.id
        }
        if let savedId, let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == savedId }) {
            popup.select(item)
            return devices.first(where: { $0.id == savedId })
        }
        if let savedName {
            let normalized = normalizedDeviceName(savedName)
            if let device = devices.first(where: { normalizedDeviceName($0.name) == normalized }),
               let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == device.id }) {
                popup.select(item)
                return device
            }
        }
        if let currentId, currentId >= 0, let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == currentId }) {
            popup.select(item)
            return devices.first(where: { $0.id == currentId })
        }
        popup.selectItem(at: 0)
        return nil
    }

    func applySavedDeviceSelections() {
        let discordDevice = populate(discord.popup, inputDevices, idKey: "discordInput", nameKey: "discordInputName")
        let xpilotDevice = populate(xpilot.popup, inputDevices, idKey: "xpilotInput", nameKey: "xpilotInputName")
        let outputDevice = populate(output.popup, outputDevices, idKey: "outputDevice", nameKey: "outputDeviceName")
        var body: [String: Any] = [:]
        if let device = discordDevice {
            body["discordInput"] = device.id
            body["discordInputName"] = device.name
        }
        if let device = xpilotDevice {
            body["xpilotInput"] = device.id
            body["xpilotInputName"] = device.name
        }
        if let device = outputDevice {
            body["outputDevice"] = device.id
            body["outputDeviceName"] = device.name
        }
        guard !body.isEmpty else { return }
        EngineManager.shared.post("/config", body: body) { _ in }
        savedConfig.merge(body) { _, new in new }
    }

    func deviceName(for id: Int, in devices: [Device]) -> String? {
        devices.first(where: { $0.id == id })?.name
    }

    func pollState() {
        EngineManager.shared.get("/state") { data in
            DispatchQueue.main.async {
                guard let data, let state = try? JSONDecoder().decode(StateResponse.self, from: data) else { return }
                self.discord.meter.valueDb = state.meters?.discord ?? -120
                self.xpilot.meter.valueDb = state.meters?.xpilot ?? -120
                self.output.meter.valueDb = state.meters?.output ?? -120
                self.levelerInfo.stringValue = "Discord: \(Int(state.meters?.discord ?? -120)) dB / \(Int(state.discordLevelerGainDb ?? 0)) dB level / \(Int(state.discordDuckGainDb ?? 0)) dB duck    xPilot: \(Int(state.meters?.xpilot ?? -120)) dB / \(Int(state.xpilotLevelerGainDb ?? state.levelerGainDb ?? 0)) dB level"
                if let diag = state.diagnostics {
                    let dQueue = Int((diag.discord?.queuedMs ?? 0).rounded())
                    let xQueue = Int((diag.xpilot?.queuedMs ?? 0).rounded())
                    let dropped = Int(((diag.discord?.droppedMs ?? 0) + (diag.xpilot?.droppedMs ?? 0)).rounded())
                    self.diagnosticsLabel.stringValue = "Audio: \(diag.sampleRate ?? 0) Hz · Block \(diag.blockSize ?? 0) · Latency \(diag.latency ?? "-") · Queue D/X \(dQueue)/\(xQueue) ms · Dropped \(dropped) ms · Callback errors \(diag.callbackErrors ?? 0)"
                }
            }
        }
    }

    @objc func configChanged() {
        var body: [String: Any] = [:]
        let did = discord.popup.selectedItem?.representedObject as? Int ?? -1
        let xid = xpilot.popup.selectedItem?.representedObject as? Int ?? -1
        let oid = output.popup.selectedItem?.representedObject as? Int ?? -1
        if did >= 0 {
            body["discordInput"] = did
            if let name = deviceName(for: did, in: inputDevices) { body["discordInputName"] = name }
        }
        if xid >= 0 {
            body["xpilotInput"] = xid
            if let name = deviceName(for: xid, in: inputDevices) { body["xpilotInputName"] = name }
        }
        if oid >= 0 {
            body["outputDevice"] = oid
            if let name = deviceName(for: oid, in: outputDevices) { body["outputDeviceName"] = name }
        }
        body["discordGainDb"] = discord.gain.doubleValue
        body["xpilotGainDb"] = xpilot.gain.doubleValue
        body["masterGainDb"] = output.gain.doubleValue
        body["discordPan"] = discord.pan.doubleValue
        body["xpilotPan"] = xpilot.pan.doubleValue
        for (key, value) in levelerConfigBody() {
            body[key] = value
        }
        body["safeMode"] = true
        body["sampleRate"] = 48000
        body["blockSize"] = 1024
        body["latency"] = "high"
        EngineManager.shared.post("/config", body: body) { _ in }
        savedConfig.merge(body) { _, new in new }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("AudioDaBitch \(ADBVersion) started")
        let vc = AppController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.center()
        window.title = "AudioDaBitch"
        window.contentViewController = vc
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit AudioDaBitch?"
        alert.informativeText = "Quitting stops the audio engine. Minimize keeps AudioDaBitch running."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Minimize")
        alert.addButton(withTitle: "Cancel")
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

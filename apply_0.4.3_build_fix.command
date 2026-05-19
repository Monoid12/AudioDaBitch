#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Applying AudioDaBitch 0.4.3 Swift concurrency build fix..."
python3 - <<'PY'
from pathlib import Path
p = Path('Sources/AudioDaBitchApp/main.swift')
if not p.exists():
    raise SystemExit('Sources/AudioDaBitchApp/main.swift nicht gefunden. Bitte Script im Repo-Root starten.')
s = p.read_text()
s = s.replace('let ADBAppVersion = "0.4.3"', 'let ADBAppVersion = "0.4.3"')
s = s.replace('@MainActor\nfinal class AppState: ObservableObject {', '@MainActor\nfinal class AppState: NSObject, ObservableObject {')
s = s.replace('''    func start() {
        AppLog.shared.write("AudioDaBitch \\(ADBAppVersion) started")
        loadBundledText()
        startEngineIfNeeded()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchState()
                self?.fetchDevices()
            }
        }
        checkForUpdates()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
    }
''', '''    func start() {
        AppLog.shared.write("AudioDaBitch \\(ADBAppVersion) started")
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
''')
s = s.replace('''    func downloadAndOpenUpdate() {
        guard let url = URL(string: updateAssetURL) else { return }
        updateStatus = "Lade Update von GitHub..."
        URLSession.shared.downloadTask(with: url) { temp, _, error in
            if let error = error { DispatchQueue.main.async { self.updateStatus = "Download fehlgeschlagen: \\(error.localizedDescription)" }; return }
            guard let temp = temp else { return }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dest = downloads.appendingPathComponent("AudioDaBitch_\\(self.latestVersion).pkg")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: temp, to: dest)
                DispatchQueue.main.async { self.updateStatus = "Update geladen. Installer wird geöffnet."; NSWorkspace.shared.open(dest) }
            } catch { DispatchQueue.main.async { self.updateStatus = "Update konnte nicht gespeichert werden: \\(error.localizedDescription)" } }
        }.resume()
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
''', '''    func downloadAndOpenUpdate() {
        guard let url = URL(string: updateAssetURL) else { return }
        let versionForFilename = latestVersion.isEmpty ? ADBAppVersion : latestVersion
        updateStatus = "Lade Update von GitHub..."
        URLSession.shared.downloadTask(with: url) { temp, _, error in
            if let error = error { DispatchQueue.main.async { self.updateStatus = "Download fehlgeschlagen: \\(error.localizedDescription)" }; return }
            guard let temp = temp else { return }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dest = downloads.appendingPathComponent("AudioDaBitch_\\(versionForFilename).pkg")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: temp, to: dest)
                DispatchQueue.main.async { self.updateStatus = "Update geladen. Installer wird geöffnet."; NSWorkspace.shared.open(dest) }
            } catch { DispatchQueue.main.async { self.updateStatus = "Update konnte nicht gespeichert werden: \\(error.localizedDescription)" } }
        }.resume()
    }

    nonisolated static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
''')
p.write_text(s)
# version strings
for p in Path('.').rglob('*'):
    if not p.is_file():
        continue
    try:
        s = p.read_text()
    except UnicodeDecodeError:
        continue
    if '0.4.3' in s:
        p.write_text(s.replace('0.4.3.0','0.4.3.0').replace('0.4.3','0.4.3'))
print('0.4.3 Build-Fix angewendet.')
PY

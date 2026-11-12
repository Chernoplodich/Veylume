import Foundation
import CryptoKit
import VeylumeCore

enum ModelIntegrity {
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ artifact: ModelArtifact, at root: URL) throws {
        let url = root.appendingPathComponent(artifact.path)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, Int64(values.fileSize ?? -1) == artifact.bytes,
              url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              try hash(url) == artifact.sha256 else { throw Problem.modelIntegrity }
    }
    static func verify(_ manifest: ModelManifest, at root: URL) throws {
        try manifest.validate(); for artifact in manifest.artifacts { try Task.checkCancellation(); try verify(artifact, at: root) }
    }
}

/// A per-file download delegate enforces HTTPS and redirects before a connection
/// is followed. Resume data is scoped to the exact immutable artifact URL.
private final class ArtifactTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let artifact: ModelArtifact, hosts: [String], target: URL, resumeURL: URL
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?, task: URLSessionDownloadTask?
    private let lock = NSLock()
    private var transferError: Error?, cancelled = false
    private var lastProgress = Date.distantPast
    init(artifact: ModelArtifact, hosts: [String], target: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.artifact = artifact; self.hosts = hosts; self.target = target; resumeURL = target.appendingPathExtension("resume"); self.progress = progress
    }
    func run() async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock(); defer { lock.unlock() }
                guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 7200; config.urlCache = nil; config.httpCookieStorage = nil
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue); self.session = session
                if let resume = try? Data(contentsOf: resumeURL) { task = session.downloadTask(withResumeData: resume) }
                else { var request = URLRequest(url: artifact.url); request.setValue("identity", forHTTPHeaderField: "Accept-Encoding"); task = session.downloadTask(with: request) }
                task?.resume()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel(byProducingResumeData: { data in if let data { try? data.write(to: self.resumeURL, options: .atomic) } })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil, hosts.contains(url.host ?? "") else {
            transferError = ValidationError.unsafeArtifact; completionHandler(nil); task.cancel(); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > artifact.bytes { transferError = ValidationError.integrity; downloadTask.cancel(); return }
        if Date().timeIntervalSince(lastProgress) >= 0.1 || totalBytesWritten == artifact.bytes {
            lastProgress = Date(); progress(min(artifact.bytes, totalBytesWritten))
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, [200, 206].contains(response.statusCode) else { transferError = Problem.download; return }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: location, to: target)
        } catch { transferError = Problem.storage }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, let resume = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? resume.write(to: resumeURL, options: .atomic) }
        lock.lock(); let continuation = self.continuation; self.continuation = nil; let cancelled = self.cancelled; lock.unlock()
        if cancelled { continuation?.resume(throwing: CancellationError()) }
        else if let error = transferError ?? error { continuation?.resume(throwing: error) }
        else { try? FileManager.default.removeItem(at: resumeURL); continuation?.resume() }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}

actor ModelInstaller {
    let root: URL
    init(root: URL) { self.root = root }
    nonisolated func directory(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func installed(_ manifest: ModelManifest) -> Bool {
        let directory = directory(for: manifest.id)
        guard let revision = try? String(contentsOf: directory.appendingPathComponent("installed.revision"), encoding: .utf8), revision == manifest.revision else { return false }
        return (try? ModelIntegrity.verify(manifest, at: directory)) != nil
    }
    func install(_ manifest: ModelManifest, progress: @escaping @Sendable (Int64, Int64, Bool) -> Void, prepare: @escaping @Sendable (URL) async throws -> Void) async throws -> URL {
        try manifest.validate()
        let staging = root.appendingPathComponent(".staging-\(manifest.id)-\(manifest.revision)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var excluded = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        var received: Int64 = 0
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            if (try? ModelIntegrity.verify(artifact, at: staging)) != nil { received += artifact.bytes; progress(received, manifest.downloadBytes, false); continue }
            let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard capacity >= max(512 * 1024 * 1024, manifest.downloadBytes - received + 256 * 1024 * 1024) else { throw Problem.lowDisk }
            let base = received
            try FileManager.default.createDirectory(at: staging.appendingPathComponent(artifact.path).deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let transfer = ArtifactTransfer(artifact: artifact, hosts: manifest.allowedHosts, target: staging.appendingPathComponent(artifact.path)) { progress(base + $0, manifest.downloadBytes, false) }
            try await transfer.run(); try Task.checkCancellation(); try ModelIntegrity.verify(artifact, at: staging)
            received += artifact.bytes; progress(received, manifest.downloadBytes, false)
        }
        progress(received, manifest.downloadBytes, true)
        try ModelIntegrity.verify(manifest, at: staging)
        try await prepare(staging); try Task.checkCancellation()
        try manifest.revision.write(to: staging.appendingPathComponent("installed.revision"), atomically: true, encoding: .utf8)
        let final = directory(for: manifest.id)
        if FileManager.default.fileExists(atPath: final.path) {
            _ = try FileManager.default.replaceItemAt(final, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: final) }
        return staging
    }
    func remove(_ id: String) throws {
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func eraseAll() throws {
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) }
    }
}

@MainActor final class ModelCoordinator: ObservableObject {
    enum Status: Equatable { case available, downloading(Int64, Int64), verifying, ready, paused, failed(Problem) }
    let catalogue: [ModelManifest]
    let installer: ModelInstaller
    let engines: EngineHost
    let preferences: PreferencesStore
    @Published var states: [String: Status] = [:]
    private var jobs: [String: Task<Void, Never>] = [:]
    var sessionIsBusy: () -> Bool = { false }
    var onActiveReady: (() -> Void)?
    var isPreparing: Bool { states.values.contains(.verifying) }
    init(preferences: PreferencesStore, engines: EngineHost, root: URL) {
        self.preferences = preferences; self.engines = engines; installer = ModelInstaller(root: root)
        catalogue = ["parakeet-v3", "cohere-transcribe", "whisper-turbo", "whisper-small", "whisper-large"].compactMap { id in
            guard let url = Bundle.module.url(forResource: id, withExtension: "json"), let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(ModelManifest.self, from: data), (try? manifest.validate()) != nil else { return nil }; return manifest
        }
    }
    var active: ModelManifest? { catalogue.first { $0.id == preferences.value.selectedModel } }
    var activeReady: Bool { active.map { states[$0.id] == .ready } ?? false }
    func refresh() async {
        for manifest in catalogue where jobs[manifest.id] == nil { states[manifest.id] = await installer.installed(manifest) ? .ready : .available }
        if activeReady { onActiveReady?() }
    }
    func bootstrap() async {
        await refresh()
        switch preferences.value.bootstrap {
        case .pending, .running:
            if states["parakeet-v3"] == .ready { preferences.value.completeBootstrap(selectionGeneration: preferences.value.modelSelectionGeneration) }
            else { download("parakeet-v3", bootstrap: true) }
        default: break
        }
    }
    func download(_ id: String, bootstrap: Bool = false) {
        guard jobs.isEmpty, let manifest = catalogue.first(where: { $0.id == id }) else { return }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= manifest.minimumOS else { states[id] = .failed(.modelNotReady); return }
        let selection = preferences.value.modelSelectionGeneration
        if bootstrap { preferences.value.bootstrap = .running }
        states[id] = .downloading(0, manifest.downloadBytes)
        jobs[id] = Task {
            do {
                let previous = try await installer.install(manifest, progress: { bytes, total, preparing in
                    Task { @MainActor in self.states[id] = preparing ? .verifying : .downloading(bytes, total) }
                }, prepare: { directory in try await self.prepare(manifest, directory: directory) })
                await engines.adoptInstalledDirectory(modelID: id, previous: previous, installed: installer.directory(for: id))
                try Task.checkCancellation()
                states[id] = .ready
                if bootstrap { preferences.value.completeBootstrap(selectionGeneration: selection) }
                if activeReady { onActiveReady?() }
            } catch is CancellationError { states[id] = .paused }
            catch { states[id] = .failed((error as? Problem) ?? .download) }
            jobs[id] = nil
        }
    }
    private func prepare(_ manifest: ModelManifest, directory: URL) async throws {
        while sessionIsBusy() { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(100)) }
        states[manifest.id] = .verifying
        try await engines.selfCheck(manifest, directory: directory)
    }
    func pause(_ id: String, cancel: Bool = false) {
        if id == "parakeet-v3" && preferences.value.bootstrap != .completed { preferences.value.bootstrap = cancel ? .cancelled : .paused }
        jobs[id]?.cancel()
    }
    func cancelAll() async {
        let tasks = Array(jobs.values)
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }
    func select(_ manifest: ModelManifest) {
        guard states[manifest.id] == .ready else { return }
        preferences.value.selectModel(manifest.id)
        if !manifest.supportsAutoLanguage && !manifest.languages.contains(preferences.value.speechLanguage) { preferences.value.speechLanguage = "choose" }
        else if manifest.supportsAutoLanguage && !manifest.languages.contains(preferences.value.speechLanguage) { preferences.value.speechLanguage = "auto" }
    }
    func remove(_ manifest: ModelManifest) async throws {
        await engines.unload(); try await installer.remove(manifest.id)
        if active?.id == manifest.id { preferences.value.selectModel(nil) }
        if manifest.id == "parakeet-v3" { preferences.value.bootstrap = .removed }
        states[manifest.id] = .available
    }
}

import AppKit
import Combine
import Foundation

@MainActor
final class CadenceStore: ObservableObject {
    @Published private(set) var events: [CadenceEvent] = []
    @Published private(set) var tasks: [CadenceTask] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var connectingAccountID: String?

    private let fileManager = FileManager.default
    private var configuration = CadenceConfiguration.load()
    private var reloadTimer: Timer?
    private var syncTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var openedMeetingIDs: Set<String> = []
    private var meetingCandidates: [MeetingCandidate] = []
    private var cacheStamps: [String: CacheStamp] = [:]
    private var unreadableFiles: Set<String> = []
    private var syncError: String?

    /// Opening the popover only triggers a sync when the cache is older than this.
    private static let popoverStaleness: TimeInterval = 60

    init() {
        lastUpdated = cacheModificationDate()
        reload()
        sync()

        // Cheap local tick: refreshes the menu bar title and auto-opens meetings.
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        scheduleSyncTimer()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: configuration.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        timer.tolerance = 30
        syncTimer = timer
    }

    func syncIfStale() {
        guard let lastUpdated else { return sync() }
        if Date().timeIntervalSince(lastUpdated) > Self.popoverStaleness { sync() }
    }

    var nextEvent: CadenceEvent? {
        let now = Date()
        return
            events
            .filter { ($0.parsedStartDate ?? .distantPast) >= now.addingTimeInterval(-3600) }
            .sorted { ($0.parsedStartDate ?? .distantFuture) < ($1.parsedStartDate ?? .distantFuture) }
            .first
    }

    var menuBarTitle: String {
        guard let event = nextEvent, let date = event.parsedStartDate else { return "Cadence" }
        let title = event.title.replacingOccurrences(of: "\n", with: " ")
        return "\(date.formatted(date: .omitted, time: .shortened)) · \(title.prefix(26))"
    }

    var configuredAccounts: [CadenceAccount] {
        configuration.configuredAccounts
    }

    func isConnected(_ account: CadenceAccount) -> Bool {
        fileManager.fileExists(atPath: account.tokenURL.path)
    }

    @discardableResult
    func saveAccounts(_ accounts: [CadenceAccount], synchronize: Bool = true) -> Bool {
        guard !accounts.isEmpty else {
            errorMessage = "Adicione ao menos uma conta."
            return false
        }

        let previousAccounts = configuration.configuredAccounts
        var updatedConfiguration = configuration
        updatedConfiguration.replaceAccounts(accounts)
        do {
            try updatedConfiguration.save()
            configuration = updatedConfiguration

            let retainedIDs = Set(accounts.map(\.id))
            for account in previousAccounts where !retainedIDs.contains(account.id) {
                try? fileManager.removeItem(at: account.tokenURL)
            }

            reload()
            if synchronize { sync() }
            return true
        } catch {
            errorMessage = "Não foi possível salvar as contas: \(error.localizedDescription)"
            return false
        }
    }

    func connect(accountID: String) {
        guard connectingAccountID == nil else { return }
        guard let account = configuredAccounts.first(where: { $0.id == accountID }) else {
            errorMessage = "Conta não encontrada."
            return
        }
        guard account.calendar || account.tasks else {
            errorMessage = "Selecione Calendar ou Tasks antes de conectar a conta."
            return
        }

        let backendCommand = configuration.backendCommandURL
        guard fileManager.isExecutableFile(atPath: backendCommand.path) else {
            errorMessage = "Backend não encontrado."
            return
        }

        connectingAccountID = account.id
        Task { [weak self] in
            let result = await Task.detached {
                Self.runZshWithOutput(arguments: [backendCommand.path, "--authenticate", account.id])
            }.value
            guard let self else { return }
            self.connectingAccountID = nil
            if result.status == 0 {
                self.sync()
            } else {
                self.errorMessage =
                    result.output.isEmpty
                    ? "Não foi possível conectar a conta."
                    : result.output
            }
        }
    }

    /// Cheap enough to run every minute: stats the cache files and only decodes
    /// the ones whose modification date or size changed since the last read.
    func reload() {
        if let loaded = loadIfChanged([CadenceEvent].self, named: "events.json") {
            events = loaded ?? []
            meetingCandidates = Self.meetingCandidates(from: events)
        }
        if let loaded = loadIfChanged([CadenceTask].self, named: "tasks.json") {
            tasks = loaded ?? []
        }

        let message: String?
        if let syncError {
            message = syncError
        } else {
            var failed: [String] = []
            if unreadableFiles.contains("events.json") { failed.append("agenda") }
            if unreadableFiles.contains("tasks.json") { failed.append("tasks") }
            message =
                failed.isEmpty
                ? nil
                : "Dados de \(failed.joined(separator: ", ")) indisponíveis. Clique em atualizar."
        }
        if errorMessage != message { errorMessage = message }

        openMeetingsStartingSoon()
    }

    /// Returns nil when the file is unchanged, `.some(nil)` when it changed but could not be read.
    private func loadIfChanged<T: Decodable>(_ type: T.Type, named name: String) -> T?? {
        let url = cacheURL(name)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let stamp = CacheStamp(
            modified: attributes?[.modificationDate] as? Date,
            size: (attributes?[.size] as? NSNumber)?.int64Value
        )
        if let previous = cacheStamps[name], previous == stamp { return nil }
        cacheStamps[name] = stamp

        do {
            let value = try decode(type, from: url)
            unreadableFiles.remove(name)
            return .some(value)
        } catch {
            unreadableFiles.insert(name)
            return .some(nil)
        }
    }

    func sync() {
        guard !isSyncing else { return }
        let script = configuration.syncScriptURL
        guard fileManager.isExecutableFile(atPath: script.path) else {
            errorMessage = "Backend não encontrado. Configure syncScript em ~/.config/cadence/config.json."
            return
        }
        isSyncing = true
        Task { [weak self] in
            let status = await Task.detached {
                Self.runZsh(arguments: [script.path])
            }.value
            guard let self else { return }
            self.isSyncing = false
            if status == 0 {
                self.syncError = nil
                self.lastUpdated = self.cacheModificationDate() ?? Date()
            } else {
                self.syncError = "Não foi possível sincronizar. Verifique as credenciais do Google."
            }
            self.reload()
        }
    }

    nonisolated static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
            ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    func open(_ event: CadenceEvent) {
        for value in [event.meetLink, event.link] {
            guard let url = Self.webURL(value) else { continue }
            NSWorkspace.shared.open(url)
            return
        }
    }

    func open(_ task: CadenceTask) {
        guard let url = Self.webURL(task.link) else { return }
        NSWorkspace.shared.open(url)
    }

    func setTaskCompleted(_ task: CadenceTask, completed: Bool) {
        let backendCommand = configuration.backendCommandURL
        guard fileManager.isExecutableFile(atPath: backendCommand.path) else {
            errorMessage = "Backend não encontrado. Configure backendCommand em ~/.config/cadence/config.json."
            return
        }
        let newStatus = completed ? "completed" : "needsAction"
        let oldTasks = tasks

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = newStatus
            tasks[index].completed = completed ? ISO8601DateFormatter().string(from: Date()) : nil
        }

        Task { [weak self] in
            let status = await Task.detached {
                Self.runZsh(arguments: [
                    backendCommand.path,
                    "--set-status",
                    task.accountId ?? "default",
                    task.listId,
                    task.taskId,
                    newStatus,
                ])
            }.value
            guard let self else { return }
            if status == 0 {
                self.sync()
            } else {
                self.tasks = oldTasks
                self.errorMessage = "Não foi possível atualizar a task."
            }
        }
    }

    /// Newest write time of the synced cache files, i.e. the last successful Google sync.
    private func cacheModificationDate() -> Date? {
        ["events.json", "tasks.json"]
            .compactMap { try? fileManager.attributesOfItem(atPath: cacheURL($0).path)[.modificationDate] as? Date }
            .max()
    }

    private func cacheURL(_ name: String) -> URL {
        configuration.cacheDirectoryURL.appendingPathComponent(name)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func openMeetingsStartingSoon() {
        let now = Date()
        for meeting in meetingCandidates {
            let secondsUntilStart = meeting.start.timeIntervalSince(now)
            guard (0...60).contains(secondsUntilStart) else { continue }
            guard openedMeetingIDs.insert(meeting.id).inserted else { continue }
            NSWorkspace.shared.open(meeting.url)
        }
    }

    /// Accepted future events with an http(s) Meet link, precomputed once per cache change.
    private static func meetingCandidates(from events: [CadenceEvent]) -> [MeetingCandidate] {
        let cutoff = Date().addingTimeInterval(-60)
        return events.compactMap { event in
            guard event.rsvp?.lowercased() == "accepted",
                let start = event.parsedStartDate,
                start >= cutoff,
                let url = Self.webURL(event.meetLink),
                url.scheme?.lowercased() == "https",
                url.host?.lowercased() == "meet.google.com"
            else { return nil }
            return MeetingCandidate(id: "\(event.id):\(event.start)", start: start, url: url)
        }
    }

    @discardableResult
    nonisolated private static func runZsh(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    nonisolated private static func runZshWithOutput(arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct CacheStamp: Equatable {
    let modified: Date?
    let size: Int64?
}

private struct MeetingCandidate {
    let id: String
    let start: Date
    let url: URL
}

private struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

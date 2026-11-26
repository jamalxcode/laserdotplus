import AppKit
import Charts
import LaserdotKit
import SwiftUI

struct DriveSheet: Identifiable {
    let id: String
    let drive: Drive
}

/// About This Drive: its facts, how full it was over time (with when it will
/// be full at this rate), what clean-ups freed, and protection against bit
/// rot (a checksum list kept on the drive; Check for Damage reads every
/// listed file again).
struct DriveInfoView: View {
    let drive: Drive
    @ObservedObject var drives: DrivesModel
    @ObservedObject var model: LibraryModel
    @StateObject private var check: ChecksumModel
    @State private var history: [DriveHistoryEntry] = []
    @Environment(\.dismiss) private var dismiss

    init(drive: Drive, drives: DrivesModel, model: LibraryModel) {
        self.drive = drive
        self.drives = drives
        self.model = model
        _check = StateObject(wrappedValue: ChecksumModel(engine: model.engine, mount: drive.mount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "externaldrive.fill").font(.title).foregroundStyle(Palette.place)
                VStack(alignment: .leading) {
                    Text(drive.name).font(.title2.weight(.semibold))
                    Text(facts).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("action.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historySection
                    Divider()
                    protectionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(width: 560, height: 560)
        .onAppear {
            let mount = drive.mount
            DispatchQueue.global(qos: .utility).async {
                let h = DriveHistory.load(mount)
                DispatchQueue.main.async { history = h }
            }
            check.refresh()
        }
    }

    private var facts: String {
        var parts: [String] = []
        let used = drive.totalBytes - min(drive.freeBytes, drive.totalBytes)
        if drive.totalBytes > 0 { parts.append(String(format: L("drive.info.space"), bytesText(used), bytesText(drive.totalBytes), bytesText(drive.freeBytes))) }
        if !drive.fsType.isEmpty { parts.append(drive.fsType.uppercased()) }
        if drive.entries > 0 { parts.append(countText(Int(drive.entries), "file")) }
        if let t = drive.lastScan { parts.append(String(format: L("drive.info.checked"), dateText(t))) }
        if drive.readOnly { parts.append(L("drive.info.readOnly")) }
        if drive.encrypted { parts.append(L("drive.info.encrypted")) }
        return parts.joined(separator: " · ")
    }

    // MARK: history

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("history.title")).font(.headline)
            let points = history.filter { $0.used != nil }
            if points.count < 2 {
                Text(L("history.empty")).font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(points, id: \.t) { e in
                    LineMark(x: .value(L("history.date"), Date(timeIntervalSince1970: TimeInterval(e.t))),
                             y: .value(L("history.used"), Double(e.used ?? 0) / 1e9))
                        .foregroundStyle(Palette.place)
                    if let total = e.total {
                        RuleMark(y: .value(L("history.capacity"), Double(total) / 1e9))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYAxisLabel(L("history.gb"))
                .frame(height: 150)
                if let months = DriveHistory.monthsUntilFull(history) {
                    Text(months > 120 ? L("history.notSoon") : String(format: L("history.fullIn"), Int(months.rounded())))
                        .font(.callout.weight(.semibold))
                }
            }
            let freed = history.compactMap(\.freed)
            if !freed.isEmpty {
                Text(String(format: L("history.freed"), bytesText(freed.reduce(0, +)), freed.count))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: protection

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("protect.title")).font(.headline)
            Text(L("protect.help")).font(.callout).foregroundStyle(.secondary)
            if !drive.onDrive || drive.encrypted {
                Text(L("protect.unavailable")).font(.callout)
            } else {
                if let s = check.status {
                    Text(s.exists
                         ? String(format: L("protect.status"), countText(Int(s.files), "file"), dateText(s.savedAt))
                           + (s.unlisted > 0 ? " " + String(format: L("protect.unlisted"), countText(Int(s.unlisted), "file")) : "")
                         : L("protect.none"))
                        .font(.callout)
                }
                if check.running {
                    HStack(spacing: 10) {
                        if let p = check.progress, p.total > 0 {
                            ProgressView(value: Double(p.done), total: Double(p.total)).frame(maxWidth: 220)
                            Text("\(p.done) / \(p.total)").monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Spacer()
                        Button(L("dupes.stop")) { check.stop() }
                    }
                    if let cur = check.progress?.current, !cur.isEmpty {
                        Text((cur as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    HStack {
                        Button(check.status?.exists == true ? L("protect.update") : L("protect.save")) { check.save() }
                            .help(L("protect.save.help"))
                        Button(L("protect.check")) { check.verify() }
                            .disabled(check.status?.exists != true)
                            .help(L("protect.check.help"))
                    }
                }
                if let r = check.result { resultView(r) }
                if let p = check.problem { Text(p).font(.callout).foregroundStyle(.orange) }
            }
        }
    }

    @ViewBuilder private func resultView(_ r: ChecksumModel.Outcome) -> some View {
        switch r {
        case let .saved(rep):
            Text(String(format: L("protect.saved"), countText(Int(rep.files), "file"), countText(Int(rep.read), "file"))
                 + (rep.stopped ? " " + L("protect.stopped") : ""))
                .font(.callout)
        case let .checked(rep):
            VStack(alignment: .leading, spacing: 4) {
                if rep.damaged.isEmpty {
                    Label(String(format: L("protect.allGood"), countText(Int(rep.read), "file")), systemImage: "checkmark.seal")
                        .foregroundStyle(Palette.place)
                } else {
                    Label(String(format: L("protect.damaged"), countText(rep.damaged.count, "file")), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.kind("video"))
                        .font(.callout.weight(.semibold))
                    ForEach(rep.damaged.prefix(50), id: \.self) { p in
                        HStack {
                            Text(friendlyPath(p)).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                                .controlSize(.small)
                        }
                    }
                }
                Text(String(format: L("protect.other"), rep.changed, rep.missing.count) + (rep.stopped ? " " + L("protect.stopped") : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The drive's checksum list: its state, a save or a check with progress.
final class ChecksumModel: ObservableObject {
    enum Outcome { case saved(ChecksumReport), checked(ChecksumReport) }
    @Published var status: ChecksumStatus?
    @Published var running = false
    @Published var progress: ChecksumProgress?
    @Published var result: Outcome?
    @Published var problem: String?
    let engine: Engine
    let mount: String
    private var poll: Timer?

    init(engine: Engine, mount: String) {
        self.engine = engine
        self.mount = mount
    }

    func refresh() {
        let (engine, mount) = (self.engine, self.mount)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = try? engine.checksumStatus(mount: mount)
            DispatchQueue.main.async { self?.status = s }
        }
    }

    func save() { run { try $0.saveChecksums(mount: $1) } done: { .saved($0) } }
    func verify() { run { try $0.checkChecksums(mount: $1) } done: { .checked($0) } }

    func stop() {
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { engine.stopChecksums() }
    }

    private func run(_ job: @escaping (Engine, String) throws -> ChecksumReport, done: @escaping (ChecksumReport) -> Outcome) {
        guard !running else { return }
        running = true
        result = nil
        problem = nil
        let (engine, mount) = (self.engine, self.mount)
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let p = engine.checksumProgress()
                DispatchQueue.main.async { if self?.running == true { self?.progress = p } }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = Result { try job(engine, mount) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.poll?.invalidate()
                self.running = false
                self.progress = nil
                switch r {
                case let .success(rep): self.result = done(rep)
                case let .failure(e): self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                }
                self.refresh()
            }
        }
    }
}

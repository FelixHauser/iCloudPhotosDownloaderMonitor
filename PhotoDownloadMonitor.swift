//
//  PhotoDownloadMonitor.swift
//  TestNuvol
//

// ── PURPOSE ───────────────────────────────────────────────────────────────────
// Production-grade alternative to the retry-with-backoff pattern in SecondView.
// One NSMetadataQuery watches the entire iCloud ubiquity-container Documents
// scope for the lifetime of the app. When a file's download status flips to
// .current, its name lands in `readyFilenames` and every SwiftUI view that
// reads that set re-renders automatically — no polling, no timers.
//
// WHY ONE QUERY FOR THE WHOLE APP
// NSMetadataQuery is backed by the system metadata daemon (bird / mds).
// Running one query per view — e.g. in a 50-photo grid — registers 50 separate
// listeners with the daemon. One app-wide instance costs the same as one
// listener regardless of how many photos are on screen.
//
// ── SETUP (TestNuvolApp.swift) ─────────────────────────────────────────────
//   @State private var photoMonitor = PhotoDownloadMonitor()
//
//   WindowGroup {
//       NavigationStack { FirstView() }
//           .environment(photoMonitor)
//           .task { photoMonitor.start() }       // starts the query once
//   }
//
// ── USAGE IN A VIEW ────────────────────────────────────────────────────────
//   @Environment(PhotoDownloadMonitor.self) private var photoMonitor
//
//   .onAppear(of: infos.count, initial: true) {
//       photoMonitor.requestDownload(filename: photoPath)
//   }
//   .onChange(of: photoPath, initial: true) { _, ready in
//       guard ready else { return }
//       Task {
//           // ▸ Thumbnail — for a list cell, card, or small preview.
//           //   Pass the target point size; CGImageSource decodes only those pixels,
//           //   so memory cost is proportional to maxSize, not the original file size.
//           image = await loadThumbnail(filename: photoPath, maxSize: 300, scale: scale)
//
//           // ▸ Full-resolution data — for a share sheet, editor, or full-screen view.
//           //   Returns the raw JPEG bytes; decode into UIImage only when needed.
//           // data = await loadPhotoAsync(filename: photoPath)
//       }
//   }
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

@Observable
final class PhotoDownloadMonitor {

    // MARK: - Public state

    /// Filenames that are fully downloaded and safe to read from disk.
    ///
    /// Backed by `@Observable`, so any SwiftUI view that reads this set is
    /// re-rendered automatically when a new filename is inserted.
    private(set) var readyFilenames: Set<String> = []

    // MARK: - Private state

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    /// Starts the metadata query. Call once at app launch (idempotent).
    ///
    /// Must be called on the main actor because `NSMetadataQuery.start()`
    /// needs a run loop, and the main run loop is always available.
    @MainActor
    func start() {
        guard query == nil else { return }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        // Broad predicate: every file in the container. The handler filters
        // by download status so we catch both newly arrived stubs and files
        // completing a download — without needing to know filenames in advance.
        q.predicate = NSPredicate(value: true)

        let handle = { [weak self, weak q] in
            guard let self, let q else { return }
            // Disable live updates while we iterate to prevent mutation during enumeration.
            q.disableUpdates()
            defer { q.enableUpdates() }

            for i in 0 ..< q.resultCount {
                guard let item = q.result(at: i) as? NSMetadataItem,
                      let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
                else { continue }

                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

                if status == NSMetadataUbiquitousItemDownloadingStatusCurrent ||
                   status == NSMetadataUbiquitousItemDownloadingStatusDownloaded {
                    // File is on disk — mark it ready. @Observable notifies observers.
                    self.readyFilenames.insert(name)
                } else {
                    // Stub present but not yet downloaded.
                    // Requesting a download here ensures the next DidUpdate fires
                    // when the status flips to .current.
                    if let base = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                            .appending(component: "Documents") {
                        try? FileManager.default.startDownloadingUbiquitousItem(
                            at: base.appending(component: name))
                    }
                }
            }
        }

        // Both notifications deliver the same handler; DidFinishGathering covers
        // files that were already local when the query started, DidUpdate covers
        // everything that changes afterwards.
        let o1 = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in handle() }
        let o2 = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { _ in handle() }

        observers = [o1, o2]
        self.query = q
        q.start()
    }

    /// Stops the metadata query. Call when the app goes to background if needed.
    @MainActor
    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        query?.stop()
        query = nil
    }

    // MARK: - Public API

    /// Tells iCloud to download `filename` if it is currently a stub.
    ///
    /// Safe to call even if the file is already local — the system silently
    /// ignores the request. Once the download finishes, `readyFilenames` gains
    /// the filename and any observing view re-renders automatically.
    ///
    /// The underlying `url(forUbiquityContainerIdentifier:)` call can block on
    /// slow connections, so this method dispatches to a background task.
    nonisolated func requestDownload(filename: String) {
        guard !filename.isEmpty else { return }
        Task.detached(priority: .utility) {
            guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                    .appending(component: "Documents") else { return }
            try? FileManager.default.startDownloadingUbiquitousItem(
                at: base.appending(component: filename))
        }
    }
}

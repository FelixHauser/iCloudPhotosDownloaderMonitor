//
//  SecondView.swift
//  TestNuvol
//

import SwiftUI
import SwiftData

struct SecondView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.modelContext) var modelContext

    // ── Approach 1: retry-with-backoff ──────────────────────────────────────
    @State private var secondViewImage: UIImage? = nil

    // ── Approach 2: PhotoDownloadMonitor ────────────────────────────────────
    // Uncomment the line below and comment out the .task modifier to switch.
    // @Environment(PhotoDownloadMonitor.self) private var photoMonitor
    // (secondViewImage above is shared — no changes needed in body)
    // ────────────────────────────────────────────────────────────────────────

    @Query var infos: [Info]

    var body: some View {
        VStack(alignment: .center) {
            if let firstInfo = infos.last {
                Text(firstInfo.name)
            } else {
                Text("No data found in SwiftData")
            }

            if let secondViewImage {
                Image(uiImage: secondViewImage)
                    .scaledToFill()
                    .frame(width: 160, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.vertical, 8)
            } else {
                Text("Image")
                    .bold()
                    .font(.title)
            }
        }

        // ── Approach 1: retry-with-backoff ──────────────────────────────────
        // Reruns on every SwiftData count change. Retries at 0 s, 2 s, 4 s,
        // 8 s to cover the gap between the record arriving and the photo file
        // being fully downloaded from iCloud.
        .task(id: infos.count) {
            let filename = infos.last?.photoPath ?? ""
            for delay in [0.0, 2.0, 4.0, 8.0] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                if let image = await loadThumbnail(filename: filename, maxSize: 160, scale: displayScale) {
                    secondViewImage = image
                    return
                }
            }
        }

        // ── Approach 2: PhotoDownloadMonitor ────────────────────────────────
        // Event-driven: no polling. The monitor's NSMetadataQuery fires the
        // moment iCloud marks the file as downloaded.
        // Requires PhotoDownloadMonitor to be injected in TestNuvolApp (already done).
        //
        // .onChange(of: infos.count, initial: true) {
        //     // Fires on first render AND when a new record arrives while the view
        //     // is already on screen — covers the cross-device sync case.
        //     photoMonitor.requestDownload(filename: infos.last?.photoPath ?? "")
        // }
        // .onChange(of: photoMonitor.readyFilenames.contains(infos.last?.photoPath ?? ""), initial: true) { _, ready in
        //     guard ready, let filename = infos.last?.photoPath else { return }
        //     Task {
        //         secondViewImage = await loadThumbnail(filename: filename, maxSize: 160, scale: displayScale)
        //     }
        // }
        // ────────────────────────────────────────────────────────────────────

        .padding()
    }
}

#Preview {
    SecondView()
}

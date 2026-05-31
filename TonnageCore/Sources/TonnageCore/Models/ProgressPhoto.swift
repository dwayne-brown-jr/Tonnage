import Foundation
import SwiftData

/// A progress photo. Storage is user-selectable, and the model supports both modes so a
/// single photo can live in whichever the user picked at capture time:
///
/// - **On-device only** → bytes are written to a local file (`localFilename`); only the
///   small metadata row syncs via CloudKit. On another device the entry shows but the
///   image is absent (it never left the original phone).
/// - **iCloud** → bytes go in `syncedData` (external-storage, mirrored to CloudKit as an
///   asset), so the image appears on every device and survives reinstalls.
///
/// This rides the existing private CloudKit container — no extra entitlement — and keeps
/// the heavy bytes out of the toggle's way: choosing "on-device" simply never populates
/// the synced field. CloudKit-friendly: every property defaults, nothing is unique.
@Model
public final class ProgressPhoto {
    public var id: UUID = UUID()
    public var date: Date = Date.now
    public var caption: String = ""
    /// Filename of the on-device copy (in the app's progress-photos directory). Set when
    /// the photo was saved in on-device mode; nil for iCloud photos.
    public var localFilename: String?
    /// JPEG bytes mirrored via CloudKit. Set when saved in iCloud mode; nil for
    /// on-device photos. External storage keeps the SQLite store small.
    @Attribute(.externalStorage) public var syncedData: Data?

    public init(id: UUID = UUID(), date: Date = .now, caption: String = "",
                localFilename: String? = nil, syncedData: Data? = nil) {
        self.id = id
        self.date = date
        self.caption = caption
        self.localFilename = localFilename
        self.syncedData = syncedData
    }

    /// True when the bytes aren't reachable on this device (an on-device photo taken on a
    /// different phone, whose file never synced). The UI shows a placeholder for these.
    public var isRemoteOnly: Bool { syncedData == nil && localFilename == nil }
}

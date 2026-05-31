import UIKit
import TonnageCore

/// File-side of progress photos: downscales picked images to a sane size and reads/writes
/// the on-device copies. iCloud photos keep their bytes on the model (`syncedData`); this
/// helper only owns the local-file mode.
enum ProgressPhotoStore {

    /// Max edge length for stored photos — plenty for a phone-screen timeline, but keeps
    /// files (and CloudKit assets) small.
    private static let maxEdge: CGFloat = 1280
    private static let jpegQuality: CGFloat = 0.8

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Downscale + JPEG-encode raw picked data. Returns nil if it isn't a decodable image.
    static func encode(_ raw: Data) -> Data? {
        guard let image = UIImage(data: raw) else { return nil }
        return downscaled(image).jpegData(compressionQuality: jpegQuality)
    }

    /// Persist bytes to a new on-device file; returns the filename to store on the model.
    static func writeLocal(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func readLocal(_ filename: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    static func deleteLocal(_ filename: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    /// Resolve the displayable bytes for a photo regardless of storage mode.
    static func data(for photo: ProgressPhoto) -> Data? {
        if let synced = photo.syncedData { return synced }
        if let name = photo.localFilename { return readLocal(name) }
        return nil
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

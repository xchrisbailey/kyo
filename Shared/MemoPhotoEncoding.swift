import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo ready to attach to a **Memo**: already encoded the way it's stored (HEIC, longest
/// edge at most 2048 px), with its small thumbnail. The id is the stored photo's id, so
/// attaching the same photo twice keeps one.
struct StoredPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    /// A small JPEG for rows and the compose sheet.
    let thumbnail: Data

    init(id: UUID = UUID(), data: Data, thumbnail: Data) {
        self.id = id
        self.data = data
        self.thumbnail = thumbnail
    }
}

/// Turns what the camera or the library hands over into a `StoredPhoto`: scaled down so the
/// longest edge is at most 2048 px (never scaled up), turned upright, and encoded as HEIC. The
/// original isn't kept (docs/adr/0004). Uses only ImageIO, so it runs anywhere and off the main
/// thread.
enum MemoPhotoEncoder {
    /// The longest edge of a stored photo, in pixels.
    static let maximumEdge = 2048
    /// The longest edge of a thumbnail, in pixels.
    static let thumbnailEdge = 320

    private static let heicQuality = 0.8
    private static let thumbnailQuality = 0.7

    /// `nil` when `source` isn't an image ImageIO can read.
    static func encode(_ source: Data) -> StoredPhoto? {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              let stored = downsampled(imageSource, maximumEdge: maximumEdge),
              let data = encoded(stored, as: .heic, quality: heicQuality) ?? encoded(stored, as: .jpeg, quality: heicQuality),
              let thumbnailImage = downsampled(imageSource, maximumEdge: thumbnailEdge),
              let thumbnail = encoded(thumbnailImage, as: .jpeg, quality: thumbnailQuality)
        else { return nil }
        return StoredPhoto(data: data, thumbnail: thumbnail)
    }

    /// The image with its longest edge at most `maximumEdge`, upright. Decodes only what's needed
    /// for that size.
    static func downsampled(_ source: CGImageSource, maximumEdge: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumEdge, max(width, height)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encoded(_ image: CGImage, as type: UTType, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

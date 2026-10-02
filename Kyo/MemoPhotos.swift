import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// Decoded photo images for the memo views, kept so scrolling a row or reopening a card doesn't
/// decode them again. Thumbnails come from the small stored JPEG; the card's larger images are
/// the stored HEIC downsampled with ImageIO, never decoded at full size.
@MainActor
enum MemoPhotoImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    static func cached(_ id: UUID, edge: Int) -> UIImage? {
        cache.object(forKey: key(id, edge))
    }

    static func store(_ image: UIImage, for id: UUID, edge: Int) {
        cache.setObject(image, forKey: key(id, edge))
    }

    /// The small stored thumbnail as an image.
    static func thumbnail(_ id: UUID, load: (UUID) -> Data?) -> UIImage? {
        if let image = cached(id, edge: 0) { return image }
        guard let data = load(id), let image = UIImage(data: data) else { return nil }
        store(image, for: id, edge: 0)
        return image
    }

    /// `data` scaled so its longest edge is `edge` pixels. Safe off the main thread.
    nonisolated static func downsample(_ data: Data, edge: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = MemoPhotoEncoder.downsampled(source, maximumEdge: edge)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private static func key(_ id: UUID, _ edge: Int) -> NSString {
        "\(id.uuidString)-\(edge)" as NSString
    }
}

/// A square thumbnail of a photo from its small stored copy.
struct MemoPhotoThumbnail: View {
    let photoID: UUID
    let size: CGFloat
    let load: (UUID) -> Data?

    var body: some View {
        Group {
            if let image = MemoPhotoImages.thumbnail(photoID, load: load) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The up-to-4 thumbnails under a row's detail line.
struct MemoRowThumbnails: View {
    let photoIDs: [UUID]
    let load: (UUID) -> Data?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(photoIDs.prefix(Memo.maximumPhotos), id: \.self) { id in
                MemoPhotoThumbnail(photoID: id, size: 40, load: load)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The photo menu: **Take Photo** and **Choose from Library**. The library uses the system
/// picker, which needs no permission. The camera prompts on first use; when camera access is
/// off the menu says so and offers **Open Settings**, and the library keeps working. Each photo
/// chosen is encoded off the main thread and handed to `onAdd`.
struct MemoPhotoMenu<Label: View>: View {
    /// How many more photos the memo can take. At zero the menu is disabled.
    let remaining: Int
    let onAdd: (StoredPhoto) -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var isCameraOff: Bool {
        cameraAccess == .denied || cameraAccess == .restricted
    }

    var body: some View {
        Menu {
            if isCameraAvailable {
                if isCameraOff {
                    Button("Camera access is off", systemImage: "camera.badge.ellipsis") {}
                        .disabled(true)
                    Button("Open Settings", systemImage: "gearshape", action: openSettings)
                } else {
                    Button("Take Photo", systemImage: "camera") {
                        Task { await takePhoto() }
                    }
                }
            }
            Button("Choose from Library", systemImage: "photo.on.rectangle") {
                isShowingLibrary = true
            }
        } label: {
            label()
        }
        .disabled(remaining <= 0)
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $libraryItems,
            maxSelectionCount: max(1, remaining),
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await addFromLibrary(items) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onCapture: { data in
                    isShowingCamera = false
                    Task { await add(data) }
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings: the answer may have changed.
            if phase == .active { cameraAccess = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private func takePhoto() async {
        if cameraAccess == .notDetermined {
            // The system prompt, on first use.
            _ = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
        }
        if cameraAccess == .authorized {
            isShowingCamera = true
        }
    }

    private func addFromLibrary(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await add(data)
        }
    }

    /// Encodes off the main thread, then attaches.
    private func add(_ source: Data) async {
        let photo = await Task.detached(priority: .userInitiated) { MemoPhotoEncoder.encode(source) }.value
        if let photo { onAdd(photo) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// The system camera for one photo.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // The orientation travels in the JPEG's metadata; the encoder turns the photo upright.
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                onCapture(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

/// A thumbnail with a button that removes it.
private struct RemovableMemoPhoto: View {
    let photoID: UUID
    let position: Int
    let size: CGFloat
    let load: (UUID) -> Data?
    let onRemove: () -> Void

    var body: some View {
        MemoPhotoThumbnail(photoID: photoID, size: size, load: load)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -6)
                .padding(.trailing, -6)
                .accessibilityLabel("Remove photo \(position)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(position)")
    }
}

/// The photos a memo is being given before it exists (the compose sheet and the recorder): their
/// thumbnails, each removable, and the photo menu while there's room.
struct MemoPendingPhotos: View {
    let photos: [StoredPhoto]
    let onAdd: (StoredPhoto) -> Void
    let onRemove: (UUID) -> Void

    private func load(_ id: UUID) -> Data? {
        photos.first { $0.id == id }?.thumbnail
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                RemovableMemoPhoto(
                    photoID: photo.id,
                    position: index + 1,
                    size: 64,
                    load: load,
                    onRemove: { onRemove(photo.id) }
                )
            }
            if photos.count < Memo.maximumPhotos {
                MemoPhotoMenu(remaining: Memo.maximumPhotos - photos.count, onAdd: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                        if photos.isEmpty { Text("Add photo") }
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KyoPalette.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(KyoPalette.accent.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .accessibilityLabel("Add photo")
                .accessibilityHint("Take a photo or choose from your library")
            }
            Spacer(minLength: 0)
        }
    }
}

/// An open memo's photo carousel: each photo larger, removable, then the add slot while the
/// memo has fewer than 4.
struct MemoPhotoCarousel: View {
    let photoIDs: [UUID]
    let loadThumbnail: (UUID) -> Data?
    let loadPhoto: (UUID) -> Data?
    let onAdd: (StoredPhoto) -> Void
    let onRemove: (UUID) -> Void

    private let tile: CGFloat = 150

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                    CarouselPhoto(
                        photoID: id,
                        position: index + 1,
                        count: photoIDs.count,
                        size: tile,
                        loadThumbnail: loadThumbnail,
                        loadPhoto: loadPhoto,
                        onRemove: { onRemove(id) }
                    )
                }
                if photoIDs.count < Memo.maximumPhotos {
                    MemoPhotoMenu(remaining: Memo.maximumPhotos - photoIDs.count, onAdd: onAdd) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 24))
                            Text("Add photo")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(KyoPalette.accent)
                        .frame(width: tile, height: tile)
                        .background(KyoPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(KyoPalette.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Add photo")
                    .accessibilityHint("Take a photo or choose from your library")
                }
            }
            .padding(.vertical, 2)
        }
        // The remove buttons reach past a tile's corner.
        .scrollClipDisabled()
    }
}

private struct CarouselPhoto: View {
    let photoID: UUID
    let position: Int
    let count: Int
    let size: CGFloat
    let loadThumbnail: (UUID) -> Data?
    let loadPhoto: (UUID) -> Data?
    let onRemove: () -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .frame(width: 44, height: 44, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo \(position)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo \(position) of \(count)")
        .task(id: photoID) { await loadImage() }
    }

    /// The thumbnail at once, then the larger image from the stored photo.
    private func loadImage() async {
        let edge = Int(size * displayScale)
        if let cached = MemoPhotoImages.cached(photoID, edge: edge) {
            image = cached
            return
        }
        image = MemoPhotoImages.thumbnail(photoID, load: loadThumbnail)
        guard let data = loadPhoto(photoID) else { return }
        let larger = await Task.detached(priority: .userInitiated) {
            MemoPhotoImages.downsample(data, edge: edge)
        }.value
        if let larger {
            MemoPhotoImages.store(larger, for: photoID, edge: edge)
            image = larger
        }
    }
}

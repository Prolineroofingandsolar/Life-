import SwiftUI
import PhotosUI

// MARK: - Progress Photos View

struct ProgressPhotosView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var labelText = ""
    @State private var showLabelSheet = false
    @State private var pendingImageData: Data? = nil
    @State private var fullscreenPhoto: ProgressPhoto? = nil
    @State private var compareMode = false
    @State private var compareA: ProgressPhoto? = nil
    @State private var compareB: ProgressPhoto? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if appState.progressPhotos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(appState.progressPhotos.sorted { $0.date > $1.date }) { photo in
                                photoCell(photo)
                            }
                        }
                        .padding(4)
                        Color.clear.frame(height: 80)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if appState.progressPhotos.count >= 2 {
                        Button {
                            compareMode = true
                            compareA = appState.progressPhotos.sorted { $0.date < $1.date }.first
                            compareB = appState.progressPhotos.sorted { $0.date > $1.date }.first
                        } label: {
                            Label("Compare", systemImage: "rectangle.split.2x1")
                        }
                    }
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.7) {
                        await MainActor.run {
                            pendingImageData = compressed
                            labelText = ""
                            showLabelSheet = true
                        }
                    }
                    await MainActor.run { selectedItem = nil }
                }
            }
            .sheet(isPresented: $showLabelSheet) {
                LabelSheet(label: $labelText) {
                    if let data = pendingImageData {
                        let lbl = labelText.isEmpty
                            ? Date().formatted(date: .abbreviated, time: .omitted)
                            : labelText
                        appState.addProgressPhoto(imageData: data, label: lbl)
                    }
                    pendingImageData = nil
                    showLabelSheet = false
                }
            }
            .sheet(item: $fullscreenPhoto) { photo in
                FullscreenPhotoView(photo: photo)
            }
            .sheet(isPresented: $compareMode) {
                if let a = compareA, let b = compareB {
                    CompareView(
                        photoA: a,
                        photoB: b,
                        allPhotos: appState.progressPhotos.sorted { $0.date < $1.date }
                    )
                }
            }
        }
    }

    // MARK: Photo Cell

    @ViewBuilder
    private func photoCell(_ photo: ProgressPhoto) -> some View {
        if let uiImage = UIImage(data: photo.imageData) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: 120)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.label)
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(photo.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(6)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { fullscreenPhoto = photo }
            .contextMenu {
                Button(role: .destructive) {
                    appState.deleteProgressPhoto(id: photo.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Track Your Transformation")
                .font(.title3.bold())
            Text("Add photos to see your progress\nover time side by side.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Add Your First Photo")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#30d158"))
                    .cornerRadius(12)
                    .padding(.horizontal, 60)
            }
            Spacer()
        }
    }
}

// MARK: - Label Sheet

private struct LabelSheet: View {
    @Binding var label: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Label (optional)") {
                    TextField("e.g. Before, Week 4, Month 3", text: $label)
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

// MARK: - Fullscreen Photo View

private struct FullscreenPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: ProgressPhoto

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = UIImage(data: photo.imageData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea(edges: .horizontal)
                }
            }
            .navigationTitle(photo.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Compare View

private struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @State var photoA: ProgressPhoto
    @State var photoB: ProgressPhoto
    let allPhotos: [ProgressPhoto]   // sorted oldest → newest

    @State private var dividerRatio: CGFloat = 0.5
    @State private var showPickerA = false
    @State private var showPickerB = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Photo pickers header
                HStack {
                    Button { showPickerA = true } label: {
                        Label(photoA.label, systemImage: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { showPickerB = true } label: {
                        Label(photoB.label, systemImage: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black)

                // Compare area
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        // Photo A — left side (full width, clipped at divider)
                        Group {
                            if let img = UIImage(data: photoA.imageData) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            }
                        }
                        .clipShape(
                            Rectangle()
                                .size(width: geo.size.width * dividerRatio, height: geo.size.height)
                        )

                        // Photo B — right side
                        Group {
                            if let img = UIImage(data: photoB.imageData) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .offset(x: geo.size.width * dividerRatio)
                                    .clipShape(
                                        Rectangle()
                                            .offset(x: geo.size.width * dividerRatio)
                                    )
                            }
                        }

                        // Divider handle
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geo.size.height)
                            .position(x: geo.size.width * dividerRatio, y: geo.size.height / 2)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "arrow.left.and.right")
                                    .font(.caption.bold())
                                    .foregroundColor(.black)
                            )
                            .position(x: geo.size.width * dividerRatio, y: geo.size.height / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let ratio = value.location.x / geo.size.width
                                        dividerRatio = max(0.1, min(0.9, ratio))
                                    }
                            )
                    }
                    .clipped()
                }
                .background(Color.black)
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPickerA) {
            PhotoPickerSheet(photos: allPhotos, selected: $photoA)
        }
        .sheet(isPresented: $showPickerB) {
            PhotoPickerSheet(photos: allPhotos, selected: $photoB)
        }
    }
}

// MARK: - Photo Picker Sheet (for compare)

private struct PhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [ProgressPhoto]
    @Binding var selected: ProgressPhoto

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos) { photo in
                        if let img = UIImage(data: photo.imageData) {
                            ZStack(alignment: .bottomLeading) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .clipped()
                                if selected.id == photo.id {
                                    Color.blue.opacity(0.35)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                        .padding(6)
                                }
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture {
                                selected = photo
                                dismiss()
                            }
                        }
                    }
                }
                .padding(4)
            }
            .navigationTitle("Select Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

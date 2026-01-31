import SwiftUI
import UIKit

enum CropShape {
    case circle
    case roundedRect(cornerRadius: CGFloat)

    var shape: AnyShape {
        switch self {
        case .circle:
            return AnyShape(Circle())
        case .roundedRect(let cornerRadius):
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct ImageRepositionerView: View {
    let image: UIImage
    let aspectRatio: CGFloat // width / height
    let cropShape: CropShape
    let outputSize: CGSize
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    private let normalizedImage: UIImage
    @State private var userScale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var userOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var frameSize: CGSize = .zero

    private let maxScale: CGFloat = 4

    init(
        image: UIImage,
        aspectRatio: CGFloat,
        cropShape: CropShape,
        outputSize: CGSize,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (UIImage) -> Void
    ) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.cropShape = cropShape
        self.outputSize = outputSize
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.normalizedImage = image.normalized()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Drag to reposition. Pinch to zoom.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    let maxWidth = min(geo.size.width - 40, 360)
                    let width = max(maxWidth, 200)
                    let height = width / max(aspectRatio, 0.1)
                    let size = CGSize(width: width, height: height)

                    ZStack {
                        Color.black.opacity(0.9)
                            .ignoresSafeArea()

                        ZStack {
                            imageLayer(frameSize: size)
                        }
                        .frame(width: size.width, height: size.height)
                        .clipShape(cropShape.shape)
                        .overlay(
                            cropShape.shape
                                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        if frameSize != size {
                            frameSize = size
                            userOffset = clampedOffset(userOffset, frameSize: size, imageSize: normalizedImage.size, scale: userScale)
                            lastOffset = userOffset
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        guard frameSize != .zero,
                              let cropped = renderCroppedImage(frameSize: frameSize) else {
                            return
                        }
                        onConfirm(cropped)
                    }
                }
            }
            .navigationTitle("Reposition")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func imageLayer(frameSize: CGSize) -> some View {
        let baseScale = max(frameSize.width / normalizedImage.size.width, frameSize.height / normalizedImage.size.height)
        let displayScale = baseScale * userScale
        let imageWidth = normalizedImage.size.width * displayScale
        let imageHeight = normalizedImage.size.height * displayScale

        return Image(uiImage: normalizedImage)
            .resizable()
            .frame(width: imageWidth, height: imageHeight)
            .offset(userOffset)
            .gesture(dragGesture(frameSize: frameSize))
            .simultaneousGesture(magnificationGesture(frameSize: frameSize))
            .onChange(of: userScale) { _, newValue in
                let clampedScale = min(max(newValue, 1), maxScale)
                if clampedScale != newValue {
                    userScale = clampedScale
                }
                let clamped = clampedOffset(userOffset, frameSize: frameSize, imageSize: normalizedImage.size, scale: clampedScale)
                if clamped != userOffset {
                    userOffset = clamped
                    lastOffset = clamped
                }
            }
    }

    private func dragGesture(frameSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(width: lastOffset.width + value.translation.width,
                                      height: lastOffset.height + value.translation.height)
                userOffset = clampedOffset(proposed, frameSize: frameSize, imageSize: normalizedImage.size, scale: userScale)
            }
            .onEnded { _ in
                lastOffset = userOffset
            }
    }

    private func magnificationGesture(frameSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposed = lastScale * value
                userScale = min(max(proposed, 1), maxScale)
                userOffset = clampedOffset(userOffset, frameSize: frameSize, imageSize: normalizedImage.size, scale: userScale)
            }
            .onEnded { _ in
                lastScale = userScale
            }
    }

    private func clampedOffset(_ proposed: CGSize, frameSize: CGSize, imageSize: CGSize, scale: CGFloat) -> CGSize {
        let baseScale = max(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
        let displayScale = baseScale * scale
        let displayedSize = CGSize(width: imageSize.width * displayScale, height: imageSize.height * displayScale)
        let maxX = max(0, (displayedSize.width - frameSize.width) / 2)
        let maxY = max(0, (displayedSize.height - frameSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func renderCroppedImage(frameSize: CGSize) -> UIImage? {
        let sourceImage = normalizedImage
        guard let cgImage = sourceImage.cgImage else { return nil }

        let baseScale = max(frameSize.width / sourceImage.size.width, frameSize.height / sourceImage.size.height)
        let displayScale = baseScale * userScale

        let displayedSize = CGSize(width: sourceImage.size.width * displayScale,
                                   height: sourceImage.size.height * displayScale)
        let imageOrigin = CGPoint(x: (frameSize.width - displayedSize.width) / 2 + userOffset.width,
                                  y: (frameSize.height - displayedSize.height) / 2 + userOffset.height)

        let cropXPoints = (0 - imageOrigin.x) / displayScale
        let cropYPoints = (0 - imageOrigin.y) / displayScale
        let cropWidthPoints = frameSize.width / displayScale
        let cropHeightPoints = frameSize.height / displayScale

        var cropRect = CGRect(
            x: cropXPoints * sourceImage.scale,
            y: cropYPoints * sourceImage.scale,
            width: cropWidthPoints * sourceImage.scale,
            height: cropHeightPoints * sourceImage.scale
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        cropRect = cropRect.intersection(bounds)
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

        let cropped = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

struct SelectedUIImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        self.pathBuilder = shape.path(in:)
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

extension UIImage {
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

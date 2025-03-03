import SwiftUI
import Photos

struct ContentView: View {
    @AppStorage("peekCount") private var peekCount: Int = 0
    
    @State private var showPhoto = false
    @State private var photoSize: CGFloat = 0
    @State private var photoPosition: CGPoint = .zero
    @State private var isExpanding = false
    @State private var isFullScreen = false
    
    @State private var originalPhotoPosition: CGPoint = .zero
    @State private var originalPhotoSize: CGFloat = 100
    
    // PhotoKit properties
    @State private var photoAssets: PHFetchResult<PHAsset>?
    @State private var currentPhoto: UIImage? = nil
    
    // A unique identifier to tag the current fetch.
    @State private var currentFetchId: UUID? = nil
    
    // States for pinch to zoom and panning
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    
    let expansionDuration: TimeInterval = 0.2

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if showPhoto, let image = currentPhoto {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Adjust height to preserve aspect ratio (capped by screen height)
                        .frame(width: photoSize,
                               height: min(photoSize * (image.size.height / image.size.width),
                                          geometry.size.height))
                        .position(photoPosition)
                        // Apply zoom scale and pan offset
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        // Combined pinch-to-zoom gesture
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    // Update zoom scale continuously
                                    zoomScale = lastZoomScale * value
                                }
                                .onEnded { _ in
                                    if zoomScale < 1.0 {
                                        withAnimation(.easeOut) {
                                            zoomScale = 1.0
                                        }
                                        lastZoomScale = 1.0
                                    } else {
                                        lastZoomScale = zoomScale
                                    }
                                }
                        )
                        // Combined drag gesture for moving the image around.
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    panOffset = value.translation
                                }
                                .onEnded { value in
                                    // Update the image position based on the pan offset.
                                    photoPosition = CGPoint(x: photoPosition.x + panOffset.width,
                                                            y: photoPosition.y + panOffset.height)
                                    panOffset = .zero
                                }
                        )
                        // Tap to close the photo.
                        .onTapGesture {
                            performHapticFeedback()
                            closePhoto()
                        }
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !showPhoto {
                            showSmallPhoto(at: value.location, in: geometry.size)
                        }
                    }
                    .onEnded { _ in
                        if isExpanding {
                            cancelExpansion()
                        }
                    }
            )
            
            VStack {
                Spacer()
                ZStack {
                    Text("\(formatNumber(peekCount))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 0)
                        .opacity(isFullScreen ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 74)
            }
            .padding(.bottom, 60)
            .padding(.top, 80)
        }
        .ignoresSafeArea()
        .onAppear(perform: requestPhotoAccess)
    }
    
    // Request access to the photo library and fetch assets.
    func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized || status == .limited {
                let fetchOptions = PHFetchOptions()
                let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                DispatchQueue.main.async {
                    self.photoAssets = assets
                }
            }
        }
    }
    
    func showSmallPhoto(at position: CGPoint, in size: CGSize) {
        let smallSize: CGFloat = 100
        let halfSize = smallSize / 2
        let x = min(max(position.x, halfSize), size.width - halfSize)
        let y = min(max(position.y, halfSize), size.height - halfSize)
        
        // Reset state for a fresh start
        showPhoto = false
        currentPhoto = nil
        photoSize = 0
        photoPosition = CGPoint(x: x, y: y)
        originalPhotoPosition = photoPosition
        originalPhotoSize = smallSize
        
        // Reset zoom and pan states
        zoomScale = 1.0
        lastZoomScale = 1.0
        panOffset = .zero
        
        // Generate a new fetch ID
        let fetchId = UUID()
        currentFetchId = fetchId
        
        // Pick a random asset if available
        if let assets = photoAssets, assets.count > 0 {
            let randomIndex = Int.random(in: 0..<assets.count)
            let asset = assets.object(at: randomIndex)
            
            fetchImage(for: asset) { image in
                if self.currentFetchId == fetchId {
                    DispatchQueue.main.async {
                        self.currentPhoto = image
                        self.showPhoto = true
                        withAnimation(.easeInOut(duration: expansionDuration)) {
                            self.photoSize = smallSize
                            self.expandPhoto(in: size) // Trigger expansion immediately
                        }
                    }
                }
            }
        }
    }
    
    // Fetch a full-quality image for a given asset.
    func fetchImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let imageManager = PHImageManager.default()
        let targetSize = CGSize(width: 600, height: 900)
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        imageManager.requestImage(for: asset,
                                  targetSize: targetSize,
                                  contentMode: .aspectFill,
                                  options: options) { image, info in
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            if !isDegraded {
                DispatchQueue.main.async {
                    completion(image)
                }
            }
        }
    }
    
    func expandPhoto(in size: CGSize) {
        performHapticFeedback()
        isExpanding = true
        let fullScreenWidth = size.width // Use screen width
        
        withAnimation(.easeInOut(duration: expansionDuration)) {
            photoSize = fullScreenWidth
            photoPosition = CGPoint(x: size.width / 2, y: size.height / 2)
            isExpanding = false // Reset immediately
            isFullScreen = true  // Set fullscreen immediately
            peekCount += 1       // Increment peek count
        }
    }
    
    func cancelExpansion() {
        isExpanding = false
        withAnimation(.easeOut(duration: 0.2)) {
            photoSize = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showPhoto = false
            withAnimation(.fastSpring) { isFullScreen = false }
            currentFetchId = nil
        }
    }
    
    func closePhoto() {
        performHapticFeedback()
        withAnimation(.easeInOut(duration: 0.2)) {
            photoSize = originalPhotoSize
            photoPosition = originalPhotoPosition
            isFullScreen = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                photoSize = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showPhoto = false
                currentFetchId = nil
            }
        }
    }
    
    func formatNumber(_ number: Int) -> String {
        switch number {
        case 0..<100:
            return "\(number)"
        case 100..<1000:
            return "\(number)"
        case 1000..<10000:
            let thousands = Double(number) / 1000.0
            return thousands.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
        case 10000..<100000:
            let thousands = Double(number) / 1000.0
            return thousands.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
        case 100000..<1000000:
            return "\(number / 1000)k"
        case 1000000...:
            let millions = Double(number) / 1000000.0
            return millions.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        default:
            return "\(number)"
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Extensions and Helpers

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(hex & 0x0000FF) / 255.0,
            alpha: alpha
        )
    }
}

extension Animation {
    static let fastSpring = Animation.interpolatingSpring(mass: 1, stiffness: 100, damping: 16, initialVelocity: 0).speed(1.5)
    static let springySpring = Animation.interpolatingSpring(mass: 1, stiffness: 100, damping: 10, initialVelocity: 5)
}

struct ButtonBounce: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.fastSpring, value: UUID())
    }
}

func performHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.impactOccurred()
}

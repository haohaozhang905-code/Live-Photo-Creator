import SwiftUI
import AVKit
import AVFoundation
import Photos
import CoreText

// 纯净播放器
struct CleanVideoPlayer: NSViewRepresentable {
    var player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect; return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct TextOverlayItem: Identifiable {
    let id = UUID()
    var text: String = "双击或在右侧修改"
    var color: Color = .white
    var fontSize: CGFloat = 36
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
}

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var statusMessage: String = "请先导入视频"
    @State private var isExporting: Bool = false
    
    // 物理尺寸状态
    @State private var videoOriginalSize: CGSize = CGSize(width: 16, height: 9)
    @State private var currentUIBoxSize: CGSize = .zero
    
    // 播控状态
    @State private var isPlaying: Bool = true
    @State private var playbackSpeed: Float = 1.0
    @State private var playerVolume: Float = 1.0

    // 裁剪、旋转与翻转状态
    @State private var selectedRatio: String = "原比例"
    @State private var cropBoxScale: CGFloat = 1.0
    @State private var cropOffset: CGSize = .zero
    @State private var lastCropOffset: CGSize = .zero
    @State private var isFlippedHorizontal: Bool = false
    @State private var isFlippedVertical: Bool = false
    @State private var rotationAngle: Int = 0 // 0, 90, 180, 270
    
    // 文本状态
    @State private var textItems: [TextOverlayItem] = []
    @State private var selectedTextID: UUID?

    // 考虑旋转后的真实物理比例
    var currentVideoSize: CGSize {
        return (rotationAngle % 180 == 0) ? videoOriginalSize : CGSize(width: videoOriginalSize.height, height: videoOriginalSize.width)
    }

    var aspectRatioFloat: CGFloat {
        switch selectedRatio {
        case "16:9": return 16.0 / 9.0; case "9:16": return 9.0 / 16.0
        case "4:3": return 4.0 / 3.0; case "3:4": return 3.0 / 4.0
        case "1:1": return 1.0
        default: return currentVideoSize.width / currentVideoSize.height // 原比例
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ==== 左侧：画板区 ====
            VStack(spacing: 12) {
                Text("✨ 拖拽框内移动位置，拖拽右下角锚点调整大小").foregroundColor(.yellow).font(.caption)
                
                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3))
                        
                        if let player = player {
                            // 1. 底层：视频画面 (响应旋转和翻转)
                            CleanVideoPlayer(player: player)
                                .rotationEffect(.degrees(Double(rotationAngle)))
                                .scaleEffect(x: isFlippedHorizontal ? -1 : 1, y: isFlippedVertical ? -1 : 1)
                            
                            // 2. 尺寸计算
                            let geoRatio = geo.size.width / geo.size.height
                            let vidRatio = currentVideoSize.width / currentVideoSize.height
                            let scaleToFit = vidRatio > geoRatio ? geo.size.width / currentVideoSize.width : geo.size.height / currentVideoSize.height
                            let actualVideoWidth = currentVideoSize.width * scaleToFit
                            let actualVideoHeight = currentVideoSize.height * scaleToFit
                            
                            let maxBoxWidth = aspectRatioFloat > vidRatio ? actualVideoWidth : actualVideoHeight * aspectRatioFloat
                            let maxBoxHeight = aspectRatioFloat > vidRatio ? actualVideoWidth / aspectRatioFloat : actualVideoHeight
                            let currentBoxWidth = maxBoxWidth * cropBoxScale
                            let currentBoxHeight = maxBoxHeight * cropBoxScale
                            
                            // 碰撞墙计算
                            let maxOffsetX = max(0, (actualVideoWidth - currentBoxWidth) / 2)
                            let maxOffsetY = max(0, (actualVideoHeight - currentBoxHeight) / 2)
                            
                            // 3. 半透明遮罩层 (原比例时隐藏黑底)
                            if selectedRatio != "原比例" || cropBoxScale < 1.0 {
                                Color.black.opacity(0.6).mask(
                                    ZStack {
                                        Color.white
                                        Rectangle().frame(width: currentBoxWidth, height: currentBoxHeight).offset(cropOffset).blendMode(.destinationOut)
                                    }.compositingGroup()
                                ).allowsHitTesting(false)
                            }
                            
                            // 4. 交互黄框
                            Rectangle()
                                .stroke(selectedRatio == "原比例" && cropBoxScale == 1.0 ? Color.clear : Color.yellow, lineWidth: 2)
                                .background(Color.white.opacity(0.001))
                                .frame(width: currentBoxWidth, height: currentBoxHeight)
                                .offset(cropOffset)
                                .gesture( // 拖拽移动
                                    DragGesture().onChanged { value in
                                        var newX = lastCropOffset.width + value.translation.width
                                        var newY = lastCropOffset.height + value.translation.height
                                        newX = min(max(newX, -maxOffsetX), maxOffsetX)
                                        newY = min(max(newY, -maxOffsetY), maxOffsetY)
                                        cropOffset = CGSize(width: newX, height: newY)
                                    }.onEnded { _ in lastCropOffset = cropOffset }
                                )
                                // 右下角缩放拖拽点
                                .overlay(
                                    Rectangle().fill(Color.yellow).frame(width: 16, height: 16)
                                        .contentShape(Rectangle()) // 增加点击区域
                                        .gesture(
                                            DragGesture().onChanged { value in
                                                // 基于拖拽距离计算缩放比例
                                                let dragDelta = value.translation.width / maxBoxWidth
                                                var newScale = cropBoxScale + dragDelta * 0.05
                                                newScale = min(max(newScale, 0.2), 1.0)
                                                cropBoxScale = newScale
                                                // 修正缩放导致的出界
                                                cropOffset = .zero; lastCropOffset = .zero
                                            }
                                        )
                                        .offset(x: 8, y: 8)
                                        .opacity(selectedRatio == "原比例" && cropBoxScale == 1.0 ? 0 : 1)
                                    , alignment: .bottomTrailing
                                )
                                .onAppear { currentUIBoxSize = CGSize(width: actualVideoWidth, height: actualVideoHeight) }
                                .onChange(of: geo.size) { _ in currentUIBoxSize = CGSize(width: actualVideoWidth, height: actualVideoHeight) }
                            
                            // 5. 文本层
                            ForEach($textItems) { $item in
                                Text(item.text).font(.system(size: item.fontSize, weight: .bold)).foregroundColor(item.color)
                                    .padding(8).border(selectedTextID == item.id ? Color.white.opacity(0.5) : Color.clear, width: 1)
                                    .offset(item.offset)
                                    .onTapGesture { selectedTextID = item.id }
                                    .gesture(
                                        DragGesture().onChanged { value in
                                            selectedTextID = item.id
                                            item.offset = CGSize(width: item.lastOffset.width + value.translation.width, height: item.lastOffset.height + value.translation.height)
                                        }.onEnded { _ in item.lastOffset = item.offset }
                                    )
                            }
                        } else {
                            Button(action: selectVideo) {
                                VStack(spacing: 12) { Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundColor(.blue); Text("点击选择视频文件").foregroundColor(.gray) }
                            }.buttonStyle(.plain)
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 播控栏
                HStack(spacing: 20) {
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 28)).foregroundColor(videoURL == nil ? .gray : .white)
                    }.buttonStyle(.plain).disabled(videoURL == nil)
                    
                    Picker("倍速", selection: $playbackSpeed) {
                        Text("0.5x").tag(Float(0.5)); Text("1.0x").tag(Float(1.0)); Text("1.5x").tag(Float(1.5)); Text("2.0x").tag(Float(2.0))
                    }.pickerStyle(.segmented).frame(width: 200).onChange(of: playbackSpeed) { val in if isPlaying { player?.rate = val } }
                    Spacer()
                    HStack {
                        Image(systemName: "speaker.wave.1.fill").foregroundColor(.gray).font(.caption)
                        Slider(value: $playerVolume, in: 0...1) { ed in if !ed { player?.volume = playerVolume } }.frame(width: 100)
                    }.disabled(videoURL == nil)
                }.padding(.horizontal, 16).padding(.vertical, 12).background(Color.black.opacity(0.4)).cornerRadius(8)
                
            }.padding().frame(maxWidth: .infinity)
            
            Divider()
            
            // ==== 右侧：控制面板区 ====
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("画面调整", systemImage: "crop").font(.headline)
                        
                        // 裁剪比例
                        VStack(alignment: .leading, spacing: 8) {
                            Text("裁剪比例").font(.subheadline).foregroundColor(.gray)
                            Picker("", selection: $selectedRatio) {
                                Text("原图").tag("原比例"); Text("1:1").tag("1:1"); Text("16:9").tag("16:9"); Text("9:16").tag("9:16"); Text("4:3").tag("4:3"); Text("3:4").tag("3:4")
                            }.pickerStyle(.menu).frame(maxWidth: .infinity)
                            .onChange(of: selectedRatio) { _ in cropBoxScale = 1.0; cropOffset = .zero; lastCropOffset = .zero }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        // 翻转与旋转
                        VStack(alignment: .leading, spacing: 8) {
                            Text("画面方向").font(.subheadline).foregroundColor(.gray)
                            HStack {
                                Button(action: { rotationAngle = (rotationAngle + 90) % 360; cropOffset = .zero; lastCropOffset = .zero }) {
                                    Label("旋转", systemImage: "rotate.right").frame(maxWidth: .infinity, minHeight: 30).background(Color.blue.opacity(0.2)).cornerRadius(6)
                                }.buttonStyle(.bordered)
                                
                                Button(action: { isFlippedHorizontal.toggle() }) {
                                    Label("水平", systemImage: "arrow.left.and.right").frame(maxWidth: .infinity, minHeight: 30).background(isFlippedHorizontal ? Color.blue.opacity(0.2) : Color.clear).cornerRadius(6)
                                }.buttonStyle(.bordered)
                                
                                Button(action: { isFlippedVertical.toggle() }) {
                                    Label("垂直", systemImage: "arrow.up.and.down").frame(maxWidth: .infinity, minHeight: 30).background(isFlippedVertical ? Color.blue.opacity(0.2) : Color.clear).cornerRadius(6)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }.padding(12).background(Color.black.opacity(0.2)).cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Label("添加文本", systemImage: "textformat").font(.headline); Spacer(); Button(action: addText) { Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3) }.buttonStyle(.plain) }
                        if let selectedID = selectedTextID, let index = textItems.firstIndex(where: { $0.id == selectedID }) {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("输入文本", text: $textItems[index].text).textFieldStyle(.roundedBorder)
                                HStack { ColorPicker("文字颜色", selection: $textItems[index].color); Spacer(); Button("删除") { textItems.remove(at: index); selectedTextID = nil }.foregroundColor(.red).font(.caption).buttonStyle(.plain) }
                                HStack { Text("字号").font(.caption); Slider(value: $textItems[index].fontSize, in: 12...150) }
                            }
                        } else { Text("点击右上角 + 号添加文字").font(.caption).foregroundColor(.gray) }
                    }.padding(12).background(Color.black.opacity(0.2)).cornerRadius(10)
                    
                    Spacer(minLength: 40)
                    
                    Button(action: exportLivePhoto) {
                        Label(isExporting ? "正在渲染系统图层..." : "渲染导出 Live Photo", systemImage: "bolt.fill")
                            .font(.headline).foregroundColor(isExporting ? .gray : .black).frame(maxWidth: .infinity, minHeight: 44)
                            .background(isExporting ? Color.gray.opacity(0.5) : Color.yellow).cornerRadius(8)
                    }.buttonStyle(.plain).disabled(isExporting || videoURL == nil)
                    
                    Text(statusMessage).font(.caption2).foregroundColor(statusMessage.contains("成功") ? .green : (statusMessage.contains("❌") ? .red : .gray)).frame(maxWidth: .infinity, alignment: .center)
                }.padding()
            }.frame(width: 280).background(Color(NSColor.windowBackgroundColor))
        }.frame(minWidth: 900, minHeight: 600).preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in isPlaying = false; player?.seek(to: .zero) }
    }
    
    // MARK: - 功能函数
    func selectVideo() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        if panel.runModal() == .OK, let url = panel.url {
            self.videoURL = url; let asset = AVAsset(url: url)
            self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            Task {
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try await track.load(.naturalSize); let t = try await track.load(.preferredTransform)
                    let actualSize = abs(t.a) == 1 ? size : CGSize(width: size.height, height: size.width)
                    DispatchQueue.main.async { self.videoOriginalSize = actualSize; self.player?.play(); self.isPlaying = true; self.statusMessage = "视频已加载完毕" }
                }
            }
        }
    }
    func togglePlay() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play(); player.rate = playbackSpeed }
        isPlaying.toggle()
    }
    func addText() { let newItem = TextOverlayItem(); textItems.append(newItem); selectedTextID = newItem.id }
    
    // MARK: - 🚀 终极渲染引擎 (核心修复版)
    func exportLivePhoto() {
        guard let asset = player?.currentItem?.asset else { return }
        isExporting = true; statusMessage = "⏳ 正在计算物理矩阵坐标..."
        player?.pause(); isPlaying = false
        
        let keyframeTime = player?.currentTime() ?? .zero
        let uuid = UUID().uuidString
        
        // 核心数学：获取物理尺寸并计算坐标
        let vSize = currentVideoSize
        let uiWidth = currentUIBoxSize.width; let uiHeight = currentUIBoxSize.height
        let vidRatio = vSize.width / vSize.height
        let maxBoxWidth = aspectRatioFloat > vidRatio ? uiWidth : uiHeight * aspectRatioFloat
        let maxBoxHeight = aspectRatioFloat > vidRatio ? uiWidth / aspectRatioFloat : uiHeight
        let boxW = maxBoxWidth * cropBoxScale; let boxH = maxBoxHeight * cropBoxScale
        
        // 归一化裁剪框 (以原点为左上角计算)
        let normCropX = (uiWidth / 2 - boxW / 2 + cropOffset.width) / uiWidth
        let normCropY = (uiHeight / 2 - boxH / 2 + cropOffset.height) / uiHeight
        let normCropW = boxW / uiWidth; let normCropH = boxH / uiHeight
        
        // 真实像素裁剪框
        let cropRect = CGRect(x: normCropX * vSize.width, y: normCropY * vSize.height, width: normCropW * vSize.width, height: normCropH * vSize.height)
        
        let textsToRender = textItems
        let rAngle = rotationAngle; let flipH = isFlippedHorizontal; let flipV = isFlippedVertical; let speed = playbackSpeed
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.executeRenderEngine(asset: asset, keyframeTime: keyframeTime, uuid: uuid, cropRect: cropRect, texts: textsToRender, uiWidth: uiWidth, uiHeight: uiHeight, flipH: flipH, flipV: flipV, rotation: rAngle, speed: speed)
        }
    }
    
    func executeRenderEngine(asset: AVAsset, keyframeTime: CMTime, uuid: String, cropRect: CGRect, texts: [TextOverlayItem], uiWidth: CGFloat, uiHeight: CGFloat, flipH: Bool, flipV: Bool, rotation: Int, speed: Float) {
        let tempDir = FileManager.default.temporaryDirectory
        let imageURL = tempDir.appendingPathComponent("\(uuid).jpg")
        let videoURL = tempDir.appendingPathComponent("\(uuid).mov")
        
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { self.isExporting = false; self.statusMessage = "❌ 视频解析失败" }
            return
        }
        
        let duration = asset.duration.seconds
        var startSeconds = max(0, keyframeTime.seconds - 1.5 * Double(speed))
        var endSeconds = min(duration, keyframeTime.seconds + 1.5 * Double(speed))
        if endSeconds - startSeconds < 3.0 * Double(speed) { startSeconds = max(0, endSeconds - 3.0 * Double(speed)) }
        
        let sourceTimeRange = CMTimeRange(start: CMTime(seconds: startSeconds, preferredTimescale: 600), duration: CMTime(seconds: endSeconds - startSeconds, preferredTimescale: 600))
        let targetDuration = CMTime(seconds: sourceTimeRange.duration.seconds / Double(speed), preferredTimescale: 600)
        let targetTimeRange = CMTimeRange(start: .zero, duration: targetDuration)
        
        try? videoTrack.insertTimeRange(sourceTimeRange, of: assetVideoTrack, at: .zero)
        if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
            try? audioTrack.insertTimeRange(sourceTimeRange, of: assetAudioTrack, at: .zero)
        }
        videoTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: sourceTimeRange.duration), toDuration: targetDuration)
        audioTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: sourceTimeRange.duration), toDuration: targetDuration)
        
        // 🚀 重构极其复杂的物理矩阵 (解决翻转黑屏问题)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropRect.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = targetTimeRange
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // 以画面中心为原点进行变换，彻底杜绝坐标系飞出黑屏
        var transform = assetVideoTrack.preferredTransform
        // 处理旋转
        transform = transform.translatedBy(x: videoOriginalSize.width / 2, y: videoOriginalSize.height / 2)
        transform = transform.rotated(by: CGFloat(rotation) * .pi / 180.0)
        // 修正旋转后的中心偏移
        let newWidth = (rotation % 180 == 0) ? videoOriginalSize.width : videoOriginalSize.height
        let newHeight = (rotation % 180 == 0) ? videoOriginalSize.height : videoOriginalSize.width
        transform = transform.translatedBy(x: -newWidth / 2, y: -newHeight / 2)
        
        // 处理翻转 (基于当前物理中心)
        if flipH { transform = transform.translatedBy(x: newWidth, y: 0).scaledBy(x: -1, y: 1) }
        if flipV { transform = transform.translatedBy(x: 0, y: newHeight).scaledBy(x: 1, y: -1) }
        
        // 处理裁剪偏移
        transform = transform.translatedBy(x: -cropRect.origin.x, y: -cropRect.origin.y)
        
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // 🚀 文字烧录重写 (解决坐标颠倒和不显示问题)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: cropRect.size)
        parentLayer.isGeometryFlipped = true // 强制 Mac 坐标系与 iOS 坐标系对齐！
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: cropRect.size)
        parentLayer.addSublayer(videoLayer)
        
        for item in texts {
            let textLayer = CATextLayer()
            textLayer.string = item.text
            textLayer.fontSize = item.fontSize * (newWidth / uiWidth)
            textLayer.foregroundColor = NSColor(item.color).cgColor
            textLayer.alignmentMode = .center
            
            // 真实物理坐标换算
            let normTextX = (uiWidth / 2 + item.offset.width) / uiWidth
            let normTextY = (uiHeight / 2 + item.offset.height) / uiHeight
            let textAbsX = normTextX * newWidth - cropRect.origin.x
            let textAbsY = normTextY * newHeight - cropRect.origin.y // Flipped 生效，无需反转Y轴
            
            textLayer.frame = CGRect(x: textAbsX - 500, y: textAbsY - textLayer.fontSize/2, width: 1000, height: textLayer.fontSize * 1.5)
            parentLayer.addSublayer(textLayer)
        }
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        
        // 生成最终文件
        let imageGenerator = AVAssetImageGenerator(asset: composition)
        imageGenerator.videoComposition = videoComposition
        imageGenerator.requestedTimeToleranceBefore = .zero; imageGenerator.requestedTimeToleranceAfter = .zero
        let relativeKeyframeTime = CMTime(seconds: (keyframeTime.seconds - startSeconds) / Double(speed), preferredTimescale: 600)
        
        guard let cgImage = try? imageGenerator.copyCGImage(at: relativeKeyframeTime, actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        
        let makerNote = NSMutableDictionary(); makerNote.setObject(uuid, forKey: "17" as NSCopying)
        let imageProperties = NSMutableDictionary(); imageProperties.setObject(makerNote, forKey: kCGImagePropertyMakerAppleDictionary as String as NSCopying)
        CGImageDestinationAddImage(dest, cgImage, imageProperties as CFDictionary)
        if !CGImageDestinationFinalize(dest) { return }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exportSession.outputURL = videoURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = .quickTimeMetadataContentIdentifier; metadataItem.dataType = "com.apple.metadata.datatype.UTF-8"
        metadataItem.value = uuid as NSString; exportSession.metadata = [metadataItem]
        
        let semaphore = DispatchSemaphore(value: 0); exportSession.exportAsynchronously { semaphore.signal() }; semaphore.wait()
        
        guard exportSession.status == .completed else {
            DispatchQueue.main.async { self.isExporting = false; self.statusMessage = "❌ 渲染失败: \(exportSession.error?.localizedDescription ?? "")" }
            return
        }
        
        DispatchQueue.main.async { self.statusMessage = "⏳ 渲染完成，正在写入相册..." }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset(); req.addResource(with: .photo, fileURL: imageURL, options: nil); req.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        }) { success, err in
            DispatchQueue.main.async {
                self.isExporting = false; if success { self.statusMessage = "✅ 魔法大成功！文字、翻转与裁剪完美生效！" } else { self.statusMessage = "❌ 写入失败" }
            }
        }
    }
}

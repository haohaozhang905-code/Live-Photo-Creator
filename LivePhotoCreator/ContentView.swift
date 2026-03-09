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
    var text: String = "输入文字"
    var color: Color = .white
    var fontSize: CGFloat = 36
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var hasBackground: Bool = true
}

private struct PanelCardModifier: ViewModifier {
    let background: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private extension View {
    func panelCard(background: Color, stroke: Color) -> some View {
        modifier(PanelCardModifier(background: background, border: stroke))
    }
}

struct ContentView: View {
    private let ratioOptions: [String] = ["原比例", "1:1", "16:9", "9:16", "4:3", "3:4"]
    private let accentYellow = Color(red: 0.99, green: 0.78, blue: 0.10)
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
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var cropScaleStartValue: CGFloat?
    @State private var timeObserver: Any?


    // 裁剪、旋转与翻转状态
    @State private var selectedRatio: String = "原比例"
    @State private var cropBoxScale: CGFloat = 1.0
    @State private var cropOffset: CGSize = .zero
    @State private var lastCropOffset: CGSize = .zero
    @State private var isFlippedHorizontal: Bool = false
    @State private var isFlippedVertical: Bool = false
    
    // 文本状态
    @State private var textItems: [TextOverlayItem] = []
    @State private var selectedTextID: UUID?
    @State private var editingTextID: UUID?
    @State private var hoveredTextID: UUID?
    @State private var isTextListExpanded: Bool = false
    @FocusState private var isTextInputFocused: Bool

    // 主题：明亮 / 暗黑
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @State private var debugRunId: String = UUID().uuidString
    @State private var lastDebugSecond: Int = -1

    private var isDarkMode: Bool { appColorScheme == "dark" }
    private var appBackground: Color {
        isDarkMode ? Color(red: 0.10, green: 0.11, blue: 0.13) : Color(red: 0.965, green: 0.97, blue: 0.985)
    }
    private var canvasBackground: Color {
        isDarkMode ? Color(red: 0.14, green: 0.15, blue: 0.18) : Color(red: 0.92, green: 0.93, blue: 0.95)
    }
    private var panelBackground: Color {
        isDarkMode ? Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.98) : Color.white.opacity(0.985)
    }
    private var panelStroke: Color {
        isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.10)
    }
    private var controlSurface: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var primaryText: Color {
        isDarkMode ? Color.white.opacity(0.88) : Color.black.opacity(0.86)
    }
    private var secondaryText: Color {
        isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.64)
    }
    private var listItemBackground: Color {
        isDarkMode ? Color.primary.opacity(0.03) : Color.black.opacity(0.045)
    }
    private var listItemSelectedBackground: Color {
        isDarkMode ? accentYellow.opacity(0.14) : accentYellow.opacity(0.22)
    }

    // 考虑旋转后的真实物理比例
    var currentVideoSize: CGSize {
        return videoOriginalSize
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
        VStack(spacing: 10) {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        appColorScheme = "light"
                    } label: {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(appColorScheme == "light" ? .black : secondaryText)
                            .frame(width: 28, height: 28)
                            .background(appColorScheme == "light" ? accentYellow : controlSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appColorScheme = "dark"
                    } label: {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(appColorScheme == "dark" ? .black : secondaryText)
                            .frame(width: 28, height: 28)
                            .background(appColorScheme == "dark" ? accentYellow : controlSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(spacing: 14) {
            // ==== 左侧：画板区 ====
            VStack(spacing: 14) {
                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canvasBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(accentYellow.opacity(0.34), lineWidth: 1.2)
                            )
                        
                        if let player = player {
                            // 1. 底层：视频画面 (响应旋转和翻转)
                            CleanVideoPlayer(player: player)
                                .scaleEffect(x: isFlippedHorizontal ? -1 : 1, y: isFlippedVertical ? -1 : 1)
                            
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(role: .destructive) {
                                        clearCurrentVideo()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("移除当前视频")
                                }
                                .padding(10)
                                Spacer()
                            }
                            
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
                                .stroke(selectedRatio == "原比例" && cropBoxScale == 1.0 ? Color.clear : accentYellow.opacity(0.95), lineWidth: 1.6)
                                .background(Color.white.opacity(0.001))
                                .frame(width: currentBoxWidth, height: currentBoxHeight)
                                .offset(cropOffset)
                                .allowsHitTesting(selectedRatio != "原比例" || cropBoxScale < 1.0)
                                .gesture( // 拖拽移动
                                    DragGesture().onChanged { value in
                                        var newX = lastCropOffset.width + value.translation.width
                                        var newY = lastCropOffset.height + value.translation.height
                                        newX = min(max(newX, -maxOffsetX), maxOffsetX)
                                        newY = min(max(newY, -maxOffsetY), maxOffsetY)
                                        cropOffset = CGSize(width: newX, height: newY)
                                    }.onEnded { _ in
                                        // #region agent log
                                        agentDebugLog(
                                            hypothesisId: "H4",
                                            location: "ContentView.swift:crop.drag.onEnded",
                                            message: "crop box moved",
                                            data: ["offsetX": cropOffset.width, "offsetY": cropOffset.height, "boxW": currentBoxWidth, "boxH": currentBoxHeight]
                                        )
                                        // #endregion
                                        lastCropOffset = cropOffset
                                    }
                                )
                                .onAppear { currentUIBoxSize = CGSize(width: actualVideoWidth, height: actualVideoHeight) }
                                .onChange(of: geo.size) { _ in currentUIBoxSize = CGSize(width: actualVideoWidth, height: actualVideoHeight) }
                            
                            if !(selectedRatio == "原比例" && cropBoxScale == 1.0) {
                                Circle()
                                    .fill(accentYellow.opacity(0.95))
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                                    .offset(
                                        x: cropOffset.width + currentBoxWidth / 2,
                                        y: cropOffset.height + currentBoxHeight / 2
                                    )
                                    .gesture(
                                        DragGesture().onChanged { value in
                                            if cropScaleStartValue == nil { cropScaleStartValue = cropBoxScale }
                                            let start = cropScaleStartValue ?? cropBoxScale
                                            // 降低灵敏度，按初始值 + 拖拽量计算，避免累计误差导致过快
                                            let dragDelta = value.translation.width / max(maxBoxWidth, 1)
                                            var newScale = start + dragDelta * 0.60
                                            newScale = min(max(newScale, 0.2), 1.0)
                                            cropBoxScale = newScale
                                            cropOffset = .zero
                                            lastCropOffset = .zero
                                            // #region agent log
                                            agentDebugLog(
                                                hypothesisId: "H4",
                                                location: "ContentView.swift:crop.scale.drag.onChanged",
                                                message: "crop scale changed and offset reset",
                                                data: ["newScale": cropBoxScale, "offsetX": cropOffset.width, "offsetY": cropOffset.height]
                                            )
                                            // #endregion
                                        }
                                        .onEnded { _ in
                                            cropScaleStartValue = nil
                                        }
                                    )
                            }
                            
                            // 5. 文本层
                            ForEach($textItems) { $item in
                                let itemID = item.id
                                let isSelected = selectedTextID == itemID
                                let controlsOpacity: Double = (hoveredTextID == itemID) ? 0.95 : 0.28
                                ZStack {
                                    Text(normalizeOverlayText(item.text))
                                        .font(.system(size: item.fontSize, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: true)
                                        .foregroundColor(item.color)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(accentYellow.opacity(0.45), lineWidth: 1.2)
                                            .padding(-4)
                                            .opacity(controlsOpacity)
                                    }
                                }
                                .scaleEffect(item.scale)
                                .offset(item.offset)
                                .onHover { inside in
                                    hoveredTextID = inside ? itemID : (hoveredTextID == itemID ? nil : hoveredTextID)
                                }
                                .onTapGesture {
                                    selectedTextID = itemID
                                    editingTextID = nil
                                }
                                .onTapGesture(count: 2) {
                                    beginEditingText(itemID)
                                }
                                .gesture(
                                    DragGesture().onChanged { value in
                                        selectedTextID = itemID
                                        editingTextID = nil
                                        guard let idx = textItems.firstIndex(where: { $0.id == itemID }) else { return }
                                        textItems[idx].offset = CGSize(
                                            width: textItems[idx].lastOffset.width + value.translation.width,
                                            height: textItems[idx].lastOffset.height + value.translation.height
                                        )
                                    }.onEnded { _ in
                                        guard let idx = textItems.firstIndex(where: { $0.id == itemID }) else { return }
                                        textItems[idx].lastOffset = textItems[idx].offset
                                    }
                                )
                                .animation(.easeOut(duration: 0.18), value: controlsOpacity)
                            }
                        } else {
                            Button(action: selectVideo) {
                                VStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 52))
                                        .foregroundColor(accentYellow)
                                    Text("点击选择视频文件")
                                        .foregroundColor(secondaryText)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if editingTextID != nil {
                                endTextEditing()
                                return
                            }
                            if selectedTextID != nil {
                                selectedTextID = nil
                                return
                            }
                            if player != nil {
                                togglePlay()
                            }
                        }
                    )
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 播控栏：进度条 + 主控 + 收起的倍速/音量
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button(action: togglePlay) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(videoURL == nil ? .gray : .black)
                                .frame(width: 42, height: 42)
                                .background(videoURL == nil ? controlSurface : accentYellow)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(videoURL == nil)

                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { currentTime },
                                    set: { t in
                                        currentTime = t
                                        if isScrubbing { seekPlayer(to: t) }
                                    }
                                ),
                                in: 0...max(1, duration),
                                onEditingChanged: { editing in
                                    isScrubbing = editing
                                    if !editing { seekPlayer(to: currentTime) }
                                }
                            )
                            .tint(accentYellow)
                            HStack {
                                Text(formatTime(currentTime)).font(.caption2).foregroundColor(.secondary)
                                Spacer()
                                Text(formatTime(duration)).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(videoURL == nil || duration <= 0)
                    }

                    HStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "speedometer").font(.system(size: 16, weight: .semibold)).foregroundColor(.secondary)
                            Picker("", selection: $playbackSpeed) {
                                Text("0.5×").tag(Float(0.5))
                                Text("1×").tag(Float(1.0))
                                Text("1.5×").tag(Float(1.5))
                                Text("2×").tag(Float(2.0))
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .tint(accentYellow)
                            .onChange(of: playbackSpeed) { _, val in
                                if isPlaying {
                                    player?.rate = val
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(.secondary)
                            Slider(value: $playerVolume, in: 0...1)
                                .frame(width: 120)
                                .tint(accentYellow)
                                .onChange(of: playerVolume) { _, v in player?.volume = v }
                        }
                    }
                    .disabled(videoURL == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .panelCard(background: panelBackground, stroke: panelStroke)
                
            }
            .padding(.leading, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            
                // ==== 右侧：控制面板区 ====
                VStack(spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("裁剪比例")
                                    .font(.headline)
                                VStack(spacing: 0) {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(ratioOptions, id: \.self) { ratio in
                                            Button {
                                                selectedRatio = ratio
                                                cropBoxScale = 1.0
                                                cropOffset = .zero
                                                lastCropOffset = .zero
                                            } label: {
                                                Text(ratio == "原比例" ? "原比例" : ratio)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(selectedRatio == ratio ? .black : primaryText)
                                                    .frame(maxWidth: .infinity, minHeight: 28)
                                                    .background(selectedRatio == ratio ? accentYellow : controlSurface)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)

                                    Divider().padding(.horizontal, 2).padding(.vertical, 10)
                                    Text("方向调整")
                                        .font(.subheadline)
                                        .foregroundColor(primaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    HStack(spacing: 8) {
                                        Button(action: { isFlippedHorizontal.toggle() }) {
                                            Image(systemName: "arrow.left.and.right")
                                                .frame(maxWidth: .infinity, minHeight: 30)
                                                .foregroundColor(primaryText)
                                                .background(isFlippedHorizontal ? accentYellow.opacity(0.22) : controlSurface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(isFlippedHorizontal ? accentYellow.opacity(0.55) : Color.clear, lineWidth: 1)
                                                )
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: { isFlippedVertical.toggle() }) {
                                            Image(systemName: "arrow.up.and.down")
                                                .frame(maxWidth: .infinity, minHeight: 30)
                                                .foregroundColor(primaryText)
                                                .background(isFlippedVertical ? accentYellow.opacity(0.22) : controlSurface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(isFlippedVertical ? accentYellow.opacity(0.55) : Color.clear, lineWidth: 1)
                                                )
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                }
                            }
                            .padding(12)
                            .panelCard(background: panelBackground, stroke: panelStroke)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("文字叠加")
                                        .font(.headline)
                                    Spacer()
                                    Button(action: addText) {
                                        Label("添加", systemImage: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(primaryText)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(controlSurface)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                if textItems.isEmpty {
                                    Text("先添加一条文本")
                                        .font(.caption)
                                        .foregroundColor(secondaryText)
                                } else {
                                    VStack(spacing: 8) {
                                        let listItems = displayTextItems()
                                        ForEach(Array(listItems.enumerated()), id: \.element.id) { idx, textItem in
                                            Button {
                                                if selectedTextID == textItem.id {
                                                    beginEditingText(textItem.id)
                                                } else {
                                                    selectedTextID = textItem.id
                                                    editingTextID = nil
                                                }
                                            } label: {
                                                HStack {
                                                    Text("文本 \(indexOfTextItem(textItem.id) + 1)")
                                                        .font(.caption)
                                                        .foregroundColor(secondaryText)
                                                    Text(normalizeOverlayText(textItem.text))
                                                        .font(.caption2)
                                                        .lineLimit(1)
                                                        .foregroundColor(secondaryText)
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        removeText(id: textItem.id)
                                                    } label: {
                                                        Image(systemName: "trash")
                                                            .font(.system(size: 11, weight: .semibold))
                                                            .foregroundColor(primaryText)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .background(selectedTextID == textItem.id ? listItemSelectedBackground : listItemBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    if textItems.count > 2 {
                                        Button(isTextListExpanded ? "收起" : "展开全部") {
                                            isTextListExpanded.toggle()
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.plain)
                                        .foregroundColor(secondaryText)
                                    }
                                }

                                if let selectedID = selectedTextID,
                                   textItems.contains(where: { $0.id == selectedID }) {
                                    let textBinding = Binding<String>(
                                        get: {
                                            textItems.first(where: { $0.id == selectedID })?.text ?? ""
                                        },
                                        set: { newValue in
                                            guard let currentIndex = textItems.firstIndex(where: { $0.id == selectedID }) else { return }
                                            textItems[currentIndex].text = normalizeOverlayText(newValue)
                                        }
                                    )
                                    let colorBinding = Binding<Color>(
                                        get: {
                                            textItems.first(where: { $0.id == selectedID })?.color ?? .white
                                        },
                                        set: { newColor in
                                            guard let currentIndex = textItems.firstIndex(where: { $0.id == selectedID }) else { return }
                                            textItems[currentIndex].color = newColor
                                        }
                                    )
                                    let scaleBinding = Binding<CGFloat>(
                                        get: {
                                            textItems.first(where: { $0.id == selectedID })?.scale ?? 1.0
                                        },
                                        set: { newScale in
                                            guard let currentIndex = textItems.firstIndex(where: { $0.id == selectedID }) else { return }
                                            textItems[currentIndex].scale = newScale
                                            textItems[currentIndex].lastScale = newScale
                                        }
                                    )
                                    TextField("文本内容（最多20字）", text: Binding(
                                        get: { textBinding.wrappedValue },
                                        set: { textBinding.wrappedValue = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($isTextInputFocused)
                                    .onTapGesture {
                                        beginEditingText(selectedID)
                                    }
                                    .onSubmit {
                                        endTextEditing()
                                    }

                                    HStack(spacing: 10) {
                                        Image(systemName: "paintpalette.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(secondaryText)
                                        ColorPicker("", selection: colorBinding)
                                            .labelsHidden()
                                        Slider(value: scaleBinding, in: 0.35...4.0)
                                            .tint(accentYellow)
                                    }
                                }
                            }
                            .padding(12)
                            .panelCard(background: panelBackground, stroke: panelStroke)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                    }

                    VStack(spacing: 8) {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundColor(statusMessage.contains("成功") ? .green : (statusMessage.contains("❌") ? .red : .secondary))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Button(action: exportLivePhoto) {
                            Label(isExporting ? "正在渲染..." : "导出 Live Photo", systemImage: "bolt.fill")
                                .font(.headline)
                                .foregroundColor(isExporting ? .gray : .black)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isExporting ? Color.gray.opacity(0.5) : accentYellow)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isExporting || videoURL == nil)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .panelCard(background: panelBackground, stroke: panelStroke)
                }
                .frame(width: 292)
                .padding(.trailing, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .disabled(videoURL == nil)
                .opacity(videoURL == nil ? 0.45 : 1)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(appBackground)
        .preferredColorScheme(appColorScheme == "light" ? .light : .dark)
        .onDeleteCommand {
            removeSelectedText()
        }
        .onExitCommand {
            if editingTextID != nil {
                endTextEditing()
            } else if selectedTextID != nil {
                selectedTextID = nil
            }
        }
        .onChange(of: editingTextID) { _, newValue in
            if newValue != nil {
                DispatchQueue.main.async {
                    isTextInputFocused = true
                }
            } else {
                isTextInputFocused = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            // #region agent log
            agentDebugLog(
                hypothesisId: "H1",
                location: "ContentView.swift:onReceive.didPlayToEnd",
                message: "player reached end and seeks to zero",
                data: ["currentTime": player?.currentTime().seconds ?? -1]
            )
            // #endregion
            isPlaying = false
            player?.seek(to: .zero)
        }
    }
    
    // MARK: - 功能函数
    func selectVideo() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        if panel.runModal() == .OK, let url = panel.url {
            let oldPlayer = self.player
            if let ob = self.timeObserver, let old = oldPlayer { old.removeTimeObserver(ob) }
            self.timeObserver = nil
            // 新视频初始化：清空文本与画面状态
            self.textItems = []
            self.selectedTextID = nil
            self.editingTextID = nil
            self.hoveredTextID = nil
            self.isTextListExpanded = false
            self.cropBoxScale = 1.0
            self.cropOffset = .zero
            self.lastCropOffset = .zero
            self.isFlippedHorizontal = false
            self.isFlippedVertical = false
            self.videoURL = url
            let asset = AVAsset(url: url)
            self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            setupTimeObserver()
            Task {
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try await track.load(.naturalSize); let t = try await track.load(.preferredTransform)
                    let actualSize = abs(t.a) == 1 ? size : CGSize(width: size.height, height: size.width)
                    let loadedDuration = (try? await asset.load(.duration).seconds) ?? 0
                    DispatchQueue.main.async {
                        self.videoOriginalSize = actualSize
                        self.duration = (loadedDuration.isFinite && loadedDuration > 0) ? loadedDuration : 0
                        self.currentTime = 0
                        self.player?.seek(to: .zero)
                        self.player?.play()
                        self.player?.rate = self.playbackSpeed
                        self.isPlaying = true
                        self.statusMessage = "视频已加载完毕"
                    }
                }
            }
        }
    }
    func togglePlay() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play(); player.rate = playbackSpeed }
        isPlaying.toggle()
    }
    func addText() {
        var newItem = TextOverlayItem()
        newItem.text = ""
        textItems.append(newItem)
        beginEditingText(newItem.id)
    }

    func removeSelectedText() {
        guard let selectedID = selectedTextID,
              let index = textItems.firstIndex(where: { $0.id == selectedID }) else { return }
        textItems.remove(at: index)
        selectedTextID = nil
        editingTextID = nil
        if textItems.count <= 2 { isTextListExpanded = false }
    }

    func clearCurrentVideo() {
        if let ob = timeObserver, let old = player {
            old.removeTimeObserver(ob)
        }
        // 先清理文本选择/编辑状态，避免 UI 闭包在数组已清空时访问失效项
        selectedTextID = nil
        editingTextID = nil
        hoveredTextID = nil
        isTextListExpanded = false
        timeObserver = nil
        videoURL = nil
        player = nil
        isPlaying = false
        duration = 0
        currentTime = 0
        cropBoxScale = 1.0
        cropOffset = .zero
        lastCropOffset = .zero
        isFlippedHorizontal = false
        isFlippedVertical = false
        textItems = []
        statusMessage = "请先导入视频"
    }

    func removeText(id: UUID) {
        guard let index = textItems.firstIndex(where: { $0.id == id }) else { return }
        textItems.remove(at: index)
        if selectedTextID == id { selectedTextID = nil }
        if editingTextID == id { editingTextID = nil }
        if textItems.count <= 2 { isTextListExpanded = false }
    }

    func beginEditingText(_ id: UUID) {
        selectedTextID = id
        editingTextID = id
    }

    func endTextEditing() {
        editingTextID = nil
        isTextInputFocused = false
    }

    func displayTextItems() -> [TextOverlayItem] {
        guard textItems.count > 1 else { return textItems }
        if isTextListExpanded { return textItems }
        // 折叠状态下默认展示首条；若当前选中不是首条，额外展示选中项，避免“选中了但看不见”
        var result: [TextOverlayItem] = [textItems[0]]
        if let selectedID = selectedTextID,
           let selected = textItems.first(where: { $0.id == selectedID }),
           selected.id != textItems[0].id {
            result.append(selected)
        }
        return result
    }

    func indexOfTextItem(_ id: UUID) -> Int {
        textItems.firstIndex(where: { $0.id == id }) ?? 0
    }

    private func normalizeOverlayText(_ raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(20))
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func agentDebugLog(hypothesisId: String, location: String, message: String, data: [String: Any]) {
        let logPath = "/Users/billzhang/Documents/GitHub/.cursor/debug-2dcd41.log"
        var payload: [String: Any] = [
            "sessionId": "2dcd41",
            "runId": debugRunId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if payload["id"] == nil {
            payload["id"] = UUID().uuidString
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: jsonData, encoding: .utf8) else { return }
        line += "\n"
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let d = line.data(using: .utf8) {
                handle.write(d)
            }
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func setupTimeObserver() {
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [self] time in
            if !isScrubbing {
                let safeDuration = duration > 0 ? duration : max(time.seconds, 0)
                currentTime = min(max(0, time.seconds), safeDuration)
            }
            let sec = Int(time.seconds.rounded())
            if sec != lastDebugSecond {
                lastDebugSecond = sec
                // #region agent log
                agentDebugLog(
                    hypothesisId: "H1",
                    location: "ContentView.swift:setupTimeObserver.tick",
                    message: "periodic time observer tick",
                    data: ["observerTime": time.seconds, "duration": duration, "isPlaying": isPlaying]
                )
                // #endregion
            }
        }
        if let item = player?.currentItem {
            duration = item.duration.seconds
            if duration.isFinite && duration > 0 { } else { duration = 0 }
        }
    }

    private func seekPlayer(to seconds: Double) {
        guard let player = player else { return }
        let upper = duration > 0 ? duration : max(seconds, 0)
        let clamped = min(max(0, seconds), upper)
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func normalizeTransform(_ transform: CGAffineTransform, for baseSize: CGSize) -> (CGAffineTransform, CGSize) {
        let rect = CGRect(origin: .zero, size: baseSize).applying(transform)
        let normalized = transform.translatedBy(x: -rect.minX, y: -rect.minY)
        return (normalized, CGSize(width: rect.width, height: rect.height))
    }

    private func watermarkImage(text: String, fontSize: CGFloat, color: NSColor) -> CGImage? {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: max(80, ceil(textSize.width) + 20), height: max(30, ceil(textSize.height) + 12))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width),
            pixelsHigh: Int(canvas.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            NSColor.clear.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()
            let drawRect = CGRect(x: 10, y: (canvas.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
            (text as NSString).draw(in: drawRect, withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
    
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
        
        // 真实像素裁剪框（ clamp 到可见区域，避免黑边）
        var cropRect = CGRect(
            x: normCropX * vSize.width,
            y: normCropY * vSize.height,
            width: normCropW * vSize.width,
            height: normCropH * vSize.height
        )
        // 确保不越界且尺寸有效
        cropRect.origin.x = max(0, min(cropRect.origin.x, vSize.width - 1))
        cropRect.origin.y = max(0, min(cropRect.origin.y, vSize.height - 1))
        cropRect.size.width = min(cropRect.width, vSize.width - cropRect.origin.x)
        cropRect.size.height = min(cropRect.height, vSize.height - cropRect.origin.y)
        cropRect.size.width = max(1, cropRect.width)
        cropRect.size.height = max(1, cropRect.height)
        cropRect.origin.x = round(cropRect.origin.x)
        cropRect.origin.y = round(cropRect.origin.y)
        cropRect.size.width = round(cropRect.size.width)
        cropRect.size.height = round(cropRect.size.height)
        cropRect.size.width = min(cropRect.size.width, vSize.width - cropRect.origin.x)
        cropRect.size.height = min(cropRect.size.height, vSize.height - cropRect.origin.y)
        
        let textsToRender = textItems.map { item in
            var normalized = item
            normalized.text = normalizeOverlayText(item.text)
            return normalized
        }
        let flipH = isFlippedHorizontal
        let flipV = isFlippedVertical
        let speed = playbackSpeed

        // #region agent log
        agentDebugLog(
            hypothesisId: "H2_H3",
            location: "ContentView.swift:exportLivePhoto.params",
            message: "export parameters prepared",
            data: [
                "keyframe": keyframeTime.seconds,
                "vW": vSize.width,
                "vH": vSize.height,
                "uiW": uiWidth,
                "uiH": uiHeight,
                "boxW": boxW,
                "boxH": boxH,
                "cropX": cropRect.origin.x,
                "cropY": cropRect.origin.y,
                "cropW": cropRect.width,
                "cropH": cropRect.height,
                "flipH": flipH,
                "flipV": flipV,
                "textCount": textsToRender.count
            ]
        )
        // #endregion
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.executeRenderEngine(asset: asset, keyframeTime: keyframeTime, uuid: uuid, cropRect: cropRect, texts: textsToRender, uiWidth: uiWidth, uiHeight: uiHeight, boxW: boxW, boxH: boxH, cropOffset: cropOffset, flipH: flipH, flipV: flipV, speed: speed)
        }
    }
    
    func executeRenderEngine(asset: AVAsset, keyframeTime: CMTime, uuid: String, cropRect: CGRect, texts: [TextOverlayItem], uiWidth: CGFloat, uiHeight: CGFloat, boxW: CGFloat, boxH: CGFloat, cropOffset: CGSize, flipH: Bool, flipV: Bool, speed: Float) {
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
        let desiredSourceWindow = 3.0 * Double(speed)
        let halfWindow = desiredSourceWindow / 2.0
        
        var startSeconds = max(0, keyframeTime.seconds - halfWindow)
        var endSeconds = min(duration, keyframeTime.seconds + halfWindow)
        
        // 优先保证总窗口达到 desiredSourceWindow：
        // 若靠近结尾，就向前补；若靠近开头，就向后补。
        var currentWindow = endSeconds - startSeconds
        if currentWindow < desiredSourceWindow {
            var missing = desiredSourceWindow - currentWindow
            
            // 先尝试向前补
            let canExtendBackward = startSeconds
            let backwardFill = min(missing, canExtendBackward)
            startSeconds -= backwardFill
            missing -= backwardFill
            
            // 再尝试向后补
            if missing > 0 {
                let canExtendForward = max(0, duration - endSeconds)
                let forwardFill = min(missing, canExtendForward)
                endSeconds += forwardFill
                missing -= forwardFill
            }
            
            // 理论兜底（素材本身不足时会保留实际可用长度）
            currentWindow = endSeconds - startSeconds
            if currentWindow < 0 {
                startSeconds = 0
                endSeconds = min(duration, desiredSourceWindow)
            }
        }
        
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
        
        // 变换：先归一化原视频方向，再应用用户旋转/翻转，最后裁剪平移。
        let naturalSize = assetVideoTrack.naturalSize
        let base = normalizeTransform(assetVideoTrack.preferredTransform, for: naturalSize)
        var userTransform = CGAffineTransform.identity
        let baseW = base.1.width
        let baseH = base.1.height
        
        var userSize = CGSize(width: baseW, height: baseH)
        
        if flipH {
            userTransform = userTransform
                .translatedBy(x: userSize.width, y: 0)
                .scaledBy(x: -1, y: 1)
        }
        if flipV {
            userTransform = userTransform
                .translatedBy(x: 0, y: userSize.height)
                .scaledBy(x: 1, y: -1)
        }
        let flipped = normalizeTransform(userTransform, for: CGSize(width: baseW, height: baseH))
        userTransform = flipped.0
        userSize = flipped.1
        
        var transform = base.0.concatenating(userTransform)
        transform = transform.translatedBy(x: -cropRect.origin.x, y: -cropRect.origin.y)

        // #region agent log
        agentDebugLog(
            hypothesisId: "H3",
            location: "ContentView.swift:executeRenderEngine.transform",
            message: "final video transform computed",
            data: [
                "renderW": cropRect.width,
                "renderH": cropRect.height,
                "tx": transform.tx,
                "ty": transform.ty,
                "a": transform.a,
                "b": transform.b,
                "c": transform.c,
                "d": transform.d
            ]
        )
        // #endregion
        
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // 文字烧录：UI 坐标 -> 裁剪框内坐标 -> 输出像素（与预览所见一致）
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: cropRect.size)
        parentLayer.isGeometryFlipped = false
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: cropRect.size)
        parentLayer.addSublayer(videoLayer)
        
        let scaleX = cropRect.width / boxW
        let scaleY = cropRect.height / boxH
        let cropBoxLeft = uiWidth / 2 - boxW / 2 + cropOffset.width
        let cropBoxTop = uiHeight / 2 - boxH / 2 + cropOffset.height

        // #region agent log
        agentDebugLog(
            hypothesisId: "H2",
            location: "ContentView.swift:executeRenderEngine.text.mapping.base",
            message: "text mapping base values",
            data: [
                "scaleX": scaleX,
                "scaleY": scaleY,
                "cropBoxLeft": cropBoxLeft,
                "cropBoxTop": cropBoxTop,
                "textCount": texts.count
            ]
        )
        // #endregion
        
        for item in texts {
            if item.text.isEmpty { continue }
            // 文字中心在 UI 中为 (uiWidth/2 + offset.width, uiHeight/2 + offset.height)
            // 转为裁剪框内坐标（左上为原点）
            let safeBoxW = max(boxW, 1)
            let safeBoxH = max(boxH, 1)
            let localX = (uiWidth / 2 + item.offset.width) - cropBoxLeft
            let localY = (uiHeight / 2 + item.offset.height) - cropBoxTop
            let normalizedX = min(max(localX / safeBoxW, 0), 1)
            let normalizedY = min(max(localY / safeBoxH, 0), 1)
            let outX = normalizedX * cropRect.width
            let outY = normalizedY * cropRect.height
            let fontSizeOut = item.fontSize * min(scaleX, scaleY) * item.scale
            let textColor = NSColor(item.color)
            let finalFontSize = max(12, fontSizeOut)
            if let textImage = watermarkImage(text: item.text, fontSize: finalFontSize, color: textColor) {
                let imageLayer = CALayer()
                let imageSize = CGSize(width: textImage.width, height: textImage.height)
                let yInCA = cropRect.height - outY - imageSize.height / 2
                imageLayer.frame = CGRect(
                    x: outX - imageSize.width / 2,
                    y: yInCA,
                    width: imageSize.width,
                    height: imageSize.height
                )
                imageLayer.contents = textImage
                imageLayer.contentsScale = 2.0
                imageLayer.shadowOpacity = 0.35
                imageLayer.shadowRadius = 1.5
                imageLayer.shadowOffset = CGSize(width: 0, height: 1)
                imageLayer.shadowColor = NSColor.black.cgColor
                parentLayer.addSublayer(imageLayer)
            }

            // #region agent log
            agentDebugLog(
                hypothesisId: "H2",
                location: "ContentView.swift:executeRenderEngine.text.frame",
                message: "text layer frame computed",
                data: [
                    "text": item.text,
                    "offsetX": item.offset.width,
                    "offsetY": item.offset.height,
                    "outX": outX,
                    "outY": outY,
                    "fontSize": finalFontSize
                ]
            )
            // #endregion
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
            // #region agent log
            agentDebugLog(
                hypothesisId: "H3",
                location: "ContentView.swift:executeRenderEngine.export.fail",
                message: "export failed",
                data: ["status": exportSession.status.rawValue, "error": exportSession.error?.localizedDescription ?? "nil"]
            )
            // #endregion
            DispatchQueue.main.async { self.isExporting = false; self.statusMessage = "❌ 渲染失败: \(exportSession.error?.localizedDescription ?? "")" }
            return
        }

        // #region agent log
        agentDebugLog(
            hypothesisId: "H3",
            location: "ContentView.swift:executeRenderEngine.export.success",
            message: "export completed",
            data: ["status": exportSession.status.rawValue]
        )
        // #endregion
        
        DispatchQueue.main.async { self.statusMessage = "⏳ 渲染完成，正在写入相册..." }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset(); req.addResource(with: .photo, fileURL: imageURL, options: nil); req.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        }) { success, err in
            DispatchQueue.main.async {
                self.isExporting = false; if success { self.statusMessage = "✅ 导出成功！快去图库看看吧~" } else { self.statusMessage = "❌ 写入失败" }
            }
        }
    }
}

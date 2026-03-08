# LivePhotoCreator

一款 macOS 桌面应用，可将视频导入并渲染导出为 **Live Photo（实况照片）**，支持裁剪、旋转、翻转与文字叠加，最终写入系统相册。

## 功能概览

- **视频导入**：支持常见视频格式（如 .mov、.mp4 等），通过文件选择器或点击画板区导入
- **Live Photo 导出**：以当前播放位置为关键帧，截取前后约 3 秒片段，生成配对的关键帧图片与短视频，并写入相册（含 Content Identifier 元数据）
- **画面调整**
  - **裁剪比例**：原比例、1:1、16:9、9:16、4:3、3:4
  - **裁剪框**：拖拽框体移动位置，拖拽右下角黄色锚点缩放
  - **方向**：旋转 90°、水平翻转、垂直翻转
- **播放控制**：播放/暂停、倍速（0.5x / 1x / 1.5x / 2x）、音量
- **文字叠加**：添加多条文字，可拖拽定位、修改内容、颜色与字号，支持删除

## 系统要求

- **macOS** 26.2 及以上
- **Xcode** 26.3（用于构建）
- **Swift** 5.0

## 项目结构

```
LivePhotoCreator/
├── LivePhotoCreatorApp.swift   # 应用入口
├── ContentView.swift           # 主界面：画板、播控、裁剪/旋转/文字、导出逻辑
├── Assets.xcassets/           # 图标与配色
└── LivePhotoCreator.xcodeproj # Xcode 工程
```

## 构建与运行

1. 用 Xcode 打开 `LivePhotoCreator.xcodeproj`
2. 选择目标 **LivePhotoCreator**，设备选 **My Mac**
3. `Cmd + R` 运行

首次运行若需写入相册，请按系统提示授予 **照片库** 访问权限；文件访问通过“用户选择的文件”权限，在导入/导出时由系统弹窗授权。

## 使用说明

1. **导入视频**：未加载视频时，在左侧画板点击「点击选择视频文件」，或通过菜单/系统支持的方式选择视频文件
2. **调整画面**：在右侧「画面调整」中选择裁剪比例；在画板上拖拽黄色框移动、拖拽右下角锚点缩放；使用「旋转」「水平」「垂直」调整方向
3. **添加文字**：在「添加文本」中点击 + 添加文字，在画板上拖拽文字定位；选中某条文字后可改内容、颜色、字号或删除
4. **选择关键帧**：拖动播放进度到想要作为 Live Photo 封面的那一帧（或保持默认）
5. **导出**：点击「渲染导出 Live Photo」，等待渲染与写入相册；成功后会提示「魔法大成功！…」

导出的 Live Photo 会出现在系统「照片」应用中，长按即可播放实况片段。

## 技术说明

- **渲染管线**：使用 `AVMutableComposition` 截取片段并做变速，`AVMutableVideoComposition` 做旋转、翻转与裁剪的变换，`AVVideoCompositionCoreAnimationTool` 烧录文字图层；关键帧通过 `AVAssetImageGenerator` + 同一 `videoComposition` 生成，保证与视频一致
- **Live Photo 格式**：关键帧存为带 Apple Maker Note（Content Identifier）的 JPEG，短视频为带同名 Content Identifier 元数据的 MOV，通过 `PHAssetCreationRequest` 的 `addResource(with: .photo)` 与 `addResource(with: .pairedVideo)` 写入相册
- **权限**：App Sandbox 开启，需「用户选择的文件」读写与照片库写入；`NSPhotoLibraryUsageDescription` 为「需要访问相册以保存实况图」

## 许可证与作者

- 作者：Bill Zhang  
- 创建日期：2026/3/8  

---

**提示**：导出前请确认已选择好关键帧位置、裁剪与文字，渲染时间取决于片段长度与分辨率。

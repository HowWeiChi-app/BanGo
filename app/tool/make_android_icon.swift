// 產生 Android 的全畫幅圖示（adaptive icon 的整張圖層）。
// Android 的圖層是 108dp，桌面只露出中間約 72dp，所以 iPhone 的圖示放在中間 2/3，
// 外圈用圖示最邊緣的像素往外延伸：不管桌面把圖示裁成圓形還是方形，都不會露出白邊。
// 用法（在 app 資料夾）：swiftc -O tool/make_android_icon.swift -o /tmp/make-android-icon && /tmp/make-android-icon ../ios/HSNUNotice/Assets.xcassets/AppIcon.appiconset/AppIcon.png tool/icon
import AppKit

let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = source.width, h = source.height

for (name, size) in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)] {
    let n = CGFloat(size), m = n / 6, icon = n * 2 / 3
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let c = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    c.interpolationQuality = .high
    func strip(_ crop: CGRect, to rect: CGRect) { c.draw(source.cropping(to: crop)!, in: rect) }
    // CGImage 的裁切座標 y 往下，畫布的 y 往上
    strip(CGRect(x: 0, y: h - 2, width: w, height: 1), to: CGRect(x: 0, y: 0, width: n, height: m + 1))              // 下
    strip(CGRect(x: 0, y: 1, width: w, height: 1), to: CGRect(x: 0, y: n - m - 1, width: n, height: m + 1))          // 上
    strip(CGRect(x: 1, y: 0, width: 1, height: h), to: CGRect(x: 0, y: m, width: m + 1, height: icon))               // 左
    strip(CGRect(x: w - 2, y: 0, width: 1, height: h), to: CGRect(x: n - m - 1, y: m, width: m + 1, height: icon))   // 右
    c.draw(source, in: CGRect(x: m, y: m, width: icon, height: icon))
    let dir = "\(args[2])/mipmap-\(name)"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/ic_launcher_foreground.png"))
}

// App 圖示產生器：經典配色的深色紙張底、一張米白公告單、右上角黃色通知圓點。輸出 1024×1024 PNG。
import AppKit
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let c = ctx.cgContext
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r/255, green: g/255, blue: b/255, alpha: a) }
// 背景：經典深色紙張，上亮下暗
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(46,44,41), rgb(24,23,21)] as CFArray, locations: [0,1])!
c.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
// 公告單（稍微傾斜）
c.saveGState()
c.translateBy(x: S/2, y: S/2 - 10)
c.rotate(by: -5 * .pi / 180)
let sheet = CGRect(x: -270, y: -330, width: 540, height: 660)
c.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0,0,0,0.55))
c.addPath(CGPath(roundedRect: sheet, cornerWidth: 56, cornerHeight: 56, transform: nil))
c.setFillColor(rgb(245,240,230)); c.fillPath()
c.setShadow(offset: .zero, blur: 0, color: nil)
// 標題粗線 + 內文細線
func bar(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
    c.addPath(CGPath(roundedRect: CGRect(x: -190, y: y, width: w, height: h), cornerWidth: h/2, cornerHeight: h/2, transform: nil))
    c.setFillColor(col); c.fillPath()
}
bar(170, 300, 56, rgb(40,38,35))
bar(60, 380, 30, rgb(160,154,145))
bar(0, 380, 30, rgb(160,154,145))
bar(-60, 330, 30, rgb(160,154,145))
bar(-120, 380, 30, rgb(160,154,145))
bar(-180, 240, 30, rgb(160,154,145))
c.restoreGState()
// 右上角黃色通知圓點（經典深色主色 255,198,0），外圈一圈背景色隔開
let dot = CGPoint(x: S/2 + 245, y: S/2 + 290)
c.setFillColor(rgb(30,29,27)); c.fillEllipse(in: CGRect(x: dot.x-100, y: dot.y-100, width: 200, height: 200))
c.setFillColor(rgb(255,198,0)); c.fillEllipse(in: CGRect(x: dot.x-80, y: dot.y-80, width: 160, height: 160))
NSGraphicsContext.restoreGraphicsState()
// 用法：swiftc -O make-icon.swift -o /tmp/make-icon && /tmp/make-icon BanGo/Assets.xcassets/AppIcon.appiconset/AppIcon.png
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

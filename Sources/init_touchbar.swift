import Foundation

// ─── Touch Bar 初始化脚本 ─────────────────────────────────────────────────────
// 加载 CoreBrightness 私有框架并初始化 Touch Bar 子系统。
// 执行一次后，app 即可通过 BrightnessSystemClient 正常访问 Touch Bar。

let TOUCHBAR_DISPLAY_ID: UInt32 = 3

// 1) 加载 CoreBrightness 框架
guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil else {
    fputs("Error: 无法加载 CoreBrightness.framework\n", stderr)
    exit(1)
}

// 2) 获取 BrightnessSystemClient 类
guard let BSCClass = NSClassFromString("BrightnessSystemClient") as? NSObject.Type else {
    fputs("Error: BrightnessSystemClient 类未找到\n", stderr)
    exit(1)
}

let bsc = BSCClass.init()

// 3) 验证必要的私有 API 方法可用
let sel3 = NSSelectorFromString("setProperty:withKey:andDisplay:")
guard bsc.responds(to: sel3) else {
    fputs("Error: setProperty:withKey:andDisplay: 不可用\n", stderr)
    exit(1)
}

let imp3 = bsc.method(for: sel3)
typealias SetFunc3 = @convention(c) (NSObject, Selector, AnyObject, NSString, UInt32) -> Bool
let setFn3 = unsafeBitCast(imp3, to: SetFunc3.self)

// 4) 验证读取 API 可用
let copySel = NSSelectorFromString("copyPropertyForKey:andDisplay:")
guard bsc.responds(to: copySel) else {
    fputs("Error: copyPropertyForKey:andDisplay: 不可用\n", stderr)
    exit(1)
}
let copyImp = bsc.method(for: copySel)
typealias CopyFunc = @convention(c) (NSObject, Selector, NSString, UInt32) -> AnyObject?
let copyFn = unsafeBitCast(copyImp, to: CopyFunc.self)

// 5) 关闭 Touch Bar 自动亮度（防止系统覆盖手动设置）
_ = setFn3(bsc, sel3, 0 as NSNumber, "DisplayBrightnessAuto" as NSString, TOUCHBAR_DISPLAY_ID)

// 6) 智能亮度初始化：读取当前亮度，只在异常值时才设置默认值
var currentBrightness: Float?
if let val = copyFn(bsc, copySel, "DisplayBrightness" as NSString, TOUCHBAR_DISPLAY_ID) {
    if let num = val as? NSNumber {
        currentBrightness = num.floatValue
    } else if let str = val as? String, let num = Float(str) {
        currentBrightness = num
    }
}

if let current = currentBrightness {
    print("当前 Touch Bar 亮度: \(current)")
    // 只在异常值（接近 0 或 1）时才设置默认值
    // 这些值通常是系统重置后的默认状态
    if current < 0.01 || current > 0.99 {
        print("亮度异常（\(current)），设置为默认值 50%")
        _ = setFn3(bsc, sel3, 0.5 as NSNumber, "DisplayBrightness" as NSString, TOUCHBAR_DISPLAY_ID)
    } else {
        print("亮度正常，保持用户设置")
    }
} else {
    print("无法读取亮度，设置为默认值 50%")
    _ = setFn3(bsc, sel3, 0.5 as NSNumber, "DisplayBrightness" as NSString, TOUCHBAR_DISPLAY_ID)
}

// 7) 关闭全局自动亮度
let setSel = NSSelectorFromString("setProperty:forKey:")
let setImp = bsc.method(for: setSel)
typealias SetFunc = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Bool
let setFn = unsafeBitCast(setImp, to: SetFunc.self)
_ = setFn(bsc, setSel, 0 as NSNumber, "DisplayBrightnessAuto" as NSString)

// 8) 最终验证
if let val = copyFn(bsc, copySel, "DisplayBrightness" as NSString, TOUCHBAR_DISPLAY_ID) {
    print("Touch Bar 亮度初始化完成，当前值: \(val)")
} else {
    fputs("Warning: 无法读取 Touch Bar 亮度（但设置可能已生效）\n", stderr)
}

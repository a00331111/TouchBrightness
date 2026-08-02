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

// 6) 从 ~/.tbinfo 读取用户设定的亮度值，强制设置
// LaunchDaemon 以 root 运行时，通过命令行参数传入用户 home 路径；
// 手动执行时回退到 getpwuid（普通用户下正确）。
let home: String
if CommandLine.arguments.count > 1 {
    home = CommandLine.arguments[1]
} else {
    home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
}
let tbinfoPath = home + "/.tbinfo"
var targetBrightness: Float = 0.5  // 默认值

if let data = FileManager.default.contents(atPath: tbinfoPath),
   let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
   let val = Float(str) {
    targetBrightness = val
    print("从 .tbinfo 读取亮度: \(targetBrightness)")
} else {
    print(".tbinfo 不存在或无法解析，使用默认值 0.5")
}

_ = setFn3(bsc, sel3, targetBrightness as NSNumber, "DisplayBrightness" as NSString, TOUCHBAR_DISPLAY_ID)

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

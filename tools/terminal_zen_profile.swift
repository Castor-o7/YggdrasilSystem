// Make the "Yggdrasil" Terminal profile: the user's default profile with a
// fully transparent background and no blur, so in zen the text sits on
// the void. Writes the .terminal file given as the argument; `open`
// imports it into Terminal.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Yggdrasil.terminal"
let prefs = UserDefaults(suiteName: "com.apple.Terminal")!
let defaultName = prefs.string(forKey: "Default Window Settings") ?? "Basic"
guard let all = prefs.dictionary(forKey: "Window Settings"),
      var profile = all[defaultName] as? [String: Any] else {
    FileHandle.standardError.write("no profile named \(defaultName)\n".data(using: .utf8)!)
    exit(1)
}

func archived(_ c: NSColor) -> Data {
    return try! NSKeyedArchiver.archivedData(withRootObject: c, requiringSecureCoding: false)
}
func unarchived(_ d: Data) -> NSColor? {
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: d)
}

var bg = NSColor.black
if let d = profile["BackgroundColor"] as? Data, let c = unarchived(d) { bg = c }
let rgb = bg.usingColorSpace(.sRGB) ?? bg
profile["BackgroundColor"] = archived(NSColor(srgbRed: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: 0.0))
profile["BackgroundBlur"] = 0.0
profile["BackgroundSettingsForInactiveWindows"] = false
profile["name"] = "Yggdrasil"
profile["type"] = "Window Settings"
profile["ProfileCurrentVersion"] = 2.07

let data = try! PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) from profile \(defaultName)")

// Verify the decoded ICNS pixels, not just its header or representation sizes.
import AppKit

func fail(_ message: String) -> Never {
    fputs("Icon verification failed: \(message)\n", stderr)
    exit(1)
}
func run(_ executable: String, _ arguments: [String]) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 { fail("\(executable) exited \(task.terminationStatus)") }
}
func pixels(_ url: URL, _ size: Int) throws -> [UInt8] {
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
          bitmap.pixelsWide == size, bitmap.pixelsHigh == size,
          let image = bitmap.cgImage else { fail("Invalid \(size)px image: \(url.lastPathComponent)") }
    var data = [UInt8](repeating: 0, count: size * size * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return data
}
if CommandLine.arguments.count != 3 { fail("Usage: check_icons.swift icon.icns master.png") }
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("gooswan-icon-check-" + UUID().uuidString)
do {
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let iconset = temp.appendingPathComponent("Gooswan.iconset")
    try run("/usr/bin/iconutil", ["-c", "iconset", CommandLine.arguments[1], "-o", iconset.path])
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let resolution = size * scale
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            let decoded = iconset.appendingPathComponent(name)
            let reference = temp.appendingPathComponent("reference-\(resolution).png")
            try run("/usr/bin/sips", ["-z", "\(resolution)", "\(resolution)", CommandLine.arguments[2], "--out", reference.path])
            let actual = try pixels(decoded, resolution)
            let expected = try pixels(reference, resolution)
            let error = zip(actual, expected).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            let mean = Double(error) / Double(actual.count * 255)
            // Allow color-space / alpha rounding, but reject misdecoded payloads.
            if mean > 0.025 { fail("\(name) differs from the master (mean error \(mean))") }
        }
    }
    print("ICNS: all 10 standard/Retina representations match the master")
} catch { fail(error.localizedDescription) }

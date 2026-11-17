// Finalize the generated PNG's alpha for native icon export. RGB is unchanged.
import AppKit

if CommandLine.arguments.count != 3 {
    fputs("Usage: normalize_icon_alpha.swift input.png output.png\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSBitmapImageRep(data: try Data(contentsOf: input)),
      image.hasAlpha, image.bitsPerSample == 8, image.samplesPerPixel == 4,
      !image.isPlanar, let pixels = image.bitmapData else {
    fputs("Expected an 8-bit RGBA PNG\n", stderr)
    exit(1)
}
// Image generation leaves 1–3/255-alpha flecks in otherwise empty areas.
// Remove that near-transparent noise and make nearly opaque interiors opaque.
// Keep the intermediate edge alpha values for smooth antialiasing.
let alphaFirst = image.bitmapFormat.contains(.alphaFirst)
let nonpremultiplied = image.bitmapFormat.contains(.alphaNonpremultiplied)
let alphaIndex = alphaFirst ? 0 : 3
for y in 0..<image.pixelsHigh {
    for x in 0..<image.pixelsWide {
        let offset = y * image.bytesPerRow + x * 4
        let oldAlpha = Int(pixels[offset + alphaIndex])
        let newAlpha = oldAlpha <= 16 ? 0 : (oldAlpha >= 239 ? 255 : oldAlpha)
        if !nonpremultiplied && oldAlpha != 0 && newAlpha != oldAlpha {
            for channel in 0..<4 where channel != alphaIndex {
                pixels[offset + channel] = UInt8(min(255, (Int(pixels[offset + channel]) * newAlpha + oldAlpha / 2) / oldAlpha))
            }
        }
        pixels[offset + alphaIndex] = UInt8(newAlpha)
        if newAlpha == 0 {
            for channel in 0..<4 where channel != alphaIndex { pixels[offset + channel] = 0 }
        }
    }
}
let corners = [(0, 0), (image.pixelsWide - 1, 0),
               (0, image.pixelsHigh - 1), (image.pixelsWide - 1, image.pixelsHigh - 1)]
guard corners.allSatisfy({ pixels[$0.1 * image.bytesPerRow + $0.0 * 4 + alphaIndex] == 0 }) else {
    fputs("Icon exterior corners must be transparent; refusing an opaque matte\n", stderr)
    exit(1)
}
guard let data = image.representation(using: .png, properties: [:]) else {
    fputs("Could not encode RGBA PNG\n", stderr)
    exit(1)
}
try data.write(to: output, options: .atomic)

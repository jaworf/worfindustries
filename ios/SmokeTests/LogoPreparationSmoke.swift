import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main enum LogoPreparationSmoke {
    static func main() throws {
        let context = CGContext(data: nil, width: 6000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 0.5))
        context.fill(CGRect(x: 0,y: 0,width: 6000,height: 1000))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        precondition(bytes.length < 300_000, "Fixture must show that small byte size can still exceed the old dimension limit")
        let output = try ChurchLogoImage.prepare(bytes as Data)
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(output as CFData, nil)!, 0, nil)!
        precondition(image.width == 1024 && image.height <= 1024)
        precondition(output.count <= ChurchLogoImage.maximumBytes)
        precondition(image.alphaInfo != .none, "PNG transparency must remain available")
        do { _ = try ChurchLogoImage.prepare(Data()); preconditionFailure("Empty image accepted") } catch ChurchLogoImage.PreparationError.unreadable { }
        do { _ = try ChurchLogoImage.prepare(Data("Not an image".utf8)); preconditionFailure("Invalid image accepted") } catch ChurchLogoImage.PreparationError.unreadable { }
        do { _ = try ChurchLogoImage.prepare(Data(repeating: 0, count: 2_097_153)); preconditionFailure("Oversize image accepted") } catch ChurchLogoImage.PreparationError.tooLarge { }
        if CommandLine.arguments.count > 1 {
            let photo = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let prepared = try ChurchLogoImage.prepare(photo)
            precondition(prepared.count <= ChurchLogoImage.maximumBytes)
            let supplied = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(prepared as CFData, nil)!, 0, nil)!
            precondition(supplied.width <= 1024 && supplied.height <= 1024)
            if CommandLine.arguments.count > 2 { try prepared.write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
            print("Supplied image prepared: \(photo.count) bytes → \(prepared.count) bytes; \(supplied.width)×\(supplied.height) pixels.")
        }
        print("Logo preparation passed: \(bytes.length)-byte 6000px PNG resized to \(image.width)×\(image.height), invalid and oversize input rejected.")
    }
}

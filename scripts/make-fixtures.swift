import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/Fixtures")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let samples: [(String, Int, Int)] = [("01 Alpine Lake.jpg",6000,4000),("02 Sunset.png",1600,1000),("03 Portrait.jpg",1200,1800),("04 Small.png",240,160),("10 Panorama.jpg",8000,1000)]
for (index, sample) in samples.enumerated() {
    let (name,w,h) = sample
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = [CGColor(red:0.09 + Double(index)*0.08,green:0.19,blue:0.3,alpha:1),CGColor(red:0.42,green:0.68,blue:0.71,alpha:1)] as CFArray
    let gradient = CGGradient(colorsSpace:space,colors:colors,locations:[0,1])!
    context.drawLinearGradient(gradient,start:CGPoint(x:0,y:h),end:.zero,options:[])
    context.setFillColor(CGColor(red:0.94,green:0.8,blue:0.48,alpha:1))
    context.fillEllipse(in:CGRect(x:Double(w)*0.7,y:Double(h)*0.7,width:Double(w)*0.09,height:Double(w)*0.09))
    for layer in 0..<3 {
        let offset = Double(layer)*0.13
        context.beginPath();context.move(to:.zero)
        context.addLine(to:CGPoint(x:0,y:Double(h)*(0.3+offset)))
        context.addLine(to:CGPoint(x:Double(w)*0.24,y:Double(h)*(0.65-offset)))
        context.addLine(to:CGPoint(x:Double(w)*0.4,y:Double(h)*(0.38-offset)))
        context.addLine(to:CGPoint(x:Double(w)*0.64,y:Double(h)*(0.72-offset)))
        context.addLine(to:CGPoint(x:Double(w),y:Double(h)*(0.3+offset)))
        context.addLine(to:CGPoint(x:w,y:0));context.closePath()
        context.setFillColor(CGColor(red:0.07 + Double(layer)*0.04,green:0.18 + Double(layer)*0.05,blue:0.23 + Double(layer)*0.04,alpha:1));context.fillPath()
    }
    let url = destination.appendingPathComponent(name)
    let type = name.hasSuffix("png") ? UTType.png : UTType.jpeg
    let output = CGImageDestinationCreateWithURL(url as CFURL,type.identifier as CFString,1,nil)!
    let props:[CFString:Any] = [kCGImageDestinationLossyCompressionQuality:0.9,kCGImagePropertyExifDictionary:[kCGImagePropertyExifDateTimeOriginal:"2026:10:22 12:00:00",kCGImagePropertyExifFNumber:5.6,kCGImagePropertyExifExposureTime:0.004],kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:37.5665,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:126.978,kCGImagePropertyGPSLongitudeRef:"E"]]
    CGImageDestinationAddImage(output,context.makeImage()!,props as CFDictionary)
    guard CGImageDestinationFinalize(output) else { fatalError("Fixture encoding failed") }
}
try FileManager.default.createDirectory(at:destination.appendingPathComponent("Empty"),withIntermediateDirectories:true)
try Data("broken image fixture".utf8).write(to:destination.appendingPathComponent("99 Corrupt.jpg"))
print(destination.path)

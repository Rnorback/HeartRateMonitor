//
//  HeartRateDetectionModel.swift
//  HeartRateMonitor
//
//  Created by Rob Norback on 12/16/16.
//  Copyright © 2016 Norback Solutions, LLC. All rights reserved.
//

import UIKit
import AVFoundation

protocol HeartRateDetectionModelDelegate: class {
    func heartRateStart()
    func heartRateUpdate(bpm:Int, atTime seconds:Int)
    func heartRateEnd()
    func heartRateRawData(data:CGFloat)
}

class HeartRateDetectionModel: NSObject {
    
    let framesPerSecond:Float = 30
    let seconds:Float = 30
    static var count:Int = 0
    weak var delegate:HeartRateDetectionModelDelegate?
    var session:AVCaptureSession = AVCaptureSession()
    var dataPointsHue:[CGFloat] = []
}

//MARK: - Data Collection
extension HeartRateDetectionModel {
    
    func startDetection() {
        
        dataPointsHue = []
        session = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPresetLow
        
        //get the back camera
        guard let backCamera = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) else
        {
            return
        }
        
        //add backCamera as an input device for this session
        do
        {
            let input = try AVCaptureDeviceInput(device: backCamera)
            session.addInput(input)
        }
        catch
        {
            print(error)
        }
        
        //find the max frame rate we can get from the given device
        var currentFormat:AVCaptureDeviceFormat?
        
        for format in backCamera.formats as! [AVCaptureDeviceFormat]
        {
            let ranges = format.videoSupportedFrameRateRanges!
            let frameRates = ranges[0] as! AVFrameRateRange
            
            //find the lowest resolution format at the frame rate we want.
            if Float(frameRates.maxFrameRate) == framesPerSecond && (currentFormat == nil || (CMVideoFormatDescriptionGetDimensions(format.formatDescription).width < CMVideoFormatDescriptionGetDimensions(currentFormat!.formatDescription).width && CMVideoFormatDescriptionGetDimensions(format.formatDescription).height < CMVideoFormatDescriptionGetDimensions(currentFormat!.formatDescription).height))
            {
                currentFormat = format;
            }
        }
        
        //tell the device to use the max frame rate.
        try! backCamera.lockForConfiguration()
        backCamera.torchMode = .on
        backCamera.activeFormat = currentFormat
        backCamera.activeVideoMinFrameDuration = CMTimeMake(1, Int32(framesPerSecond))
        backCamera.activeVideoMaxFrameDuration = CMTimeMake(1, Int32(framesPerSecond))
        backCamera.unlockForConfiguration()
        
        //set the output
        let videoOutput:AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
        
        //create a queue to run the capture on
        let captureQueue = DispatchQueue(label: "captureQueue")
        
        // setup our delegate
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        //configure the pixel format
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable : Int(kCVPixelFormatType_32BGRA)]
        
        videoOutput.alwaysDiscardsLateVideoFrames = false
        
        session.addOutput(videoOutput)
        
        //start the video session
        session.startRunning()
        
        if self.delegate != nil
        {
            DispatchQueue.main.async {
                self.delegate!.heartRateStart()
            }
        }
    }
    
    func stopDetection() {
        session.stopRunning()
        
        if self.delegate != nil
        {
            DispatchQueue.main.async {
                self.delegate!.heartRateEnd()
            }
        }
    }
}

//MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension HeartRateDetectionModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        HeartRateDetectionModel.count += 1
        
        // only run if we're not already processing an image
        // this is the image buffer
        let cvimgRef = CMSampleBufferGetImageBuffer(sampleBuffer)!

        // Lock the image buffer
        CVPixelBufferLockBaseAddress(cvimgRef,CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        // access the data
        let width = CVPixelBufferGetWidth(cvimgRef)
        let height = CVPixelBufferGetHeight(cvimgRef)
        
        // get the raw image bytes
        let baseAddress = CVPixelBufferGetBaseAddress(cvimgRef)!
        var buf = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bprow = CVPixelBufferGetBytesPerRow(cvimgRef)
        var r:Float = 0, g:Float = 0, b:Float = 0
        
        let widthScaleFactor:Int = width/192
        let heightScaleFactor:Int = height/144
        
        //get the average rgb values for the entire image
        for _ in stride(from: 0, to: height, by: heightScaleFactor)
        {
            for x in stride(from: 0, to: width*4, by: widthScaleFactor*4)
            {
                b += Float(buf[x])
                g += Float(buf[x+1])
                r += Float(buf[x+2])
            }
            buf += bprow
        }
        r /= Float(255 * width * height) / Float(widthScaleFactor) / Float(heightScaleFactor)
        g /= Float(255 * width * height) / Float(widthScaleFactor) / Float(heightScaleFactor)
        b /= Float(255 * width * height) / Float(widthScaleFactor) / Float(heightScaleFactor)
        
        // The hue value is the most expressive when looking for heart beats.
        // Here we convert our rgb values in hsv and continue with the h value.
        let color:UIColor = UIColor(colorLiteralRed: r, green: g, blue: b, alpha: 1.0)
        var hue:CGFloat = 0, sat:CGFloat = 0, bright:CGFloat = 0
        color.getHue(&hue, saturation: &sat, brightness: &bright, alpha: nil)
        dataPointsHue.append(hue)
        delegate?.heartRateRawData(data: hue)
        
        // Only send UI updates once a second
        if dataPointsHue.count % Int(framesPerSecond) == 0
        {
            if self.delegate != nil
            {
                let displaySeconds:Float = Float(dataPointsHue.count) / framesPerSecond
                
                let bandpassFilteredItems = butterworthBandpassFilter(inputData: dataPointsHue)
                let smoothedBandpassItems = medianSmoothing(inputData: bandpassFilteredItems)
                let myPeakCount = peakCount(inputData: smoothedBandpassItems)
                
                let secondsPassed:Float = Float(smoothedBandpassItems.count) / framesPerSecond;
                let percentage:Float = secondsPassed / 60;
                let heartRate:Float = Float(myPeakCount) / percentage
                
                DispatchQueue.main.async {
                    self.delegate!.heartRateUpdate(bpm: Int(heartRate), atTime: Int(displaySeconds))
                }
            }
        }
        
        // If we have enough data points, start the analysis
        if dataPointsHue.count == Int(seconds * framesPerSecond)
        {
            stopDetection()
        }
        
        // Unlock the image buffer
        CVPixelBufferUnlockBaseAddress(cvimgRef,CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)));
    }
}

//MARK: - Data Processing
extension HeartRateDetectionModel {
    
    func butterworthBandpassFilter(inputData:[CGFloat]) -> [CGFloat] {
        
        let nzeros:Int = 8
        let npoles:Int = 8
        
        //was static, not sure why
        var xv = [CGFloat](repeating: 0.0, count: nzeros+1)
        var yv = [CGFloat](repeating: 0.0, count: npoles+1)
        
        // http://www-users.cs.york.ac.uk/~fisher/cgi-bin/mkfscript
        // Butterworth Bandpass filter
        // 4th order
        // sample rate - varies between possible camera frequencies. Either 30, 60, 120, or 240 FPS
        // corner1 freq. = 0.667 Hz (assuming a minimum heart rate of 40 bpm, 40 beats/60 seconds = 0.667 Hz)
        // corner2 freq. = 4.167 Hz (assuming a maximum heart rate of 250 bpm, 250 beats/60 secods = 4.167 Hz)
        // Bandpass filter was chosen because it removes frequency noise outside of our target range (both higher and lower)
        
        let dGain:CGFloat = 1.232232910e+02
        var outputData:[CGFloat] = []
        
        for number in inputData
        {
            let input = number
            
            xv[0] = xv[1]
            xv[1] = xv[2]
            xv[2] = xv[3]
            xv[3] = xv[4]
            xv[4] = xv[5]
            xv[5] = xv[6]
            xv[6] = xv[7]
            xv[7] = xv[8]
            xv[8] = input / dGain
            yv[0] = yv[1]
            yv[1] = yv[2]
            yv[2] = yv[3]
            yv[3] = yv[4]
            yv[4] = yv[5]
            yv[5] = yv[6]
            yv[6] = yv[7]
            yv[7] = yv[8]
            yv[8] = (xv[0] + xv[8]) - 4 * (xv[2] + xv[6]) + 6 * xv[4]
                + ( -0.1397436053 * yv[0]) + (  1.2948188815 * yv[1])
                + ( -5.4070037946 * yv[2]) + ( 13.2683981280 * yv[3])
                + (-20.9442560520 * yv[4]) + ( 21.7932169160 * yv[5])
                + (-14.5817197500 * yv[6]) + (  5.7161939252 * yv[7])
            
            outputData.append(yv[8])
        }
        
        return outputData;
    }
    
    // Find the peaks in our data - these are the heart beats.
    // At a 30 Hz detection rate, assuming 250 max beats per minute, a peak can't be closer than 7 data points apart.
    func peakCount(inputData:[CGFloat]) -> Int {
        
        if inputData.count == 0
        {
            return 0
        }
        
        var peaks:Int = 0
        var isPeak:Bool = false
        let first:Int = 3
        let last:Int = inputData.count - 3
        var interval:Int = 1

        for i in sequence(first: first, next: {$0 + interval < last ? $0 + interval : nil}) {
            
            isPeak = inputData[i] > 0 &&
                     inputData[i] > inputData[i-1] &&
                     inputData[i] > inputData[i-2] &&
                     inputData[i] > inputData[i-3] &&
                     inputData[i] > inputData[i+1] &&
                     inputData[i] > inputData[i+2] &&
                     inputData[i] > inputData[i+3]
            
            if isPeak
            {
                peaks += 1
                interval = 4
            }
            else
            {
                interval = 1
            }
        }
        
        return peaks
    }
    
    // Smoothed data helps remove outliers that may be caused by interference, finger movement or pressure changes.
    // This will only help with small interference changes.
    // This also helps keep the data more consistent.
    func medianSmoothing(inputData:[CGFloat]) -> [CGFloat] {
        
        var newData:[CGFloat] = []
        
        for i in 0..<inputData.count
        {
            if  i == 0 ||
                i == 1 ||
                i == 2 ||
                i == inputData.count - 1 ||
                i == inputData.count - 2 ||
                i == inputData.count - 3
            {
                newData.append(inputData[i])
            }
            else
            {
                var items = [inputData[i-2],
                             inputData[i-1],
                             inputData[i],
                             inputData[i+1],
                             inputData[i+2]].sorted()
                
                newData.append(items[2])
            }
        }
        
        return newData
    }
}

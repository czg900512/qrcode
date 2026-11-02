//
//  QRScannerOrientation.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRScannerOrientation.h"

@implementation QRScannerOrientation

#pragma mark - Public Methods

+ (AVCaptureVideoOrientation)videoOrientationForInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
                                                            fallback:(AVCaptureVideoOrientation)fallback {
    switch (interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIInterfaceOrientationUnknown:
        default:
            return fallback;
    }
}

+ (CGImagePropertyOrientation)visionOrientationForVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    switch (videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            return kCGImagePropertyOrientationRight;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            return kCGImagePropertyOrientationLeft;
        case AVCaptureVideoOrientationLandscapeLeft:
            return kCGImagePropertyOrientationDown;
        case AVCaptureVideoOrientationLandscapeRight:
            return kCGImagePropertyOrientationUp;
        default:
            return kCGImagePropertyOrientationRight;
    }
}

@end

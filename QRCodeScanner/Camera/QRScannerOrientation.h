//
//  QRScannerOrientation.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 把手机朝向，换成相机画面方向，以及找码时用的图片方向
@interface QRScannerOrientation : NSObject

/**
 把界面方向换成相机采集方向。

 @param interfaceOrientation 当前窗口的界面方向
 @param fallback 方向还不明确时，沿用上一次有效的相机方向
 @return 和屏幕显示一致的相机方向
 */
+ (AVCaptureVideoOrientation)videoOrientationForInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
                                                            fallback:(AVCaptureVideoOrientation)fallback;

/**
 把相机方向换成找码用的图片方向。

 后置相机的画面和屏幕方向不是同一个数，这里专门做这层对应。

 @param videoOrientation 当前相机方向
 @return 找码接口需要的图片方向
 */
+ (CGImagePropertyOrientation)visionOrientationForVideoOrientation:(AVCaptureVideoOrientation)videoOrientation;

@end

NS_ASSUME_NONNULL_END

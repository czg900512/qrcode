//
//  QRCodeLocator.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

@class QRScannerPreviewGeometry;

NS_ASSUME_NONNULL_BEGIN

/**
 找二维码在画面里的位置。

 只找框，不读内容。每一帧只找一次，轮流看画面中心、四个角和整幅画面。
 找到后会先跟着上次的位置看几帧；连续找不到时，偶尔把画面稍微变清晰再找。
 它会记住上一帧的进度，所有方法都要在同一条队列里调用。
 */
@interface QRCodeLocator : NSObject

/**
 在一帧相机画面里找二维码框。

 @param sampleBuffer 相机原始画面，不要先把整帧缩小
 @param previewGeometry 主线程记下的预览坐标
 @param visionRectInPreview 这一帧要搜索的预览区域
 @param orientation 当前相机画面的方向
 @return 预览画面上的二维码框。没找到就返回空数组
 */
- (NSArray<NSValue *> *)locateQRCodeRectsInSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                        previewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                                     visionRectInPreview:(CGRect)visionRectInPreview
                                             orientation:(CGImagePropertyOrientation)orientation;

/** 清空上次扫描记住的位置。重新开扫前调用，避免沿用上一轮的搜索进度 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END

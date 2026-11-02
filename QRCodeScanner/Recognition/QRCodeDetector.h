//
//  QRCodeDetector.h
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
 用系统的 Vision 在画面里找二维码框。

 必要时把画面稍微变清晰。坐标换算只用主线程事先记好的预览信息，后台不要直接读预览图层。
 同一次识别请求会被重复使用，所以必须在同一条队列里调用。
 */
@interface QRCodeDetector : NSObject

/**
 在预览画面的一块区域里找二维码框。

 @param sampleBuffer 相机原始画面
 @param previewGeometry 主线程记下的预览坐标
 @param previewRect 这一帧要搜索的区域，用预览画面的坐标
 @param orientation 当前相机画面的方向
 @param imageEnhancementEnabled 这一帧要不要把画面稍微变清晰再找
 @return 预览画面上的二维码框。没找到就返回空数组
 */
- (NSArray<NSValue *> *)detectQRCodeRectsInSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                        previewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                                            previewRect:(CGRect)previewRect
                                            orientation:(CGImagePropertyOrientation)orientation
                               imageEnhancementEnabled:(BOOL)imageEnhancementEnabled;

@end

NS_ASSUME_NONNULL_END

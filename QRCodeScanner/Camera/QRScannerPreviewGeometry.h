//
//  QRScannerPreviewGeometry.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 预览画面和相机坐标的对应关系。

 在主线程从预览图层记下来，之后后台找码只读这份记录，不再碰预览图层。
 */
@interface QRScannerPreviewGeometry : NSObject

/** 记录时预览图层的大小，也是找码能看到的范围 */
@property (nonatomic, assign, readonly) CGRect previewBounds;

/**
 在主线程记下当前预览图层的坐标关系。

 @param previewLayer 相机预览图层
 @return 可用的记录。预览还没有大小，或坐标换不回去时，返回 nil
 */
+ (nullable instancetype)geometryFromPreviewLayer:(AVCaptureVideoPreviewLayer *)previewLayer;

/**
 把预览上的一块区域，换成相机内部使用的坐标。

 @param previewRect 预览画面上的矩形
 @return 相机坐标。和画面没有交集时返回 CGRectZero
 */
- (CGRect)metadataRectForPreviewRect:(CGRect)previewRect;

/**
 把相机内部坐标换回预览画面上的位置。

 @param metadataRect 相机坐标里的矩形
 @return 预览画面上的矩形。换算失败时返回 CGRectZero
 */
- (CGRect)previewRectForMetadataRect:(CGRect)metadataRect;

@end

NS_ASSUME_NONNULL_END

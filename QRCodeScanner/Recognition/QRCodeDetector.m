//
//  QRCodeDetector.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodeDetector.h"
#import "QRScannerPreviewGeometry.h"
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>

/// 补救时只稍微提高清晰度，对比拉太强会把暗处噪点也放大
static const CGFloat kQRCodeEnhancementContrast = 1.08f;
/// 锐化低于系统默认值，避免远处码点阵边缘产生光晕
static const CGFloat kQRCodeEnhancementSharpness = 0.35f;

@interface QRCodeDetector ()

/** 仅检测 QR 位置，不承担业务解码 */
@property (nonatomic, strong) VNDetectBarcodesRequest *barcodeRequest;

/** 视频流复用序列处理器，避免每帧创建请求处理器 */
@property (nonatomic, strong) VNSequenceRequestHandler *sequenceRequestHandler;

/** 连续失败补救使用的对比度滤镜 */
@property (nonatomic, strong) CIFilter *contrastFilter;

/** 连续失败补救使用的锐化滤镜 */
@property (nonatomic, strong) CIFilter *sharpenFilter;

@end

@implementation QRCodeDetector

#pragma mark - Life Cycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _barcodeRequest = [[VNDetectBarcodesRequest alloc] init];
        _barcodeRequest.symbologies = @[VNBarcodeSymbologyQR];
        _barcodeRequest.revision = VNDetectBarcodesRequest.currentRevision;
        _sequenceRequestHandler = [[VNSequenceRequestHandler alloc] init];
        _contrastFilter = [CIFilter filterWithName:@"CIColorControls"];
        _sharpenFilter = [CIFilter filterWithName:@"CISharpenLuminance"];
    }
    return self;
}

#pragma mark - Public Methods

- (NSArray<NSValue *> *)detectQRCodeRectsInSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                        previewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                                            previewRect:(CGRect)previewRect
                                            orientation:(CGImagePropertyOrientation)orientation
                               imageEnhancementEnabled:(BOOL)imageEnhancementEnabled {
    CVPixelBufferRef pixelBuffer = sampleBuffer ? CMSampleBufferGetImageBuffer(sampleBuffer) : NULL;
    if (!pixelBuffer || !previewGeometry || CGRectIsEmpty(previewRect)) {
        return @[];
    }

    CGRect metadataROI = [previewGeometry metadataRectForPreviewRect:previewRect];
    CGRect visionROI = [self visionROIFromMetadataROI:metadataROI orientation:orientation];
    if (CGRectIsEmpty(visionROI) || CGRectIsEmpty(metadataROI)) {
        return @[];
    }

    if (![self performRequestOnPixelBuffer:pixelBuffer
                                    visionROI:visionROI
                                  orientation:orientation
                    imageEnhancementEnabled:imageEnhancementEnabled]) {
        return @[];
    }
    return [self previewRectsFromResultsWithPreviewGeometry:previewGeometry
                                                   orientation:orientation
                                                     visionROI:visionROI
                                    observationIsRelativeToROI:self.barcodeRequest.revision > 1];
}

#pragma mark - Private Methods

/// 平时直接在相机原始画面上找。只有偶尔补救时，才把画面转成图片并稍微变清晰
- (BOOL)performRequestOnPixelBuffer:(CVPixelBufferRef)pixelBuffer
                             visionROI:(CGRect)visionROI
                           orientation:(CGImagePropertyOrientation)orientation
             imageEnhancementEnabled:(BOOL)imageEnhancementEnabled {
    NSError *error = nil;
    self.barcodeRequest.regionOfInterest = visionROI;
    if (!imageEnhancementEnabled) {
        return [self.sequenceRequestHandler performRequests:@[self.barcodeRequest]
                                            onCVPixelBuffer:pixelBuffer
                                                orientation:orientation
                                                      error:&error];
    }

    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CIImage *enhancedImage = [self enhancedImageForBarcode:sourceImage];
    if (!enhancedImage) {
        return NO;
    }
    return [self.sequenceRequestHandler performRequests:@[self.barcodeRequest]
                                              onCIImage:enhancedImage
                                            orientation:orientation
                                                  error:&error];
}

/// 变清晰只在偶尔补救时做，避免每次扫描都把相机画面转成图片
- (CIImage *)enhancedImageForBarcode:(CIImage *)image {
    if (!image) {
        return nil;
    }

    CIImage *enhancedImage = image;
    if (self.contrastFilter) {
        [self.contrastFilter setValue:enhancedImage forKey:kCIInputImageKey];
        [self.contrastFilter setValue:@(kQRCodeEnhancementContrast) forKey:kCIInputContrastKey];
        enhancedImage = self.contrastFilter.outputImage ?: enhancedImage;
    }
    if (self.sharpenFilter) {
        [self.sharpenFilter setValue:enhancedImage forKey:kCIInputImageKey];
        [self.sharpenFilter setValue:@(kQRCodeEnhancementSharpness) forKey:kCIInputSharpnessKey];
        enhancedImage = self.sharpenFilter.outputImage ?: enhancedImage;
    }
    return enhancedImage;
}

/// 较新的系统返回的码框是相对本次搜索区域的，要先还原到整张图，再换到预览坐标
- (NSArray<NSValue *> *)previewRectsFromResultsWithPreviewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                                                          orientation:(CGImagePropertyOrientation)orientation
                                                            visionROI:(CGRect)visionROI
                                           observationIsRelativeToROI:(BOOL)observationIsRelativeToROI {
    NSMutableArray<NSValue *> *previewRects = [NSMutableArray array];
    for (VNObservation *observation in self.barcodeRequest.results) {
        if (![observation isKindOfClass:[VNBarcodeObservation class]]) {
            continue;
        }

        VNBarcodeObservation *barcodeObservation = (VNBarcodeObservation *)observation;
        CGRect fullImageBox = [self fullImageBoxFromObservationBox:barcodeObservation.boundingBox
                                                            visionROI:visionROI
                                           observationIsRelativeToROI:observationIsRelativeToROI];
        CGRect previewRect = [self previewRectFromVisionBox:fullImageBox
                                               previewGeometry:previewGeometry
                                                   orientation:orientation];
        if (!CGRectIsEmpty(previewRect)) {
            [previewRects addObject:[NSValue valueWithCGRect:previewRect]];
        }
    }
    return [previewRects copy];
}

/// 搜索区域里的框要还原到整张图。旧版本系统返回的本来就是整张图坐标
- (CGRect)fullImageBoxFromObservationBox:(CGRect)observationBox
                                  visionROI:(CGRect)visionROI
                 observationIsRelativeToROI:(BOOL)observationIsRelativeToROI {
    if (!observationIsRelativeToROI) {
        return observationBox;
    }

    CGRect fullImageBox = CGRectMake(visionROI.origin.x + observationBox.origin.x * visionROI.size.width,
                                     visionROI.origin.y + observationBox.origin.y * visionROI.size.height,
                                     observationBox.size.width * visionROI.size.width,
                                     observationBox.size.height * visionROI.size.height);
    return CGRectIntersection(fullImageBox, CGRectMake(0.f, 0.f, 1.f, 1.f));
}

/// 系统相机坐标从画面左上角算起，Vision 的搜索区域从旋转后的左下角算起
- (CGRect)visionROIFromMetadataROI:(CGRect)metadataROI
                          orientation:(CGImagePropertyOrientation)orientation {
    CGFloat x = metadataROI.origin.x;
    CGFloat y = metadataROI.origin.y;
    CGFloat width = metadataROI.size.width;
    CGFloat height = metadataROI.size.height;
    CGRect visionROI = CGRectZero;
    switch (orientation) {
        case kCGImagePropertyOrientationRight:
            visionROI = CGRectMake(1.f - y - height, 1.f - x - width, height, width);
            break;
        case kCGImagePropertyOrientationLeft:
            visionROI = CGRectMake(y, x, height, width);
            break;
        case kCGImagePropertyOrientationDown:
            visionROI = CGRectMake(1.f - x - width, y, width, height);
            break;
        case kCGImagePropertyOrientationUp:
        default:
            visionROI = CGRectMake(x, 1.f - y - height, width, height);
            break;
    }
    return CGRectIntersection(visionROI, CGRectMake(0.f, 0.f, 1.f, 1.f));
}

/// Vision 框先逆变换到 Metadata 坐标，再交给几何快照处理 aspectFill
- (CGRect)previewRectFromVisionBox:(CGRect)boundingBox
                      previewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                          orientation:(CGImagePropertyOrientation)orientation {
    if (!previewGeometry) {
        return CGRectZero;
    }
    CGRect orientedTopLeft = CGRectMake(boundingBox.origin.x,
                                        1.f - boundingBox.origin.y - boundingBox.size.height,
                                        boundingBox.size.width,
                                        boundingBox.size.height);
    CGFloat x = orientedTopLeft.origin.x;
    CGFloat y = orientedTopLeft.origin.y;
    CGFloat width = orientedTopLeft.size.width;
    CGFloat height = orientedTopLeft.size.height;
    CGRect metadataRect = CGRectZero;
    switch (orientation) {
        case kCGImagePropertyOrientationRight:
            metadataRect = CGRectMake(y, 1.f - x - width, height, width);
            break;
        case kCGImagePropertyOrientationLeft:
            metadataRect = CGRectMake(1.f - y - height, x, height, width);
            break;
        case kCGImagePropertyOrientationDown:
            metadataRect = CGRectMake(1.f - x - width, 1.f - y - height, width, height);
            break;
        case kCGImagePropertyOrientationUp:
        default:
            metadataRect = orientedTopLeft;
            break;
    }

    CGRect previewRect = [previewGeometry previewRectForMetadataRect:metadataRect];
    return previewRect.size.width >= 1.f && previewRect.size.height >= 1.f
        ? previewRect
        : CGRectZero;
}

@end

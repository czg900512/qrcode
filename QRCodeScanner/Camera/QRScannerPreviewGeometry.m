//
//  QRScannerPreviewGeometry.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRScannerPreviewGeometry.h"

static const CGFloat kQRScannerPreviewGeometryMinDeterminant = 1e-8f;

@interface QRScannerPreviewGeometry ()

/** PreviewLayer 采样时的 bounds */
@property (nonatomic, assign, readwrite) CGRect previewBounds;

/** 预览上的点，换成相机内部坐标 */
@property (nonatomic, assign) CGAffineTransform previewToMetadataTransform;

/** 相机内部坐标，换回预览上的点 */
@property (nonatomic, assign) CGAffineTransform metadataToPreviewTransform;

@end

@implementation QRScannerPreviewGeometry

#pragma mark - Public Methods

+ (instancetype)geometryFromPreviewLayer:(AVCaptureVideoPreviewLayer *)previewLayer {
    if (!previewLayer) {
        return nil;
    }

    CGRect previewBounds = previewLayer.bounds;
    if (CGRectIsEmpty(previewBounds) || previewBounds.size.width < 1.f || previewBounds.size.height < 1.f) {
        return nil;
    }

    CGPoint origin = [previewLayer captureDevicePointOfInterestForPoint:previewBounds.origin];
    CGPoint maxXPoint = [previewLayer captureDevicePointOfInterestForPoint:CGPointMake(CGRectGetMaxX(previewBounds),
                                                                                       CGRectGetMinY(previewBounds))];
    CGPoint maxYPoint = [previewLayer captureDevicePointOfInterestForPoint:CGPointMake(CGRectGetMinX(previewBounds),
                                                                                       CGRectGetMaxY(previewBounds))];

    CGFloat width = previewBounds.size.width;
    CGFloat height = previewBounds.size.height;
    CGAffineTransform previewToMetadata = CGAffineTransformMake((maxXPoint.x - origin.x) / width,
                                                                (maxXPoint.y - origin.y) / width,
                                                                (maxYPoint.x - origin.x) / height,
                                                                (maxYPoint.y - origin.y) / height,
                                                                origin.x,
                                                                origin.y);
    CGFloat determinant = previewToMetadata.a * previewToMetadata.d - previewToMetadata.b * previewToMetadata.c;
    if (fabs(determinant) < kQRScannerPreviewGeometryMinDeterminant) {
        return nil;
    }

    QRScannerPreviewGeometry *geometry = [[QRScannerPreviewGeometry alloc] init];
    geometry.previewBounds = previewBounds;
    geometry.previewToMetadataTransform = previewToMetadata;
    geometry.metadataToPreviewTransform = CGAffineTransformInvert(previewToMetadata);
    return geometry;
}

- (CGRect)metadataRectForPreviewRect:(CGRect)previewRect {
    CGRect metadataRect = [self mappedRectFromRect:previewRect transform:self.previewToMetadataTransform];
    metadataRect = CGRectIntersection(metadataRect, CGRectMake(0.f, 0.f, 1.f, 1.f));
    return CGRectIsNull(metadataRect) ? CGRectZero : metadataRect;
}

- (CGRect)previewRectForMetadataRect:(CGRect)metadataRect {
    return [self mappedRectFromRect:metadataRect transform:self.metadataToPreviewTransform];
}

#pragma mark - Private Methods

/// 将轴对齐矩形的四角变换后取包围盒，覆盖 90° 旋转后的轴交换
- (CGRect)mappedRectFromRect:(CGRect)rect transform:(CGAffineTransform)transform {
    if (CGRectIsEmpty(rect) || CGRectIsNull(rect)) {
        return CGRectZero;
    }

    CGPoint p0 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)), transform);
    CGPoint p1 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)), transform);
    CGPoint p2 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)), transform);
    CGPoint p3 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)), transform);
    CGFloat minX = MIN(MIN(p0.x, p1.x), MIN(p2.x, p3.x));
    CGFloat minY = MIN(MIN(p0.y, p1.y), MIN(p2.y, p3.y));
    CGFloat maxX = MAX(MAX(p0.x, p1.x), MAX(p2.x, p3.x));
    CGFloat maxY = MAX(MAX(p0.y, p1.y), MAX(p2.y, p3.y));
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

@end

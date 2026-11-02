//
//  QRCodeLocator.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodeLocator.h"
#import "QRScannerPreviewGeometry.h"
#import "QRCodeSearchPlanner.h"
#import "QRCodeDetector.h"

@interface QRCodeLocator ()

/** 记住连续几帧要搜哪一块、上次找到的位置，以及什么时候需要把画面变清晰 */
@property (nonatomic, strong) QRCodeSearchPlanner *searchPlanner;

/** 真正执行找码，并在需要时把画面变清晰 */
@property (nonatomic, strong) QRCodeDetector *detector;

@end

@implementation QRCodeLocator

#pragma mark - Life Cycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _searchPlanner = [[QRCodeSearchPlanner alloc] init];
        _detector = [[QRCodeDetector alloc] init];
    }
    return self;
}

#pragma mark - Public Methods

- (NSArray<NSValue *> *)locateQRCodeRectsInSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                        previewGeometry:(QRScannerPreviewGeometry *)previewGeometry
                                     visionRectInPreview:(CGRect)visionRectInPreview
                                             orientation:(CGImagePropertyOrientation)orientation {
    if (!sampleBuffer || !previewGeometry || CGRectIsEmpty(visionRectInPreview)) {
        return @[];
    }

    // 先限制在 Preview 可见区域，防止 aspectFill 外部坐标进入搜索规划。
    CGRect visibleRect = CGRectIntersection(visionRectInPreview, previewGeometry.previewBounds);
    QRCodeSearchTask *task = [self.searchPlanner nextTaskInVisibleRect:visibleRect];
    if (!task) {
        return @[];
    }

    NSArray<NSValue *> *rects = [self.detector detectQRCodeRectsInSampleBuffer:sampleBuffer
                                                                     previewGeometry:previewGeometry
                                                                         previewRect:task.previewRect
                                                                         orientation:orientation
                                                            imageEnhancementEnabled:task.isImageEnhancementEnabled];
    [self.searchPlanner recordLocatedRects:rects inVisibleRect:visibleRect];
    return rects;
}

- (void)reset {
    [self.searchPlanner reset];
}

@end

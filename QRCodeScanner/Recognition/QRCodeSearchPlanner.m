//
//  QRCodeSearchPlanner.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodeSearchPlanner.h"
#import <UIKit/UIKit.h>

/// 中心搜索区域占可见区域的比例
static const CGFloat kQRCodeCenterRegionRatio = 0.50f;
/// 四角区域保留少量重叠，避免二维码落在分界线上
static const CGFloat kQRCodeCornerRegionRatio = 0.55f;
/// 命中后优先跟踪附近区域的帧数
static const NSUInteger kQRCodePreferredSearchFrameCount = 2;
/// 连续未命中达到该次数后启用图像增强补救
static const NSUInteger kQRCodeEnhancementStartMissCount = 4;
/// 进入补救阶段后图像增强的帧间隔
static const NSUInteger kQRCodeEnhancementFrameInterval = 3;

/// 无命中跟踪任务时的常规搜索顺序
typedef NS_ENUM(NSUInteger, QRCodeSearchPhase) {
    QRCodeSearchPhaseCenter,
    QRCodeSearchPhaseTopLeft,
    QRCodeSearchPhaseTopRight,
    QRCodeSearchPhaseBottomLeft,
    QRCodeSearchPhaseBottomRight,
    QRCodeSearchPhaseFull,
    QRCodeSearchPhaseCount
};

@interface QRCodeSearchTask ()

/** 本帧需要搜索的 Preview 坐标系区域 */
@property (nonatomic, assign, readwrite) CGRect previewRect;

/** 是否启用低频图像增强补救 */
@property (nonatomic, assign, readwrite, getter=isImageEnhancementEnabled) BOOL imageEnhancementEnabled;

/**
 创建不可变搜索任务

 @param previewRect Preview 坐标系搜索区域
 @param imageEnhancementEnabled 是否启用图像增强
 */
- (instancetype)initWithPreviewRect:(CGRect)previewRect
            imageEnhancementEnabled:(BOOL)imageEnhancementEnabled;

@end

@interface QRCodeSearchPlanner ()

/** 当前常规搜索阶段 */
@property (nonatomic, assign) QRCodeSearchPhase searchPhase;

/** 连续未定位到二维码的帧数 */
@property (nonatomic, assign) NSUInteger consecutiveMissCount;

/** 上次命中位置扩展后的优先搜索区域 */
@property (nonatomic, assign) CGRect preferredPreviewRect;

/** 上次命中区域剩余的优先搜索帧数 */
@property (nonatomic, assign) NSUInteger preferredSearchFramesRemaining;

@end

@implementation QRCodeSearchTask

#pragma mark - Life Cycle

- (instancetype)initWithPreviewRect:(CGRect)previewRect
            imageEnhancementEnabled:(BOOL)imageEnhancementEnabled {
    self = [super init];
    if (self) {
        _previewRect = previewRect;
        _imageEnhancementEnabled = imageEnhancementEnabled;
    }
    return self;
}

@end

@implementation QRCodeSearchPlanner

#pragma mark - Public Methods

- (QRCodeSearchTask *)nextTaskInVisibleRect:(CGRect)visibleRect {
    if (CGRectIsEmpty(visibleRect)) {
        return nil;
    }

    CGRect previewRect = [self nextSearchRectInVisibleRect:visibleRect];
    if (CGRectIsEmpty(previewRect)) {
        return nil;
    }
    return [[QRCodeSearchTask alloc] initWithPreviewRect:previewRect
                                      imageEnhancementEnabled:[self shouldUseImageEnhancement]];
}

- (void)recordLocatedRects:(NSArray<NSValue *> *)rects
             inVisibleRect:(CGRect)visibleRect {
    if (rects.count == 0) {
        self.consecutiveMissCount += 1;
        return;
    }

    self.consecutiveMissCount = 0;
    self.preferredPreviewRect = [self preferredRectForLocatedRects:rects
                                                          visibleRect:visibleRect];
    self.preferredSearchFramesRemaining = CGRectIsEmpty(self.preferredPreviewRect)
        ? 0
        : kQRCodePreferredSearchFrameCount;
}

- (void)reset {
    self.searchPhase = QRCodeSearchPhaseCenter;
    self.consecutiveMissCount = 0;
    self.preferredPreviewRect = CGRectZero;
    self.preferredSearchFramesRemaining = 0;
}

#pragma mark - Private Methods

/// 命中后先稳定跟踪附近区域，否则按语义化阶段轮换全局搜索
- (CGRect)nextSearchRectInVisibleRect:(CGRect)visibleRect {
    if (self.preferredSearchFramesRemaining > 0 && !CGRectIsEmpty(self.preferredPreviewRect)) {
        self.preferredSearchFramesRemaining -= 1;
        CGRect preferredRect = CGRectIntersection(self.preferredPreviewRect, visibleRect);
        if (!CGRectIsEmpty(preferredRect)) {
            return CGRectIntegral(preferredRect);
        }
    }

    QRCodeSearchPhase phase = self.searchPhase;
    self.searchPhase = (phase + 1) % QRCodeSearchPhaseCount;
    switch (phase) {
        case QRCodeSearchPhaseCenter:
            return [self centerRectInRect:visibleRect ratio:kQRCodeCenterRegionRatio];
        case QRCodeSearchPhaseTopLeft:
        case QRCodeSearchPhaseTopRight:
        case QRCodeSearchPhaseBottomLeft:
        case QRCodeSearchPhaseBottomRight:
            return [self cornerRectForPhase:phase
                                 inVisibleRect:visibleRect
                                         ratio:kQRCodeCornerRegionRatio];
        case QRCodeSearchPhaseFull:
        case QRCodeSearchPhaseCount:
            return visibleRect;
    }
}

/// 四角区域按帧轮换，限制单帧 Vision 最坏耗时
- (CGRect)cornerRectForPhase:(QRCodeSearchPhase)phase
                  inVisibleRect:(CGRect)visibleRect
                          ratio:(CGFloat)ratio {
    CGFloat keepRatio = MIN(MAX(ratio, 0.2f), 1.f);
    CGFloat width = visibleRect.size.width * keepRatio;
    CGFloat height = visibleRect.size.height * keepRatio;
    BOOL usesRightEdge = phase == QRCodeSearchPhaseTopRight
        || phase == QRCodeSearchPhaseBottomRight;
    BOOL usesBottomEdge = phase == QRCodeSearchPhaseBottomLeft
        || phase == QRCodeSearchPhaseBottomRight;
    CGFloat x = usesRightEdge ? CGRectGetMaxX(visibleRect) - width : CGRectGetMinX(visibleRect);
    CGFloat y = usesBottomEdge ? CGRectGetMaxY(visibleRect) - height : CGRectGetMinY(visibleRect);
    return CGRectIntegral(CGRectMake(x, y, width, height));
}

/// 中心区域缩小 Vision 输入范围，提高远处小码在模型输入中的占比
- (CGRect)centerRectInRect:(CGRect)rect ratio:(CGFloat)ratio {
    if (ratio >= 0.99f || rect.size.width < 16.f || rect.size.height < 16.f) {
        return rect;
    }
    CGFloat keepRatio = MIN(MAX(ratio, 0.2f), 1.f);
    CGFloat horizontalInset = rect.size.width * (1.f - keepRatio) * 0.5f;
    CGFloat verticalInset = rect.size.height * (1.f - keepRatio) * 0.5f;
    return CGRectIntegral(CGRectInset(rect, horizontalInset, verticalInset));
}

/// 连续失败后间歇增强，避免正常场景持续支付 YUV 转 CIImage 的成本
- (BOOL)shouldUseImageEnhancement {
    if (self.consecutiveMissCount < kQRCodeEnhancementStartMissCount) {
        return NO;
    }
    NSUInteger fallbackIndex = self.consecutiveMissCount - kQRCodeEnhancementStartMissCount;
    return fallbackIndex % kQRCodeEnhancementFrameInterval == 0;
}

/// 扩大命中联合框并保留静区，使后续两帧能稳定更新位置
- (CGRect)preferredRectForLocatedRects:(NSArray<NSValue *> *)rects
                              visibleRect:(CGRect)visibleRect {
    CGRect unionRect = CGRectZero;
    for (NSValue *value in rects) {
        CGRect rect = value.CGRectValue;
        if (!CGRectIsEmpty(rect)) {
            unionRect = CGRectIsEmpty(unionRect) ? rect : CGRectUnion(unionRect, rect);
        }
    }
    if (CGRectIsEmpty(unionRect)) {
        return CGRectZero;
    }

    CGFloat width = MAX(unionRect.size.width * 3.f, visibleRect.size.width * 0.25f);
    CGFloat height = MAX(unionRect.size.height * 3.f, visibleRect.size.height * 0.25f);
    CGRect expandedRect = CGRectMake(CGRectGetMidX(unionRect) - width * 0.5f,
                                     CGRectGetMidY(unionRect) - height * 0.5f,
                                     width,
                                     height);
    return CGRectIntegral(CGRectIntersection(expandedRect, visibleRect));
}

@end

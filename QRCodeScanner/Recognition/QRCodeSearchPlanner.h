//
//  QRCodeSearchPlanner.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 下一帧该看画面的哪一块，以及要不要把画面变清晰
@interface QRCodeSearchTask : NSObject

/** 这一帧要搜索的区域，用预览画面的坐标 */
@property (nonatomic, assign, readonly) CGRect previewRect;

/** 这一帧要不要把画面稍微变清晰再找 */
@property (nonatomic, assign, readonly, getter=isImageEnhancementEnabled) BOOL imageEnhancementEnabled;

@end

/**
 安排每一帧去画面的哪一块找码。

 它只决定搜索区域，自己不识别。必须在同一条队列里调用，避免两帧的进度写乱。
 */
@interface QRCodeSearchPlanner : NSObject

/**
 给出下一帧的搜索安排。

 @param visibleRect 当前能看到的预览区域
 @return 搜索安排。区域无效时返回 nil
 */
- (nullable QRCodeSearchTask *)nextTaskInVisibleRect:(CGRect)visibleRect;

/**
 记下这一帧找到的框，并推进到下一次搜索。

 @param rects 这一帧找到的二维码框，用预览坐标。空数组表示没找到
 @param visibleRect 当前能看到的预览区域
 */
- (void)recordLocatedRects:(NSArray<NSValue *> *)rects
             inVisibleRect:(CGRect)visibleRect;

/** 清空搜索进度，开始新的一轮扫描 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END

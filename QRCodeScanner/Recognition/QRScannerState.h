//
//  QRScannerState.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 某一时刻的扫描状态副本。后台拿这份副本做判断，避免读到一半被别人改掉
@interface QRScannerStateSnapshot : NSObject

/** 现在是否正在扫描，可以处理相机画面 */
@property (nonatomic, assign, readonly, getter=isScanning) BOOL scanning;

/** 现在是否正在处理已经识别出的结果 */
@property (nonatomic, assign, readonly, getter=isResolving) BOOL resolving;

/** 镜头是否正在自动拉近 */
@property (nonatomic, assign, readonly, getter=isAutoZooming) BOOL autoZooming;

/** 是否已经请求拉近，但镜头还没开始动 */
@property (nonatomic, assign, readonly, getter=isZoomRequestInFlight) BOOL zoomRequestInFlight;

/** 最近一次系统读出码内容的时间 */
@property (nonatomic, assign, readonly) NSTimeInterval lastMetadataDecodedTime;

/** 最近一次开始找码框的时间 */
@property (nonatomic, assign, readonly) NSTimeInterval lastVisionDetectTime;

/** 最近一次看到二维码框的时间 */
@property (nonatomic, assign, readonly) NSTimeInterval lastQRSeenTime;

/** 本次开扫的序号。序号变了，就丢掉开扫前留下的旧画面 */
@property (nonatomic, assign, readonly) NSUInteger captureGeneration;

/** 本次拉近的序号。序号变了，就取消上一轮还没做完的拉近 */
@property (nonatomic, assign, readonly) NSUInteger autoZoomGeneration;

@end

/**
 扫描过程中的共享状态。

 主线程、找码线程和相机会话线程都会读它，所以内部加锁。
 不要跨线程直接改页面上的普通属性。
 */
@interface QRScannerState : NSObject

/** 取一份当前状态的副本 */
- (QRScannerStateSnapshot *)snapshot;

/** 开始新一轮扫描，并清掉上一轮的找码计时。返回这一轮的序号 */
- (NSUInteger)beginScanning;

/** 停止扫描，并让旧画面、旧拉近任务全部作废 */
- (void)stopScanning;

/** 手机转向或画面尺寸变了时，让转向前的旧画面作废 */
- (void)invalidateCaptureGeneration;

/** 记录现在是不是正在处理识别结果 */
- (void)setResolving:(BOOL)resolving;

/** 记下系统刚刚读出码内容的时间 */
- (void)recordMetadataDecodedAtTime:(NSTimeInterval)time;

/** 记下刚刚开始找码框的时间 */
- (void)recordVisionDetectionAtTime:(NSTimeInterval)time;

/** 记下刚刚看到二维码框的时间 */
- (void)recordQRCodeSeenAtTime:(NSTimeInterval)time;

/** 发起一次新的自动拉近，返回这次拉近的序号 */
- (NSUInteger)beginAutoZoomRequest;

/**
 标记这次拉近已经开始。

 @param generation 这次拉近的序号
 @return 序号还没过期时返回 YES
 */
- (BOOL)markAutoZoomStartedForGeneration:(NSUInteger)generation;

/** 结束这次拉近，并清掉请求中的标记 */
- (void)finishAutoZoomForGeneration:(NSUInteger)generation;

/** 取消当前拉近，并让还没做完的拉近任务作废 */
- (void)invalidateAutoZoom;

/** 这个开扫序号是不是还有效 */
- (BOOL)isCaptureGenerationCurrent:(NSUInteger)generation;

/** 这个拉近序号是不是还有效 */
- (BOOL)isAutoZoomGenerationCurrent:(NSUInteger)generation;

@end

NS_ASSUME_NONNULL_END

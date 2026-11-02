//
//  QRScannerState.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRScannerState.h"
#import <os/lock.h>

@interface QRScannerStateSnapshot ()

/** 现在是否正在扫描 */
@property (nonatomic, assign, readwrite, getter=isScanning) BOOL scanning;

/** 现在是否正在处理识别结果 */
@property (nonatomic, assign, readwrite, getter=isResolving) BOOL resolving;

/** 镜头是否正在自动拉近 */
@property (nonatomic, assign, readwrite, getter=isAutoZooming) BOOL autoZooming;

/** 是否已经请求拉近，但镜头还没开始动 */
@property (nonatomic, assign, readwrite, getter=isZoomRequestInFlight) BOOL zoomRequestInFlight;

/** 最近一次系统读出码内容的时间 */
@property (nonatomic, assign, readwrite) NSTimeInterval lastMetadataDecodedTime;

/** 最近一次开始找码框的时间 */
@property (nonatomic, assign, readwrite) NSTimeInterval lastVisionDetectTime;

/** 最近一次看到二维码框的时间 */
@property (nonatomic, assign, readwrite) NSTimeInterval lastQRSeenTime;

/** 本次开扫的序号 */
@property (nonatomic, assign, readwrite) NSUInteger captureGeneration;

/** 本次拉近的序号 */
@property (nonatomic, assign, readwrite) NSUInteger autoZoomGeneration;

@end

@interface QRScannerState () {
    os_unfair_lock _stateLock;
    BOOL _scanning;
    BOOL _resolving;
    BOOL _autoZooming;
    BOOL _zoomRequestInFlight;
    NSTimeInterval _lastMetadataDecodedTime;
    NSTimeInterval _lastVisionDetectTime;
    NSTimeInterval _lastQRSeenTime;
    NSUInteger _captureGeneration;
    NSUInteger _autoZoomGeneration;
}

@end

@implementation QRScannerStateSnapshot

@end

@implementation QRScannerState

#pragma mark - Life Cycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateLock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

#pragma mark - Public Methods

- (QRScannerStateSnapshot *)snapshot {
    QRScannerStateSnapshot *snapshot = [[QRScannerStateSnapshot alloc] init];
    os_unfair_lock_lock(&_stateLock);
    snapshot.scanning = _scanning;
    snapshot.resolving = _resolving;
    snapshot.autoZooming = _autoZooming;
    snapshot.zoomRequestInFlight = _zoomRequestInFlight;
    snapshot.lastMetadataDecodedTime = _lastMetadataDecodedTime;
    snapshot.lastVisionDetectTime = _lastVisionDetectTime;
    snapshot.lastQRSeenTime = _lastQRSeenTime;
    snapshot.captureGeneration = _captureGeneration;
    snapshot.autoZoomGeneration = _autoZoomGeneration;
    os_unfair_lock_unlock(&_stateLock);
    return snapshot;
}

- (NSUInteger)beginScanning {
    os_unfair_lock_lock(&_stateLock);
    _scanning = YES;
    _captureGeneration += 1;
    _lastMetadataDecodedTime = 0;
    _lastVisionDetectTime = 0;
    _lastQRSeenTime = 0;
    _autoZooming = NO;
    _zoomRequestInFlight = NO;
    NSUInteger generation = _captureGeneration;
    os_unfair_lock_unlock(&_stateLock);
    return generation;
}

- (void)stopScanning {
    os_unfair_lock_lock(&_stateLock);
    _scanning = NO;
    _captureGeneration += 1;
    _autoZoomGeneration += 1;
    _autoZooming = NO;
    _zoomRequestInFlight = NO;
    os_unfair_lock_unlock(&_stateLock);
}

- (void)invalidateCaptureGeneration {
    os_unfair_lock_lock(&_stateLock);
    _captureGeneration += 1;
    os_unfair_lock_unlock(&_stateLock);
}

- (void)setResolving:(BOOL)resolving {
    os_unfair_lock_lock(&_stateLock);
    _resolving = resolving;
    os_unfair_lock_unlock(&_stateLock);
}

- (void)recordMetadataDecodedAtTime:(NSTimeInterval)time {
    os_unfair_lock_lock(&_stateLock);
    _lastMetadataDecodedTime = time;
    os_unfair_lock_unlock(&_stateLock);
}

- (void)recordVisionDetectionAtTime:(NSTimeInterval)time {
    os_unfair_lock_lock(&_stateLock);
    _lastVisionDetectTime = time;
    os_unfair_lock_unlock(&_stateLock);
}

- (void)recordQRCodeSeenAtTime:(NSTimeInterval)time {
    os_unfair_lock_lock(&_stateLock);
    _lastQRSeenTime = time;
    os_unfair_lock_unlock(&_stateLock);
}

- (NSUInteger)beginAutoZoomRequest {
    os_unfair_lock_lock(&_stateLock);
    _autoZoomGeneration += 1;
    _zoomRequestInFlight = YES;
    NSUInteger generation = _autoZoomGeneration;
    os_unfair_lock_unlock(&_stateLock);
    return generation;
}

- (BOOL)markAutoZoomStartedForGeneration:(NSUInteger)generation {
    os_unfair_lock_lock(&_stateLock);
    BOOL isCurrent = generation == _autoZoomGeneration;
    if (isCurrent) {
        _autoZooming = YES;
    }
    os_unfair_lock_unlock(&_stateLock);
    return isCurrent;
}

- (void)finishAutoZoomForGeneration:(NSUInteger)generation {
    os_unfair_lock_lock(&_stateLock);
    if (generation == _autoZoomGeneration) {
        _autoZooming = NO;
        _zoomRequestInFlight = NO;
    }
    os_unfair_lock_unlock(&_stateLock);
}

- (void)invalidateAutoZoom {
    os_unfair_lock_lock(&_stateLock);
    _autoZoomGeneration += 1;
    _autoZooming = NO;
    _zoomRequestInFlight = NO;
    os_unfair_lock_unlock(&_stateLock);
}

- (BOOL)isCaptureGenerationCurrent:(NSUInteger)generation {
    os_unfair_lock_lock(&_stateLock);
    BOOL isCurrent = generation == _captureGeneration;
    os_unfair_lock_unlock(&_stateLock);
    return isCurrent;
}

- (BOOL)isAutoZoomGenerationCurrent:(NSUInteger)generation {
    os_unfair_lock_lock(&_stateLock);
    BOOL isCurrent = generation == _autoZoomGeneration;
    os_unfair_lock_unlock(&_stateLock);
    return isCurrent;
}

@end

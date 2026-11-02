//
//  QRScannerTimer.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 不抓住回调对象的定时器，页面关掉后不会被定时器继续留着
@interface QRScannerTimer : NSObject

/**
 创建并启动定时器。

 @param interval 触发间隔
 @param target 到点后调用的对象。定时器不抓住它，对象释放后定时器会自己停
 @param selector 无参数的方法
 @param userInfo 预留参数，当前没有使用
 @param repeats 是否重复触发
 @param dispatchQueue 在哪条队列回调。传 nil 时用主队列
 */
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                        target:(id)target
                                      selector:(SEL)selector
                                      userInfo:(nullable id)userInfo
                                       repeats:(BOOL)repeats
                                 dispatchQueue:(nullable dispatch_queue_t)dispatchQueue;

/** 停止后续回调。可重复调用 */
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END

//
//  QRScannerTimer.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRScannerTimer.h"

@interface QRScannerTimer ()

/** 回调对象，不持有，避免和页面形成循环引用 */
@property (nonatomic, weak) id target;
/** 无参回调方法 */
@property (nonatomic, assign) SEL selector;
/** 是否重复触发 */
@property (nonatomic, assign) BOOL repeats;
/** GCD 定时源。置空表示已停止 */
@property (nonatomic, strong, nullable) dispatch_source_t timer;

@end

@implementation QRScannerTimer

+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                        target:(id)target
                                      selector:(SEL)selector
                                      userInfo:(id)userInfo
                                       repeats:(BOOL)repeats
                                 dispatchQueue:(dispatch_queue_t)dispatchQueue {
    QRScannerTimer *timer = [[QRScannerTimer alloc] init];
    timer.target = target;
    timer.selector = selector;
    timer.repeats = repeats;

    dispatch_queue_t queue = dispatchQueue ?: dispatch_get_main_queue();
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t nanoseconds = (uint64_t)(interval * (NSTimeInterval)NSEC_PER_SEC);
    if (nanoseconds == 0) {
        nanoseconds = 1;
    }
    dispatch_source_set_timer(source,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)nanoseconds),
                              repeats ? nanoseconds : DISPATCH_TIME_FOREVER,
                              nanoseconds / 10);

    __weak QRScannerTimer *weakTimer = timer;
    dispatch_source_set_event_handler(source, ^{
        QRScannerTimer *strongTimer = weakTimer;
        id targetObject = strongTimer.target;
        SEL callback = strongTimer.selector;
        if (!strongTimer || !targetObject || !callback || ![targetObject respondsToSelector:callback]) {
            [strongTimer invalidate];
            return;
        }
        IMP implementation = [targetObject methodForSelector:callback];
        void (*function)(id, SEL) = (void (*)(id, SEL))implementation;
        function(targetObject, callback);
        if (!strongTimer.repeats) {
            [strongTimer invalidate];
        }
    });

    timer.timer = source;
    dispatch_resume(source);
    return timer;
}

- (void)invalidate {
    dispatch_source_t source = self.timer;
    if (!source) {
        return;
    }
    self.timer = nil;
    dispatch_source_cancel(source);
}

- (void)dealloc {
    [self invalidate];
}

@end

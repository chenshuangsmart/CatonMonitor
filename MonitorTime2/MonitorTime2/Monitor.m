//
//  Monitor.m
//  MonitorTime2
//
//  Created by cs on 2019/7/1.
//  Copyright © 2019 cs. All rights reserved.
//

#import "Monitor.h"
#import <CrashReporter/CrashReporter.h>

@interface Monitor()
/** thread */
@property(nonatomic, strong)NSThread *monitorThread;
/** startDate */
@property(nonatomic, strong)NSDate *startDate;
/** excuting */
@property(nonatomic, assign, getter=isExcuting)BOOL excuting;  // 是否正在执行任务
@end

@implementation Monitor {
    CFRunLoopObserverRef _observer;  // observer
    CFRunLoopTimerRef _timer; // 定时器
}

/** 单例 */
+ (instancetype)shareInstance {
    static Monitor *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        instance.monitorThread = [[NSThread alloc] initWithTarget:self selector:@selector(monitorThreadEntryPoint) object:nil];
        [instance.monitorThread start];
    });
    return instance;
}

/// 创建一个子线程，在线程启动时，启动其RunLoop
+ (void)monitorThreadEntryPoint {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"Monitor"];
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

// 第二步,在开始监测时，往主线程的RunLoop中添加一个observer，并往子线程中添加一个定时器，每0.1秒检测一次耗时的时长。
- (void)startMonitor {
    if (_observer) {
        return;
    }
    // 1.创建 observer
    CFRunLoopObserverContext context = {0,(__bridge void*)self, NULL, NULL, NULL};
    _observer = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                        kCFRunLoopAllActivities,
                                        YES,
                                        0,
                                        &runLoopObserverCallBack,
                                        &context);
    // 2.将 observer 添加到住线程的 runloop 中
    CFRunLoopAddObserver(CFRunLoopGetMain(), _observer, kCFRunLoopCommonModes);
    // 3.创建一个 timer,并添加到子线程的 runloop 中
    [self performSelector:@selector(addTimerToMonitorThread) onThread:self.monitorThread withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
}

/** observer 回调
 1.因为主线程中的 block,交互事件,以及其他任务都是在 kCFRunLoopBeforeSources到kCFRunLoopBeforeWaiting之前执行.
 2.所以在开始执行Sources时,即kCFRunLoopBeforeSources状态时,记录一下时间,并把正在执行任务的标记设置为 YES.
 3.将要进入睡眠状态时,即kCFRunLoopBeforeWaiting状态时,将正在执行任务的标记设置为 NO.
 */
static void runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    Monitor *monitor = (__bridge Monitor *)info;
    switch (activity) {
        case kCFRunLoopEntry:
            NSLog(@"kCFRunLoopEntry");
            break;
        case kCFRunLoopBeforeTimers:
            NSLog(@"kCFRunLoopBeforeTimers");
            break;
        case kCFRunLoopBeforeSources:
            NSLog(@"kCFRunLoopBeforeSources");
            monitor.startDate = [NSDate date];
            monitor.excuting = YES;
            break;
        case kCFRunLoopBeforeWaiting:
            NSLog(@"kCFRunLoopBeforeWaiting");
            monitor.excuting = NO;
            break;
        case kCFRunLoopAfterWaiting:
            NSLog(@"kCFRunLoopAfterWaiting");
            break;
        case kCFRunLoopExit:
            NSLog(@"kCFRunLoopExit");
            break;
        default:
            break;
    }
}

#pragma mark - 定时器

/// 添加定时器到 runloop 中
- (void)addTimerToMonitorThread {
    if (_timer) {
        return;
    }
    // 创建一个 timer
    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
    CFRunLoopTimerContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
    
    _timer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                  0.1,
                                  0.1,
                                  0,
                                  0,
                                  &runLoopTimerCallBack,
                                  &context);
    
    // 添加到子线程的 runloop 中
    CFRunLoopAddTimer(currentRunLoop, _timer, kCFRunLoopCommonModes);
}

static void runLoopTimerCallBack(CFRunLoopTimerRef timer, void *info) {
    Monitor *monitor = (__bridge Monitor *)info;
    if (!monitor.isExcuting) {  // 即 runloop 已经进入了休眠 kCFRunLoopBeforeWaiting
        return;
    }
    
    // 如果主线程正在执行任务，并且这一次loop 执行到 现在还没执行完，那就需要计算时间差
    // 即从kCFRunLoopBeforeSources状态到当前时间的时间差 excuteTime
    NSTimeInterval excuteTime = [[NSDate date] timeIntervalSinceDate:monitor.startDate];
    NSLog(@"定时器: 当前线程:%@,主线程执行时间:%f秒",[NSThread currentThread], excuteTime);
    
    // Time 每 0.01S执行一次,如果当前正在执行任务的状态为YES，并且从开始执行到现在的时间大于阙值，则把堆栈信息保存下来，便于后面处理。
    // 为了能够捕获到堆栈信息，我把timer的间隔调的很小（0.01），而评定为卡顿的阙值也调的很小（0.01）
    if (excuteTime >= 0.01) {
        NSLog(@"线程卡顿了%f 秒",excuteTime);
        [monitor handleStackInfo];
    }
}

#pragma mark - 对线

- (void)handleStackInfo {
    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];
    
    PLCrashReporter *crashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];
    
    NSData *data = [crashReporter generateLiveReport];
    PLCrashReport *reporter = [[PLCrashReport alloc] initWithData:data error:NULL];
    NSString *report = [PLCrashReportTextFormatter stringValueForCrashReport:reporter withTextFormat:PLCrashReportTextFormatiOS];
    
    NSLog(@"---------卡顿信息\n%@\n--------------",report);
}

@end

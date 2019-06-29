//
//  Monitor.m
//  MonitorTimer
//
//  Created by cs on 2019/6/28.
//  Copyright © 2019 cs. All rights reserved.
//

#import "Monitor.h"
#import <objc/runtime.h>
#import <CrashReporter/CrashReporter.h>

static double _waitStartTime;   // 等待启动的时间

@implementation Monitor {
    CFRunLoopObserverRef _observer; // runloop observer
    double _lastRecordTime; // last record time
    NSMutableArray *_backtraces;
}

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    static id shareInstance;
    dispatch_once(&onceToken, ^{
        shareInstance = [[self alloc] init];
    });
    return shareInstance;
}

#pragma mark - start | end

- (void)startMonitor {
    [self addMainThreadObserver];
    [self addSecondaryThreadAndObserver];
}

- (void)endMonitor {
    if (!_observer) {
        return;
    }
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), _observer, kCFRunLoopCommonModes);
    CFRelease(_observer);
    _observer = NULL;
}

#pragma mark - MainThread runloop observer

/// 添加在主线程的 runloop 监听器
- (void)addMainThreadObserver {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 建立自动释放池
        @autoreleasepool {
            // 获得当前线程的 runloop
            NSRunLoop *mainRunLoop = [NSRunLoop currentRunLoop];
            
            // 设置runloop observer 的运行环境
            /** 第一个参数用于分配observer对象的内存
                第二个参数用以设置observer所要关注的事件，详见回调函数myRunLoopObserver中注释
                第三个参数用于标识该observer是在第一次进入run loop时执行还是每次进入run loop处理时均执行
                第四个参数用于设置该observer的优先级
                第五个参数用于设置该observer的回调函数
                第六个参数用于设置该observer的运行环境 */
            CFRunLoopObserverContext context =  {0, (__bridge void *)(self), NULL, NULL, NULL};
            
            // 创建 runloop observer 对象
            self->_observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &mainRunLoopObserver, &context);
            
            if (self->_observer) {
                // 将 cocoa的 NSRunLoop 类型转换为 Core Foundation 的 CFRunLoopRef 类型
                CFRunLoopRef cfRunLoop = [mainRunLoop getCFRunLoop];
                // 将新建的 observer 加入到当前 thread 的 runloop 中
                CFRunLoopAddObserver(cfRunLoop, self->_observer, kCFRunLoopDefaultMode);
            }
        }
    });

}

void mainRunLoopObserver(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss:SSS"];
    NSString *time = [formatter stringFromDate:[NSDate date]];
    
    switch (activity) {
            //The entrance of the run loop, before entering the event processing loop.
            //This activity occurs once for each call to CFRunLoopRun and CFRunLoopRunInMode
        case kCFRunLoopEntry:
            NSLog(@"kCFRunLoopEntry - %@",time);
            break;
            //Inside the event processing loop before any timers are processed
        case kCFRunLoopBeforeTimers:
            NSLog(@"kCFRunLoopBeforeTimers - %@",time);
            break;
            //Inside the event processing loop before any sources are processed
        case kCFRunLoopBeforeSources:
            NSLog(@"kCFRunLoopBeforeSources - %@",time);
            break;
            //Inside the event processing loop before the run loop sleeps, waiting for a source or timer to fire.
            //This activity does not occur if CFRunLoopRunInMode is called with a timeout of 0 seconds.
            //It also does not occur in a particular iteration of the event processing loop if a version 0 source fires
        case kCFRunLoopBeforeWaiting:{  // 即将进入休眠-这个时候处理 UI 操作
            _waitStartTime = 0;
            NSLog(@"kCFRunLoopBeforeWaiting - %@",time);
            break;
        }
            //Inside the event processing loop after the run loop wakes up, but before processing the event that woke it up.
            //This activity occurs only if the run loop did in fact go to sleep during the current loop
        case kCFRunLoopAfterWaiting:{   // 从休眠中醒来开始做事情了
            _waitStartTime = [[NSDate date] timeIntervalSince1970];
            NSLog(@"kCFRunLoopAfterWaiting - %@",time);
            break;
        }
            //The exit of the run loop, after exiting the event processing loop.
            //This activity occurs once for each call to CFRunLoopRun and CFRunLoopRunInMode
        case kCFRunLoopExit:
            NSLog(@"kCFRunLoopExit - %@",time);
            break;
            /*
             A combination of all the preceding stages
             case kCFRunLoopAllActivities:
             break;
             */
        default:
            break;
    }
}

#pragma mark - second thread observer

- (void)addSecondaryThreadAndObserver {
    NSThread *thread = [self secondaryThread];
    [self performSelector:@selector(addSecondaryTimer) onThread:thread withObject:nil waitUntilDone:YES];
}

#pragma mark - timer

- (void)addSecondaryTimer {
    __weak typeof(self)weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf timerFired];
    }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
}

- (void)timerFired {
    if (_waitStartTime < 1) {   // 因为刚刚经历了kCFRunLoopBeforeWaiting状态,_waitStartTime=0,直接 pass
        NSLog(@"timerFired return curTime:%@, waitStartTime:%@",[self getCurTimeStamp], [self getTimeStamp:_waitStartTime]);
        return;
    }

    double currentTime = [[NSDate date] timeIntervalSince1970];
    double timeDiff = currentTime - _waitStartTime;

    NSLog(@"timerFired curTime:%@, waitStartTime:%@, timeDiff:%f, _lastRecordTime:%f",[self getCurTimeStamp], [self getTimeStamp:_waitStartTime], timeDiff, _lastRecordTime);

    // 如果 timeDiff 时间间隔超过 2S,表示 runloop 处于kCFRunLoopAfterWaiting跟kCFRunLoopBeforeWaiting之间状态很长时间
    // 即长时间处于kCFRunLoopBeforeTimers和kCFRunLoopBeforeSources状态,就是进行 UI 操作了
    if (timeDiff > 2.0) {
        NSLog(@"last lastRecordTime:%f waitStartTime:%f",_lastRecordTime,_waitStartTime);
        if (_lastRecordTime - _waitStartTime < 0.001 && _lastRecordTime != 0) { // 距离上一次记录堆栈信息时间过短的话,就直接 pass,避免短时间内多次记录堆栈信息
            NSLog(@"last return timeDiff:%f waitStartTime:%@ lastRecordTime:%@ difference:%f",timeDiff, [self getTimeStamp:_waitStartTime], [self getTimeStamp:_lastRecordTime], _lastRecordTime - _waitStartTime);
            return;
        }
        // 只有当上一次记录堆栈信息时,_waitStartTime刚好为 0,导致_lastRecordTime也为零
        // 或者 _waitStartTime的值为零,则满足条件
        NSLog(@"记录崩溃堆栈信息");
        [self logStack];
        _lastRecordTime = _waitStartTime;
    }
}

#pragma mark - stack

- (void)printTraceLog {
    
}

- (void)logStack {
    // 收集Crash信息也可用于实时获取各线程的调用堆栈
    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];
    
    PLCrashReporter *crashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];
    
    NSData *data = [crashReporter generateLiveReport];
    PLCrashReport *reporter = [[PLCrashReport alloc] initWithData:data error:NULL];
    NSString *report = [PLCrashReportTextFormatter stringValueForCrashReport:reporter withTextFormat:PLCrashReportTextFormatiOS];
    
    NSLog(@"---------卡顿信息\n%@\n--------------",report);
}

#pragma mark - private

/// 返回一个子线程
- (NSThread *)secondaryThread {
    static NSThread *_secondaryThread = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _secondaryThread = [[NSThread alloc] initWithTarget:self
                                                   selector:@selector(networkRequestThreadEntryPoint:)
                                                     object:nil];
        [_secondaryThread start];
    });
    return _secondaryThread;
}

- (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"MonitorThread"];
        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
        [runloop addPort:[NSMachPort port] forMode:NSRunLoopCommonModes];
        [runloop run];
    }
}

- (NSString *)getCurTimeStamp {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss:SSS"];
    return [formatter stringFromDate:[NSDate date]];
}

- (NSString *)getTimeStamp:(double)time {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:time];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss:SSS"];
    return [formatter stringFromDate:date];
}

@end

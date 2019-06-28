//
//  BGPerformanceMonitor.m
//  1129_PerformanceMonitor
//
//  Created by cs on 2017/11/29.
//  Copyright © 2017年 cs. All rights reserved.
//

#import "BGPerformanceMonitor.h"
#import <CrashReporter/CrashReporter.h>

@interface BGPerformanceMonitor () {
    int timeoutCount;   // 耗时次数
    CFRunLoopObserverRef observer;  // 观察者
    
    @public
    dispatch_semaphore_t semaphore; // 信号
    CFRunLoopActivity activity; // 状态
}
@end

@implementation BGPerformanceMonitor

// 单例
+ (instancetype)shareInstance {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

// 开始监听
- (void)startMonitor {
    if (observer) {
        return;
    }
    
    // 创建信号
    semaphore = dispatch_semaphore_create(0);
    NSLog(@"dispatch_semaphore_create:%@",[BGPerformanceMonitor getCurTime]);
    
    // 注册RunLoop状态观察
    CFRunLoopObserverContext context = {0,(__bridge void*)self,NULL,NULL};
    //创建Run loop observer对象
    //第一个参数用于分配observer对象的内存
    //第二个参数用以设置observer所要关注的事件，详见回调函数myRunLoopObserver中注释
    //第三个参数用于标识该observer是在第一次进入run loop时执行还是每次进入run loop处理时均执行
    //第四个参数用于设置该observer的优先级
    //第五个参数用于设置该observer的回调函数
    //第六个参数用于设置该observer的运行环境
    observer = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                       kCFRunLoopAllActivities,
                                       YES,
                                       0,
                                       &runLoopObserverCallBack,
                                       &context);
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    
    // 在子线程监控时长
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (YES) {   // 有信号的话 就查询当前runloop的状态
            // 假定连续5次超时50ms认为卡顿(当然也包含了单次超时250ms)
            // 因为下面 runloop 状态改变回调方法runLoopObserverCallBack中会将信号量递增 1,所以每次 runloop 状态改变后,下面的语句都会执行一次
            // dispatch_semaphore_wait:Returns zero on success, or non-zero if the timeout occurred.
            long st = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 50*NSEC_PER_MSEC));
            NSLog(@"dispatch_semaphore_wait:st=%ld,time:%@",st,[self getCurTime]);
            if (st != 0) {  // 信号量超时了 - 即 runloop 的状态长时间没有发生变更,长期处于某一个状态下
                if (!observer) {
                    timeoutCount = 0;
                    semaphore = 0;
                    activity = 0;
                    return;
                }
                NSLog(@"st = %ld,activity = %lu,timeoutCount = %d,time:%@",st,activity,timeoutCount,[self getCurTime]);
                // kCFRunLoopBeforeSources - 即将处理source kCFRunLoopAfterWaiting - 刚从休眠中唤醒
                // 获取kCFRunLoopBeforeSources到kCFRunLoopBeforeWaiting再到kCFRunLoopAfterWaiting的状态就可以知道是否有卡顿的情况。
                // kCFRunLoopBeforeSources:停留在这个状态,表示在做很多事情
                if (activity == kCFRunLoopBeforeSources || activity == kCFRunLoopAfterWaiting) {    // 发生卡顿,记录卡顿次数
                    if (++timeoutCount < 5) {
                        continue;   // 不足 5 次,直接 continue 当次循环,不将timeoutCount置为0
                    }
                    
                    // 收集Crash信息也可用于实时获取各线程的调用堆栈
                    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];
                    
                    PLCrashReporter *crashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];
                    
                    NSData *data = [crashReporter generateLiveReport];
                    PLCrashReport *reporter = [[PLCrashReport alloc] initWithData:data error:NULL];
                    NSString *report = [PLCrashReportTextFormatter stringValueForCrashReport:reporter withTextFormat:PLCrashReportTextFormatiOS];
                    
                    NSLog(@"---------卡顿信息\n%@\n--------------",report);
                }
            }
            NSLog(@"dispatch_semaphore_wait timeoutCount = 0，time:%@",[self getCurTime]);
            timeoutCount = 0;
        }
    });
}

// 停止监听
- (void)stopMonitor {
    if (!observer) {
        return;
    }
    
    // 移除观察并释放资源
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
    observer = NULL;
}

#pragma mark - runloop observer callback

// 就是runloop有一个状态改变 就记录一下
static void runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    BGPerformanceMonitor *monitor = (__bridge BGPerformanceMonitor*)info;
    
    // 记录状态值
    monitor->activity = activity;
    
    // 发送信号
    dispatch_semaphore_t semaphore = monitor->semaphore;
    long st = dispatch_semaphore_signal(semaphore);
    NSLog(@"dispatch_semaphore_signal:st=%ld,time:%@",st,[BGPerformanceMonitor getCurTime]);
    
    /* Run Loop Observer Activities */
//    typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
//        kCFRunLoopEntry = (1UL << 0),    // 进入RunLoop循环(这里其实还没进入)
//        kCFRunLoopBeforeTimers = (1UL << 1),  // RunLoop 要处理timer了
//        kCFRunLoopBeforeSources = (1UL << 2), // RunLoop 要处理source了
//        kCFRunLoopBeforeWaiting = (1UL << 5), // RunLoop要休眠了
//        kCFRunLoopAfterWaiting = (1UL << 6),   // RunLoop醒了
//        kCFRunLoopExit = (1UL << 7),           // RunLoop退出（和kCFRunLoopEntry对应）
//        kCFRunLoopAllActivities = 0x0FFFFFFFU
//    };
    
    if (activity == kCFRunLoopEntry) {  // 即将进入RunLoop
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopEntry");
    } else if (activity == kCFRunLoopBeforeTimers) {    // 即将处理Timer
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopBeforeTimers");
    } else if (activity == kCFRunLoopBeforeSources) {   // 即将处理Source
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopBeforeSources");
    } else if (activity == kCFRunLoopBeforeWaiting) {   //即将进入休眠
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopBeforeWaiting");
    } else if (activity == kCFRunLoopAfterWaiting) {    // 刚从休眠中唤醒
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopAfterWaiting");
    } else if (activity == kCFRunLoopExit) {    // 即将退出RunLoop
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopExit");
    } else if (activity == kCFRunLoopAllActivities) {
        NSLog(@"runLoopObserverCallBack - %@",@"kCFRunLoopAllActivities");
    }
}

#pragma mark - private function

- (NSString *)getCurTime {
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"YYYY/MM/dd hh:mm:ss:SSS"];
    NSString *curTime = [format stringFromDate:[NSDate date]];
    
    return curTime;
}

+ (NSString *) getCurTime {
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"YYYY/MM/dd hh:mm:ss:SSS"];
    NSString *curTime = [format stringFromDate:[NSDate date]];
    
    return curTime;
}

@end

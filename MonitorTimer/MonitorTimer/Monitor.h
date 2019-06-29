//
//  Monitor.h
//  MonitorTimer
//
//  Created by cs on 2019/6/28.
//  Copyright © 2019 cs. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 卡顿监控工具类
 */
@interface Monitor : NSObject

/// 单例
+ (instancetype)shareInstance;

/// 开启卡顿监听
- (void)startMonitor;

/// 停止监听
- (void)endMonitor;

/// 打印堆栈信息
- (void)printTraceLog;

@end

NS_ASSUME_NONNULL_END

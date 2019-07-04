//
//  Monitor.h
//  MonitorTime2
//
//  Created by cs on 2019/7/1.
//  Copyright © 2019 cs. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 卡顿监控工具类
 */
@interface Monitor : NSObject

/** 单例 */
+ (instancetype)shareInstance;

/** 开始卡顿监测 */
- (void)startMonitor;

@end

NS_ASSUME_NONNULL_END

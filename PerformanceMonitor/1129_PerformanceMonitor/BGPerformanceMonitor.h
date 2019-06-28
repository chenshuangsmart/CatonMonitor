//
//  BGPerformanceMonitor.h
//  1129_PerformanceMonitor
//
//  Created by cs on 2017/11/29.
//  Copyright © 2017年 cs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BGPerformanceMonitor : NSObject

/// 单例
+ (instancetype)shareInstance;

/// 开始监听卡顿
- (void)startMonitor;

/// 停止监听卡顿
- (void)stopMonitor;

@end

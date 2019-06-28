//
//  ViewController.m
//  1129_PerformanceMonitor
//
//  Created by cs on 2017/11/29.
//  Copyright © 2017年 cs. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () <UITableViewDataSource> {
    UITableView *_tableView;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self drawTableView];
}

/// 绘制TableView视图
- (void)drawTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    _tableView.dataSource = self;
    [self.view addSubview:_tableView];
}

#pragma mark --------------------------------------------
#pragma mark UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 100;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    }
    
    NSString *text = nil;
    
    if (indexPath.row % 10 == 0) {  // 每10行休眠0.2S
        usleep(500 * 1000); // 1 * 1000 * 1000 == 1秒
        text = @"我在做复杂的事情，需要一些时间";
    } else {
        text = [NSString stringWithFormat:@"cell - %ld",indexPath.row];
    }
    
    cell.textLabel.text = text;
    
    return cell;
}

#pragma mark --------------------------------------------
#pragma mark 内存警告信息处理
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
@end

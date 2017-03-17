//
//  ASScreenRecordManager.h
//  PrepareLesson
//
//  Created by yuelixing on 2017/3/14.
//  Copyright © 2017年 QingGuo. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ASScreenRecorder.h"

@interface ASScreenRecordManager : NSObject

+ (instancetype)shareManager;

@property (nonatomic, retain) ASScreenRecorder * recorder;

- (void)startRecoder:(NSString *)fileName;

- (void)stop:(void(^)(NSURL * fileURL))completion;

@end

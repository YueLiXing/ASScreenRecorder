//
//  ASScreenRecordManager.m
//  PrepareLesson
//
//  Created by yuelixing on 2017/3/14.
//  Copyright © 2017年 QingGuo. All rights reserved.
//

#import "ASScreenRecordManager.h"
#import "ASScreenRecorder.h"

@interface ASScreenRecordManager ()

@property (nonatomic, copy) NSString * cachePath;

@property (nonatomic, assign) BOOL isDebug;

@property (nonatomic, copy) NSString * filePath;

@end

@implementation ASScreenRecordManager

+ (instancetype)shareManager {
    static id manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        self.cachePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"upload_video"];
        
        NSFileManager * manager = [NSFileManager defaultManager];
        if ([manager fileExistsAtPath:self.cachePath] == NO) {
            [manager createDirectoryAtPath:self.cachePath withIntermediateDirectories:NO attributes:nil error:nil];
            LxLog(@"创建视频缓存文件夹");
        }
        self.recorder = [ASScreenRecorder sharedInstance];
        self.isDebug = NO;
//        self.isDebug = YES;
    }
    return self;
}


- (void)startRecoder:(NSString *)fileName {
    if (self.isDebug) {
        return;
    }
    self.filePath = [self.cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", fileName]];
    
    self.recorder.videoURL = [NSURL fileURLWithPath:self.filePath];
    [self.recorder startRecording];
}

- (void)stop:(void(^)(NSURL * fileURL))completion {
    if (self.isDebug) {
        return;
    }
    if (self.recorder) {
        [self.recorder stopRecordingWithCompletion:^{
            LxLog(@"录制完成");
            UISaveVideoAtPathToSavedPhotosAlbum(self.filePath, nil, nil, nil);
            if (completion) {
                completion(self.recorder.videoURL);
            }
        }];
    } else {
        LxLog(@"未找到可用的 ASScreenRecorder");
    }
}


@end

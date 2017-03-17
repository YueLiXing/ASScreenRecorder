//
//  RecorderManager.h
//  Record
//
//  Created by yuelixing on 15/4/8.
//  Copyright (c) 2015年 yuelixing. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void(^VolumeChange)(CGFloat volume);
typedef void(^TimeChange)(CGFloat time);

@class AVAudioRecorder;
/**
 *  录音
 */
@interface RecorderManager : NSObject
{
    NSOperationQueue * _changeQueue;
    NSString * _fileName;
}

@property (nonatomic, retain) AVAudioRecorder * recorder;

+ (instancetype)shareManager;
/**
 *  开始录音
 *
 *  @param volumeChange 音量变化回调，取值范围 0~1
 */
- (void)startRecordVolumeChange:(VolumeChange)volumeChange TimeChange:(TimeChange)timeChange;
- (void)record; // 继续录音
- (void)pasue; // 暂停
- (void)endRecord:(void(^)(NSString * filaPath, NSInteger sec))complition; // 回调参数为路径和时长

- (void)cancleRecord;

@end
/*
 
 */

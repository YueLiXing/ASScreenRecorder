//
//  RecorderManager.m
//  Record
//
//  Created by yuelixing on 15/4/8.
//  Copyright (c) 2015年 yuelixing. All rights reserved.
//

#import "RecorderManager.h"
//#import <NSString+YYAdd.h>
//#import "NSString+Hashing.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioSession.h>
#import "Logger.h"

@interface RecorderManager () <AVAudioRecorderDelegate>

@property (nonatomic, copy) NSString * lastPath;
@property (nonatomic, retain) NSMutableDictionary * setting;
@property (nonatomic, retain) NSTimer * timer;

@property (nonatomic, copy) VolumeChange volumeChange;
@property (nonatomic, copy) TimeChange timeChange;

@end

@implementation RecorderManager

+ (instancetype)shareManager {
    static RecorderManager * manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[RecorderManager alloc] init];
    });
    return manager;
    
}
#pragma mark - AVAudioRecorder

- (instancetype)init {
    if (self = [super init]) {
//        NSFileManager * fileManager = [NSFileManager defaultManager];
//        NSString * path = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@/", DefaultSubPath]];
//        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (NSMutableDictionary *)setting {
    //录音设置
    if (_setting == nil) {
        _setting = [[NSMutableDictionary alloc]init];
    }
    
    //    [_setting setObject:[NSNumber numberWithInt: kAudioFormatLinearPCM] forKey:AVFormatIDKey];
    ////    [_setting setObject:[NSNumber numberWithInt: kAudioFormatMPEG4AAC] forKeyedSubscript:AVFormatIDKey];
    //    //设置录音采样率(Hz) 如：AVSampleRateKey==8000/44100/96000（影响音频的质量）
    //    [_setting setObject:[NSNumber numberWithFloat: 8000] forKeyedSubscript:AVSampleRateKey];
    ////    [_setting setObject:[NSNumber numberWithFloat: 16000] forKey:AVSampleRateKey];
    //    [_setting setObject:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey]; //线性采样位数  8、16、24、32
    //    [_setting setObject:[NSNumber numberWithInt: 1] forKey:AVNumberOfChannelsKey]; //录音通道数  1 或 2
    //    [_setting setObject:[NSNumber numberWithInt:AVAudioQualityMax] forKey:AVEncoderAudioQualityKey]; //录音的质量
    //    [_setting setObject:[NSNumber numberWithBool:YES] forKey:AVLinearPCMIsBigEndianKey]; //大端还是小端是内存的组织方式
    //    [_setting setObject:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey]; //采样信号是整数还是浮点数
    
    //设置录音格式  AVFormatIDKey==kAudioFormatLinearPCM
    [_setting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    //设置录音采样率(Hz) 如：AVSampleRateKey==8000/44100/96000（影响音频的质量）
    [_setting setValue:[NSNumber numberWithFloat:44100] forKey:AVSampleRateKey];
    //录音通道数  1 或 2
    [_setting setValue:[NSNumber numberWithInt:1] forKey:AVNumberOfChannelsKey];
    //线性采样位数  8、16、24、32
    [_setting setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    //录音的质量
    [_setting setValue:[NSNumber numberWithInt:AVAudioQualityHigh] forKey:AVEncoderAudioQualityKey];
    
    return _setting;
}

- (NSString *)dateStringWithFormat:(NSString *)format {
    NSDateFormatter * temp = [[NSDateFormatter alloc] init];
    temp.dateFormat = format;
    return [temp stringFromDate:[NSDate date]];
}


- (void)startRecordVolumeChange:(VolumeChange)volumeChange TimeChange:(TimeChange)timeChange {
    self.volumeChange = volumeChange;
    self.timeChange = timeChange;
    
    
    AVAudioSession * session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [session setActive:YES error:nil];
    NSString * timeString = [self dateStringWithFormat:@"yyyy-MM-dd_HH:mm:ss"];
    NSString * fileName = [NSString stringWithFormat:@"%@_%d", timeString, arc4random()%10];
    
    self.lastPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.aac", fileName]];
//    [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@", [NSString stringWithFormat:@"%@/%@.aac", DefaultSubPath, fileName]]]
//    self.lastPath = RecorderPath(fileName);
    
    if (self.recorder) {
        [self.recorder stop];
        [self.recorder deleteRecording];
        self.recorder.delegate = nil;
        self.recorder = nil;
    }
    
    NSError * error;
    NSLog(@"path : %@", self.lastPath);
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.lastPath]) {
        NSError * tempError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.lastPath error:&tempError];
    }
    self.recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL URLWithString:self.lastPath] settings:self.setting error:&error];
    self.recorder.delegate = self;
    self.recorder.meteringEnabled = YES;
    if (error) {
        NSLog(@"%@ %@", error, self.recorder.url.absoluteString);
    }
    [self.recorder prepareToRecord];
    [self.recorder record];
    NSLog(@"录音开始 filePath:%@", self.lastPath);
    if (volumeChange || timeChange) {
        [self.timer invalidate];
        self.timer = nil;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateMeters) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)record {
    [self.recorder record];
}

- (void)pasue {
    [self.recorder pause];
}

- (void)endRecord:(void (^)(NSString *, NSInteger))complition {
    NSLog(@"录音结束");
    NSInteger second = (NSInteger)(self.recorder.currentTime+0.5);
    [self.recorder stop];
    if (complition) {
        complition(self.lastPath, second);
    }
    [self.timer invalidate];
    self.timer = nil;
    //    []
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:NO error:nil];
}

- (void)cancleRecord {
    [self.timer invalidate];
    self.timer = nil;
    if (self.recorder) {
        [self.recorder deleteRecording];
        [self.recorder stop];
    }
}


- (void)updateMeters {
    /*  发送updateMeters消息来刷新平均和峰值功率。
     *  此计数是以对数刻度计量的，-160表示完全安静，
     *  0表示最大输入值
     */
    
    if (_recorder) {
        [_recorder updateMeters];
    }
    
    float peakPower = [_recorder averagePowerForChannel:0];
    double ALPHA = 0.05;
    double peakPowerForChannel = pow(10, (ALPHA * peakPower));
    
    if (self.volumeChange) {
        self.volumeChange(peakPowerForChannel);
    }
    if (self.timeChange) {
        self.timeChange([_recorder currentTime]);
        NSLog(@"%.3f", [_recorder currentTime]);
    }
}


- (void)dealloc {
    self.lastPath = nil;
    self.setting = nil;
    [self.timer invalidate];
    self.timer = nil;
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    NSLogCMD
    NSLog(@"flag : %d", flag);
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError * __nullable)error {
    NSLogCMD
    NSLog(@"error : %@", error);
}

- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
    NSLogCMD
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withOptions:(NSUInteger)flags {
    NSLogCMD
    NSLog(@"flags : %lu", flags);
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withFlags:(NSUInteger)flags {
    NSLogCMD
    NSLog(@"flags : %lu", flags);
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder {
    NSLogCMD
}

@end

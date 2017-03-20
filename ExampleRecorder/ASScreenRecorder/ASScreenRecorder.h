//
//  ASScreenRecorder.h
//  PrepareLesson
//
//  Created by yuelixing on 2017/3/10.
//  Copyright © 2017年 QingGuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void (^VideoCompletionBlock)(void);

@protocol ASScreenRecorderDelegate;

@interface ASScreenRecorder : NSObject
@property (nonatomic, readonly) BOOL isRecording;

// delegate is only required when implementing ASScreenRecorderDelegate - see below
@property (nonatomic, weak) id <ASScreenRecorderDelegate> delegate;

// if saveURL is nil, video will be saved into camera roll
// this property can not be changed whilst recording is in progress
@property (strong, nonatomic) NSURL *videoURL;

+ (instancetype)sharedInstance;
- (BOOL)startRecording;
- (void)stopRecordingWithCompletion:(VideoCompletionBlock)completionBlock;
// 检查音频权限
- (void)checkAudioAuth:(void (^)(BOOL granted))handler;

//@property (nonatomic, assign) NSInteger count;

@end


// If your view contains an AVCaptureVideoPreviewLayer or an openGL view
// you'll need to write that data into the CGContextRef yourself.
// In the viewcontroller responsible for the AVCaptureVideoPreviewLayer / openGL view
// set yourself as the delegate for ASScreenRecorder.
// [ASScreenRecorder sharedInstance].delegate = self
// Then implement 'writeBackgroundFrameInContext:(CGContextRef*)contextRef'
// use 'CGContextDrawImage' to draw your view into the provided CGContextRef
@protocol ASScreenRecorderDelegate <NSObject>
- (void)writeBackgroundFrameInContext:(CGContextRef*)contextRef;
@end

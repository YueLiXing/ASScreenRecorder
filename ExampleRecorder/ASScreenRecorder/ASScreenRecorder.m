//
//  ASScreenRecorder.m
//  PrepareLesson
//
//  Created by yuelixing on 2017/3/10.
//  Copyright © 2017年 QingGuo. All rights reserved.
//

#import "ASScreenRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "RecorderManager.h"

@interface ASScreenRecorder()
@property (strong, nonatomic) AVAssetWriter *videoWriter;
@property (strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *avAdaptor;
@property (strong, nonatomic) CADisplayLink *displayLink;
@property (strong, nonatomic) NSDictionary *outputBufferPoolAuxAttributes;
@property (nonatomic) CFTimeInterval firstTimeStamp;
@property (nonatomic) BOOL isRecording;

@property (nonatomic, copy) NSString * audioPath;

@property (nonatomic, assign) int showRecorde;

// 从下面复制上来的
@property (nonatomic, retain) dispatch_queue_t render_queue;

@property (nonatomic, retain) dispatch_queue_t append_pixelBuffer_queue;
@property (nonatomic, retain) dispatch_semaphore_t frameRenderingSemaphore;
@property (nonatomic, retain) dispatch_semaphore_t pixelAppendSemaphore;

@property (nonatomic, assign) CGSize viewSize;
@property (nonatomic, assign) CGFloat scale;

@property (nonatomic, assign) CGColorSpaceRef rgbColorSpace;
@property (nonatomic, assign) CVPixelBufferPoolRef outputBufferPool;

@property (nonatomic, copy) NSString * tempFilePath;

@end

@implementation ASScreenRecorder
//{
//    dispatch_queue_t _render_queue;
//    dispatch_queue_t _append_pixelBuffer_queue;
//    dispatch_semaphore_t _frameRenderingSemaphore;
//    dispatch_semaphore_t _pixelAppendSemaphore;
//    
//    CGSize _viewSize;
//    CGFloat _scale;
//    
//    CGColorSpaceRef _rgbColorSpace;
//    CVPixelBufferPoolRef _outputBufferPool;
//}

#pragma mark - initializers

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static ASScreenRecorder *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)checkAudioAuth:(void (^)(BOOL granted))handler {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(granted);
            });
        }
    }];
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        _viewSize = [UIApplication sharedApplication].delegate.window.bounds.size;
        _scale = [UIScreen mainScreen].scale;
        // record half size resolution for retina iPads
        if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) && _scale > 1) {
            _scale = 1.0;
        }
        _isRecording = NO;
        
        _append_pixelBuffer_queue = dispatch_queue_create("ASScreenRecorder.append_queue", DISPATCH_QUEUE_SERIAL);
        _render_queue = dispatch_queue_create("ASScreenRecorder.render_queue", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_render_queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        _frameRenderingSemaphore = dispatch_semaphore_create(1);
        _pixelAppendSemaphore = dispatch_semaphore_create(1);
        
//        self.count = 0;
    }
    return self;
}

#pragma mark - public

- (void)setVideoURL:(NSURL *)videoURL
{
    NSAssert(!_isRecording, @"videoURL can not be changed whilst recording is in progress");
    _videoURL = videoURL;
}

- (BOOL)startRecording
{
    if (_isRecording == NO) {
        [self setUpWriter];
        self.showRecorde = 0;
        _isRecording = (_videoWriter.status == AVAssetWriterStatusWriting);
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(writeVideoFrame)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.audioPath = nil;
//        if (self.count == 0) {
            [[RecorderManager shareManager] startRecordVolumeChange:nil TimeChange:nil];
//        }
//        self.count += 1 ;
    }
    return _isRecording;
}

- (void)stopRecordingWithCompletion:(VideoCompletionBlock)completionBlock;
{
    if (_isRecording) {
        [self.displayLink invalidate];
        self.displayLink = nil;
        if ([RecorderManager shareManager].recorder.isRecording) {
            [[RecorderManager shareManager] endRecord:^(NSString *filaPath, NSInteger sec) {
                self.audioPath = filaPath;
                LxLog(@"%@", filaPath);
                _isRecording = NO;
                
                [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
                [self completeRecordingSession:completionBlock];
            }];
        } else {
            _isRecording = NO;
            [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            [self completeRecordingSession:completionBlock];
        }
    }
}

#pragma mark - private

-(void)setUpWriter
{
    _rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    NSDictionary *bufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                       (id)kCVPixelBufferWidthKey : @(_viewSize.width * _scale),
                                       (id)kCVPixelBufferHeightKey : @(_viewSize.height * _scale),
                                       (id)kCVPixelBufferBytesPerRowAlignmentKey : @(_viewSize.width * _scale * 4)
                                       };
    
    _outputBufferPool = NULL;
    CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)(bufferAttributes), &_outputBufferPool);
    
    
    NSError* error = nil;
    NSURL * tempURL = [self tempFileURL];
    self.tempFilePath = tempURL.absoluteString;
    _videoWriter = [[AVAssetWriter alloc] initWithURL:tempURL
                                             fileType:AVFileTypeQuickTimeMovie
                                                error:&error];
    if (error) {
        LogError(@"%@", error);
    }
    NSParameterAssert(_videoWriter);
    
    NSInteger pixelNumber = _viewSize.width * _viewSize.height * _scale;
    NSDictionary* videoCompression = @{AVVideoAverageBitRateKey: @(pixelNumber * 11.4)};
    
    NSDictionary* videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                    AVVideoWidthKey: [NSNumber numberWithInt:_viewSize.width*_scale],
                                    AVVideoHeightKey: [NSNumber numberWithInt:_viewSize.height*_scale],
                                    AVVideoCompressionPropertiesKey: videoCompression};
    
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSParameterAssert(_videoWriterInput);
    
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    _videoWriterInput.transform = [self videoTransformForDeviceOrientation];
    
    _avAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:nil];
    
    [_videoWriter addInput:_videoWriterInput];
    
    [_videoWriter startWriting];
    [_videoWriter startSessionAtSourceTime:CMTimeMake(0, 1000)];
}

- (CGAffineTransform)videoTransformForDeviceOrientation
{
    CGAffineTransform videoTransform;
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationLandscapeLeft:
            videoTransform = CGAffineTransformMakeRotation(-M_PI_2);
            break;
        case UIDeviceOrientationLandscapeRight:
            videoTransform = CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            videoTransform = CGAffineTransformMakeRotation(M_PI);
            break;
        default:
            videoTransform = CGAffineTransformIdentity;
    }
    return videoTransform;
}

- (NSURL*)tempFileURL {
    NSString * string = [NSString stringWithFormat:@"tmp/screenCapture_%.lf.mp4", [NSDate date].timeIntervalSince1970];

    NSString *outputPath = [NSHomeDirectory() stringByAppendingPathComponent:string];
//    NSString *outputPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/screenCapture.mp4"];
//    [self removeTempFilePath:outputPath];
    return [NSURL fileURLWithPath:outputPath];
}

- (void)removeTempFilePath:(NSString*)filePath
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError* error;
        if ([fileManager removeItemAtPath:filePath error:&error] == NO) {
            NSLog(@"Could not delete old recording:%@", [error localizedDescription]);
        }
    }
}


- (void)completeRecordingSession:(VideoCompletionBlock)completionBlock {
    dispatch_async(_render_queue, ^{
        dispatch_sync(_append_pixelBuffer_queue, ^{
            
            [_videoWriterInput markAsFinished];
            [_videoWriter finishWritingWithCompletionHandler:^{
                
                void (^completion)(void) = ^() {
                    [self cleanup];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completionBlock) completionBlock();
                    });
                };
                LxLog(@"开始融合视频和音频");
                
                [self mergeVideo:_videoWriter.outputURL.absoluteString andAudio:self.audioPath ExportPath:self.videoURL Compltion:^{
                    LxLog(@"删除缓存视频文件和音频文件");
                    [self removeTempFilePath:self.tempFilePath];
                    [self removeTempFilePath:_videoWriter.outputURL.path];
                    [self removeTempFilePath:self.audioPath];
                    dispatch_async(dispatch_get_main_queue(), completion);
                }];
                
//                [self mergeVideo:_videoWriter.outputURL.absoluteString andAudio:self.audioPath Compltion:^(NSString * exportPath) {
//                    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
//                    [library writeVideoAtPathToSavedPhotosAlbum:[NSURL URLWithString:exportPath] completionBlock:^(NSURL *assetURL, NSError *error) {
//                        NSLog(@"保存融合后的视频 error:%@", error);
//                    }];
//                    
////                    NSCachesDirectory
////                    [NSFileManager defaultManager] moveItemAtPath:exportPath toPath: error:(NSError * _Nullable __autoreleasing * _Nullable)
//                    dispatch_async(dispatch_get_main_queue(), completion);
//                }];
//
            }];
        });
    });
}

- (void)cleanup
{
    self.avAdaptor = nil;
    self.videoWriterInput = nil;
    self.videoWriter = nil;
    self.firstTimeStamp = 0;
    self.outputBufferPoolAuxAttributes = nil;
    self.audioPath = nil;
    CGColorSpaceRelease(_rgbColorSpace);
    CVPixelBufferPoolRelease(_outputBufferPool);
}

- (void)writeVideoFrame {
    if (self.showRecorde != 0) {
        self.showRecorde += 1;
        if (self.showRecorde >= 1) {
            self.showRecorde = 0;
            return;
        }
    }
    self.showRecorde += 1;
    // throttle the number of frames to prevent meltdown
    // technique gleaned from Brad Larson's answer here: http://stackoverflow.com/a/5956119
    if (dispatch_semaphore_wait(_frameRenderingSemaphore, DISPATCH_TIME_NOW) != 0) {
        return;
    }
    dispatch_async(_render_queue, ^{
        if (![_videoWriterInput isReadyForMoreMediaData]) return;
        
        if (!self.firstTimeStamp) {
            self.firstTimeStamp = _displayLink.timestamp;
        }
        CFTimeInterval elapsed = (_displayLink.timestamp - self.firstTimeStamp);
        CMTime time = CMTimeMakeWithSeconds(elapsed, 1000);
        
        CVPixelBufferRef pixelBuffer = NULL;
        CGContextRef bitmapContext = [self createPixelBufferAndBitmapContext:&pixelBuffer];
        
        if (self.delegate) {
            [self.delegate writeBackgroundFrameInContext:&bitmapContext];
        }
        // draw each window into the context (other windows include UIKeyboard, UIAlert)
        // FIX: UIKeyboard is currently only rendered correctly in portrait orientation
        
//        dispatch_sync(dispatch_get_main_queue(), ^{
            UIGraphicsPushContext(bitmapContext); {
                for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                    [window drawViewHierarchyInRect:CGRectMake(0, 0, _viewSize.width, _viewSize.height) afterScreenUpdates:NO];
                }
            } UIGraphicsPopContext();
//        });
        
        // append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
        // must not overwhelm the queue with pixelBuffers, therefore:
        // check if _append_pixelBuffer_queue is ready
        // if it’s not ready, release pixelBuffer and bitmapContext
        if (dispatch_semaphore_wait(_pixelAppendSemaphore, DISPATCH_TIME_NOW) == 0) {
            dispatch_async(_append_pixelBuffer_queue, ^{
                BOOL success = [_avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                if (!success) {
                    LxLog(@"Warning: Unable to write buffer to video");
                }
                CGContextRelease(bitmapContext);
                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                CVPixelBufferRelease(pixelBuffer);
                
                dispatch_semaphore_signal(_pixelAppendSemaphore);
            });
        } else {
            CGContextRelease(bitmapContext);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            CVPixelBufferRelease(pixelBuffer);
        }
        
        dispatch_semaphore_signal(_frameRenderingSemaphore);
    });
}

- (CGContextRef)createPixelBufferAndBitmapContext:(CVPixelBufferRef *)pixelBuffer
{
    CVPixelBufferPoolCreatePixelBuffer(NULL, _outputBufferPool, pixelBuffer);
    CVPixelBufferLockBaseAddress(*pixelBuffer, 0);
    
    CGContextRef bitmapContext = NULL;
    bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(*pixelBuffer),
                                          CVPixelBufferGetWidth(*pixelBuffer),
                                          CVPixelBufferGetHeight(*pixelBuffer),
                                          8, CVPixelBufferGetBytesPerRow(*pixelBuffer), _rgbColorSpace,
                                          kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                          );
    CGContextScaleCTM(bitmapContext, _scale, _scale);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _viewSize.height);
    CGContextConcatCTM(bitmapContext, flipVertical);
    
    return bitmapContext;
}

- (void)mergeVideo:(NSString *)videoPath andAudio:(NSString *)audioPath ExportPath:(NSURL *) exportURL Compltion:(void(^)())completion {
    NSURL *audioUrl = [NSURL fileURLWithPath:audioPath];
    //    NSURL *videoUrl = [NSURL fileURLWithPath:videoPath];
    NSURL *videoUrl = [NSURL URLWithString:videoPath];
    
    AVURLAsset* audioAsset = [[AVURLAsset alloc]initWithURL:audioUrl options:nil];
    AVURLAsset* videoAsset = [[AVURLAsset alloc]initWithURL:videoUrl options:nil];
    
    
    AVMutableComposition* mixComposition = [AVMutableComposition composition];
    //混合音乐
    AVMutableCompositionTrack *compositionCommentaryTrack =
        [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                    preferredTrackID:kCMPersistentTrackID_Invalid];
    [compositionCommentaryTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset.duration)
                                        ofTrack:[[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0]
                                         atTime:kCMTimeZero error:nil];
    
    
    //混合视频
    AVMutableCompositionTrack *compositionVideoTrack =
        [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                    preferredTrackID:kCMPersistentTrackID_Invalid];
    [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration)
                                   ofTrack:[[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0]
                                    atTime:kCMTimeZero error:nil];
    AVAssetExportSession* _assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                          presetName:AVAssetExportPresetHighestQuality];
    
    
    
    //保存混合后的文件的过程
//    NSString* videoName = @"export2.mp4";
//    NSString *exportPath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:videoName];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:exportURL.absoluteString]) {
        [[NSFileManager defaultManager] removeItemAtURL:exportURL error:nil];
    }
    
    //    _assetExport.outputFileType = @"com.apple.quicktime-movie";
    _assetExport.outputFileType = AVFileTypeMPEG4;
    LxLog(@"file type %@",_assetExport.outputFileType);
    _assetExport.outputURL = exportURL;
    _assetExport.shouldOptimizeForNetworkUse = YES;
    
    [_assetExport exportAsynchronouslyWithCompletionHandler:^(void) {
        LxLog(@"完成了");
        // your completion code here
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    }];
}


@end

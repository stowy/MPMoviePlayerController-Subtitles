//
//  MPMoviePlayerController+Subtitles.h
//  MPMoviePlayerControllerSubtitles
//
//  Created by mhergon on 03/12/13.
//  Copyright (c) 2013 mhergon. All rights reserved.
//

#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface MPMoviePlayerController (Subtitles)

#pragma mark - Properties
@property (strong, nonatomic) NSMutableDictionary *subtitlesParts;
@property (strong, nonatomic) NSTimer *subtitleTimer;
@property (strong, nonatomic) UILabel *subtitleLabel;
@property (strong, nonatomic) UIView *subtitlesView;
@property (strong, nonatomic) AVPlayerLayer *playerLayer;
@property (strong, nonatomic) AVSynchronizedLayer *syncedLayer;

@property (nonatomic, readonly)  CGRect subtitleCurrentRect;
@property (nonatomic, strong) NSNumber *isInitialised;

#pragma mark - Methods
- (void)openWithSRTString:(NSString*)srtString completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure;
- (void)openSRTFileAtPath:(NSString *)localFile completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure;
- (void)showSubtitles;
- (void)hideSubtitles;




@end
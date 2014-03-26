//
//  MPMoviePlayerController+Subtitles.m
//  MPMoviePlayerControllerSubtitles
//
//  Created by mhergon on 03/12/13.
//  Copyright (c) 2013 mhergon. All rights reserved.
//

#import "MPMoviePlayerController+Subtitles.h"
#import <objc/runtime.h>
#import "UIViewHierarchy.h"


static NSString *const kIndex = @"kIndex";
static NSString *const kStart = @"kStart";
static NSString *const kEnd = @"kEnd";
static NSString *const kText = @"kText";

static CGFloat const SUBTITLE_INIT_HEIGHT = 100;
static NSTimeInterval const OFFSET_TIME = 8;


@interface MPMoviePlayerViewController ()

#pragma mark - Private methods
- (void)showSubtitles:(BOOL)show;
- (void)parseString:(NSString *)string parsed:(void (^)(BOOL parsed, NSError *error))completion;
- (NSTimeInterval)timeFromString:(NSString *)yimeString;
- (void)searchAndShowSubtitle;

#pragma mark - Notifications
- (void)playbackStateDidChange:(NSNotification *)notification;
- (void)orientationWillChange:(NSNotification *)notification;
- (void)orientationDidChange:(NSNotification *)notification;


@end

@implementation MPMoviePlayerController (Subtitles)
@dynamic subtitlesParts;
@dynamic subtitleLabel;
@dynamic subtitleTimer;
@dynamic subtitleCurrentRect;
@dynamic subtitlesView;
@dynamic playerLayer;
@dynamic syncedLayer;
@dynamic isInitialised;




#pragma mark - Methods
- (void)openSRTFileAtPath:(NSString *)localFile completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure {
    
    NSError *error = nil;
    NSStringEncoding encoding;
    //NSString *my_string = [[NSString alloc] initWithContentsOfURL:url
    //                                                     encoding:NSUTF8StringEncoding
    //                                                        error:&error];
    NSString *subtitleString = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:localFile]
                                                usedEncoding:&encoding
                                                       error:&error];
    NSLog(@"Encoding: %lu", (unsigned long)encoding);
    
    if (error)
    {
        NSLog(@"there was a problem reading a subtitles file: %@", error);
        return;
    }

    
    [self openWithSRTString:subtitleString completion:success failure:failure];
    
    
}

- (void)openWithSRTString:(NSString*)srtString completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure{
    
    [self parseString:srtString
               parsed:^(BOOL parsed, NSError *error) {
                   
                   if (!error && success != NULL) {
                       
                       //UIView *subview = [[self.view subviews][0] subviews][0];
                       UIView *videoView = [self.view findSubviewWithLayerOfClass:[AVPlayerLayer class]];
                       
                       if (videoView) {
                           self.subtitlesView = videoView;
                           self.playerLayer = (AVPlayerLayer *)videoView.layer;
                           // listen to readyForDisplay indicator
                           if (self.playerLayer.isReadyForDisplay) {
                               [self addSyncedLayerForPlayerLayer];
                           } else {
                               self.isInitialised = @NO;
//                               [self.playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:0 context:nil];
                           }
                           
                       }
                       
                       // Register for notifications
                       [[NSNotificationCenter defaultCenter] addObserver:self
                                                                selector:@selector(playbackStateDidChange:)
                                                                    name:MPMoviePlayerPlaybackStateDidChangeNotification
                                                                  object:nil];
                       
                       [[NSNotificationCenter defaultCenter] addObserver:self
                                                                selector:@selector(orientationWillChange:)
                                                                    name:UIApplicationWillChangeStatusBarFrameNotification
                                                                  object:nil];
                       
                       [[NSNotificationCenter defaultCenter] addObserver:self
                                                                selector:@selector(orientationDidChange:)
                                                                    name:UIDeviceOrientationDidChangeNotification
                                                                  object:nil];
                       
                       success(YES);
                       
                   } else if (error && failure != NULL) {
                       
                       failure(error);
                       
                   }
                   
               }];
    
}

- (void)showSubtitles:(BOOL)show {
    
    // Hide label
    self.subtitlesView.hidden = !show;
    
}

- (void)showSubtitles {
    
    [self showSubtitles:YES];
    
}

- (void)hideSubtitles {
    
    [self showSubtitles:NO];
    
}

#pragma mark - Private methods
- (void)parseString:(NSString *)string parsed:(void (^)(BOOL parsed, NSError *error))completion {
    
    // Create Scanner
    NSScanner *scanner = [NSScanner scannerWithString:string];
    
    // Subtitles parts
    self.subtitlesParts = [NSMutableDictionary dictionary];
    
    // Search for members
    while (!scanner.isAtEnd) {
        
        // Variables
        NSString *indexString;
        [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet]
                                intoString:&indexString];
        
        NSString *startString;
        [scanner scanUpToString:@" --> " intoString:&startString];
        [scanner scanString:@"-->" intoString:NULL];
        
        NSString *endString;
        [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet]
                                intoString:&endString];
        
        
        
        NSString *textString;
        [scanner scanUpToString:@"\r\n\r\n" intoString:&textString];
        textString = [textString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        // Regular expression to replace tags
        NSError *error = nil;
        NSRegularExpression *regExp = [NSRegularExpression regularExpressionWithPattern:@"[<|\\{][^>|\\^}]*[>|\\}]"
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&error];
        if (error) {
            completion(NO, error);
            return;
        }
        
        textString = [regExp stringByReplacingMatchesInString:textString
                                                      options:0
                                                        range:NSMakeRange(0, textString.length)
                                                 withTemplate:@""];
        
        
        // Temp object
        NSTimeInterval startInterval = [self timeFromString:startString];
        NSTimeInterval endInterval = [self timeFromString:endString];
        NSDictionary *tempInterval = @{
                                       kIndex : indexString,
                                       kStart : @(startInterval),
                                       kEnd : @(endInterval),
                                       kText : textString ? textString : @""
                                       };
        [self.subtitlesParts setObject:tempInterval
                                forKey:indexString];
        
    }
    
    completion(YES, nil);
    
}

- (NSTimeInterval)timeFromString:(NSString *)timeString {
    
    NSScanner *scanner = [NSScanner scannerWithString:timeString];
    
    int h, m, s, c;
    [scanner scanInt:&h];
    [scanner scanString:@":" intoString:NULL];
    [scanner scanInt:&m];
    [scanner scanString:@":" intoString:NULL];
    [scanner scanInt:&s];
    [scanner scanString:@"," intoString:NULL];
    [scanner scanInt:&c];
    
    return (h * 3600) + (m * 60) + s + (c / 1000.0);
    
}

- (void)searchAndShowSubtitle {
    
    NSDictionary *lastFounded = [self subtitleForPlaybackTime:self.currentPlaybackTime];
    
    // Show text
    if (lastFounded) {
        
        // Get text
        self.subtitleLabel.text = [lastFounded objectForKey:kText];
        [self resizeLabel:self.subtitleLabel];
        
        
        self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);
        
    } else {
        
        self.subtitleLabel.text = @"";
        
    }
    
    
}

-(void)resizeLabel:(UILabel *)label {
    // Label position
    CGSize size = [self sizeForText:label.text
                           withFont:label.font
               constrainedWithWidth:CGRectGetWidth(label.bounds)];
    
    label.frame = ({
        CGRect frame = label.frame;
        frame.size.height = size.height;
        frame;
    });
}

-(void)createAndAnimateSubtitles {
    
//    NSTimeInterval timeWithOffset = self.currentPlaybackTime + OFFSET_TIME;
    
//    NSDictionary *nextSubDict = [self subtitleForPlaybackTime:timeWithOffset];
    
    NSArray *subtitles = [self.subtitlesParts allValues];
    // Sort
    
    NSSortDescriptor *sortDescriptor =
    [[NSSortDescriptor alloc] initWithKey:kStart ascending:YES];
    
    NSArray *sortedSubs =  [subtitles sortedArrayUsingDescriptors:@[sortDescriptor]];

    for (NSDictionary *nextSubDict in sortedSubs) {
        
        CGFloat bottomScreenY = CGRectGetHeight(self.subtitlesView.bounds) + (SUBTITLE_INIT_HEIGHT / 2.0);
        
        UILabel *subtitleLabel = [self subtitleLabelAddedToSubtitlesViewAtYcenter:bottomScreenY];
        subtitleLabel.text = [nextSubDict objectForKey:kText];
        [self resizeLabel:subtitleLabel];
        
        subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        NSTimeInterval startTime = [[nextSubDict objectForKey:kStart] integerValue];
        NSTimeInterval endTime = [[nextSubDict objectForKey:kEnd] integerValue];
        NSTimeInterval duration = [[nextSubDict objectForKey:kEnd] integerValue] - startTime;

        if (startTime == 0) {
            startTime += 0.001;
        }
        
        CGFloat subtitleXPos = subtitleLabel.layer.position.x;
        CGFloat subtitleHeight = CGRectGetHeight(subtitleLabel.frame);
        
        CGPoint bottomScreen = CGPointMake(subtitleXPos, bottomScreenY);
        CGPoint offTopEndPoint = CGPointMake(subtitleXPos, 0 - subtitleHeight);
        
        CGPoint midPoint = CGPointMake(subtitleXPos, CGRectGetHeight(self.subtitlesView.frame)/2);
        CGPoint startCurrentVis = CGPointMake(subtitleXPos, midPoint.y + subtitleHeight/2);
        CGPoint endCurrentVis = CGPointMake(subtitleXPos, midPoint.y - subtitleHeight/2);
        
        CGPoint subStartPoint = bottomScreen;
        
        
        [self.syncedLayer addSublayer:subtitleLabel.layer];
        
        [UIView animateWithDuration:duration animations:^{
            
            CABasicAnimation* onAnim = [CABasicAnimation animationWithKeyPath:@"position"];
            onAnim.fromValue = [NSValue valueWithCGPoint:subStartPoint];
            onAnim.toValue = [NSValue valueWithCGPoint:startCurrentVis];
            onAnim.duration = OFFSET_TIME;
            onAnim.beginTime = startTime - OFFSET_TIME;
            onAnim.removedOnCompletion = NO;
            
            CABasicAnimation* mainAnim = [CABasicAnimation animationWithKeyPath:@"position"];
            mainAnim.fromValue = [NSValue valueWithCGPoint:startCurrentVis];
            mainAnim.toValue = [NSValue valueWithCGPoint:endCurrentVis];
            mainAnim.duration = duration;
            mainAnim.beginTime = startTime;
            mainAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            
            mainAnim.removedOnCompletion = NO;
            
            CABasicAnimation* offAnim = [CABasicAnimation animationWithKeyPath:@"position"];
            offAnim.fromValue = [NSValue valueWithCGPoint:endCurrentVis];
            offAnim.toValue = [NSValue valueWithCGPoint:offTopEndPoint];
            offAnim.duration = OFFSET_TIME;
            offAnim.beginTime = endTime;
            offAnim.removedOnCompletion = NO;

            [subtitleLabel.layer addAnimation:onAnim forKey:@"AnimateFrameBefore"];
            [subtitleLabel.layer addAnimation:mainAnim forKey:@"AnimateFrameDuring"];
            [subtitleLabel.layer addAnimation:offAnim forKey:@"AnimateFrameAfter"];
        }];
    }

    self.isInitialised = @YES;
    
}

-(NSDictionary *)subtitleForPlaybackTime:(NSTimeInterval)playbackTime {
    // Search for timeInterval
    NSPredicate *initialPredicate = [NSPredicate predicateWithFormat:@"(%@ >= %K) AND (%@ <= %K)", @(playbackTime), kStart, @(playbackTime), kEnd];
    NSArray *objectsFound = [[self.subtitlesParts allValues] filteredArrayUsingPredicate:initialPredicate];
    NSDictionary *lastFounded = (NSDictionary *)[objectsFound lastObject];
    
    return lastFounded;
}

-(CGSize)sizeForText:(NSString *)text withFont:(UIFont *)font constrainedWithWidth:(CGFloat)widthConstraint {
    
    CGSize size;
    
    if ([text respondsToSelector:@selector(boundingRectWithSize:options:context:)]) {
        
        NSAttributedString *attributedText =
        [[NSAttributedString alloc]
         initWithString:text
         attributes:@
         {
         NSFontAttributeName:font
         }];
        CGRect rect = [attributedText boundingRectWithSize:(CGSize){widthConstraint, CGFLOAT_MAX}
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                   context:nil];
        CGSize tempSize = rect.size;
        CGFloat height = ceilf(tempSize.height);
        CGFloat width = ceilf(tempSize.width);
        
        size = CGSizeMake(width, height);
        
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        size = [text sizeWithFont:font
                constrainedToSize:CGSizeMake(widthConstraint, CGFLOAT_MAX)];
#pragma clang diagnostic pop
    }
    
    return size;
}

#pragma mark - Notifications
- (void)playbackStateDidChange:(NSNotification *)notification {
    
    if (![self.isInitialised boolValue]) {
        [self addSyncedLayerForPlayerLayer];
    }
    
    switch (self.playbackState) {
            
        case MPMoviePlaybackStateStopped: {
            
            // Stop
            if (self.subtitleTimer.isValid) {
                [self.subtitleTimer invalidate];
            }
            
            break;
        }
            
        case MPMoviePlaybackStatePlaying: {
            
            // Start timer
            self.subtitleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                  target:self
                                                                selector:@selector(searchAndShowSubtitle)
                                                                userInfo:nil
                                                                 repeats:YES];
            [self.subtitleTimer fire];
            
            // Add label
            if (!self.subtitleLabel) {
                
                CGFloat yCenter = CGRectGetHeight(self.subtitlesView.bounds) - (SUBTITLE_INIT_HEIGHT / 2.0) - 15.0;
                
                self.subtitleLabel = [self subtitleLabelAddedToSubtitlesViewAtYcenter:yCenter];
            }
            
            break;
        }
            
        default: {
            
            break;
        }
            
    }
    
}

-(UILabel *)subtitleLabelAddedToSubtitlesViewAtYcenter:(CGFloat)yCenter {
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, CGRectGetWidth(self.subtitlesView.bounds) - 30.0, SUBTITLE_INIT_HEIGHT)];
    
    CGFloat xCenter = CGRectGetWidth(self.view.bounds) / 2.0;
    
    label.center = CGPointMake(xCenter, yCenter);
    label.backgroundColor = [UIColor clearColor];
    
    // Add label
    CGFloat fontSize = 0.0;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        fontSize = 40.0;
    } else {
        fontSize = 20.0;
    }
    label.font = [UIFont boldSystemFontOfSize:fontSize];
    
    label.textColor = [UIColor whiteColor];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(6.0, 6.0);
    label.layer.shadowOpacity = 0.9;
    label.layer.shadowRadius = 4.0;
    label.layer.shouldRasterize = YES;
    label.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    [self.subtitlesView addSubview:label];
    
    return label;
}

- (void)orientationWillChange:(NSNotification *)notification {
    
    // Hidden label
    self.subtitlesView.hidden = YES;
    
}

- (void)orientationDidChange:(NSNotification *)notification {
    
    // Label position
    
    CGSize size = [self sizeForText:self.subtitleLabel.text
                           withFont:self.subtitleLabel.font
               constrainedWithWidth:CGRectGetWidth(self.subtitleLabel.bounds)];
    
    self.subtitleLabel.frame = ({
        CGRect frame = self.subtitleLabel.frame;
        frame.size.height = size.height;
        frame;
    });
    self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);
    
    // Hidden label
    self.subtitlesView.hidden = NO;
    
}


-(void)addSyncedLayerForPlayerLayer {
    
    AVPlayerItem *item = self.playerLayer.player.currentItem;
    AVSynchronizedLayer *syncedLayer = [AVSynchronizedLayer synchronizedLayerWithPlayerItem:item];
    syncedLayer.frame = self.playerLayer.frame;
    
    UIView *videoView = self.subtitlesView;
    self.subtitlesView = [[UIView alloc] initWithFrame:videoView.frame];
    [videoView addSubview:self.subtitlesView];
    
    [self.subtitlesView.layer addSublayer:syncedLayer];
    self.syncedLayer = syncedLayer;
    [self createAndAnimateSubtitles];
}

-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context
{
    if ([keyPath isEqualToString:@"readyForDisplay"]) {
        AVPlayerLayer *layer = (AVPlayerLayer*) object;
        if (layer.readyForDisplay) {
            [layer removeObserver:self forKeyPath:@"readyForDisplay"];
            
            [self addSyncedLayerForPlayerLayer];
            
        }
        
    }
}


#pragma mark - Others
- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

- (void)setSubtitlesParts:(NSMutableDictionary *)subtitlesParts {
    
    objc_setAssociatedObject(self, @selector(subtitlesParts), subtitlesParts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (NSMutableDictionary *)subtitlesParts {
    
    return objc_getAssociatedObject(self, @selector(subtitlesParts));
    
}

- (void)setSubtitleTimer:(NSTimer *)timer {
    
    objc_setAssociatedObject(self, @selector(subtitleTimer), timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (NSTimer *)subtitleTimer {
    
    return objc_getAssociatedObject(self, @selector(subtitleTimer));
    
}

- (void)setSubtitleLabel:(UILabel *)subtitleLabel {
    
    objc_setAssociatedObject(self, @selector(subtitleLabel), subtitleLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (UILabel *)subtitleLabel {
    
    return objc_getAssociatedObject(self, @selector(subtitleLabel));
    
}

-(void)setSubtitlesView:(UIView *)subtitlesView {
    objc_setAssociatedObject(self, @selector(subtitlesView), subtitlesView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(UIView *)subtitlesView {
    return objc_getAssociatedObject(self, @selector(subtitlesView));
}

-(void)setPlayerLayer:(AVPlayerLayer *)playerLayer {
    objc_setAssociatedObject(self, @selector(playerLayer), playerLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(AVPlayerLayer *)playerLayer {
    return objc_getAssociatedObject(self, @selector(playerLayer));
}

-(void)setSyncedLayer:(AVSynchronizedLayer *)syncedLayer {
    objc_setAssociatedObject(self, @selector(syncedLayer), syncedLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(AVSynchronizedLayer *)syncedLayer {
    return objc_getAssociatedObject(self, @selector(syncedLayer));
}

-(CGRect)subtitleCurrentRect {
    
    CGFloat boundsHeight = CGRectGetHeight(self.view.bounds);
    
    CGFloat originY = 31*boundsHeight / 64;
    CGFloat visibleHeight = boundsHeight / 32;
    
    return CGRectMake(0, originY, CGRectGetWidth(self.view.bounds), visibleHeight);
}

-(void)setIsInitialised:(NSNumber *)isInitialised {
    objc_setAssociatedObject(self, @selector(isInitialised), isInitialised, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(NSNumber *)isInitialised {
    return objc_getAssociatedObject(self, @selector(isInitialised));
}


@end

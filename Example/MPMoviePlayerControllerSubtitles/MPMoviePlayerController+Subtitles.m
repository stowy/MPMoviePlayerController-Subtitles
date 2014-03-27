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
@dynamic subtitleCurrentRect;
@dynamic playerLayer;
@dynamic syncedLayer;
@dynamic isInitialised;
@dynamic startTime;



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
    self.syncedLayer.hidden = !show;
    
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



#pragma mark - Notifications
- (void)playbackStateDidChange:(NSNotification *)notification {
    
    if (![self.isInitialised boolValue]) {
        [self addSyncedLayerForPlayerLayer];
    }
    
    self.syncedLayer.hidden = NO;
    self.syncedLayer.timeOffset = [self.startTime doubleValue]  + self.currentPlaybackTime;;
    self.syncedLayer.beginTime = ([self.startTime doubleValue]);
    
    switch (self.playbackState) {
            
        case MPMoviePlaybackStateStopped: {
            self.syncedLayer.speed = 0;
            break;
        }
            
        case MPMoviePlaybackStatePlaying: {
            self.syncedLayer.timeOffset -=  CACurrentMediaTime() - [self.startTime doubleValue];
            self.syncedLayer.speed = 1;

            break;
        }
        case MPMoviePlaybackStatePaused: {
            self.syncedLayer.speed = 0;
            
            break;
        }
        case MPMoviePlaybackStateInterrupted:  {
            self.syncedLayer.speed = 0;
            
            break;
        }
        case MPMoviePlaybackStateSeekingForward: {
            self.syncedLayer.speed = 0;
            break;
        }
        case MPMoviePlaybackStateSeekingBackward: {
            self.syncedLayer.speed = 0;
            break;
        }
        default: {
            
            break;
        }
    }
    
}


#pragma mark - Scrolling Subtitles methods

-(void)addSyncedLayerForPlayerLayer {
    
    CALayer *syncedLayer = [CALayer layer];
    syncedLayer.frame = self.view.frame;
    
    [self.playerLayer addSublayer:syncedLayer];
    self.syncedLayer = syncedLayer;
    self.syncedLayer.hidden = NO;
    [self createAndAnimateSubtitles];
    
}


-(void)createAndAnimateSubtitles {
    
    self.syncedLayer.timeOffset = [self.syncedLayer convertTime:CACurrentMediaTime() fromLayer:nil];
    self.syncedLayer.beginTime = CACurrentMediaTime();
    self.startTime = @(CACurrentMediaTime());
    
    if (self.customBackgroundImage) {
        CALayer *layer = [CALayer layer];
        layer.frame = self.view.frame;
        layer.contents = (__bridge_transfer id)(self.customBackgroundImage.CGImage);
        [self.syncedLayer addSublayer:layer];
    }
    
    NSArray *subtitles = [self.subtitlesParts allValues];
    
    
    NSSortDescriptor *sortDescriptor =
    [[NSSortDescriptor alloc] initWithKey:kStart ascending:YES];
    
    NSArray *sortedSubs =  [subtitles sortedArrayUsingDescriptors:@[sortDescriptor]];
    
    for (NSDictionary *nextSubDict in sortedSubs) {
        
        NSTimeInterval startTime = [[nextSubDict objectForKey:kStart] integerValue];
        NSTimeInterval endTime = [[nextSubDict objectForKey:kEnd] integerValue];
        NSTimeInterval duration = endTime - startTime;
        
        if (startTime == 0) {
            startTime += 0.001;
        }
        
        CGFloat bottomScreenY = CGRectGetHeight(self.view.bounds) + (SUBTITLE_INIT_HEIGHT / 2.0);
        
        CATextLayer *subtitleLayer = [self subtitleLayerAddedToSubtitlesViewAtYcenter:bottomScreenY withText:[nextSubDict objectForKey:kText]];
        
        CGFloat subtitleXPos = subtitleLayer.position.x;
        CGFloat subtitleHeight = CGRectGetHeight(subtitleLayer.frame);
        
        CGPoint bottomScreen = CGPointMake(subtitleXPos, bottomScreenY);
        CGPoint offTopEndPoint = CGPointMake(subtitleXPos, 0 - subtitleHeight);
        
        CGPoint midPoint = CGPointMake(subtitleXPos, CGRectGetHeight(self.view.frame)/2);
        CGPoint startCurrentVis = CGPointMake(subtitleXPos, midPoint.y + subtitleHeight/2);
        CGPoint endCurrentVis = CGPointMake(subtitleXPos, midPoint.y - subtitleHeight/2);
        
        CGPoint subStartPoint = bottomScreen;
        
        [self.syncedLayer addSublayer:subtitleLayer];
        
        //        CABasicAnimation *basicAnim = [CABasicAnimation animationWithKeyPath:@"position"];
        //
        //        basicAnim.fromValue = [NSValue valueWithCGPoint:subStartPoint];
        //        basicAnim.toValue = [NSValue valueWithCGPoint:offTopEndPoint];
        //
        //        NSTimeInterval totDuration = duration + 2 * OFFSET_TIME;
        //        basicAnim.duration = totDuration;
        //        basicAnim.beginTime = CACurrentMediaTime()  + (startTime - OFFSET_TIME) - self.currentPlaybackTime;
        //        basicAnim.removedOnCompletion = NO;
        //
        //        [subtitleLayer addAnimation:basicAnim forKey:@"anim"];
        CAKeyframeAnimation *keyAnim = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        [keyAnim setValues:@[[NSValue valueWithCGPoint:subStartPoint],
                             [NSValue valueWithCGPoint:startCurrentVis],
                             [NSValue valueWithCGPoint:endCurrentVis],
                             [NSValue valueWithCGPoint:offTopEndPoint]]];
        
        
        NSTimeInterval totDuration = duration + 2 * OFFSET_TIME;
        keyAnim.duration = totDuration;
        keyAnim.beginTime = CACurrentMediaTime()  + (startTime - OFFSET_TIME) - self.currentPlaybackTime;
        
        float startVisTime = OFFSET_TIME / totDuration;
        float endVisTime = (OFFSET_TIME + duration) / totDuration;
        
        [keyAnim setKeyTimes:@[@0, @(startVisTime), @(endVisTime), @1]];
        keyAnim.removedOnCompletion = NO;
        
        [subtitleLayer addAnimation:keyAnim forKey:@"FullAnimation"];
        
    }
    
    self.syncedLayer.hidden = NO;
    self.isInitialised = @YES;
    
}

-(CATextLayer *)subtitleLayerAddedToSubtitlesViewAtYcenter:(CGFloat)yCenter withText:(NSString *)text {
    CATextLayer *textLayer = [CATextLayer layer];
    textLayer.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds) - 30.0, SUBTITLE_INIT_HEIGHT);
    
    CGFloat xCenter = CGRectGetWidth(self.view.bounds) / 2.0;
    
    textLayer.position = CGPointMake(xCenter, yCenter);
    
    textLayer.wrapped = YES;
    
    CGFloat fontSize = 0.0;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        fontSize = 40.0;
    } else {
        fontSize = 20.0;
    }

    textLayer.fontSize = fontSize;
    textLayer.font = CGFontCreateWithFontName((__bridge CFStringRef)([UIFont systemFontOfSize:fontSize].fontName));
    textLayer.foregroundColor = [[UIColor whiteColor] CGColor];
    textLayer.string = text;
    [self resizeLayer:textLayer];
    
    textLayer.backgroundColor = [[UIColor clearColor] CGColor];

    textLayer.alignmentMode = kCAAlignmentCenter;
    textLayer.shadowColor = [UIColor blackColor].CGColor;
    textLayer.shadowOffset = CGSizeMake(6.0, 6.0);
    textLayer.shadowOpacity = 0.9;
    textLayer.shadowRadius = 4.0;
    textLayer.shouldRasterize = YES;
    textLayer.rasterizationScale = [[UIScreen mainScreen] scale];
    
    return textLayer;
}

-(void)resizeLayer:(CATextLayer *)layer {
    // Label position
    CFTypeRef fontRef = layer.font;
    CFTypeID fType = CFGetTypeID(fontRef);
    
    NSString *fontName = nil;
    if (fType == CGFontGetTypeID()) {
        fontName = CFBridgingRelease(CGFontCopyPostScriptName((CGFontRef)fontRef));
    } else if (fType == CFStringGetTypeID()) {
        fontName = (__bridge NSString *)(fontRef);
    } else {
        fontName = [[UIFont systemFontOfSize:layer.fontSize] fontName];
    }
    UIFont *font = [UIFont fontWithName:fontName size:layer.fontSize];
    
    CGSize size = [self sizeForText:layer.string
                           withFont:font
               constrainedWithWidth:CGRectGetWidth(layer.bounds)];
    
    layer.frame = ({
        CGRect frame = layer.frame;
        frame.size.height = size.height;
        frame;
    });
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



- (void)orientationWillChange:(NSNotification *)notification {
    
    // Hidden label
//    self.subtitlesView.hidden = YES;
    
}

- (void)orientationDidChange:(NSNotification *)notification {
    
    // Label position
//    
//    CGSize size = [self sizeForText:self.subtitleLabel.text
//                           withFont:self.subtitleLabel.font
//               constrainedWithWidth:CGRectGetWidth(self.subtitleLabel.bounds)];
//    
//    self.subtitleLabel.frame = ({
//        CGRect frame = self.subtitleLabel.frame;
//        frame.size.height = size.height;
//        frame;
//    });
//    self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);
//    
//    // Hidden label
//    self.subtitlesView.hidden = NO;
    
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
            
            if (![self.isInitialised boolValue]) {
                [self addSyncedLayerForPlayerLayer];
            }
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

-(void)setStartTime:(NSNumber *)startTime {
    objc_setAssociatedObject(self, @selector(startTime), startTime, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(NSNumber *)startTime {
    return objc_getAssociatedObject(self, @selector(startTime));
}

-(void)setCustomBackgroundImage:(UIImage *)customBackgroundImage {
    objc_setAssociatedObject(self, @selector(customBackgroundImage), customBackgroundImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(UIImage *)customBackgroundImage {
    return  objc_getAssociatedObject(self, @selector(customBackgroundImage));
}
    

@end

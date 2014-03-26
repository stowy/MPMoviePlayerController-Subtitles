//
//  MPMoviePlayerController+Subtitles.m
//  MPMoviePlayerControllerSubtitles
//
//  Created by mhergon on 03/12/13.
//  Copyright (c) 2013 mhergon. All rights reserved.
//

#import "MPMoviePlayerController+Subtitles.h"
#import <objc/runtime.h>

static NSString *const kIndex = @"kIndex";
static NSString *const kStart = @"kStart";
static NSString *const kEnd = @"kEnd";
static NSString *const kText = @"kText";


@interface MPMoviePlayerViewController ()

#pragma mark - Properties
@property (strong, nonatomic) NSMutableDictionary *subtitlesParts;
@property (strong, nonatomic) NSTimer *subtitleTimer;
@property (strong, nonatomic) UILabel *subtitleLabel;

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

#pragma mark - Methods
- (void)openSRTFileAtPath:(NSString *)localFile completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure {
    
    // Error
    NSError *error = nil;
    NSStringEncoding encoding;
    
    // File to string
    NSString *subtitleString = [NSString stringWithContentsOfFile:localFile
                                                         usedEncoding:&encoding
                                                            error:&error];
    if (error && failure != NULL) {
        failure(error);
        return;
    }
    
    // Parse and show text
    
    [self openWithSRTString:subtitleString completion:success failure:failure];

    
}

- (void)openWithSRTString:(NSString*)srtString completion:(void (^)(BOOL finished))success failure:(void (^)(NSError *error))failure{
    
    [self parseString:srtString
               parsed:^(BOOL parsed, NSError *error) {
                   
                   if (!error && success != NULL) {
                       
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
    self.subtitleLabel.hidden = !show;
    
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
    
    // Search for timeInterval
    NSPredicate *initialPredicate = [NSPredicate predicateWithFormat:@"(%@ >= %K) AND (%@ <= %K)", @(self.currentPlaybackTime), kStart, @(self.currentPlaybackTime), kEnd];
    NSArray *objectsFound = [[self.subtitlesParts allValues] filteredArrayUsingPredicate:initialPredicate];
    NSDictionary *lastFounded = (NSDictionary *)[objectsFound lastObject];
    
    // Show text
    if (lastFounded) {
        
        // Get text
        self.subtitleLabel.text = [lastFounded objectForKey:kText];


        // Label position
        CGSize size = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font
                                          constrainedToSize:CGSizeMake(CGRectGetWidth(self.subtitleLabel.bounds), CGFLOAT_MAX)];
        self.subtitleLabel.frame = ({
            CGRect frame = self.subtitleLabel.frame;
            frame.size.height = size.height;
            frame;
        });
        self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);

    } else {
        
        self.subtitleLabel.text = @"";
        
    }
    
}

#pragma mark - Notifications
- (void)playbackStateDidChange:(NSNotification *)notification {
    
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
            
            [self addAndAnimateViews];
            // Add label
            if (!self.subtitleLabel) {
                
                // Add label
                CGFloat fontSize = 0.0;
                if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
                    fontSize = 40.0;
                } else {
                    fontSize = 20.0;
                }
                self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds) - 30.0, 100.0)];
                self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);
                self.subtitleLabel.backgroundColor = [UIColor clearColor];
                self.subtitleLabel.font = [UIFont boldSystemFontOfSize:fontSize];
                self.subtitleLabel.textColor = [UIColor whiteColor];
                self.subtitleLabel.numberOfLines = 0;
                self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
                self.subtitleLabel.layer.shadowColor = [UIColor blackColor].CGColor;
                self.subtitleLabel.layer.shadowOffset = CGSizeMake(6.0, 6.0);
                self.subtitleLabel.layer.shadowOpacity = 0.9;
                self.subtitleLabel.layer.shadowRadius = 4.0;
                self.subtitleLabel.layer.shouldRasterize = YES;
                self.subtitleLabel.layer.rasterizationScale = [[UIScreen mainScreen] scale];
                [self.view addSubview:self.subtitleLabel];
                
            }
            
            break;
        }
            
        default: {

            break;
        }
            
    }
    
}

-(void)addAndAnimateViews {
    UIView *view = self.view;
    
    CALayer *coverLayer = [CALayer layer];
    coverLayer.frame = CGRectInset(self.view.frame, 0,CGRectGetHeight(self.view.frame)/4);
    coverLayer.backgroundColor = [[UIColor blackColor] CGColor];
    [view.layer addSublayer:coverLayer];
    
    CATextLayer *textLayer = [CATextLayer layer];
    textLayer.frame = CGRectMake(0.0, CGRectGetHeight(self.view.bounds) / 2,
                                 CGRectGetWidth(self.view.bounds), 100.0);
    textLayer.string = @"Here is some text to display";
    [self formatTextLayer:textLayer];
    [view.layer addSublayer:textLayer];
    
    CATextLayer *textLayer2 = [CATextLayer layer];
    textLayer2.frame = CGRectOffset(textLayer.frame, 0, 45);
    textLayer2.string = @"Here is some more text to display";
    [self formatTextLayer:textLayer2];
    [view.layer addSublayer:textLayer2];
    
    CABasicAnimation* fadeAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeAnim.fromValue = [NSNumber numberWithFloat:1.0];
    fadeAnim.toValue = [NSNumber numberWithFloat:0.7];
    fadeAnim.duration = 1.0;
    [textLayer addAnimation:fadeAnim forKey:@"opacity"];
    
    // Change the actual data value in the layer to the final value.
    textLayer.opacity = 0.7;
    
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"position"];
    
    CGPoint endPoint = CGPointMake(textLayer.position.x, 100);
    anim.fromValue = [NSValue valueWithCGPoint:textLayer.position];
    anim.toValue = [NSValue valueWithCGPoint:endPoint];
    anim.duration = 3.0;
    
    textLayer.position = endPoint;
    
    [textLayer addAnimation:anim forKey:@"positionyStuff"];
}

-(void)formatTextLayer:(CATextLayer *)textLayer {
    textLayer.wrapped = YES;
    
    CGFloat fontSize = 0.0;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        fontSize = 40.0;
    } else {
        fontSize = 20.0;
    }
    textLayer.fontSize = fontSize;
    
    textLayer.backgroundColor = [[UIColor clearColor] CGColor];
    //    textLayer.font = CGFontCreateWithFontName(<#CFStringRef name#>);
    textLayer.foregroundColor = [[UIColor whiteColor] CGColor];
    //    self.subtitleLabel.numberOfLines = 0;
    textLayer.alignmentMode = kCAAlignmentCenter;
    textLayer.shadowColor = [UIColor blackColor].CGColor;
    textLayer.shadowOffset = CGSizeMake(6.0, 6.0);
    textLayer.shadowOpacity = 0.9;
    textLayer.shadowRadius = 4.0;
    textLayer.shouldRasterize = YES;
    textLayer.rasterizationScale = [[UIScreen mainScreen] scale];
}

- (void)orientationWillChange:(NSNotification *)notification {
    
    // Hidden label
    self.subtitleLabel.hidden = YES;
    
}

- (void)orientationDidChange:(NSNotification *)notification {
    
    [self addAndAnimateViews];
    // Label position
    CGSize size = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font
                                      constrainedToSize:CGSizeMake(CGRectGetWidth(self.subtitleLabel.bounds), CGFLOAT_MAX)];
    self.subtitleLabel.frame = ({
        CGRect frame = self.subtitleLabel.frame;
        frame.size.height = size.height;
        frame;
    });
    self.subtitleLabel.center = CGPointMake(CGRectGetWidth(self.view.bounds) / 2.0, CGRectGetHeight(self.view.bounds) - (CGRectGetHeight(self.subtitleLabel.bounds) / 2.0) - 15.0);
    
    // Hidden label
    self.subtitleLabel.hidden = NO;
    
}

#pragma mark - Others
- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

- (void)setSubtitlesParts:(NSMutableDictionary *)subtitlesParts {
    
    objc_setAssociatedObject(self, @"subtitlesParts", subtitlesParts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (NSMutableDictionary *)subtitlesParts {
    
    return objc_getAssociatedObject(self, @"subtitlesParts");
    
}

- (void)setSubtitleTimer:(NSTimer *)timer {
    
    objc_setAssociatedObject(self, @"timer", timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (NSTimer *)subtitleTimer {
    
    return objc_getAssociatedObject(self, @"timer");
    
}

- (void)setSubtitleLabel:(UILabel *)subtitleLabel {
    
    objc_setAssociatedObject(self, @"subtitleLabel", subtitleLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

- (UILabel *)subtitleLabel {
    
    return objc_getAssociatedObject(self, @"subtitleLabel");
    
}


@end

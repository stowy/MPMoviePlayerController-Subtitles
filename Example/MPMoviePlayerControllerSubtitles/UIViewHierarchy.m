//
//  UIViewHierarchy.m
//
//  Created by Denis Gryzlov on 09.08.13.
//  Copyright (c) 2013 Armada. All rights reserved.
//

#import "UIViewHierarchy.h"

@implementation UIView (Hierarchy)

- (UIView *) findSubviewOfClass:(Class)someClass {
    if ( [self isMemberOfClass:someClass] ) {
        return self;
    } else {
        for ( UIView *view in self.subviews ) {
            UIView *insideView = [view findSubviewOfClass:someClass];
            if ( insideView != nil ) {
                return insideView;
            }
        }
    }

    return nil;
}

- (UIView *) findSubviewOfClassName:(NSString *)someClassName {
    if ( [NSStringFromClass([self class]) isEqualToString:someClassName]) {
        return self;
    } else {
        for ( UIView *view in self.subviews ) {
            UIView *insideView = [view findSubviewOfClassName:someClassName];
            if ( insideView != nil ) {
                return insideView;
            }
        }
    }
    
    return nil;
}

- (UIView *) findSubviewWithLayerOfClass:(Class)someClass {
    if ( [self.layer isMemberOfClass:someClass] ) {
        return self;
    } else {
        for ( UIView *view in self.subviews ) {
            UIView *insideView = [view findSubviewWithLayerOfClass:someClass];
            if ( insideView != nil ) {
                return insideView;
            }
        }
    }
    
    return nil;
}


- (void) dumpViewHierarchy {
    int level = 0;
    [self _logViewHierarchyWithLevel:&level];
}

- (void) _logViewHierarchyWithLevel:(int *)level {
    NSMutableString *paddingStr = [NSMutableString new];
    for (int i = 0; i < *level; i++) {
        [paddingStr appendString:@"   "];
    }
    
    NSLog(@"%@%@", paddingStr, self);
    
    *level = *level + 1;
    
    for ( UIView *subview in self.subviews ) {
        if ( subview.subviews.count > 0 ) {
            [subview _logViewHierarchyWithLevel:level];
        }
        else {
            NSLog(@"%@> %@", paddingStr, subview);
        }
    }
}

@end
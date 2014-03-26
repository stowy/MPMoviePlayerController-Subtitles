//
//  UIViewHierarchy.h
//
//  Created by Denis Gryzlov on 09.08.13.
//  Copyright (c) 2013 Armada. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIView (Hierarchy)

- (UIView *) findSubviewOfClassName:(NSString *)someClassName;
- (UIView *) findSubviewOfClass:(Class)someClass;

- (UIView *) findSubviewWithLayerOfClass:(Class)someClass;

- (void) dumpViewHierarchy;

@end
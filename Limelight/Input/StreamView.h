//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@end

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (OnScreenControlsLevel) getCurrentOscState;

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;

// Draw the host's mouse pointer here, so it moves without waiting for video.
// The host leaves it out of the video once asked, which only a host with
// LI_FF_LOCAL_CURSOR does. Returns whether it was asked.
- (BOOL) startLocalCursor;
- (BOOL) isLocalCursorActive;
- (void) setHostCursorVisible:(BOOL)visible image:(NSData*)image width:(int)width height:(int)height hotX:(int)hotX hotY:(int)hotY scale:(int)scale;

// Move the pointer by a distance in this view's points. Only possible while
// the pointer is drawn here, since only then is its position known here.
- (BOOL) moveLocalCursorBy:(CGPoint)delta;
#endif

@end

//
//  ConnectionCallbacks.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

@protocol ConnectionCallbacks <NSObject>

- (void) connectionStarted;
- (void) connectionTerminated:(int)errorCode;
- (void) stageStarting:(const char*)stageName;
- (void) stageComplete:(const char*)stageName;
- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags;
- (void) launchFailed:(NSString*)message;
- (void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor;
- (void) connectionStatusUpdate:(int)status;
- (void) setHdrMode:(bool)enabled;
- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger;
- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz;
- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;
- (void) videoContentShown;

// The host's mouse pointer for the client to draw. image is nil when the
// image has not changed, and is BGRA with straight alpha otherwise.
- (void) localCursorUpdate:(BOOL)visible image:(NSData*)image width:(int)width height:(int)height hotX:(int)hotX hotY:(int)hotY scale:(int)scale;

@end

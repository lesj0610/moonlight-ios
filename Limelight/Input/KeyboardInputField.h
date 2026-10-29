//
//  KeyboardInputField.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/2/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How the keyboard input field handles its text, so that dictation can be
// compared across runs
typedef NS_ENUM(NSInteger, InputDiagMode) {
    // A: as before, except that U+FFFC is not sent
    InputDiagModeSend,
    // B: nothing is sent and the field is not reset
    InputDiagModeKeep,
    // C: as B, and the field claims the dictation end calls
    InputDiagModeKeepEndCalls,
};

// Temporary diagnostics for dictation into the keyboard input field. Keeps
// the last events in memory until they are copied out, and writes each one
// to the system log.
@interface InputDiagnostics : NSObject

// Safe to call from any thread
+ (void)record:(NSString *)event;

+ (InputDiagMode)mode;
+ (NSString *)modeName;

// Moves to the next mode
+ (void)nextMode;

// Counts a new run and returns its number
+ (NSUInteger)beginTrial;
+ (NSUInteger)trial;

// Text as Unicode scalar values, so that invisible characters show
+ (NSString *)describeText:(nullable NSString *)text;

+ (NSString *)exportWithCount:(NSUInteger *)count;

@end

@interface KeyboardInputField : UITextField

// Text, selection, marked text and input mode. Main thread only.
- (NSString *)diagState;

// Which optional text input methods UITextField implements
- (NSString *)diagOptionalMethods;

@end

NS_ASSUME_NONNULL_END

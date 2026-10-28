//
//  KeyboardInputField.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/2/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Temporary diagnostics for dictation into the keyboard input field. Keeps
// the last events in memory until they are copied out.
@interface InputDiagnostics : NSObject

// Safe to call from any thread
+ (void)record:(NSString *)event;

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

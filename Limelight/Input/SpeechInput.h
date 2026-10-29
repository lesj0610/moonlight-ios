//
//  SpeechInput.h
//  Moonlight
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Called on the main thread
@protocol SpeechInputDelegate <NSObject>

// What has been heard so far, while listening, or after recognition ended
// before the text was asked for
- (void)speechInputShowsText:(NSString *)text inLanguage:(NSString *)language listening:(BOOL)listening;

// Listening ended, with the text to send, or nil if there is none
- (void)speechInputFinishedWithText:(nullable NSString *)text;

- (void)speechInputFailed:(NSString *)message;

@end

// Turns what the user says into text, using the iPad's speech recognition.
// Main thread only.
@interface SpeechInput : NSObject

@property (nonatomic, weak) id<SpeechInputDelegate> delegate;

// From start until the delegate gets the text or a failure
@property (nonatomic, readonly) BOOL isActive;

// Listens in the first of the iPad's preferred languages that speech
// recognition supports, or the second one
- (void)startInSecondLanguage:(BOOL)secondLanguage;

// Stops listening and hands over the text, or the text kept after
// recognition ended
- (void)stop;

// Stops listening and drops the text
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

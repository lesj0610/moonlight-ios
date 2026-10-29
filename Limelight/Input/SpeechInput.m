//
//  SpeechInput.m
//  Moonlight
//

#import "SpeechInput.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <os/log.h>

typedef NS_ENUM(NSInteger, SpeechInputState) {
    SpeechInputIdle,
    SpeechInputStarting,
    SpeechInputListening,
    SpeechInputFinishing,
    // Recognition ended, or the final text is late, so the text waits for
    // the user to ask for it
    SpeechInputHeld,
};

// How long to wait for the final text after listening stops
static const NSTimeInterval FINAL_TEXT_TIMEOUT = 5.0;

// How long nothing new is heard before the sentence counts as finished and
// listening stops, as if Globe-D was pressed
static const NSTimeInterval PAUSE_TIMEOUT = 1.5;

// Public, so that it can be read from the system log. It never has the text.
static os_log_t speechLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.moonlight-stream.Moonlight", "SpeechInput");
    });
    return log;
}

@implementation SpeechInput {
    SpeechInputState state;

    // Bumped when listening ends, so that later callbacks are ignored
    NSUInteger generation;

    SFSpeechRecognizer* recognizer;
    SFSpeechAudioBufferRecognitionRequest* request;
    SFSpeechRecognitionTask* task;
    AVAudioEngine* engine;
    NSString* languageName;
    NSString* heardText;
    NSUInteger heardChanges;

    // The audio session as it was before listening
    BOOL sessionChanged;
    AVAudioSessionCategory savedCategory;
    AVAudioSessionMode savedMode;
    AVAudioSessionCategoryOptions savedOptions;
}

- (BOOL)isActive {
    return state != SpeechInputIdle;
}

// The first two of the preferred languages that speech recognition supports,
// with English after them
+ (NSArray<NSLocale *> *)languages {
    NSSet<NSLocale *>* supported = [SFSpeechRecognizer supportedLocales];
    NSString* currentCountry = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    NSMutableArray<NSLocale *>* languages = [NSMutableArray array];
    NSMutableSet<NSString *>* languageCodes = [NSMutableSet set];

    for (NSString* identifier in [[NSLocale preferredLanguages] arrayByAddingObject:@"en-US"]) {
        NSLocale* wanted = [NSLocale localeWithLocaleIdentifier:identifier];
        NSString* languageCode = [wanted objectForKey:NSLocaleLanguageCode];
        if (languageCode == nil || [languageCodes containsObject:languageCode]) {
            continue;
        }

        // The same country if there is one, else the iPad's country, else the US
        NSArray<NSString *>* countries = @[[wanted objectForKey:NSLocaleCountryCode] ?: @"",
                                           currentCountry ?: @"",
                                           @"US"];
        NSLocale* match = nil;
        NSUInteger matchRank = NSNotFound;
        for (NSLocale* locale in supported) {
            if (![[locale objectForKey:NSLocaleLanguageCode] isEqualToString:languageCode]) {
                continue;
            }
            NSString* country = [locale objectForKey:NSLocaleCountryCode] ?: @"";
            NSUInteger rank = [countries indexOfObject:country];
            if (match == nil || rank < matchRank) {
                match = locale;
                matchRank = rank;
            }
        }

        if (match != nil) {
            [languageCodes addObject:languageCode];
            [languages addObject:match];
            if (languages.count == 2) {
                break;
            }
        }
    }

    return languages;
}

- (void)startInSecondLanguage:(BOOL)secondLanguage {
    if (state != SpeechInputIdle) {
        return;
    }

    NSArray<NSLocale *>* languages = [SpeechInput languages];
    if (languages.count == 0) {
        os_log(speechLog(), "MLSPEECH no supported language");
        [self.delegate speechInputFailed:NSLocalizedString(@"Speech recognition does not support the iPad's languages", nil)];
        return;
    }
    NSLocale* locale = languages[secondLanguage && languages.count > 1 ? 1 : 0];

    state = SpeechInputStarting;
    NSUInteger current = ++generation;
    [self requestPermissions:^(BOOL granted) {
        if (current != self->generation) {
            return;
        }
        if (!granted) {
            [self finishWithText:nil failure:NSLocalizedString(@"Allow the microphone and speech recognition for Moonlight in Settings", nil)];
            return;
        }
        [self listenInLocale:locale];
    }];
}

// Calls back on the main thread
- (void)requestPermissions:(void (^)(BOOL granted))completion {
    void (^microphoneHandler)(BOOL) = ^(BOOL granted) {
        os_log(speechLog(), "MLSPEECH microphone permission %d", granted);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(granted);
        });
    };

    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        os_log(speechLog(), "MLSPEECH speech recognition permission %ld", (long)status);
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
            return;
        }

        if (@available(iOS 17.0, *)) {
            [AVAudioApplication requestRecordPermissionWithCompletionHandler:microphoneHandler];
        }
        else {
            [[AVAudioSession sharedInstance] requestRecordPermission:microphoneHandler];
        }
    }];
}

- (void)listenInLocale:(NSLocale *)locale {
    recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    os_log(speechLog(), "MLSPEECH start %{public}@, available %d, on device %d",
           locale.localeIdentifier, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition);
    if (recognizer == nil || !recognizer.isAvailable) {
        [self finishWithText:nil failure:NSLocalizedString(@"Speech recognition is not available right now", nil)];
        return;
    }

    // The stream plays through a session that cannot record, so it is
    // switched while listening and put back after
    AVAudioSession* session = [AVAudioSession sharedInstance];
    savedCategory = session.category;
    savedMode = session.mode;
    savedOptions = session.categoryOptions;
    NSError* error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers |
                              AVAudioSessionCategoryOptionDefaultToSpeaker |
                              AVAudioSessionCategoryOptionAllowBluetoothA2DP
                        error:&error]) {
        os_log(speechLog(), "MLSPEECH session category failed: %{public}@", error);
        [self finishWithText:nil failure:NSLocalizedString(@"Could not start listening", nil)];
        return;
    }
    sessionChanged = YES;
    if (![session setActive:YES error:&error]) {
        os_log(speechLog(), "MLSPEECH session activation failed: %{public}@", error);
        [self finishWithText:nil failure:NSLocalizedString(@"Could not start listening", nil)];
        return;
    }

    request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    request.shouldReportPartialResults = YES;
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition;
    if (@available(iOS 16.0, *)) {
        request.addsPunctuation = YES;
    }

    engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode* input = engine.inputNode;
    AVAudioFormat* format = [input outputFormatForBus:0];
    os_log(speechLog(), "MLSPEECH input %.0f Hz, %u channels", format.sampleRate, format.channelCount);
    if (format.sampleRate == 0 || format.channelCount == 0) {
        [self finishWithText:nil failure:NSLocalizedString(@"Could not start listening", nil)];
        return;
    }
    SFSpeechAudioBufferRecognitionRequest* audioRequest = request;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
        [audioRequest appendAudioPCMBuffer:buffer];
    }];
    [engine prepare];
    if (![engine startAndReturnError:&error]) {
        os_log(speechLog(), "MLSPEECH audio engine failed: %{public}@", error);
        [self finishWithText:nil failure:NSLocalizedString(@"Could not start listening", nil)];
        return;
    }

    // Results come on the main queue
    NSUInteger current = generation;
    __weak SpeechInput* weakSelf = self;
    task = [recognizer recognitionTaskWithRequest:request
                                    resultHandler:^(SFSpeechRecognitionResult* result, NSError* error) {
        [weakSelf handleResult:result error:error generation:current];
    }];

    state = SpeechInputListening;
    languageName = [[NSLocale currentLocale] localizedStringForLanguageCode:[locale objectForKey:NSLocaleLanguageCode]] ?: locale.localeIdentifier;
    heardText = @"";
    [self.delegate speechInputShowsText:heardText inLanguage:languageName listening:YES];
}

- (void)handleResult:(SFSpeechRecognitionResult *)result error:(NSError *)error generation:(NSUInteger)current {
    if (current != generation) {
        return;
    }

    NSString* previousText = heardText;
    if (result != nil) {
        heardText = result.bestTranscription.formattedString;
    }
    if (state == SpeechInputHeld) {
        if (result != nil) {
            [self.delegate speechInputShowsText:heardText inLanguage:languageName listening:NO];
        }
        return;
    }
    if (!result.isFinal && error == nil) {
        if (state == SpeechInputListening && ![heardText isEqualToString:previousText]) {
            [self.delegate speechInputShowsText:heardText inLanguage:languageName listening:YES];
            [self stopAfterPause];
        }
        return;
    }

    os_log(speechLog(), "MLSPEECH ended while %ld, final %d, %lu characters, error %{public}@ %ld",
           (long)state, result.isFinal, (unsigned long)heardText.length, error.domain, (long)error.code);
    if (result.isFinal && state == SpeechInputFinishing) {
        [self finishWithText:heardText failure:nil];
    }
    else if (heardText.length == 0) {
        [self finishWithText:nil failure:state == SpeechInputListening ? NSLocalizedString(@"Speech recognition stopped", nil) : nil];
    }
    else {
        // It also ends by itself, after about a minute of server recognition
        [self holdText];
    }
}

// Stops listening unless something new is heard before the pause ends
- (void)stopAfterPause {
    NSUInteger changes = ++heardChanges;
    NSUInteger current = generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PAUSE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (current == self->generation && changes == self->heardChanges && self->state == SpeechInputListening) {
            os_log(speechLog(), "MLSPEECH pause");
            [self stop];
        }
    });
}

// Stops listening but keeps the task, so that a late final text still comes
- (void)holdText {
    state = SpeechInputHeld;
    [self stopAudio];
    [request endAudio];
    [self restoreSession];
    [self.delegate speechInputShowsText:heardText inLanguage:languageName listening:NO];
}

- (void)stop {
    if (state == SpeechInputStarting) {
        [self cancel];
        return;
    }
    if (state == SpeechInputHeld) {
        [self finishWithText:heardText failure:nil];
        return;
    }
    if (state != SpeechInputListening) {
        return;
    }

    os_log(speechLog(), "MLSPEECH stop, %lu characters so far", (unsigned long)heardText.length);
    state = SpeechInputFinishing;
    [self stopAudio];
    [request endAudio];

    NSUInteger current = generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FINAL_TEXT_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (current == self->generation && self->state == SpeechInputFinishing) {
            os_log(speechLog(), "MLSPEECH no final text in time, %lu characters", (unsigned long)self->heardText.length);
            if (self->heardText.length > 0) {
                [self holdText];
            }
            else {
                [self finishWithText:nil failure:nil];
            }
        }
    });
}

- (void)cancel {
    if (state != SpeechInputIdle) {
        os_log(speechLog(), "MLSPEECH cancel");
        [self finishWithText:nil failure:nil];
    }
}

- (void)stopAudio {
    if (engine != nil) {
        [engine.inputNode removeTapOnBus:0];
        [engine stop];
        engine = nil;
    }
}

- (void)finishWithText:(NSString *)text failure:(NSString *)failure {
    generation++;
    state = SpeechInputIdle;

    [self stopAudio];
    [task cancel];
    task = nil;
    request = nil;
    recognizer = nil;
    [self restoreSession];

    if (failure != nil) {
        [self.delegate speechInputFailed:failure];
    }
    else {
        [self.delegate speechInputFinishedWithText:text.length > 0 ? text : nil];
    }
}

- (void)restoreSession {
    if (sessionChanged) {
        sessionChanged = NO;
        NSError* error = nil;
        if (![[AVAudioSession sharedInstance] setCategory:savedCategory mode:savedMode options:savedOptions error:&error]) {
            os_log(speechLog(), "MLSPEECH session restore failed: %{public}@", error);
        }
    }
}

@end

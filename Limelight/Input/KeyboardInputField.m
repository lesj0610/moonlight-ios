//
//  KeyboardInputField.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/2/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import "KeyboardInputField.h"
#import <QuartzCore/QuartzCore.h>

static const NSUInteger DIAG_MAX_EVENTS = 500;

static NSMutableArray<NSString *>* diagEvents;
static NSUInteger diagSequence;
static NSUInteger diagOverwritten;
static CFTimeInterval diagStart;

@implementation InputDiagnostics

+ (void)record:(NSString *)event {
    CFTimeInterval now = CACurrentMediaTime();
    NSString* thread = [NSThread isMainThread] ? @"main" : @"send";

    @synchronized ([InputDiagnostics class]) {
        if (diagEvents == nil) {
            diagEvents = [[NSMutableArray alloc] init];
            diagStart = now;
        }

        diagSequence++;
        [diagEvents addObject:[NSString stringWithFormat:@"%lu +%.1fms %@ %@",
                               (unsigned long)diagSequence, (now - diagStart) * 1000, thread, event]];
        if (diagEvents.count > DIAG_MAX_EVENTS) {
            [diagEvents removeObjectAtIndex:0];
            diagOverwritten++;
        }
    }
}

+ (NSString *)describeText:(NSString *)text {
    if (text == nil) {
        return @"nil";
    }

    NSMutableString* description = [NSMutableString stringWithFormat:@"len=%lu [", (unsigned long)text.length];
    NSUInteger shown = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        if (shown == 48) {
            [description appendFormat:@" ...+%lu units", (unsigned long)(text.length - i)];
            break;
        }

        unichar c = [text characterAtIndex:i];
        uint32_t scalar = c;
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < text.length &&
            CFStringIsSurrogateLowCharacter([text characterAtIndex:i + 1])) {
            scalar = (uint32_t)CFStringGetLongCharacterForSurrogatePair(c, [text characterAtIndex:i + 1]);
            i++;
        }
        [description appendFormat:shown == 0 ? @"U+%04X" : @" U+%04X", scalar];
        shown++;
    }
    [description appendString:@"]"];
    return description;
}

+ (NSString *)exportWithCount:(NSUInteger *)count {
    NSString* header;
    NSArray<NSString *>* events;

    @synchronized ([InputDiagnostics class]) {
        events = [diagEvents copy] ?: @[];
        header = [NSString stringWithFormat:@"Moonlight input log: %lu events kept, %lu recorded, %lu overwritten, iOS %@, exported %@\n",
                  (unsigned long)events.count, (unsigned long)diagSequence, (unsigned long)diagOverwritten,
                  [[UIDevice currentDevice] systemVersion], [NSDate date]];
    }

    *count = events.count;
    return [header stringByAppendingString:[events componentsJoinedByString:@"\n"]];
}

@end

@implementation KeyboardInputField {
    // How deep the observed calls are nested, so that a call UIKit makes
    // from inside another is not taken for a separate input
    int diagDepth;
}

- (UIEditingInteractionConfiguration) editingInteractionConfiguration {
    // Suppress the Undo menu that appears with a 3 finger tap
    return UIEditingInteractionConfigurationNone;
}

- (NSString *)diagRange:(UITextRange *)range {
    if (range == nil) {
        return @"nil";
    }

    NSInteger location = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    NSInteger length = [self offsetFromPosition:range.start toPosition:range.end];
    return [NSString stringWithFormat:@"{%ld,%ld}", (long)location, (long)length];
}

- (NSString *)diagState {
    if (![NSThread isMainThread]) {
        return @"(not on the main thread)";
    }

    NSString* mode = @"?";
#if !TARGET_OS_TV
    mode = self.textInputMode.primaryLanguage ?: @"nil";
#endif
    return [NSString stringWithFormat:@"text=%@ sel=%@ marked=%@ mode=%@ first=%d",
            [InputDiagnostics describeText:self.text],
            [self diagRange:self.selectedTextRange],
            [self diagRange:self.markedTextRange],
            mode, self.isFirstResponder];
}

- (void)diagRecord:(NSString *)event {
    [InputDiagnostics record:[NSString stringWithFormat:@"%*s%@", diagDepth * 2, "", event]];
}

- (void)diagBefore:(NSString *)call {
    [self diagRecord:[NSString stringWithFormat:@"> %@ | %@", call, [self diagState]]];
    diagDepth++;
}

- (void)diagAfter:(NSString *)call {
    diagDepth--;
    [self diagRecord:[NSString stringWithFormat:@"< %@ | %@", call, [self diagState]]];
}

#if !TARGET_OS_TV

// Optional UITextInput methods observed here. The field claims them only
// where UITextField has them, so that UIKit treats it as it did before.
+ (NSArray<NSString *> *)diagOptionalSelectors {
    static NSArray<NSString *>* selectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        selectors = @[@"insertDictationResult:",
                 @"dictationRecordingDidEnd",
                 @"dictationRecognitionFailed",
                 @"insertDictationResultPlaceholder",
                 @"frameForDictationResultPlaceholder:",
                 @"removeDictationResultPlaceholder:willInsertResult:",
                 @"insertTextPlaceholderWithSize:",
                 @"removeTextPlaceholder:",
                 @"insertText:alternatives:style:",
                 @"setAttributedMarkedText:selectedRange:"];
    });
    return selectors;
}

+ (BOOL)textFieldHas:(SEL)selector {
    return [UITextField instancesRespondToSelector:selector];
}

- (BOOL)respondsToSelector:(SEL)selector {
    if ([[KeyboardInputField diagOptionalSelectors] containsObject:NSStringFromSelector(selector)]) {
        return [KeyboardInputField textFieldHas:selector];
    }
    return [super respondsToSelector:selector];
}

- (NSString *)diagOptionalMethods {
    NSMutableArray<NSString *>* present = [NSMutableArray array];
    NSMutableArray<NSString *>* missing = [NSMutableArray array];
    for (NSString* name in [KeyboardInputField diagOptionalSelectors]) {
        if ([KeyboardInputField textFieldHas:NSSelectorFromString(name)]) {
            [present addObject:name];
        }
        else {
            [missing addObject:name];
        }
    }
    return [NSString stringWithFormat:@"UITextField has: %@; lacks: %@",
            [present componentsJoinedByString:@" "], [missing componentsJoinedByString:@" "]];
}

- (void)insertText:(NSString *)text {
    NSString* call = [NSString stringWithFormat:@"insertText: %@", [InputDiagnostics describeText:text]];
    [self diagBefore:call];
    [super insertText:text];
    [self diagAfter:call];
}

- (void)deleteBackward {
    [self diagBefore:@"deleteBackward"];
    [super deleteBackward];
    [self diagAfter:@"deleteBackward"];
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    NSString* call = [NSString stringWithFormat:@"setMarkedText: %@ selectedRange:{%lu,%lu}",
                      [InputDiagnostics describeText:markedText],
                      (unsigned long)selectedRange.location, (unsigned long)selectedRange.length];
    [self diagBefore:call];
    [super setMarkedText:markedText selectedRange:selectedRange];
    [self diagAfter:call];
}

- (void)setAttributedMarkedText:(NSAttributedString *)markedText selectedRange:(NSRange)selectedRange {
    NSString* call = [NSString stringWithFormat:@"setAttributedMarkedText: %@ selectedRange:{%lu,%lu}",
                      [InputDiagnostics describeText:markedText.string],
                      (unsigned long)selectedRange.location, (unsigned long)selectedRange.length];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super setAttributedMarkedText:markedText selectedRange:selectedRange];
    }
    [self diagAfter:call];
}

- (void)unmarkText {
    [self diagBefore:@"unmarkText"];
    [super unmarkText];
    [self diagAfter:@"unmarkText"];
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    NSString* call = [NSString stringWithFormat:@"replaceRange:%@ withText: %@",
                      [self diagRange:range], [InputDiagnostics describeText:text]];
    [self diagBefore:call];
    [super replaceRange:range withText:text];
    [self diagAfter:call];
}

- (void)insertText:(NSString *)text alternatives:(NSArray<NSString *> *)alternatives style:(UITextAlternativeStyle)style API_AVAILABLE(ios(16.0)) {
    NSString* call = [NSString stringWithFormat:@"insertText: %@ alternatives:%lu style:%ld",
                      [InputDiagnostics describeText:text], (unsigned long)alternatives.count, (long)style];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super insertText:text alternatives:alternatives style:style];
    }
    [self diagAfter:call];
}

- (void)insertDictationResult:(NSArray<UIDictationPhrase *> *)dictationResult {
    NSMutableString* phrases = [NSMutableString string];
    for (UIDictationPhrase* phrase in dictationResult) {
        [phrases appendFormat:@" %@(alt %lu)", [InputDiagnostics describeText:phrase.text],
         (unsigned long)phrase.alternativeInterpretations.count];
    }
    NSString* call = [NSString stringWithFormat:@"insertDictationResult: %lu phrases%@",
                      (unsigned long)dictationResult.count, phrases];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super insertDictationResult:dictationResult];
    }
    [self diagAfter:call];
}

- (void)dictationRecordingDidEnd {
    [self diagBefore:@"dictationRecordingDidEnd"];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super dictationRecordingDidEnd];
    }
    [self diagAfter:@"dictationRecordingDidEnd"];
}

- (void)dictationRecognitionFailed {
    [self diagBefore:@"dictationRecognitionFailed"];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super dictationRecognitionFailed];
    }
    [self diagAfter:@"dictationRecognitionFailed"];
}

- (id)insertDictationResultPlaceholder {
    id placeholder = nil;
    [self diagBefore:@"insertDictationResultPlaceholder"];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        placeholder = [super insertDictationResultPlaceholder];
    }
    [self diagAfter:[NSString stringWithFormat:@"insertDictationResultPlaceholder -> %p", placeholder]];
    return placeholder;
}

- (CGRect)frameForDictationResultPlaceholder:(id)placeholder {
    CGRect frame = CGRectZero;
    if ([KeyboardInputField textFieldHas:_cmd]) {
        frame = [super frameForDictationResultPlaceholder:placeholder];
    }
    [self diagRecord:[NSString stringWithFormat:@"= frameForDictationResultPlaceholder: %p -> %@",
                      placeholder, NSStringFromCGRect(frame)]];
    return frame;
}

- (void)removeDictationResultPlaceholder:(id)placeholder willInsertResult:(BOOL)willInsertResult {
    NSString* call = [NSString stringWithFormat:@"removeDictationResultPlaceholder: %p willInsertResult:%d",
                      placeholder, willInsertResult];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super removeDictationResultPlaceholder:placeholder willInsertResult:willInsertResult];
    }
    [self diagAfter:call];
}

- (UITextPlaceholder *)insertTextPlaceholderWithSize:(CGSize)size {
    UITextPlaceholder* placeholder = nil;
    NSString* call = [NSString stringWithFormat:@"insertTextPlaceholderWithSize: %@", NSStringFromCGSize(size)];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        placeholder = [super insertTextPlaceholderWithSize:size];
    }
    [self diagAfter:[NSString stringWithFormat:@"%@ -> %p", call, placeholder]];
    return placeholder;
}

- (void)removeTextPlaceholder:(UITextPlaceholder *)textPlaceholder {
    NSString* call = [NSString stringWithFormat:@"removeTextPlaceholder: %p", textPlaceholder];
    [self diagBefore:call];
    if ([KeyboardInputField textFieldHas:_cmd]) {
        [super removeTextPlaceholder:textPlaceholder];
    }
    [self diagAfter:call];
}

- (BOOL)becomeFirstResponder {
    [self diagBefore:@"becomeFirstResponder"];
    BOOL result = [super becomeFirstResponder];
    [self diagAfter:[NSString stringWithFormat:@"becomeFirstResponder -> %d", result]];
    return result;
}

- (BOOL)resignFirstResponder {
    [self diagBefore:@"resignFirstResponder"];
    BOOL result = [super resignFirstResponder];
    [self diagAfter:[NSString stringWithFormat:@"resignFirstResponder -> %d", result]];
    return result;
}

- (void)diagPresses:(NSSet<UIPress *> *)presses phase:(NSString *)phase {
    if (@available(iOS 13.4, *)) {
        for (UIPress* press in presses) {
            [self diagRecord:[NSString stringWithFormat:@"field press %@ usage=%ld mods=0x%lx type=%ld",
                              phase, (long)press.key.keyCode, (long)press.key.modifierFlags, (long)press.type]];
        }
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self diagPresses:presses phase:@"began"];
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self diagPresses:presses phase:@"ended"];
    [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self diagPresses:presses phase:@"cancelled"];
    [super pressesCancelled:presses withEvent:event];
}

#else

- (NSString *)diagOptionalMethods {
    return @"";
}

#endif

@end

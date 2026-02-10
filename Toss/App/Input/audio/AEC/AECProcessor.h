#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps WebRTC AudioProcessing Module (AEC3) for echo cancellation.
/// Thread-safe: feedFarEnd and processNearEnd can be called from different threads.
/// Handles frame chunking internally — callers can pass arbitrary sample counts.
@interface AECProcessor : NSObject

- (instancetype)initWithSampleRate:(int)sampleRate channelCount:(int)channelCount;

/// Feed far-end (speaker) audio. Accepts arbitrary sample count.
/// Internally chunks into 10ms frames and calls ProcessReverseStream.
/// Thread-safe: can be called concurrently with processNearEnd.
- (void)feedFarEnd:(const float *)samples count:(int)count;

/// Process near-end (mic) audio, removing echo in-place. Accepts arbitrary sample count.
/// Internally chunks into 10ms frames, accumulates remainder across calls.
/// Returns number of processed samples (may be <= count due to remainder buffering).
- (int)processNearEnd:(float *)samples count:(int)count;

/// Flush any buffered remainder samples (call on stop).
/// Zero-pads to a full 10ms frame for AEC processing, but writes only
/// the original remainder sample count to avoid appending artificial tail audio.
/// Returns number of valid samples written, or 0 if empty.
- (int)flushNearEnd:(float *)samples capacity:(int)capacity;

/// Set estimated delay between render and capture streams in ms.
/// Optional — defaults to 0, letting AEC3's internal estimator handle it.
- (void)setBufferDelayMs:(int)delayMs;

/// Reset AEC state (e.g., after device change). Also clears remainder buffers.
- (void)reset;

@property (nonatomic, readonly) BOOL isValid;

@end

NS_ASSUME_NONNULL_END

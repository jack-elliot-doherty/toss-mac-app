#import "AECProcessor.h"

#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstring>
#include <memory>
#include <vector>

#include "modules/audio_processing/include/audio_processing.h"

@implementation AECProcessor {
	rtc::scoped_refptr<webrtc::AudioProcessing> _apm;
	std::unique_ptr<webrtc::StreamConfig> _streamConfig;

	int _sampleRate;
	int _channelCount;
	int _frameSamples;     // samples per 10 ms frame (e.g. 160 at 16 kHz)
	int _maxInputSamples;  // preallocation bound for real-time path

	// Buffered input until we have exactly one 10 ms frame.
	std::vector<float> _nearRemainder;
	std::vector<float> _farRemainder;

	// Reused scratch frame for ProcessStream/ProcessReverseStream.
	std::vector<float> _scratchInput;

	// Per-call processed output staging (real-time safe: fixed capacity).
	std::vector<float> _outputFifo;
	int _outputFifoCount;

	// Persisted processed samples that did not fit in the caller buffer.
	std::vector<float> _outputCarry;
	int _outputCarryCount;

	std::atomic<int> _bufferDelayMs;

	// Diagnostic counters (throttled logging every ~1s)
	int _farCallCount;
	int _farTotalSamples;
	int _farFramesProcessed;
	int _nearCallCount;
	int _nearTotalIn;
	int _nearTotalOut;
	int _nearFramesProcessed;
}

- (instancetype)initWithSampleRate:(int)sampleRate channelCount:(int)channelCount {
	self = [super init];
	if (!self) return nil;

	_sampleRate = sampleRate;
	_channelCount = channelCount;
	_frameSamples = sampleRate / 100;  // 10 ms
	_maxInputSamples = 4096;
	_outputFifoCount = 0;
	_outputCarryCount = 0;
	_bufferDelayMs.store(0, std::memory_order_relaxed);
	_farCallCount = 0;
	_farTotalSamples = 0;
	_farFramesProcessed = 0;
	_nearCallCount = 0;
	_nearTotalIn = 0;
	_nearTotalOut = 0;
	_nearFramesProcessed = 0;

	if (_frameSamples <= 0) {
		NSLog(@"[AECProcessor] Invalid frame size for sample rate %d", sampleRate);
		_isValid = NO;
		return self;
	}

	webrtc::AudioProcessing::Config config;
	config.echo_canceller.enabled = true;
	config.echo_canceller.mobile_mode = false;
	config.noise_suppression.enabled = false;
	config.gain_controller1.enabled = false;
	config.gain_controller2.enabled = false;
	config.high_pass_filter.enabled = false;

	_apm = webrtc::AudioProcessingBuilder().Create();
	if (!_apm) {
		NSLog(@"[AECProcessor] Failed to create AudioProcessing");
		_isValid = NO;
		return self;
	}

	_apm->ApplyConfig(config);
	_streamConfig = std::make_unique<webrtc::StreamConfig>(_sampleRate, _channelCount);

	_nearRemainder.reserve(_frameSamples);
	_farRemainder.reserve(_frameSamples);
	_scratchInput.resize(_frameSamples, 0.0f);

	// Keep enough room for one full callback plus remainder/carry.
	const int maxFrames = (_maxInputSamples / _frameSamples) + 3;
	const int fifoCapacity = maxFrames * _frameSamples;
	_outputFifo.resize(fifoCapacity, 0.0f);
	_outputCarry.resize(fifoCapacity * 2, 0.0f);

	_isValid = YES;
	NSLog(@"[AECProcessor] Initialized: %d Hz, %d ch, %d samples/frame",
		  _sampleRate, _channelCount, _frameSamples);
	return self;
}

- (void)feedFarEnd:(const float *)samples count:(int)count {
	if (!_isValid || !_apm || count <= 0) return;

	_farCallCount++;
	_farTotalSamples += count;
	int offset = 0;

	if (!_farRemainder.empty()) {
		const int needed = _frameSamples - (int)_farRemainder.size();
		const int available = std::min(needed, count);
		const int start = (int)_farRemainder.size();

		_farRemainder.resize(start + available);
		std::memcpy(_farRemainder.data() + start, samples, available * sizeof(float));
		offset += available;

		if ((int)_farRemainder.size() == _frameSamples) {
			float *inOut = _farRemainder.data();
			const float *const *inputPtrs = const_cast<const float *const *>(&inOut);
			float *const *outputPtrs = &inOut;
			_apm->ProcessReverseStream(inputPtrs, *_streamConfig, *_streamConfig, outputPtrs);
			_farRemainder.clear();
			_farFramesProcessed++;
		}
	}

	while (offset + _frameSamples <= count) {
		float *inOut = const_cast<float *>(samples + offset);
		const float *const *inputPtrs = const_cast<const float *const *>(&inOut);
		float *const *outputPtrs = &inOut;
		_apm->ProcessReverseStream(inputPtrs, *_streamConfig, *_streamConfig, outputPtrs);
		offset += _frameSamples;
		_farFramesProcessed++;
	}

	const int leftover = count - offset;
	if (leftover > 0) {
		_farRemainder.resize(leftover);
		std::memcpy(_farRemainder.data(), samples + offset, leftover * sizeof(float));
	}

	// Log every ~100 calls (~1s at typical callback rate)
	if (_farCallCount % 100 == 0) {
		NSLog(@"[AEC] far-end: %d calls, %d samples total, %d frames processed",
			  _farCallCount, _farTotalSamples, _farFramesProcessed);
	}
}

- (int)processNearEnd:(float *)samples count:(int)count {
	if (!_isValid || !_apm || count <= 0) return 0;

	_nearCallCount++;
	_nearTotalIn += count;

	// 1) Process new input into FIFO (never touching caller output yet).
	_outputFifoCount = 0;
	int offset = 0;

	if (!_nearRemainder.empty()) {
		const int needed = _frameSamples - (int)_nearRemainder.size();
		const int available = std::min(needed, count);
		const int start = (int)_nearRemainder.size();

		_nearRemainder.resize(start + available);
		std::memcpy(_nearRemainder.data() + start, samples, available * sizeof(float));
		offset += available;

		if ((int)_nearRemainder.size() == _frameSamples) {
			std::memcpy(_scratchInput.data(), _nearRemainder.data(), _frameSamples * sizeof(float));
			[self processOneFrame:_scratchInput.data()];
			[self appendToFifo:_scratchInput.data() count:_frameSamples];
			_nearRemainder.clear();
			_nearFramesProcessed++;
		}
	}

	while (offset + _frameSamples <= count) {
		std::memcpy(_scratchInput.data(), samples + offset, _frameSamples * sizeof(float));
		[self processOneFrame:_scratchInput.data()];
		[self appendToFifo:_scratchInput.data() count:_frameSamples];
		offset += _frameSamples;
		_nearFramesProcessed++;
	}

	const int leftover = count - offset;
	if (leftover > 0) {
		_nearRemainder.resize(leftover);
		std::memcpy(_nearRemainder.data(), samples + offset, leftover * sizeof(float));
	} else {
		_nearRemainder.clear();
	}

	// 2) Return carry first, then newly processed FIFO output.
	int written = 0;

	if (_outputCarryCount > 0) {
		const int fromCarry = std::min(_outputCarryCount, count);
		std::memcpy(samples, _outputCarry.data(), fromCarry * sizeof(float));
		written += fromCarry;

		if (fromCarry < _outputCarryCount) {
			std::memmove(
				_outputCarry.data(),
				_outputCarry.data() + fromCarry,
				(_outputCarryCount - fromCarry) * sizeof(float));
		}
		_outputCarryCount -= fromCarry;
	}

	const int remainingCapacity = count - written;
	if (remainingCapacity > 0 && _outputFifoCount > 0) {
		const int fromFifo = std::min(_outputFifoCount, remainingCapacity);
		std::memcpy(samples + written, _outputFifo.data(), fromFifo * sizeof(float));
		written += fromFifo;

		const int fifoLeftover = _outputFifoCount - fromFifo;
		if (fifoLeftover > 0) {
			[self appendToCarry:_outputFifo.data() + fromFifo count:fifoLeftover];
		}
	} else if (remainingCapacity == 0 && _outputFifoCount > 0) {
		[self appendToCarry:_outputFifo.data() count:_outputFifoCount];
	}

	_nearTotalOut += written;

	// Log every ~100 calls (~1s at typical tap rate)
	if (_nearCallCount % 100 == 0) {
		NSLog(@"[AEC] near-end: %d calls, in=%d out=%d samples, %d frames, carry=%d remainder=%d",
			  _nearCallCount, _nearTotalIn, _nearTotalOut,
			  _nearFramesProcessed, _outputCarryCount, (int)_nearRemainder.size());
	}

	assert(written >= 0 && written <= count);
	return written;
}

- (int)flushNearEnd:(float *)samples capacity:(int)capacity {
	if (!_isValid || !_apm || capacity <= 0) return 0;

	int written = 0;

	if (_outputCarryCount > 0) {
		const int fromCarry = std::min(_outputCarryCount, capacity);
		std::memcpy(samples, _outputCarry.data(), fromCarry * sizeof(float));
		written += fromCarry;

		if (fromCarry < _outputCarryCount) {
			std::memmove(
				_outputCarry.data(),
				_outputCarry.data() + fromCarry,
				(_outputCarryCount - fromCarry) * sizeof(float));
		}
		_outputCarryCount -= fromCarry;

		if (written == capacity) {
			return written;
		}
	}

	if (_nearRemainder.empty()) {
		return written;
	}

	const int remainderCount = (int)_nearRemainder.size();
	std::memcpy(_scratchInput.data(), _nearRemainder.data(), remainderCount * sizeof(float));
	std::memset(
		_scratchInput.data() + remainderCount,
		0,
		(_frameSamples - remainderCount) * sizeof(float));
	[self processOneFrame:_scratchInput.data()];

	const int fromRemainder = std::min(remainderCount, capacity - written);
	std::memcpy(samples + written, _scratchInput.data(), fromRemainder * sizeof(float));
	written += fromRemainder;

	const int remainderLeftover = remainderCount - fromRemainder;
	if (remainderLeftover > 0) {
		[self appendToCarry:_scratchInput.data() + fromRemainder count:remainderLeftover];
	}

	_nearRemainder.clear();
	assert(written >= 0 && written <= capacity);
	return written;
}

- (void)processOneFrame:(float *)frameData {
	const int delayMs = _bufferDelayMs.load(std::memory_order_relaxed);
	_apm->set_stream_delay_ms(delayMs);

	float *channelPtr = frameData;
	float *const *outputPtrs = &channelPtr;
	_apm->ProcessStream(
		const_cast<const float *const *>(&channelPtr),
		*_streamConfig,
		*_streamConfig,
		outputPtrs);
}

- (void)appendToFifo:(const float *)data count:(int)count {
	if (count <= 0) return;

	const int available = (int)_outputFifo.size() - _outputFifoCount;
	const int writeCount = std::min(count, available);
	if (writeCount > 0) {
		std::memcpy(_outputFifo.data() + _outputFifoCount, data, writeCount * sizeof(float));
		_outputFifoCount += writeCount;
	}

	if (writeCount < count) {
		NSLog(@"[AECProcessor] FIFO overflow, dropped %d samples", (count - writeCount));
	}
}

- (void)appendToCarry:(const float *)data count:(int)count {
	if (count <= 0) return;

	const int available = (int)_outputCarry.size() - _outputCarryCount;
	const int writeCount = std::min(count, available);
	if (writeCount > 0) {
		std::memcpy(_outputCarry.data() + _outputCarryCount, data, writeCount * sizeof(float));
		_outputCarryCount += writeCount;
	}

	if (writeCount < count) {
		NSLog(@"[AECProcessor] Carry overflow, dropped %d samples", (count - writeCount));
	}
}

- (void)setBufferDelayMs:(int)delayMs {
	_bufferDelayMs.store(std::max(0, delayMs), std::memory_order_relaxed);
}

- (void)reset {
	if (_apm) {
		webrtc::AudioProcessing::Config config;
		config.echo_canceller.enabled = true;
		config.echo_canceller.mobile_mode = false;
		config.noise_suppression.enabled = false;
		config.gain_controller1.enabled = false;
		config.gain_controller2.enabled = false;
		config.high_pass_filter.enabled = false;
		_apm->ApplyConfig(config);
	}

	_nearRemainder.clear();
	_farRemainder.clear();
	_outputFifoCount = 0;
	_outputCarryCount = 0;
	_bufferDelayMs.store(0, std::memory_order_relaxed);

	NSLog(@"[AECProcessor] Reset");
}

@end

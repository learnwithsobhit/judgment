/// Shared caps for ephemeral voice notes (mirrors server `audio.rs`).
library;

const int maxVoiceDurationMs = 6000;
const int minVoiceDurationMs = 400;
const int maxVoiceB64Bytes = 40000;
const int maxAudioQueueDepth = 3;

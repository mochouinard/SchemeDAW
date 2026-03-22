#ifndef AUDIO_BACKEND_H
#define AUDIO_BACKEND_H

#include "dsp-core.h"
#include "ringbuffer.h"

/*
 * AudioBackend wraps the AudioEngine with SDL2 audio device management
 * and the command ring buffer for thread-safe Scheme -> C communication.
 */
typedef struct {
    AudioEngine engine;
    RingBuffer  cmd_ring;
    int         device_id;    /* SDL audio device ID */
    int         running;
} AudioBackend;

/* Create and initialize the audio backend.
 * sample_rate: e.g. 44100 or 48000
 * buffer_size: SDL audio buffer size in samples (e.g. 256, 512, 1024)
 * Returns pointer to AudioBackend, or NULL on failure.
 * Caller must eventually call backend_destroy(). */
AudioBackend* backend_create(int sample_rate, int buffer_size);

/* Open and start the SDL audio device. Returns 0 on success, -1 on error. */
int backend_start(AudioBackend *ab);

/* Pause the audio device. */
void backend_stop(AudioBackend *ab);

/* Close audio device and free all resources. */
void backend_destroy(AudioBackend *ab);

/* Send a command from the Scheme thread to the audio thread.
 * Returns 1 on success, 0 if ring buffer is full. */
int backend_send_command(AudioBackend *ab, uint8_t type, uint8_t track,
                         uint8_t p1, uint8_t p2, float fval);

/* Get a pointer to the engine (for read-only queries from Scheme, e.g. metering) */
AudioEngine* backend_get_engine(AudioBackend *ab);

#endif /* AUDIO_BACKEND_H */

#ifndef SAMPLE_ENGINE_H
#define SAMPLE_ENGINE_H

#include <stdint.h>

#define MAX_SAMPLES       256
#define MAX_SAMPLE_VOICES  32

/* A loaded sample stored in memory */
typedef struct {
    float *data;           /* interleaved stereo float samples */
    int    frames;         /* number of frames */
    int    channels;       /* 1 or 2 */
    int    sample_rate;
    int    loaded;         /* 1 if this slot has a valid sample */
    char   name[64];       /* sample name (filename) */
} Sample;

/* An active sample playback voice */
typedef struct {
    int    sample_id;      /* index into sample slots */
    float  play_pos;       /* current playback position (float for pitch) */
    float  volume;         /* 0.0 - 1.0 */
    float  pan;            /* -1.0 to 1.0 */
    float  pitch;          /* playback rate multiplier (1.0 = original) */
    int    playing;        /* 1 = active */
    int    loop;           /* 0 = one-shot, 1 = loop */
    int    loop_start;     /* loop start frame */
    int    loop_end;       /* loop end frame (0 = end of sample) */
    int    reverse;        /* 1 = play backwards */
} SampleVoice;

/* The sample engine manages loaded samples and playback voices */
typedef struct {
    Sample       slots[MAX_SAMPLES];
    SampleVoice  voices[MAX_SAMPLE_VOICES];
    float        sample_rate;
} SampleEngine;

/* Initialize the sample engine */
void sample_engine_init(SampleEngine *se, float sample_rate);

/* Load a WAV file into a slot. Returns slot index (0-255), or -1 on error. */
int sample_engine_load(SampleEngine *se, const char *filename, int slot);

/* Unload a sample from a slot */
void sample_engine_unload(SampleEngine *se, int slot);

/* Trigger a sample (returns voice index, or -1 if no free voice) */
int sample_engine_trigger(SampleEngine *se, int slot, float volume,
                          float pan, float pitch);

/* Stop a specific voice */
void sample_engine_stop_voice(SampleEngine *se, int voice_id);

/* Stop all voices playing a given sample slot */
void sample_engine_stop_sample(SampleEngine *se, int slot);

/* Stop all voices */
void sample_engine_stop_all(SampleEngine *se);

/* Render sample voices into stereo output buffer (adds to existing content) */
void sample_engine_render(SampleEngine *se, float *left, float *right, int frames);

/* Destroy and free all sample data */
void sample_engine_destroy(SampleEngine *se);

#endif /* SAMPLE_ENGINE_H */

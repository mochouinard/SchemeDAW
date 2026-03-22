#ifndef EFFECTS_H
#define EFFECTS_H

/* Effect types */
#define EFFECT_NONE       0
#define EFFECT_DELAY      1
#define EFFECT_REVERB     2
#define EFFECT_DISTORTION 3
#define EFFECT_CHORUS     4
#define EFFECT_PHASER     5

/* Maximum delay/reverb buffer size: ~2 seconds at 48kHz */
#define MAX_DELAY_SAMPLES 96000

/* ---- Delay ---- */
typedef struct {
    float *buffer_l;       /* left delay buffer */
    float *buffer_r;       /* right delay buffer */
    int    buf_size;       /* buffer size in samples */
    int    write_pos;      /* current write position */
    float  delay_time;     /* delay time in seconds */
    float  feedback;       /* 0.0 - 0.95 */
    float  mix;            /* dry/wet: 0.0 = dry, 1.0 = wet */
    float  sample_rate;
    int    active;
} DelayEffect;

void delay_init(DelayEffect *d, float sample_rate);
void delay_set_params(DelayEffect *d, float time, float feedback, float mix);
void delay_process(DelayEffect *d, float *left, float *right, int frames);
void delay_destroy(DelayEffect *d);

/* ---- Reverb (Schroeder) ---- */
/* 4 parallel comb filters + 2 series allpass filters */
#define REVERB_NUM_COMBS    4
#define REVERB_NUM_ALLPASS  2

typedef struct {
    float *buffer;
    int    size;
    int    pos;
} ReverbDelayLine;

typedef struct {
    ReverbDelayLine comb_l[REVERB_NUM_COMBS];
    ReverbDelayLine comb_r[REVERB_NUM_COMBS];
    ReverbDelayLine allpass_l[REVERB_NUM_ALLPASS];
    ReverbDelayLine allpass_r[REVERB_NUM_ALLPASS];
    float  comb_feedback[REVERB_NUM_COMBS];
    float  allpass_feedback[REVERB_NUM_ALLPASS];
    float  room_size;      /* 0.0 - 1.0 */
    float  damping;        /* 0.0 - 1.0 */
    float  mix;            /* dry/wet */
    float  width;          /* stereo width 0.0 - 1.0 */
    float  sample_rate;
    float  damp_state_l[REVERB_NUM_COMBS];
    float  damp_state_r[REVERB_NUM_COMBS];
    int    active;
} ReverbEffect;

void reverb_init(ReverbEffect *r, float sample_rate);
void reverb_set_params(ReverbEffect *r, float room_size, float damping,
                       float mix, float width);
void reverb_process(ReverbEffect *r, float *left, float *right, int frames);
void reverb_destroy(ReverbEffect *r);

/* ---- Distortion ---- */
typedef struct {
    float  drive;          /* 1.0 - 100.0 */
    float  tone;           /* LP filter cutoff after distortion */
    float  mix;            /* dry/wet */
    float  output_gain;    /* post-distortion gain */
    /* Tone filter state */
    float  filter_state_l;
    float  filter_state_r;
    float  sample_rate;
    int    active;
} DistortionEffect;

void distortion_init(DistortionEffect *d, float sample_rate);
void distortion_set_params(DistortionEffect *d, float drive, float tone,
                           float mix, float output_gain);
void distortion_process(DistortionEffect *d, float *left, float *right, int frames);

/* ---- Effect Chain ---- */
#define MAX_CHAIN_EFFECTS 8

typedef struct {
    int type[MAX_CHAIN_EFFECTS];
    void *effect[MAX_CHAIN_EFFECTS];  /* pointer to specific effect struct */
    int count;
} EffectChain;

void effect_chain_init(EffectChain *chain);
int  effect_chain_add(EffectChain *chain, int type, float sample_rate);
void effect_chain_process(EffectChain *chain, float *left, float *right, int frames);
void effect_chain_destroy(EffectChain *chain);

#endif /* EFFECTS_H */

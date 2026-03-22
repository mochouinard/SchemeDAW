#ifndef VST3_HOST_H
#define VST3_HOST_H

#include <stdint.h>

/*
 * VST3 Host for Audio DAC
 *
 * Loads VST3 plugins using dlopen and the VST3 C API.
 * Each loaded plugin gets a slot with component, controller,
 * and audio processor interfaces.
 *
 * VST3 plugins are shared libraries (.vst3 bundles) that export
 * a single entry point: GetPluginFactory.
 */

#define MAX_VST3_PLUGINS   16
#define MAX_VST3_PARAMS    256
#define MAX_VST3_BUS_CHANNELS 2  /* stereo */

/* Parameter info */
typedef struct {
    uint32_t id;
    char     name[128];
    char     units[32];
    double   default_value;
    double   min_value;
    double   max_value;
    int      is_automatable;
} Vst3ParamInfo;

/* Plugin instance */
typedef struct {
    void    *lib_handle;              /* dlopen handle */
    void    *component;               /* IComponent* */
    void    *controller;              /* IEditController* */
    void    *processor;               /* IAudioProcessor* */
    char     name[256];
    char     path[1024];
    int      loaded;
    int      active;                  /* audio processing active */

    /* Parameters */
    Vst3ParamInfo params[MAX_VST3_PARAMS];
    int      num_params;

    /* Audio buffers (pre-allocated) */
    float   *input_l;
    float   *input_r;
    float   *output_l;
    float   *output_r;
    int      buffer_size;
    float    sample_rate;

    /* Plugin classification */
    int      is_instrument;           /* 1 = synth/instrument, 0 = effect */
} Vst3Plugin;

/* VST3 host context */
typedef struct {
    Vst3Plugin plugins[MAX_VST3_PLUGINS];
    float      sample_rate;
    int        buffer_size;
} Vst3Host;

/* ---- Lifecycle ---- */

/* Initialize the VST3 host */
void vst3_host_init(Vst3Host *host, float sample_rate, int buffer_size);

/* Scan a directory for .vst3 plugin bundles.
 * Calls callback for each found plugin with (path, name).
 * Returns number of plugins found. */
int vst3_host_scan(const char *directory,
                   void (*callback)(const char *path, const char *name, void *userdata),
                   void *userdata);

/* Load a VST3 plugin from a .vst3 bundle path.
 * Returns slot index (0-15) on success, -1 on error. */
int vst3_host_load(Vst3Host *host, const char *path, int slot);

/* Unload a plugin from a slot */
void vst3_host_unload(Vst3Host *host, int slot);

/* Activate audio processing for a plugin */
int vst3_host_activate(Vst3Host *host, int slot);

/* Deactivate audio processing */
void vst3_host_deactivate(Vst3Host *host, int slot);

/* ---- Parameters ---- */

/* Get number of parameters for a loaded plugin */
int vst3_host_get_param_count(Vst3Host *host, int slot);

/* Get parameter info by index */
const Vst3ParamInfo* vst3_host_get_param_info(Vst3Host *host, int slot, int param_idx);

/* Set parameter value (0.0 - 1.0 normalized) */
void vst3_host_set_param(Vst3Host *host, int slot, int param_idx, double value);

/* Get parameter value */
double vst3_host_get_param(Vst3Host *host, int slot, int param_idx);

/* ---- Audio Processing ---- */

/* Process audio through the plugin.
 * input/output are stereo interleaved float buffers.
 * For instruments, input may be NULL (generates audio from MIDI).
 * Returns 0 on success. */
int vst3_host_process(Vst3Host *host, int slot,
                      float *input_l, float *input_r,
                      float *output_l, float *output_r,
                      int frames);

/* Send a MIDI note to an instrument plugin */
void vst3_host_send_note(Vst3Host *host, int slot,
                         int note, int velocity, int channel);

/* ---- Cleanup ---- */

/* Destroy the host and unload all plugins */
void vst3_host_destroy(Vst3Host *host);

#endif /* VST3_HOST_H */

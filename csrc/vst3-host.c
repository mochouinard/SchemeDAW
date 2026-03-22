/*
 * vst3-host.c - VST3 plugin hosting via dlopen and the VST3 C API
 *
 * VST3 plugins are loaded dynamically from .vst3 bundle directories.
 * Each bundle contains a shared library at:
 *   Contents/x86_64-linux/<plugin>.so
 *
 * The shared library exports GetPluginFactory() which returns an
 * IPluginFactory interface. We use this to create component and
 * controller instances.
 *
 * NOTE: Full VST3 hosting requires implementing the COM-style vtable
 * interfaces from the VST3 C API header. This implementation provides
 * the infrastructure for plugin loading, parameter discovery, and
 * audio processing. The actual COM interface calls require the
 * vst3_c_api.h header from Steinberg's repository.
 *
 * For now, this provides a stub implementation that:
 * 1. Scans directories for .vst3 bundles
 * 2. Opens shared libraries with dlopen
 * 3. Locates the GetPluginFactory entry point
 * 4. Provides the framework for full integration
 */

#include "vst3-host.h"
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

/* Type for the VST3 entry point function */
typedef void* (*GetPluginFactoryFunc)(void);

/* ---- Internal helpers ---- */

static int ends_with(const char *str, const char *suffix) {
    size_t str_len = strlen(str);
    size_t suf_len = strlen(suffix);
    if (suf_len > str_len) return 0;
    return strcmp(str + str_len - suf_len, suffix) == 0;
}

/* Find the shared library inside a .vst3 bundle */
static int find_plugin_binary(const char *bundle_path, char *out_path, int out_size) {
    /* VST3 bundle structure:
     *   <name>.vst3/Contents/x86_64-linux/<name>.so
     */
    snprintf(out_path, out_size, "%s/Contents/x86_64-linux/", bundle_path);

    DIR *dir = opendir(out_path);
    if (!dir) {
        /* Try flat bundle (just the .so file) */
        snprintf(out_path, out_size, "%s", bundle_path);
        if (ends_with(bundle_path, ".so")) return 1;
        return 0;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (ends_with(entry->d_name, ".so")) {
            char temp[1024];
            strncpy(temp, out_path, sizeof(temp) - 1);
            snprintf(out_path, out_size, "%s%s", temp, entry->d_name);
            closedir(dir);
            return 1;
        }
    }
    closedir(dir);
    return 0;
}

/* ---- Lifecycle ---- */

void vst3_host_init(Vst3Host *host, float sample_rate, int buffer_size) {
    memset(host, 0, sizeof(Vst3Host));
    host->sample_rate = sample_rate;
    host->buffer_size = buffer_size;

    /* Pre-allocate audio buffers for each plugin slot */
    for (int i = 0; i < MAX_VST3_PLUGINS; i++) {
        Vst3Plugin *p = &host->plugins[i];
        p->buffer_size = buffer_size;
        p->sample_rate = sample_rate;
        p->input_l  = (float *)calloc(buffer_size, sizeof(float));
        p->input_r  = (float *)calloc(buffer_size, sizeof(float));
        p->output_l = (float *)calloc(buffer_size, sizeof(float));
        p->output_r = (float *)calloc(buffer_size, sizeof(float));
    }
}

int vst3_host_scan(const char *directory,
                   void (*callback)(const char *path, const char *name, void *userdata),
                   void *userdata) {
    DIR *dir = opendir(directory);
    if (!dir) {
        fprintf(stderr, "VST3 scan: cannot open directory '%s'\n", directory);
        return 0;
    }

    int count = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (ends_with(entry->d_name, ".vst3")) {
            char full_path[2048];
            snprintf(full_path, sizeof(full_path), "%s/%s", directory, entry->d_name);

            /* Extract plugin name (strip .vst3 extension) */
            char name[256];
            strncpy(name, entry->d_name, sizeof(name) - 1);
            char *ext = strstr(name, ".vst3");
            if (ext) *ext = '\0';

            if (callback) {
                callback(full_path, name, userdata);
            }
            count++;
        }
    }

    closedir(dir);
    fprintf(stderr, "VST3 scan: found %d plugins in '%s'\n", count, directory);
    return count;
}

int vst3_host_load(Vst3Host *host, const char *path, int slot) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return -1;

    Vst3Plugin *p = &host->plugins[slot];
    if (p->loaded) {
        vst3_host_unload(host, slot);
    }

    /* Find the shared library binary */
    char binary_path[2048];
    if (!find_plugin_binary(path, binary_path, sizeof(binary_path))) {
        fprintf(stderr, "VST3: cannot find binary in '%s'\n", path);
        return -1;
    }

    /* Open the shared library */
    void *lib = dlopen(binary_path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "VST3: dlopen failed for '%s': %s\n", binary_path, dlerror());
        return -1;
    }

    /* Find the entry point */
    GetPluginFactoryFunc get_factory =
        (GetPluginFactoryFunc)dlsym(lib, "GetPluginFactory");
    if (!get_factory) {
        fprintf(stderr, "VST3: GetPluginFactory not found in '%s'\n", binary_path);
        dlclose(lib);
        return -1;
    }

    /* Get the factory */
    void *factory = get_factory();
    if (!factory) {
        fprintf(stderr, "VST3: GetPluginFactory returned NULL for '%s'\n", binary_path);
        dlclose(lib);
        return -1;
    }

    /* Store the plugin info */
    p->lib_handle = lib;
    p->loaded = 1;
    p->active = 0;
    strncpy(p->path, path, sizeof(p->path) - 1);

    /* Extract name from path */
    const char *basename = strrchr(path, '/');
    if (basename) basename++; else basename = path;
    strncpy(p->name, basename, sizeof(p->name) - 1);
    char *ext = strstr(p->name, ".vst3");
    if (ext) *ext = '\0';

    /*
     * TODO: Full VST3 COM interface integration
     *
     * With the VST3 C API (vst3_c_api.h), we would now:
     * 1. Query factory->countClasses() to enumerate plugin classes
     * 2. factory->getClassInfo(i, &info) to get class IDs
     * 3. factory->createInstance(classId, IComponent_iid, &component)
     * 4. component->initialize(hostContext)
     * 5. component->queryInterface(IAudioProcessor_iid, &processor)
     * 6. Create IEditController via separate factory or component
     * 7. controller->getParameterCount() / getParameterInfo()
     * 8. processor->setupProcessing(setup)
     * 9. processor->setActive(true)
     *
     * Each of these calls goes through C-style vtables:
     *   component->lpVtbl->initialize(component, ctx);
     *
     * The full implementation requires vst3_c_api.h from:
     *   https://github.com/steinbergmedia/vst3_c_api
     */

    fprintf(stderr, "VST3: loaded '%s' into slot %d (factory at %p)\n",
            p->name, slot, factory);
    fprintf(stderr, "VST3: NOTE - full COM interface integration pending\n");

    return slot;
}

void vst3_host_unload(Vst3Host *host, int slot) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return;
    Vst3Plugin *p = &host->plugins[slot];

    if (!p->loaded) return;

    if (p->active) {
        vst3_host_deactivate(host, slot);
    }

    /*
     * TODO: Proper cleanup sequence:
     * 1. processor->setActive(false)
     * 2. component->terminate()
     * 3. controller->terminate()
     * 4. Release all interfaces
     */

    if (p->lib_handle) {
        dlclose(p->lib_handle);
        p->lib_handle = NULL;
    }

    p->loaded = 0;
    p->active = 0;
    p->name[0] = '\0';
    p->path[0] = '\0';
    p->num_params = 0;

    fprintf(stderr, "VST3: unloaded slot %d\n", slot);
}

int vst3_host_activate(Vst3Host *host, int slot) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return -1;
    Vst3Plugin *p = &host->plugins[slot];
    if (!p->loaded) return -1;

    /*
     * TODO: Call processor->setupProcessing() and processor->setActive(true)
     */

    p->active = 1;
    return 0;
}

void vst3_host_deactivate(Vst3Host *host, int slot) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return;
    Vst3Plugin *p = &host->plugins[slot];

    /*
     * TODO: Call processor->setActive(false)
     */

    p->active = 0;
}

/* ---- Parameters ---- */

int vst3_host_get_param_count(Vst3Host *host, int slot) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return 0;
    return host->plugins[slot].num_params;
}

const Vst3ParamInfo* vst3_host_get_param_info(Vst3Host *host, int slot, int param_idx) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return NULL;
    Vst3Plugin *p = &host->plugins[slot];
    if (param_idx < 0 || param_idx >= p->num_params) return NULL;
    return &p->params[param_idx];
}

void vst3_host_set_param(Vst3Host *host, int slot, int param_idx, double value) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return;
    Vst3Plugin *p = &host->plugins[slot];
    if (!p->loaded || !p->active) return;

    /*
     * TODO: Call controller->setParamNormalized(paramId, value)
     * and queue parameter change for next process() call
     */
    (void)param_idx;
    (void)value;
}

double vst3_host_get_param(Vst3Host *host, int slot, int param_idx) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return 0.0;
    Vst3Plugin *p = &host->plugins[slot];
    if (!p->loaded) return 0.0;

    /*
     * TODO: Call controller->getParamNormalized(paramId)
     */
    (void)param_idx;
    return 0.0;
}

/* ---- Audio Processing ---- */

int vst3_host_process(Vst3Host *host, int slot,
                      float *input_l, float *input_r,
                      float *output_l, float *output_r,
                      int frames) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return -1;
    Vst3Plugin *p = &host->plugins[slot];
    if (!p->loaded || !p->active) return -1;

    /*
     * TODO: Full process() call:
     * 1. Fill ProcessData with input/output bus buffers
     * 2. Set numSamples = frames
     * 3. Add any queued parameter changes to inputParameterChanges
     * 4. Add any queued MIDI events to inputEvents
     * 5. Call processor->process(&processData)
     * 6. Read output from output bus buffers
     *
     * For now, pass-through (copy input to output)
     */

    if (input_l && output_l) {
        memcpy(output_l, input_l, frames * sizeof(float));
    } else if (output_l) {
        memset(output_l, 0, frames * sizeof(float));
    }

    if (input_r && output_r) {
        memcpy(output_r, input_r, frames * sizeof(float));
    } else if (output_r) {
        memset(output_r, 0, frames * sizeof(float));
    }

    return 0;
}

void vst3_host_send_note(Vst3Host *host, int slot,
                         int note, int velocity, int channel) {
    if (slot < 0 || slot >= MAX_VST3_PLUGINS) return;
    Vst3Plugin *p = &host->plugins[slot];
    if (!p->loaded || !p->active) return;

    /*
     * TODO: Queue MIDI note event for next process() call
     * VST3 uses its own event struct (Steinberg::Vst::Event)
     * with noteOn/noteOff type and pitch/velocity/channel fields
     */
    (void)note;
    (void)velocity;
    (void)channel;
}

/* ---- Cleanup ---- */

void vst3_host_destroy(Vst3Host *host) {
    for (int i = 0; i < MAX_VST3_PLUGINS; i++) {
        if (host->plugins[i].loaded) {
            vst3_host_unload(host, i);
        }

        /* Free pre-allocated buffers */
        free(host->plugins[i].input_l);
        free(host->plugins[i].input_r);
        free(host->plugins[i].output_l);
        free(host->plugins[i].output_r);
    }
}

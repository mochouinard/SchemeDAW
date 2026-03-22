;;; audio-dac.scm - Main entry point for Audio DAC electronic music DAW
;;;
;;; Starts the audio engine and GUI, runs the main event loop.
;;; Supports two modes:
;;;   --no-gui : headless mode (test tone, no window)
;;;   default  : full GUI mode with Nuklear+SDL2 interface

(import scheme
        (chicken base)
        (chicken process-context)
        (chicken format)
        (chicken string))

;; Include all C sources directly (single-file compilation)
(foreign-declare "
#include \"ringbuffer.c\"
#include \"dsp-core.c\"
#include \"audio-backend.c\"
#include \"sample-engine.c\"
#include \"effects.c\"

/* Nuklear config */
#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#define NK_IMPLEMENTATION
#include \"../lib/nuklear/nuklear.h\"

#define NK_SDL_RENDERER_IMPLEMENTATION
#include \"../lib/nuklear/nuklear_sdl_renderer.h\"

/* GUI backend must come after nuklear includes */
/* We inline gui-backend.c but skip its nuklear includes since we already did them */
")

;; Separate declare for gui-backend to avoid double-including nuklear
(foreign-declare "
#include <stdio.h>
#include <math.h>

/* Forward declarations from gui-backend */
int gui_init(int width, int height, const char *title);
void gui_shutdown(void);
void gui_process_events(int *quit);
void gui_frame_begin(void);
void gui_frame_end(void);
struct nk_context* gui_get_ctx(void);
int gui_begin_panel(const char *title, float x, float y, float w, float h, int flags);
void gui_end_panel(void);
void gui_row_dynamic(float height, int cols);
void gui_row_static(float height, int item_width, int cols);
float gui_slider(const char *label, float value, float min, float max, float step);
float gui_knob(const char *label, float value, float min, float max);
int gui_button(const char *label);
int gui_toggle(const char *label, int active);
void gui_label(const char *text);
void gui_label_colored(const char *text, int r, int g, int b);
float gui_property_float(const char *label, float min, float value, float max,
                         float step, float inc_per_pixel);
int gui_property_int(const char *label, int min, int value, int max,
                     int step, float inc_per_pixel);
void gui_meter(const char *label, float level);
int gui_sequencer_grid(int *grid_data, int rows, int cols, int current_step,
                       int cell_width, int cell_height);
void gui_set_daw_theme(void);
int gui_get_width(void);
int gui_get_height(void);

/* Labeled sequencer grid: draws track labels on the left */
int gui_sequencer_grid_labeled(int *grid_data, int rows, int cols,
    int current_step, int cell_w, int cell_h,
    const char **row_labels, float dpi_scale);

/* Horizontal separator */
void gui_separator(float height);
float gui_get_dpi_scale(void);
")

;; Include gui-backend implementation with guard
(foreign-declare "
/* ---- Inlined gui-backend.c ---- */
static SDL_Window   *g_window   = NULL;
static SDL_Renderer *g_renderer = NULL;
static struct nk_context *g_ctx = NULL;
static int g_width  = 1280;
static int g_height = 800;
static float g_dpi_scale = 1.0f;

int gui_get_width(void) { return g_width; }
int gui_get_height(void) { return g_height; }
float gui_get_dpi_scale(void) { return g_dpi_scale; }

int gui_init(int width, int height, const char *title) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) {
        fprintf(stderr, \"SDL_Init failed: %s\\n\", SDL_GetError());
        return -1;
    }

    /* Detect DPI scale: compare logical and pixel sizes */
    /* SDL_WINDOW_ALLOW_HIGHDPI tells SDL to create a high-DPI drawable */
    g_window = SDL_CreateWindow(title,
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        width, height,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (!g_window) { fprintf(stderr, \"Window failed: %s\\n\", SDL_GetError()); return -1; }

    /* Calculate DPI scale from display DPI */
    float dpi = 0;
    int display_idx = SDL_GetWindowDisplayIndex(g_window);
    if (SDL_GetDisplayDPI(display_idx, &dpi, NULL, NULL) == 0 && dpi > 0) {
        g_dpi_scale = dpi / 96.0f;  /* 96 DPI is the baseline */
        if (g_dpi_scale < 1.0f) g_dpi_scale = 1.0f;
    } else {
        /* Fallback: check renderer output vs window size */
        g_dpi_scale = 1.0f;
    }
    fprintf(stderr, \"DPI scale: %.2f\\n\", g_dpi_scale);

    /* Get actual window size */
    SDL_GetWindowSize(g_window, &g_width, &g_height);

    g_renderer = SDL_CreateRenderer(g_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!g_renderer) { SDL_DestroyWindow(g_window); return -1; }

    g_ctx = nk_sdl_init(g_window, g_renderer);

    /* Load font scaled to DPI */
    { struct nk_font_atlas *atlas;
      float font_size = 14.0f * g_dpi_scale;
      if (font_size < 14.0f) font_size = 14.0f;
      nk_sdl_font_stash_begin(&atlas);
      struct nk_font *font = nk_font_atlas_add_default(atlas, font_size, NULL);
      nk_sdl_font_stash_end();
      nk_style_set_font(g_ctx, &font->handle); }

    gui_set_daw_theme();

    /* Scale style elements for DPI */
    g_ctx->style.button.rounding = 3.0f * g_dpi_scale;
    g_ctx->style.slider.bar_height = 6.0f * g_dpi_scale;

    return 0;
}
void gui_shutdown(void) {
    if (g_ctx) { nk_sdl_shutdown(); g_ctx = NULL; }
    if (g_renderer) { SDL_DestroyRenderer(g_renderer); g_renderer = NULL; }
    if (g_window) { SDL_DestroyWindow(g_window); g_window = NULL; }
}
void gui_process_events(int *quit) {
    SDL_Event evt;
    nk_input_begin(g_ctx);
    while (SDL_PollEvent(&evt)) {
        if (evt.type == SDL_QUIT) *quit = 1;
        if (evt.type == SDL_WINDOWEVENT) {
            if (evt.window.event == SDL_WINDOWEVENT_SIZE_CHANGED ||
                evt.window.event == SDL_WINDOWEVENT_RESIZED) {
                SDL_GetWindowSize(g_window, &g_width, &g_height);
            }
        }
        nk_sdl_handle_event(&evt);
    }
    nk_input_end(g_ctx);
}
void gui_frame_begin(void) { }
void gui_frame_end(void) {
    SDL_SetRenderDrawColor(g_renderer, 30, 30, 30, 255);
    SDL_RenderClear(g_renderer);
    nk_sdl_render(NK_ANTI_ALIASING_ON);
    SDL_RenderPresent(g_renderer);
}
struct nk_context* gui_get_ctx(void) { return g_ctx; }
int gui_begin_panel(const char *title, float x, float y, float w, float h, int flags) {
    nk_flags f = NK_WINDOW_BORDER | NK_WINDOW_TITLE;
    if (flags & 1) f |= NK_WINDOW_MOVABLE;
    if (flags & 2) f |= NK_WINDOW_SCALABLE;
    if (flags & 4) f |= NK_WINDOW_MINIMIZABLE;
    if (flags & 8) f |= NK_WINDOW_NO_SCROLLBAR;
    return nk_begin(g_ctx, title, nk_rect(x,y,w,h), f);
}
void gui_end_panel(void) { nk_end(g_ctx); }
void gui_row_dynamic(float h, int c) { nk_layout_row_dynamic(g_ctx, h, c); }
void gui_row_static(float h, int w, int c) { nk_layout_row_static(g_ctx, h, w, c); }
float gui_slider(const char *label, float val, float mn, float mx, float step) {
    float rh = 20.0f * g_dpi_scale;
    nk_layout_row_dynamic(g_ctx, rh, 2);
    nk_label(g_ctx, label, NK_TEXT_LEFT);
    nk_slider_float(g_ctx, mn, &val, mx, step);
    return val;
}
float gui_knob(const char *label, float val, float mn, float mx) {
    float rh = 20.0f * g_dpi_scale;
    nk_layout_row_dynamic(g_ctx, rh, 1);
    nk_label(g_ctx, label, NK_TEXT_CENTERED);
    nk_layout_row_dynamic(g_ctx, rh, 1);
    nk_slider_float(g_ctx, mn, &val, mx, (mx-mn)/100.0f);
    return val;
}
int gui_button(const char *label) { return nk_button_label(g_ctx, label); }
int gui_toggle(const char *label, int active) { return nk_check_label(g_ctx, label, active); }
void gui_label(const char *text) { nk_label(g_ctx, text, NK_TEXT_LEFT); }
void gui_label_colored(const char *text, int r, int g, int b) {
    nk_label_colored(g_ctx, text, NK_TEXT_LEFT, nk_rgb(r,g,b)); }
float gui_property_float(const char *label, float mn, float val, float mx, float step, float ipp) {
    nk_property_float(g_ctx, label, mn, &val, mx, step, ipp); return val; }
int gui_property_int(const char *label, int mn, int val, int mx, int step, float ipp) {
    nk_property_int(g_ctx, label, mn, &val, mx, step, ipp); return val; }
void gui_meter(const char *label, float level) {
    if (level < 0.0f) level = 0.0f; if (level > 1.0f) level = 1.0f;
    nk_layout_row_dynamic(g_ctx, 20.0f * g_dpi_scale, 2);
    nk_label(g_ctx, label, NK_TEXT_LEFT);
    struct nk_color c = (level > 0.9f) ? nk_rgb(255,50,50) :
                        (level > 0.7f) ? nk_rgb(255,200,50) : nk_rgb(50,200,80);
    struct nk_style_item old = g_ctx->style.progress.cursor_normal;
    g_ctx->style.progress.cursor_normal = nk_style_item_color(c);
    nk_size v = (nk_size)(level * 100.0f);
    nk_progress(g_ctx, &v, 100, NK_FIXED);
    g_ctx->style.progress.cursor_normal = old;
}
int gui_sequencer_grid(int *grid_data, int rows, int cols, int current_step,
                       int cell_w, int cell_h) {
    int changed = 0;
    for (int r = 0; r < rows; r++) {
        nk_layout_row_static(g_ctx, (float)cell_h, cell_w, cols);
        for (int c = 0; c < cols; c++) {
            int idx = r * cols + c;
            int active = grid_data[idx];
            struct nk_color clr;
            if (c == current_step) {
                clr = active ? nk_rgb(255,180,50) : nk_rgb(80,80,50);
            } else {
                clr = active ? nk_rgb(80,180,220) : (c%4==0 ? nk_rgb(55,55,55) : nk_rgb(45,45,45));
            }
            struct nk_style_button style = g_ctx->style.button;
            style.normal = nk_style_item_color(clr);
            style.hover = nk_style_item_color(nk_rgb(
                clr.r*1.2f>255?255:(int)(clr.r*1.2f),
                clr.g*1.2f>255?255:(int)(clr.g*1.2f),
                clr.b*1.2f>255?255:(int)(clr.b*1.2f)));
            style.active = nk_style_item_color(nk_rgb(200,200,200));
            style.border_color = nk_rgb(60,60,60); style.border = 1;
            if (nk_button_label_styled(g_ctx, &style, active ? \"#\" : \"\")) {
                grid_data[idx] = !grid_data[idx]; changed = 1; }
        }
    }
    return changed;
}
void gui_set_daw_theme(void) {
    struct nk_color t[NK_COLOR_COUNT];
    t[NK_COLOR_TEXT]=nk_rgb(200,200,200); t[NK_COLOR_WINDOW]=nk_rgb(35,35,38);
    t[NK_COLOR_HEADER]=nk_rgb(45,45,48); t[NK_COLOR_BORDER]=nk_rgb(60,60,65);
    t[NK_COLOR_BUTTON]=nk_rgb(55,55,60); t[NK_COLOR_BUTTON_HOVER]=nk_rgb(70,70,75);
    t[NK_COLOR_BUTTON_ACTIVE]=nk_rgb(80,130,200); t[NK_COLOR_TOGGLE]=nk_rgb(55,55,60);
    t[NK_COLOR_TOGGLE_HOVER]=nk_rgb(70,70,75); t[NK_COLOR_TOGGLE_CURSOR]=nk_rgb(80,130,200);
    t[NK_COLOR_SELECT]=nk_rgb(55,55,60); t[NK_COLOR_SELECT_ACTIVE]=nk_rgb(80,130,200);
    t[NK_COLOR_SLIDER]=nk_rgb(45,45,48); t[NK_COLOR_SLIDER_CURSOR]=nk_rgb(80,130,200);
    t[NK_COLOR_SLIDER_CURSOR_HOVER]=nk_rgb(100,150,220);
    t[NK_COLOR_SLIDER_CURSOR_ACTIVE]=nk_rgb(120,170,240);
    t[NK_COLOR_PROPERTY]=nk_rgb(45,45,48); t[NK_COLOR_EDIT]=nk_rgb(45,45,48);
    t[NK_COLOR_EDIT_CURSOR]=nk_rgb(200,200,200); t[NK_COLOR_COMBO]=nk_rgb(55,55,60);
    t[NK_COLOR_CHART]=nk_rgb(45,45,48); t[NK_COLOR_CHART_COLOR]=nk_rgb(80,130,200);
    t[NK_COLOR_CHART_COLOR_HIGHLIGHT]=nk_rgb(255,180,50);
    t[NK_COLOR_SCROLLBAR]=nk_rgb(45,45,48); t[NK_COLOR_SCROLLBAR_CURSOR]=nk_rgb(70,70,75);
    t[NK_COLOR_SCROLLBAR_CURSOR_HOVER]=nk_rgb(80,80,85);
    t[NK_COLOR_SCROLLBAR_CURSOR_ACTIVE]=nk_rgb(90,90,95);
    t[NK_COLOR_TAB_HEADER]=nk_rgb(45,45,48);
    nk_style_from_table(g_ctx, t);
    g_ctx->style.button.rounding = 3;
    g_ctx->style.slider.bar_height = 6;
}

int gui_sequencer_grid_labeled(int *grid_data, int rows, int cols,
    int current_step, int cell_w, int cell_h,
    const char **row_labels, float dpi_scale) {
    int changed = 0;
    int label_w = (int)(70.0f * dpi_scale);

    for (int r = 0; r < rows; r++) {
        /* Row with label + grid cells */
        nk_layout_row_begin(g_ctx, NK_STATIC, (float)cell_h, cols + 1);

        /* Track label */
        nk_layout_row_push(g_ctx, (float)label_w);
        struct nk_color label_clr = (r < 4) ? nk_rgb(80,180,220) : nk_rgb(220,160,80);
        nk_label_colored(g_ctx, row_labels[r], NK_TEXT_LEFT, label_clr);

        /* Grid cells */
        for (int c = 0; c < cols; c++) {
            nk_layout_row_push(g_ctx, (float)cell_w);
            int idx = r * cols + c;
            int active = grid_data[idx];
            struct nk_color clr;
            if (c == current_step) {
                clr = active ? nk_rgb(255,180,50) : nk_rgb(70,70,45);
            } else {
                if (active)
                    clr = (r < 4) ? nk_rgb(60,160,200) : nk_rgb(200,140,50);
                else
                    clr = (c % 4 == 0) ? nk_rgb(52,52,56) : nk_rgb(42,42,46);
            }
            struct nk_style_button style = g_ctx->style.button;
            style.normal = nk_style_item_color(clr);
            style.hover = nk_style_item_color(nk_rgb(
                (int)fminf(clr.r * 1.3f, 255),
                (int)fminf(clr.g * 1.3f, 255),
                (int)fminf(clr.b * 1.3f, 255)));
            style.active = nk_style_item_color(nk_rgb(220,220,220));
            style.border_color = nk_rgb(55,55,60);
            style.border = 1.0f;
            style.rounding = 2.0f;
            if (nk_button_label_styled(g_ctx, &style, active ? \"#\" : \"\")) {
                grid_data[idx] = !grid_data[idx];
                changed = 1;
            }
        }
        nk_layout_row_end(g_ctx);
    }
    return changed;
}

void gui_separator(float height) {
    nk_layout_row_dynamic(g_ctx, height, 1);
    nk_label(g_ctx, \"\", NK_TEXT_LEFT);
}
")

;; ---- FFI Bindings ----

(define backend-create
  (foreign-lambda c-pointer "backend_create" int int))
(define backend-start
  (foreign-lambda int "backend_start" c-pointer))
(define backend-stop
  (foreign-lambda void "backend_stop" c-pointer))
(define backend-destroy
  (foreign-lambda void "backend_destroy" c-pointer))
(define backend-send
  (foreign-lambda int "backend_send_command"
    c-pointer unsigned-byte unsigned-byte
    unsigned-byte unsigned-byte float))

;; GUI FFI
(define gui-init       (foreign-lambda int "gui_init" int int c-string))
(define gui-shutdown   (foreign-lambda void "gui_shutdown"))
(define gui-frame-begin (foreign-lambda void "gui_frame_begin"))
(define gui-frame-end  (foreign-lambda void "gui_frame_end"))
(define gui-begin-panel (foreign-lambda int "gui_begin_panel" c-string float float float float int))
(define gui-end-panel  (foreign-lambda void "gui_end_panel"))
(define gui-row-dynamic (foreign-lambda void "gui_row_dynamic" float int))
(define gui-row-static (foreign-lambda void "gui_row_static" float int int))
(define gui-slider     (foreign-lambda float "gui_slider" c-string float float float float))
(define gui-button     (foreign-lambda int "gui_button" c-string))
(define gui-label      (foreign-lambda void "gui_label" c-string))
(define gui-label-colored (foreign-lambda void "gui_label_colored" c-string int int int))
(define gui-property-float (foreign-lambda float "gui_property_float" c-string float float float float float))
(define gui-meter      (foreign-lambda void "gui_meter" c-string float))
(define gui-sequencer-grid-raw
  (foreign-lambda int "gui_sequencer_grid" c-pointer int int int int int))
(define gui-get-width  (foreign-lambda int "gui_get_width"))
(define gui-get-height (foreign-lambda int "gui_get_height"))
(define gui-get-dpi-scale (foreign-lambda float "gui_get_dpi_scale"))
(define gui-separator (foreign-lambda void "gui_separator" float))

;; Labeled grid FFI - needs C string array
(define gui-sequencer-grid-labeled-raw
  (foreign-lambda int "gui_sequencer_grid_labeled"
    c-pointer int int int int int c-pointer float))

;; Scale a value by DPI
(define (dpi* val)
  (inexact->exact (round (* val (gui-get-dpi-scale)))))

;; ---- Save / Load ----

(define (save-project! filename grid bpm track-presets track-volumes)
  (call-with-output-file filename
    (lambda (port)
      (display ";; Audio DAC Project File\n" port)
      (write `(project
        (bpm ,bpm)
        (presets ,(vector->list track-presets))
        (volumes ,(map exact->inexact (vector->list track-volumes)))
        (grid ,(let loop ((i 0) (acc '()))
                 (if (>= i (* GRID_ROWS GRID_COLS))
                     (reverse acc)
                     (loop (+ i 1) (cons (grid-get grid i) acc))))))
             port)
      (newline port)))
  (format #t "Saved project to ~A~%" filename))

(define (load-project! filename grid track-presets track-volumes backend)
  (condition-case
    (let ((data (call-with-input-file filename read)))
      (when (and (pair? data) (eq? (car data) 'project))
        (let ((body (cdr data)))
          ;; BPM
          (let ((bpm-entry (assq 'bpm body)))
            (when bpm-entry (set! *loaded-bpm* (cadr bpm-entry))))
          ;; Presets
          (let ((presets-entry (assq 'presets body)))
            (when presets-entry
              (let loop ((i 0) (ps (cadr presets-entry)))
                (when (and (< i GRID_ROWS) (pair? ps))
                  (vector-set! track-presets i (car ps))
                  (backend-send backend CMD_LOAD_PRESET i (car ps) 0 0.0)
                  (loop (+ i 1) (cdr ps))))))
          ;; Volumes
          (let ((vols-entry (assq 'volumes body)))
            (when vols-entry
              (let loop ((i 0) (vs (cadr vols-entry)))
                (when (and (< i GRID_ROWS) (pair? vs))
                  (vector-set! track-volumes i (car vs))
                  (backend-send backend CMD_SET_VOLUME i 0 0
                    (exact->inexact (car vs)))
                  (loop (+ i 1) (cdr vs))))))
          ;; Grid
          (let ((grid-entry (assq 'grid body)))
            (when grid-entry
              (let loop ((i 0) (gs (cadr grid-entry)))
                (when (and (< i (* GRID_ROWS GRID_COLS)) (pair? gs))
                  (grid-set! grid i (car gs))
                  (loop (+ i 1) (cdr gs))))))))
      (format #t "Loaded project from ~A~%" filename))
    ((exn) (format (current-error-port) "Error loading ~A~%" filename))))

;; Global for passing loaded BPM back
(define *loaded-bpm* #f)

;; ---- C string array for row labels ----
(define row-labels-alloc
  (foreign-lambda* c-pointer ((int count))
    "const char **arr = (const char **)calloc(count, sizeof(char*));
     C_return(arr);"))

(define row-labels-set!
  (foreign-lambda* void ((c-pointer arr) (int idx) (c-string str))
    "((const char **)arr)[idx] = str;"))

(define row-labels-free
  (foreign-lambda* void ((c-pointer arr))
    "free(arr);"
    ))

;; SDL delay for timing
(foreign-declare "void c_delay_ms(int ms) { SDL_Delay(ms); }")
(define c-delay-ms (foreign-lambda void "c_delay_ms" int))
(define (thread-sleep! seconds)
  (c-delay-ms (inexact->exact (round (* seconds 1000.0)))))

;; Process events, returns #t if quit requested
(define (gui-process-events!)
  (let-location ((quit int 0))
    ((foreign-lambda void "gui_process_events" (c-pointer int)) (location quit))
    (not (= quit 0))))

;; ---- Constants ----
(define CMD_NOTE_ON       #x01)
(define CMD_NOTE_OFF      #x02)
(define CMD_SET_PARAM     #x03)
(define CMD_SET_VOLUME    #x04)
(define CMD_SET_PAN       #x05)
(define CMD_MUTE_TRACK    #x09)
(define CMD_SOLO_TRACK    #x0A)
(define CMD_ALL_NOTES_OFF #x0B)
(define CMD_SET_WAVEFORM  #x0C)
(define CMD_SET_FILTER    #x0D)
(define CMD_SET_ENVELOPE  #x0E)

(define WAVE_SINE 0) (define WAVE_SAW 1)
(define WAVE_SQUARE 2) (define WAVE_TRIANGLE 3) (define WAVE_NOISE 4)

(define CMD_SET_OSC_COUNT  #x0F)
(define CMD_SET_OSC2       #x10)
(define CMD_SET_OSC3       #x11)
(define CMD_SET_FM         #x12)
(define CMD_SET_PITCH_ENV  #x13)
(define CMD_SET_SYNTH_TYPE #x14)
(define CMD_SET_EXP_ENV    #x15)
(define CMD_LOAD_PRESET    #x20)

;; Preset names (must match C load_builtin_preset indices)
(define preset-names
  #("Supersaw Lead"   ;; 0
    "Deep Sub Bass"    ;; 1
    "Acid Bass 303"    ;; 2
    "Warm Pad"         ;; 3
    "FM Bell"          ;; 4
    "FM E.Piano"       ;; 5
    "808 Kick"         ;; 6
    "Snare"            ;; 7
    "HiHat Closed"     ;; 8
    "HiHat Open"       ;; 9
    "Clap"             ;; 10
    "Pluck"            ;; 11
    "Stab"             ;; 12
    "Reese Bass"       ;; 13
    "Strings"          ;; 14
    "Brass"            ;; 15
    ))

;; ---- Sequencer Grid State (C-allocated for FFI) ----
(define GRID_ROWS 8)   ;; 8 tracks
(define GRID_COLS 16)  ;; 16 steps

(define grid-alloc
  (foreign-lambda* c-pointer ((int size))
    "int *g = (int *)calloc(size, sizeof(int)); C_return(g);"))

(define grid-get
  (foreign-lambda* int ((c-pointer grid) (int idx))
    "C_return(((int*)grid)[idx]);"))

(define grid-set!
  (foreign-lambda* void ((c-pointer grid) (int idx) (int val))
    "((int*)grid)[idx] = val;"))

(define grid-free
  (foreign-lambda* void ((c-pointer grid))
    "free(grid);"))

;; ---- Note mapping for grid ----
;; Row 0-3: melodic tracks (C minor), Row 4-7: drum tracks
(define grid-row-notes
  #(48 51 55 60    ;; C3 Eb3 G3 C4 (C minor)
    36 38 42 46))  ;; Kick Snare ClosedHH OpenHH

;; Default presets for each row
(define grid-row-presets
  #(0   ;; Row 0: Supersaw Lead
    13  ;; Row 1: Reese Bass
    11  ;; Row 2: Pluck
    3   ;; Row 3: Warm Pad
    6   ;; Row 4: 808 Kick
    7   ;; Row 5: Snare
    8   ;; Row 6: HiHat Closed
    9   ;; Row 7: HiHat Open
    ))

;; Row labels for the sequencer
(define grid-row-labels
  #("Lead" "Bass" "Pluck" "Pad" "Kick" "Snare" "HH-C" "HH-O"))

;; ---- Helper ----
(define (note-name midi-note)
  (let* ((names #("C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))
         (name (vector-ref names (modulo midi-note 12)))
         (octave (- (quotient midi-note 12) 1)))
    (string-append name (number->string octave))))

;; ---- Main ----
(define (main)
  (let ((args (command-line-arguments)))
    (if (member "--no-gui" args)
        (main-headless)
        (main-gui))))

;; Headless mode: play test sequence
(define (main-headless)
  (format #t "Audio DAC - Headless Mode~%")
  (let ((backend (backend-create 44100 512)))
    (unless backend (error "Failed to create audio backend"))
    (when (< (backend-start backend) 0)
      (backend-destroy backend)
      (error "Failed to start audio"))
    (format #t "Audio engine running. Playing C minor arpeggio...~%")
    (backend-send backend CMD_SET_WAVEFORM 0 WAVE_SAW 0 0.0)
    (let loop ((notes '(48 51 55 60 55 51)) (count 0))
      (when (< count 48)
        (let ((note (car notes))
              (rest (if (null? (cdr notes)) '(48 51 55 60 55 51) (cdr notes))))
          (backend-send backend CMD_NOTE_ON 0 note 100 0.0)
          (thread-sleep! 0.2)
          (backend-send backend CMD_NOTE_OFF 0 note 0 0.0)
          (thread-sleep! 0.05)
          (loop rest (+ count 1)))))
    (thread-sleep! 1.0)
    (backend-stop backend)
    (backend-destroy backend)
    (format #t "Done.~%")))

;; GUI mode: full DAW interface
(define (main-gui)
  (format #t "Audio DAC - Electronic Music DAW~%")

  ;; Initialize audio
  (let ((backend (backend-create 44100 512)))
    (unless backend (error "Failed to create audio backend"))

    ;; Initialize GUI (this also inits SDL video)
    (when (< (gui-init 1280 800 "Audio DAC - Electronic Music DAW") 0)
      (backend-destroy backend)
      (error "Failed to initialize GUI"))

    ;; Start audio after GUI (SDL already initialized)
    (when (< (backend-start backend) 0)
      (gui-shutdown)
      (backend-destroy backend)
      (error "Failed to start audio"))

    ;; Allocate sequencer grid and row labels
    (let ((grid (grid-alloc (* GRID_ROWS GRID_COLS)))
          (c-row-labels (row-labels-alloc GRID_ROWS)))

      ;; DAW state
      (let ((bpm 120.0)
            (playing? #f)
            (waveform 1)     ;; saw
            (cutoff 4000.0)
            (resonance 0.3)
            (current-step 0)
            (step-timer 0)
            (track-volumes (make-vector 8 0.8))
            (track-mutes (make-vector 8 #f))
            (track-solos (make-vector 8 #f)))

        ;; Set up C row label array
        (do ((i 0 (+ i 1))) ((>= i GRID_ROWS))
          (row-labels-set! c-row-labels i (vector-ref grid-row-labels i)))

        ;; Load presets for all tracks
        (do ((i 0 (+ i 1))) ((>= i GRID_ROWS))
          (backend-send backend CMD_LOAD_PRESET i
            (vector-ref grid-row-presets i) 0 0.0))

        ;; Track preset state
        (let ((track-presets (make-vector 8 0)))
          (do ((i 0 (+ i 1))) ((>= i GRID_ROWS))
            (vector-set! track-presets i (vector-ref grid-row-presets i)))

        ;; Main loop
        (let loop ()
          (let ((quit? (gui-process-events!)))
            (unless quit?

              ;; ---- Sequencer tick ----
              (when playing?
                (set! step-timer (+ step-timer 1))
                (let ((step-duration (inexact->exact
                                      (round (/ (* 44100.0 60.0) (* bpm 4.0 60.0))))))
                  ;; ~every N frames, advance step (approximation via frame count)
                  (when (>= step-timer 8) ;; ~8 frames at vsync = ~133ms at 60fps
                    (set! step-timer 0)
                    ;; Note off previous step
                    (do ((r 0 (+ r 1))) ((>= r GRID_ROWS))
                      (let ((note (vector-ref grid-row-notes r))
                            (prev-active (grid-get grid (+ (* r GRID_COLS) current-step))))
                        (when (= prev-active 1)
                          (backend-send backend CMD_NOTE_OFF r note 0 0.0))))
                    ;; Advance step
                    (set! current-step (modulo (+ current-step 1) GRID_COLS))
                    ;; Note on current step
                    (do ((r 0 (+ r 1))) ((>= r GRID_ROWS))
                      (let ((note (vector-ref grid-row-notes r))
                            (active (grid-get grid (+ (* r GRID_COLS) current-step))))
                        (when (= active 1)
                          (backend-send backend CMD_NOTE_ON r note 100 0.0)))))))

              ;; ---- Draw GUI ----
              (gui-frame-begin)

              ;; Get current window dimensions for responsive layout
              (let* ((W (exact->inexact (gui-get-width)))
                     (H (exact->inexact (gui-get-height)))
                     (S (gui-get-dpi-scale))
                     ;; Scaled sizes
                     (row-h  (* 25.0 S))
                     (row-sm (* 20.0 S))
                     (row-lg (* 30.0 S))
                     (pad    (* 4.0 S))
                     ;; Layout: toolbar | sequencer+sounds | mixer
                     (toolbar-h (* 50.0 S))
                     (mixer-h   (* 0.28 (- H toolbar-h)))
                     (seq-h     (- H toolbar-h mixer-h))
                     (seq-y     toolbar-h)
                     (mixer-y   (+ toolbar-h seq-h))
                     ;; Sequencer takes 65% width, sounds 35%
                     (seq-w     (* 0.65 W))
                     (sounds-w  (* 0.35 W))
                     ;; Grid cells
                     (label-w   (* 70.0 S))
                     (grid-cell-w (max 16 (inexact->exact
                                    (round (/ (- seq-w label-w (* 50.0 S)) 16.0)))))
                     (grid-cell-h (max 14 (inexact->exact
                                    (round (/ (- seq-h (* 80.0 S)) 8.0))))))

              ;; ==== TOOLBAR ====
              (when (gui-begin-panel "##Toolbar" 0.0 0.0 W toolbar-h 8)
                (gui-row-dynamic row-lg 10)
                ;; File operations
                (when (= (gui-button "Save") 1)
                  (save-project! "project.daw" grid bpm track-presets track-volumes))
                (when (= (gui-button "Load") 1)
                  (load-project! "project.daw" grid track-presets track-volumes backend)
                  (when *loaded-bpm* (set! bpm *loaded-bpm*) (set! *loaded-bpm* #f)))
                ;; Separator
                (gui-label "|")
                ;; Transport
                (when (= (gui-button (if playing? "Stop" "Play")) 1)
                  (set! playing? (not playing?))
                  (when (not playing?)
                    (do ((r 0 (+ r 1))) ((>= r GRID_ROWS))
                      (backend-send backend CMD_ALL_NOTES_OFF r 0 0 0.0))
                    (set! current-step 0)))
                (set! bpm (gui-property-float "#BPM" 40.0
                            (exact->inexact bpm) 300.0 1.0 0.5))
                (gui-label (string-append "Step " (number->string (+ current-step 1)) "/16"))
                (if playing?
                    (gui-label-colored "PLAYING" 50 200 80)
                    (gui-label-colored "STOPPED" 140 140 140))
                ;; Spacers
                (gui-label "")
                (gui-label "")
                (gui-label-colored "Audio DAC" 100 160 220)
                (gui-end-panel))

              ;; ==== SEQUENCER (with track labels) ====
              (when (gui-begin-panel "Sequencer" 0.0 seq-y seq-w seq-h 8)
                ;; Use the labeled grid
                (gui-sequencer-grid-labeled-raw
                  grid GRID_ROWS GRID_COLS
                  (if playing? current-step -1)
                  grid-cell-w grid-cell-h
                  c-row-labels S)
                (gui-end-panel))

              ;; ==== SOUNDS PANEL ====
              (when (gui-begin-panel "Sounds" seq-w seq-y sounds-w seq-h 8)
                ;; Track preset selectors
                (do ((r 0 (+ r 1))) ((>= r GRID_ROWS))
                  ;; Track header
                  (gui-row-dynamic (* 16.0 S) 2)
                  (gui-label-colored
                    (string-append (number->string (+ r 1)) ". "
                      (vector-ref grid-row-labels r))
                    (if (< r 4) 80 220) (if (< r 4) 180 160) (if (< r 4) 220 80))
                  (gui-label-colored
                    (vector-ref preset-names (vector-ref track-presets r))
                    160 200 160)
                  ;; Preset buttons
                  (let* ((presets-for-row
                          (if (>= r 4)
                              (case r
                                ((4) #(6 1 2 13))
                                ((5) #(7 10 12 11))
                                ((6) #(8 9 10 4))
                                ((7) #(9 8 4 5))
                                (else #(6 7 8 9)))
                              (case r
                                ((0) #(0 15 11 12))
                                ((1) #(13 1 2 14))
                                ((2) #(11 4 5 12))
                                ((3) #(3 14 5 4))
                                (else #(0 1 2 3))))))
                    (gui-row-dynamic (* 22.0 S) 4)
                    (do ((p 0 (+ p 1))) ((>= p 4))
                      (let* ((pi (vector-ref presets-for-row p))
                             (pn (vector-ref preset-names pi))
                             (act (= (vector-ref track-presets r) pi)))
                        (when (= (gui-button (if act (string-append ">" pn) pn)) 1)
                          (vector-set! track-presets r pi)
                          (backend-send backend CMD_LOAD_PRESET r pi 0 0.0))))))

                ;; Filter at bottom
                (gui-separator (* 5.0 S))
                (gui-row-dynamic (* 14.0 S) 1)
                (gui-label-colored "Filter" 120 160 200)
                (let ((new-cutoff (gui-slider "Cutoff"
                                    (exact->inexact cutoff) 20.0 20000.0 10.0)))
                  (when (not (= new-cutoff cutoff))
                    (set! cutoff new-cutoff)
                    (backend-send backend CMD_SET_FILTER 0 0 0 cutoff)))
                (let ((new-reso (gui-slider "Reso"
                                  (exact->inexact resonance) 0.0 0.95 0.01)))
                  (when (not (= new-reso resonance))
                    (set! resonance new-reso)
                    (backend-send backend CMD_SET_FILTER 0 1 0 resonance)))
                (gui-end-panel))

              ;; ==== MIXER ====
              (when (gui-begin-panel "Mixer" 0.0 mixer-y W mixer-h 8)
                (do ((i 0 (+ i 1))) ((>= i 8))
                  (gui-row-dynamic row-h 6)
                  ;; Mute
                  (let ((m (vector-ref track-mutes i)))
                    (when (= (gui-button (if m "M!" "M ")) 1)
                      (vector-set! track-mutes i (not m))
                      (backend-send backend CMD_MUTE_TRACK i (if (not m) 1 0) 0 0.0)))
                  ;; Solo
                  (let ((s (vector-ref track-solos i)))
                    (when (= (gui-button (if s "S!" "S ")) 1)
                      (vector-set! track-solos i (not s))
                      (backend-send backend CMD_SOLO_TRACK i (if (not s) 1 0) 0 0.0)))
                  ;; Track name + preset
                  (gui-label-colored
                    (string-append (vector-ref grid-row-labels i) " - "
                      (vector-ref preset-names (vector-ref track-presets i)))
                    (if (< i 4) 80 220) (if (< i 4) 180 160) (if (< i 4) 220 80))
                  ;; Volume
                  (let* ((vol (vector-ref track-volumes i))
                         (new-vol (gui-slider ""
                                    (exact->inexact vol) 0.0 1.0 0.01)))
                    (when (not (= new-vol vol))
                      (vector-set! track-volumes i new-vol)
                      (backend-send backend CMD_SET_VOLUME i 0 0
                        (exact->inexact new-vol)))))
                (gui-end-panel))

              ) ;; end let* for layout dimensions

              (gui-frame-end)

              (loop)))))) ;; loop, unless, let-quit, let-loop, let-track-presets

        ;; Cleanup
        (row-labels-free c-row-labels)
        (grid-free grid)
        (backend-stop backend)
        (gui-shutdown)
        (backend-destroy backend)
        (format #t "Goodbye.~%")))) ;; let-state, let-grid, let-backend, main-gui

;; Run
(main)

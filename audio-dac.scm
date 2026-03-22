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

;; Scale a value by DPI
(define (dpi* val)
  (inexact->exact (round (* val (gui-get-dpi-scale)))))

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
;; Row 0-3: melodic tracks, Row 4-7: drum tracks
(define grid-row-notes
  #(60 64 67 72    ;; C4 E4 G4 C5 (C major chord)
    36 38 42 46))  ;; Kick Snare ClosedHH OpenHH

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

    ;; Allocate sequencer grid
    (let ((grid (grid-alloc (* GRID_ROWS GRID_COLS))))

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

        ;; Set initial synth params
        (backend-send backend CMD_SET_WAVEFORM 0 WAVE_SAW 0 0.0)

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
                     ;; Scaled row heights
                     (row-h  (* 25.0 S))
                     (row-sm (* 20.0 S))
                     (row-lg (* 30.0 S))
                     ;; Layout regions
                     (transport-h (* 55.0 S))
                     (mid-h (* 0.4 (- H transport-h)))   ;; 40% for seq+synth
                     (mixer-h (- H transport-h mid-h))    ;; rest for mixer
                     (mid-y transport-h)
                     (mixer-y (+ transport-h mid-h))
                     (half-w (* 0.5 W))
                     ;; Grid cell sizes scale with available space
                     (grid-cell-w (max 20 (inexact->exact (round (/ (- half-w (* 40.0 S)) 16.0)))))
                     (grid-cell-h (max 16 (inexact->exact (round (/ (- mid-h (* 60.0 S)) 8.0))))))

              ;; Transport bar
              (when (gui-begin-panel "Transport" 0.0 0.0 W transport-h 8)
                (gui-row-dynamic row-lg 8)
                (gui-label "Audio DAC")
                (set! bpm (gui-property-float "#BPM" 40.0
                            (exact->inexact bpm) 300.0 1.0 0.5))
                (when (= (gui-button (if playing? "STOP" "PLAY")) 1)
                  (set! playing? (not playing?))
                  (when (not playing?)
                    ;; All notes off when stopping
                    (do ((r 0 (+ r 1))) ((>= r GRID_ROWS))
                      (backend-send backend CMD_ALL_NOTES_OFF r 0 0 0.0))
                    (set! current-step 0)))
                (gui-label (string-append "Step: "
                             (number->string (+ current-step 1))
                             "/16"))
                (if playing?
                    (gui-label-colored "PLAYING" 50 200 80)
                    (gui-label "STOPPED"))
                (gui-label "")
                (gui-label "")
                (gui-label "")
                (gui-end-panel))

              ;; Sequencer grid
              (when (gui-begin-panel "Sequencer" 0.0 mid-y half-w mid-h 8)
                ;; Row labels
                (gui-row-dynamic (* 15.0 S) 1)
                (gui-label "Click cells to toggle notes. Rows = tracks, Cols = steps")
                ;; Grid
                (gui-sequencer-grid-raw grid GRID_ROWS GRID_COLS
                  (if playing? current-step -1) grid-cell-w grid-cell-h)
                (gui-end-panel))

              ;; Synth editor
              (when (gui-begin-panel "Synth" half-w mid-y half-w mid-h 8)
                ;; Waveform selector
                (gui-row-dynamic row-h 5)
                (when (= (gui-button (if (= waveform 0) "[SIN]" "SIN")) 1)
                  (set! waveform 0)
                  (backend-send backend CMD_SET_WAVEFORM 0 0 0 0.0))
                (when (= (gui-button (if (= waveform 1) "[SAW]" "SAW")) 1)
                  (set! waveform 1)
                  (backend-send backend CMD_SET_WAVEFORM 0 1 0 0.0))
                (when (= (gui-button (if (= waveform 2) "[SQR]" "SQR")) 1)
                  (set! waveform 2)
                  (backend-send backend CMD_SET_WAVEFORM 0 2 0 0.0))
                (when (= (gui-button (if (= waveform 3) "[TRI]" "TRI")) 1)
                  (set! waveform 3)
                  (backend-send backend CMD_SET_WAVEFORM 0 3 0 0.0))
                (when (= (gui-button (if (= waveform 4) "[NSE]" "NSE")) 1)
                  (set! waveform 4)
                  (backend-send backend CMD_SET_WAVEFORM 0 4 0 0.0))

                ;; Filter
                (gui-row-dynamic row-sm 1)
                (gui-label "-- Filter --")
                (let ((new-cutoff (gui-slider "Cutoff"
                                    (exact->inexact cutoff) 20.0 20000.0 10.0)))
                  (when (not (= new-cutoff cutoff))
                    (set! cutoff new-cutoff)
                    (backend-send backend CMD_SET_FILTER 0 0 0 cutoff)))
                (let ((new-reso (gui-slider "Resonance"
                                  (exact->inexact resonance) 0.0 0.99 0.01)))
                  (when (not (= new-reso resonance))
                    (set! resonance new-reso)
                    (backend-send backend CMD_SET_FILTER 0 1 0 resonance)))

                (gui-end-panel))

              ;; Mixer
              (when (gui-begin-panel "Mixer" 0.0 mixer-y W mixer-h 8)
                ;; Track names
                (gui-row-dynamic row-sm 8)
                (do ((i 0 (+ i 1))) ((>= i 8))
                  (gui-label (string-append "Track " (number->string (+ i 1)))))

                ;; Volume sliders
                (gui-row-dynamic row-sm 8)
                (do ((i 0 (+ i 1))) ((>= i 8))
                  (let* ((vol (vector-ref track-volumes i))
                         (new-vol (gui-slider ""
                                    (exact->inexact vol) 0.0 1.0 0.01)))
                    (when (not (= new-vol vol))
                      (vector-set! track-volumes i new-vol)
                      (backend-send backend CMD_SET_VOLUME i 0 0
                        (exact->inexact new-vol)))))

                ;; Mute/Solo buttons
                (gui-row-dynamic row-h 8)
                (do ((i 0 (+ i 1))) ((>= i 8))
                  (let ((m (vector-ref track-mutes i)))
                    (when (= (gui-button (if m "[M]" "M")) 1)
                      (vector-set! track-mutes i (not m))
                      (backend-send backend CMD_MUTE_TRACK i
                        (if (not m) 1 0) 0 0.0))))

                (gui-row-dynamic row-h 8)
                (do ((i 0 (+ i 1))) ((>= i 8))
                  (let ((s (vector-ref track-solos i)))
                    (when (= (gui-button (if s "[S]" "S")) 1)
                      (vector-set! track-solos i (not s))
                      (backend-send backend CMD_SOLO_TRACK i
                        (if (not s) 1 0) 0 0.0))))

                (gui-end-panel))

              ) ;; end let* for layout dimensions

              (gui-frame-end)

              (loop))))

        ;; Cleanup
        (grid-free grid)
        (backend-stop backend)
        (gui-shutdown)
        (backend-destroy backend)
        (format #t "Goodbye.~%")))))

;; Run
(main)

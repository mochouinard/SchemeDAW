#ifndef GUI_BACKEND_H
#define GUI_BACKEND_H

#include <SDL2/SDL.h>

/* Opaque Nuklear context - actual type defined in gui-backend.c */
struct nk_context;

/* ---- Lifecycle ---- */

/* Initialize SDL2 window + renderer + Nuklear.
 * Returns 0 on success, -1 on error. */
int gui_init(int width, int height, const char *title);

/* Shut down GUI and free resources. */
void gui_shutdown(void);

/* ---- Frame cycle ---- */

/* Process SDL events. Sets *quit = 1 if user requested close. */
void gui_process_events(int *quit);

/* Begin a new Nuklear frame (call after gui_process_events). */
void gui_frame_begin(void);

/* End frame and render to screen. */
void gui_frame_end(void);

/* ---- Nuklear context access ---- */

/* Get the Nuklear context pointer for direct Nuklear calls from C. */
struct nk_context* gui_get_ctx(void);

/* Get the SDL renderer for custom drawing. */
SDL_Renderer* gui_get_renderer(void);

/* ---- High-level widget helpers ---- */
/* These wrap common Nuklear calls for DAW-specific widgets. */

/* Begin a panel (returns 1 if visible, 0 if collapsed). */
int gui_begin_panel(const char *title, float x, float y, float w, float h, int flags);
void gui_end_panel(void);

/* Layout helpers */
void gui_row_dynamic(float height, int cols);
void gui_row_static(float height, int item_width, int cols);

/* Basic widgets - return updated value or 1 if clicked */
float gui_slider(const char *label, float value, float min, float max, float step);
float gui_knob(const char *label, float value, float min, float max);
int   gui_button(const char *label);
int   gui_toggle(const char *label, int active);
void  gui_label(const char *text);
void  gui_label_colored(const char *text, int r, int g, int b);
int   gui_combo(const char *label, const char **items, int count, int selected,
                int item_height, int max_height);

/* Numeric property editor */
float gui_property_float(const char *label, float min, float value, float max,
                         float step, float inc_per_pixel);
int   gui_property_int(const char *label, int min, int value, int max,
                       int step, float inc_per_pixel);

/* Meter (horizontal bar showing level 0.0-1.0) */
void gui_meter(const char *label, float level);

/* Sequencer grid: draws a grid of toggleable cells.
 * grid_data: array of length rows*cols, each 0 or 1.
 * current_step: highlighted column (-1 for none).
 * Returns 1 if any cell was toggled (grid_data is modified in-place). */
int gui_sequencer_grid(int *grid_data, int rows, int cols, int current_step,
                       int cell_width, int cell_height);

/* Color constants for the DAW theme */
void gui_set_daw_theme(void);

#endif /* GUI_BACKEND_H */

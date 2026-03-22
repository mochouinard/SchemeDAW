/*
 * gui-backend.c - Nuklear + SDL2 Renderer GUI backend for Audio DAC
 *
 * Implements the Nuklear immediate-mode GUI with SDL2 renderer backend.
 * Provides high-level widget functions that can be called from Scheme via FFI.
 */

#include <SDL2/SDL.h>

/* Nuklear configuration - must be before nuklear.h include */
#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#define NK_IMPLEMENTATION
#include "../lib/nuklear/nuklear.h"

#define NK_SDL_RENDERER_IMPLEMENTATION
#include "../lib/nuklear/nuklear_sdl_renderer.h"

#include "gui-backend.h"
#include <stdio.h>
#include <math.h>

/* ---- Global state ---- */
static SDL_Window   *g_window   = NULL;
static SDL_Renderer *g_renderer = NULL;
static struct nk_context *g_ctx = NULL;
static int g_width  = 1280;
static int g_height = 800;

/* ---- Lifecycle ---- */

int gui_init(int width, int height, const char *title) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL_Init(VIDEO) failed: %s\n", SDL_GetError());
        return -1;
    }

    g_width = width;
    g_height = height;

    g_window = SDL_CreateWindow(title,
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        width, height,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
    if (!g_window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        return -1;
    }

    g_renderer = SDL_CreateRenderer(g_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!g_renderer) {
        fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(g_window);
        return -1;
    }

    /* Initialize Nuklear with SDL renderer */
    g_ctx = nk_sdl_init(g_window, g_renderer);

    /* Load default font */
    {
        struct nk_font_atlas *atlas;
        nk_sdl_font_stash_begin(&atlas);
        /* NULL = use default font, 14px */
        struct nk_font *font = nk_font_atlas_add_default(atlas, 14, NULL);
        nk_sdl_font_stash_end();
        nk_style_set_font(g_ctx, &font->handle);
    }

    gui_set_daw_theme();

    fprintf(stderr, "GUI initialized: %dx%d\n", width, height);
    return 0;
}

void gui_shutdown(void) {
    if (g_ctx) {
        nk_sdl_shutdown();
        g_ctx = NULL;
    }
    if (g_renderer) {
        SDL_DestroyRenderer(g_renderer);
        g_renderer = NULL;
    }
    if (g_window) {
        SDL_DestroyWindow(g_window);
        g_window = NULL;
    }
}

/* ---- Frame cycle ---- */

void gui_process_events(int *quit) {
    SDL_Event evt;
    nk_input_begin(g_ctx);
    while (SDL_PollEvent(&evt)) {
        if (evt.type == SDL_QUIT) {
            *quit = 1;
        }
        /* Handle window resize */
        if (evt.type == SDL_WINDOWEVENT &&
            evt.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
            g_width = evt.window.data1;
            g_height = evt.window.data2;
        }
        nk_sdl_handle_event(&evt);
    }
    nk_input_end(g_ctx);
}

void gui_frame_begin(void) {
    /* Nothing needed - nk_input_end was already called in gui_process_events */
}

void gui_frame_end(void) {
    /* Clear background */
    SDL_SetRenderDrawColor(g_renderer, 30, 30, 30, 255);
    SDL_RenderClear(g_renderer);

    /* Render Nuklear */
    nk_sdl_render(NK_ANTI_ALIASING_ON);

    SDL_RenderPresent(g_renderer);
}

/* ---- Context access ---- */

struct nk_context* gui_get_ctx(void) {
    return g_ctx;
}

SDL_Renderer* gui_get_renderer(void) {
    return g_renderer;
}

/* ---- High-level widgets ---- */

int gui_begin_panel(const char *title, float x, float y, float w, float h, int flags) {
    struct nk_rect bounds = nk_rect(x, y, w, h);
    nk_flags nk_panel_flags = NK_WINDOW_BORDER | NK_WINDOW_TITLE;
    if (flags & 1) nk_panel_flags |= NK_WINDOW_MOVABLE;
    if (flags & 2) nk_panel_flags |= NK_WINDOW_SCALABLE;
    if (flags & 4) nk_panel_flags |= NK_WINDOW_MINIMIZABLE;
    if (flags & 8) nk_panel_flags |= NK_WINDOW_NO_SCROLLBAR;

    return nk_begin(g_ctx, title, bounds, nk_panel_flags);
}

void gui_end_panel(void) {
    nk_end(g_ctx);
}

void gui_row_dynamic(float height, int cols) {
    nk_layout_row_dynamic(g_ctx, height, cols);
}

void gui_row_static(float height, int item_width, int cols) {
    nk_layout_row_static(g_ctx, height, item_width, cols);
}

float gui_slider(const char *label, float value, float min_val, float max_val, float step) {
    nk_layout_row_dynamic(g_ctx, 20, 2);
    nk_label(g_ctx, label, NK_TEXT_LEFT);
    nk_slider_float(g_ctx, min_val, &value, max_val, step);
    return value;
}

float gui_knob(const char *label, float value, float min_val, float max_val) {
    /* Nuklear doesn't have a native knob widget.
     * We implement it as a vertical slider with a label.
     * A proper knob could use custom drawing, but this works for now. */
    nk_layout_row_dynamic(g_ctx, 20, 1);
    nk_label(g_ctx, label, NK_TEXT_CENTERED);
    nk_layout_row_dynamic(g_ctx, 20, 1);
    float step = (max_val - min_val) / 100.0f;
    nk_slider_float(g_ctx, min_val, &value, max_val, step);
    return value;
}

int gui_button(const char *label) {
    return nk_button_label(g_ctx, label);
}

int gui_toggle(const char *label, int active) {
    return nk_check_label(g_ctx, label, active);
}

void gui_label(const char *text) {
    nk_label(g_ctx, text, NK_TEXT_LEFT);
}

void gui_label_colored(const char *text, int r, int g, int b) {
    nk_label_colored(g_ctx, text, NK_TEXT_LEFT, nk_rgb(r, g, b));
}

int gui_combo(const char *label, const char **items, int count, int selected,
              int item_height, int max_height) {
    nk_layout_row_dynamic(g_ctx, 25, 2);
    nk_label(g_ctx, label, NK_TEXT_LEFT);
    /* Use nk_combo to create a dropdown */
    struct nk_vec2 size = nk_vec2(200, (float)max_height);
    return nk_combo(g_ctx, items, count, selected, item_height, size);
}

float gui_property_float(const char *label, float min_val, float value, float max_val,
                         float step, float inc_per_pixel) {
    nk_property_float(g_ctx, label, min_val, &value, max_val, step, inc_per_pixel);
    return value;
}

int gui_property_int(const char *label, int min_val, int value, int max_val,
                     int step, float inc_per_pixel) {
    nk_property_int(g_ctx, label, min_val, &value, max_val, step, inc_per_pixel);
    return value;
}

void gui_meter(const char *label, float level) {
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;

    nk_layout_row_dynamic(g_ctx, 20, 2);
    nk_label(g_ctx, label, NK_TEXT_LEFT);

    /* Draw meter as a colored progress bar */
    struct nk_color color;
    if (level > 0.9f) {
        color = nk_rgb(255, 50, 50);     /* Red - clipping */
    } else if (level > 0.7f) {
        color = nk_rgb(255, 200, 50);    /* Yellow - hot */
    } else {
        color = nk_rgb(50, 200, 80);     /* Green - normal */
    }

    /* Save current style, modify progress bar color, then restore */
    struct nk_style_progress *prog = &g_ctx->style.progress;
    struct nk_style_item old_cursor = prog->cursor_normal;
    prog->cursor_normal = nk_style_item_color(color);

    nk_size val = (nk_size)(level * 100.0f);
    nk_progress(g_ctx, &val, 100, NK_FIXED);

    prog->cursor_normal = old_cursor;
}

int gui_sequencer_grid(int *grid_data, int rows, int cols, int current_step,
                       int cell_width, int cell_height) {
    int changed = 0;

    for (int r = 0; r < rows; r++) {
        nk_layout_row_static(g_ctx, (float)cell_height, cell_width, cols);
        for (int c = 0; c < cols; c++) {
            int idx = r * cols + c;
            int active = grid_data[idx];

            /* Determine cell color */
            struct nk_color color;
            if (c == current_step) {
                if (active)
                    color = nk_rgb(255, 180, 50);   /* Active + playing */
                else
                    color = nk_rgb(80, 80, 50);     /* Playing position */
            } else {
                if (active)
                    color = nk_rgb(80, 180, 220);   /* Active */
                else {
                    /* Every 4th column slightly brighter for beat reference */
                    if (c % 4 == 0)
                        color = nk_rgb(55, 55, 55);
                    else
                        color = nk_rgb(45, 45, 45);
                }
            }

            /* Use colored button for grid cell */
            struct nk_style_button style = g_ctx->style.button;
            style.normal = nk_style_item_color(color);
            style.hover = nk_style_item_color(nk_rgb(
                (int)(color.r * 1.2f > 255 ? 255 : color.r * 1.2f),
                (int)(color.g * 1.2f > 255 ? 255 : color.g * 1.2f),
                (int)(color.b * 1.2f > 255 ? 255 : color.b * 1.2f)));
            style.active = nk_style_item_color(nk_rgb(200, 200, 200));
            style.border_color = nk_rgb(60, 60, 60);
            style.border = 1;

            if (nk_button_label_styled(g_ctx, &style, active ? "#" : "")) {
                grid_data[idx] = !grid_data[idx];
                changed = 1;
            }
        }
    }

    return changed;
}

/* ---- DAW Theme ---- */

void gui_set_daw_theme(void) {
    struct nk_color table[NK_COLOR_COUNT];
    table[NK_COLOR_TEXT]                    = nk_rgb(200, 200, 200);
    table[NK_COLOR_WINDOW]                  = nk_rgb(35, 35, 38);
    table[NK_COLOR_HEADER]                  = nk_rgb(45, 45, 48);
    table[NK_COLOR_BORDER]                  = nk_rgb(60, 60, 65);
    table[NK_COLOR_BUTTON]                  = nk_rgb(55, 55, 60);
    table[NK_COLOR_BUTTON_HOVER]            = nk_rgb(70, 70, 75);
    table[NK_COLOR_BUTTON_ACTIVE]           = nk_rgb(80, 130, 200);
    table[NK_COLOR_TOGGLE]                  = nk_rgb(55, 55, 60);
    table[NK_COLOR_TOGGLE_HOVER]            = nk_rgb(70, 70, 75);
    table[NK_COLOR_TOGGLE_CURSOR]           = nk_rgb(80, 130, 200);
    table[NK_COLOR_SELECT]                  = nk_rgb(55, 55, 60);
    table[NK_COLOR_SELECT_ACTIVE]           = nk_rgb(80, 130, 200);
    table[NK_COLOR_SLIDER]                  = nk_rgb(45, 45, 48);
    table[NK_COLOR_SLIDER_CURSOR]           = nk_rgb(80, 130, 200);
    table[NK_COLOR_SLIDER_CURSOR_HOVER]     = nk_rgb(100, 150, 220);
    table[NK_COLOR_SLIDER_CURSOR_ACTIVE]    = nk_rgb(120, 170, 240);
    table[NK_COLOR_PROPERTY]                = nk_rgb(45, 45, 48);
    table[NK_COLOR_EDIT]                    = nk_rgb(45, 45, 48);
    table[NK_COLOR_EDIT_CURSOR]             = nk_rgb(200, 200, 200);
    table[NK_COLOR_COMBO]                   = nk_rgb(55, 55, 60);
    table[NK_COLOR_CHART]                   = nk_rgb(45, 45, 48);
    table[NK_COLOR_CHART_COLOR]             = nk_rgb(80, 130, 200);
    table[NK_COLOR_CHART_COLOR_HIGHLIGHT]   = nk_rgb(255, 180, 50);
    table[NK_COLOR_SCROLLBAR]               = nk_rgb(45, 45, 48);
    table[NK_COLOR_SCROLLBAR_CURSOR]        = nk_rgb(70, 70, 75);
    table[NK_COLOR_SCROLLBAR_CURSOR_HOVER]  = nk_rgb(80, 80, 85);
    table[NK_COLOR_SCROLLBAR_CURSOR_ACTIVE] = nk_rgb(90, 90, 95);
    table[NK_COLOR_TAB_HEADER]              = nk_rgb(45, 45, 48);
    nk_style_from_table(g_ctx, table);

    /* Make buttons slightly rounded */
    g_ctx->style.button.rounding = 3;
    g_ctx->style.slider.bar_height = 6;
}

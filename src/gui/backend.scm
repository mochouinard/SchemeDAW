;;; backend.scm - Scheme FFI bindings to the Nuklear+SDL2 GUI backend

(module audio-dac.gui.backend
  (gui-init!
   gui-shutdown!
   gui-process-events!
   gui-frame-begin!
   gui-frame-end!
   gui-begin-panel
   gui-end-panel
   gui-row-dynamic
   gui-row-static
   gui-slider
   gui-knob
   gui-button
   gui-toggle
   gui-label
   gui-label-colored
   gui-combo
   gui-property-float
   gui-property-int
   gui-meter
   gui-sequencer-grid
   ;; Panel flags
   PANEL_MOVABLE
   PANEL_SCALABLE
   PANEL_MINIMIZABLE
   PANEL_NO_SCROLLBAR)

  (import scheme
          (chicken base)
          (chicken foreign)
          (chicken memory))

  (foreign-declare "
#include \"gui-backend.h\"
")

  ;; Panel flags
  (define PANEL_MOVABLE     1)
  (define PANEL_SCALABLE    2)
  (define PANEL_MINIMIZABLE 4)
  (define PANEL_NO_SCROLLBAR 8)

  ;; ---- Lifecycle ----

  (define gui-init-raw
    (foreign-lambda int "gui_init" int int c-string))

  (define (gui-init! #!key (width 1280) (height 800) (title "Audio DAC"))
    (let ((result (gui-init-raw width height title)))
      (when (< result 0)
        (error "Failed to initialize GUI"))
      result))

  (define gui-shutdown!
    (foreign-lambda void "gui_shutdown"))

  ;; ---- Frame cycle ----

  ;; Returns #t if quit was requested
  (define (gui-process-events!)
    (let-location ((quit int 0))
      ((foreign-lambda void "gui_process_events" (c-pointer int)) (location quit))
      (not (= quit 0))))

  (define gui-frame-begin!
    (foreign-lambda void "gui_frame_begin"))

  (define gui-frame-end!
    (foreign-lambda void "gui_frame_end"))

  ;; ---- Panels ----

  (define gui-begin-panel
    (foreign-lambda int "gui_begin_panel" c-string float float float float int))

  (define gui-end-panel
    (foreign-lambda void "gui_end_panel"))

  ;; ---- Layout ----

  (define gui-row-dynamic
    (foreign-lambda void "gui_row_dynamic" float int))

  (define gui-row-static
    (foreign-lambda void "gui_row_static" float int int))

  ;; ---- Widgets ----

  (define gui-slider
    (foreign-lambda float "gui_slider" c-string float float float float))

  (define gui-knob
    (foreign-lambda float "gui_knob" c-string float float float))

  (define gui-button
    (foreign-lambda int "gui_button" c-string))

  (define gui-toggle
    (foreign-lambda int "gui_toggle" c-string int))

  (define gui-label
    (foreign-lambda void "gui_label" c-string))

  (define gui-label-colored
    (foreign-lambda void "gui_label_colored" c-string int int int))

  (define gui-combo-raw
    (foreign-lambda int "gui_combo" c-string c-pointer int int int int))

  ;; Scheme-friendly combo: takes a list of strings
  (define (gui-combo label items selected
                     #!key (item-height 25) (max-height 200))
    ;; For now, use a simplified approach - call as raw C strings
    gui-combo-raw)  ;; TODO: proper string array marshalling

  (define gui-property-float
    (foreign-lambda float "gui_property_float" c-string float float float float float))

  (define gui-property-int
    (foreign-lambda int "gui_property_int" c-string int int int int float))

  (define gui-meter
    (foreign-lambda void "gui_meter" c-string float))

  ;; Sequencer grid - works with SRFI-4 s32vector
  (define gui-sequencer-grid-raw
    (foreign-lambda int "gui_sequencer_grid" c-pointer int int int int int))

  (define (gui-sequencer-grid grid-ptr rows cols current-step
                              #!key (cell-width 28) (cell-height 24))
    (gui-sequencer-grid-raw grid-ptr rows cols current-step cell-width cell-height))

) ;; end module

;;; widgets.scm - Reusable DAW-specific widget compositions
;;;
;;; Higher-level widgets built on top of the Nuklear backend bindings.
;;; These combine multiple Nuklear primitives into DAW-style controls.

(module audio-dac.gui.widgets
  (draw-transport-bar
   draw-track-fader
   draw-waveform-selector)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken foreign))

  (foreign-declare "
#include \"gui-backend.h\"
")

  ;; Reuse raw FFI calls directly for widget compositions
  (define gui-begin-panel  (foreign-lambda int "gui_begin_panel" c-string float float float float int))
  (define gui-end-panel    (foreign-lambda void "gui_end_panel"))
  (define gui-row-dynamic  (foreign-lambda void "gui_row_dynamic" float int))
  (define gui-row-static   (foreign-lambda void "gui_row_static" float int int))
  (define gui-button       (foreign-lambda int "gui_button" c-string))
  (define gui-label        (foreign-lambda void "gui_label" c-string))
  (define gui-label-colored (foreign-lambda void "gui_label_colored" c-string int int int))
  (define gui-slider-raw   (foreign-lambda float "gui_slider" c-string float float float float))
  (define gui-meter        (foreign-lambda void "gui_meter" c-string float))
  (define gui-property-float (foreign-lambda float "gui_property_float" c-string float float float float float))

  ;; Transport bar: BPM, Play/Stop/Record buttons
  ;; Returns: (values bpm playing? recording?)
  (define (draw-transport-bar bpm playing? recording? x y w h)
    (when (gui-begin-panel "Transport" x y w h 8) ;; NO_SCROLLBAR
      (gui-row-dynamic 30.0 7)

      ;; BPM control
      (gui-label "BPM:")
      (let ((new-bpm (gui-property-float "#BPM:" 40.0 (exact->inexact bpm) 300.0 1.0 0.5)))

        ;; Play button
        (let ((play-clicked (gui-button (if playing? "||" ">"))))

          ;; Stop button
          (let ((stop-clicked (gui-button "[]")))

            ;; Record button
            (let ((rec-clicked (gui-button (if recording? "[R]" "R"))))

              ;; Status display
              (if playing?
                  (gui-label-colored "PLAYING" 50 200 80)
                  (gui-label "STOPPED"))

              (gui-label "")  ;; spacer

              (gui-end-panel)

              ;; Return new state
              (values
               new-bpm
               (if play-clicked (not playing?) playing?)
               (if stop-clicked #f playing?)
               (if rec-clicked (not recording?) recording?)))))))

  ;; Single track fader strip
  ;; Returns: (values new-volume new-mute? new-solo?)
  (define (draw-track-fader name volume mute? solo? level)
    (gui-row-dynamic 15.0 1)
    (gui-label name)

    ;; VU Meter
    (gui-meter "" (exact->inexact level))

    ;; Volume slider
    (gui-row-dynamic 20.0 1)
    (let ((new-vol (gui-slider-raw "Vol" (exact->inexact volume) 0.0 1.0 0.01)))

      ;; Mute and Solo buttons
      (gui-row-dynamic 25.0 2)
      (let ((new-mute (if (= (gui-button (if mute? "[M]" "M")) 1)
                          (not mute?) mute?))
            (new-solo (if (= (gui-button (if solo? "[S]" "S")) 1)
                          (not solo?) solo?)))
        (values new-vol new-mute new-solo))))

  ;; Waveform type selector (returns selected waveform index)
  (define (draw-waveform-selector current-wave)
    (gui-row-dynamic 25.0 5)
    (let* ((sine-clicked  (gui-button "SIN"))
           (saw-clicked   (gui-button "SAW"))
           (sq-clicked    (gui-button "SQR"))
           (tri-clicked   (gui-button "TRI"))
           (noise-clicked (gui-button "NSE")))
      (cond
       ((= sine-clicked 1)  0)
       ((= saw-clicked 1)   1)
       ((= sq-clicked 1)    2)
       ((= tri-clicked 1)   3)
       ((= noise-clicked 1) 4)
       (else current-wave))))

) ;; end module

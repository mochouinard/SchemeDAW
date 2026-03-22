;;; main-window.scm - Main DAW window layout
;;;
;;; Orchestrates the top-level window with toolbar, sequencer,
;;; synth editor, and mixer panels.

(module audio-dac.gui.main-window
  (draw-main-window)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken foreign))

  (foreign-declare "
#include \"gui-backend.h\"
")

  ;; Raw FFI calls
  (define gui-begin-panel    (foreign-lambda int "gui_begin_panel" c-string float float float float int))
  (define gui-end-panel      (foreign-lambda void "gui_end_panel"))
  (define gui-row-dynamic    (foreign-lambda void "gui_row_dynamic" float int))
  (define gui-row-static     (foreign-lambda void "gui_row_static" float int int))
  (define gui-button         (foreign-lambda int "gui_button" c-string))
  (define gui-label          (foreign-lambda void "gui_label" c-string))
  (define gui-label-colored  (foreign-lambda void "gui_label_colored" c-string int int int))
  (define gui-slider         (foreign-lambda float "gui_slider" c-string float float float float))
  (define gui-property-float (foreign-lambda float "gui_property_float" c-string float float float float float))
  (define gui-meter          (foreign-lambda void "gui_meter" c-string float))

  ;; Draw the complete main window
  ;; state: mutable alist of DAW state
  ;; Returns updated state
  (define (draw-main-window state)
    (let ((bpm       (alist-ref 'bpm state))
          (playing?  (alist-ref 'playing? state))
          (track-vol (alist-ref 'track-volumes state))
          (waveform  (alist-ref 'waveform state))
          (cutoff    (alist-ref 'cutoff state))
          (resonance (alist-ref 'resonance state))
          (step      (alist-ref 'current-step state)))

      ;; ---- Transport Bar ----
      (when (gui-begin-panel "Transport" 0.0 0.0 1280.0 60.0 8)
        (gui-row-dynamic 30.0 8)
        (gui-label "Audio DAC")
        (gui-label (string-append "BPM: " (number->string (inexact->exact (round bpm)))))

        (let ((new-bpm (gui-property-float "#BPM" 40.0 (exact->inexact bpm) 300.0 1.0 0.5)))
          (when (= (gui-button (if playing? "STOP" "PLAY")) 1)
            (set! playing? (not playing?)))
          (gui-label (string-append "Step: " (number->string step)))
          (if playing?
              (gui-label-colored "PLAYING" 50 200 80)
              (gui-label "STOPPED"))
          (gui-label "")
          (gui-label "")
          (gui-end-panel)
          (set! bpm new-bpm)))

      ;; ---- Synth Editor ----
      (when (gui-begin-panel "Synth" 0.0 60.0 640.0 370.0 8)
        ;; Waveform selector
        (gui-row-dynamic 25.0 5)
        (when (= (gui-button "SIN") 1) (set! waveform 0))
        (when (= (gui-button "SAW") 1) (set! waveform 1))
        (when (= (gui-button "SQR") 1) (set! waveform 2))
        (when (= (gui-button "TRI") 1) (set! waveform 3))
        (when (= (gui-button "NSE") 1) (set! waveform 4))

        ;; Filter controls
        (gui-row-dynamic 25.0 1)
        (gui-label "-- Filter --")
        (set! cutoff (gui-slider "Cutoff" (exact->inexact cutoff)
                                 20.0 20000.0 10.0))
        (set! resonance (gui-slider "Resonance" (exact->inexact resonance)
                                    0.0 0.99 0.01))

        ;; Amp Envelope
        (gui-row-dynamic 25.0 1)
        (gui-label "-- Amp Envelope --")
        (let ((aa (gui-slider "Attack" 0.01 0.001 2.0 0.001))
              (ad (gui-slider "Decay" 0.2 0.001 2.0 0.001))
              (as (gui-slider "Sustain" 0.7 0.0 1.0 0.01))
              (ar (gui-slider "Release" 0.3 0.001 4.0 0.001)))
          (set! state (alist-update 'amp-a aa state))
          (set! state (alist-update 'amp-d ad state))
          (set! state (alist-update 'amp-s as state))
          (set! state (alist-update 'amp-r ar state)))

        (gui-end-panel))

      ;; ---- Mixer ----
      (when (gui-begin-panel "Mixer" 0.0 430.0 1280.0 370.0 8)
        (gui-row-dynamic 20.0 8)
        ;; Track labels
        (let loop ((i 0))
          (when (< i 8)
            (gui-label (string-append "Trk " (number->string (+ i 1))))
            (loop (+ i 1))))

        ;; Volume sliders
        (gui-row-dynamic 150.0 8)
        (let loop ((i 0) (vols track-vol))
          (when (and (< i 8) (pair? vols))
            (let ((new-vol (gui-slider ""
                             (exact->inexact (car vols))
                             0.0 1.0 0.01)))
              (set-car! vols new-vol))
            (loop (+ i 1) (cdr vols))))

        ;; Meters
        (gui-row-dynamic 20.0 8)
        (let loop ((i 0))
          (when (< i 8)
            (gui-meter "" 0.0)  ;; TODO: actual levels
            (loop (+ i 1))))

        (gui-end-panel))

      ;; Return updated state
      (alist-update 'bpm bpm
        (alist-update 'playing? playing?
          (alist-update 'waveform waveform
            (alist-update 'cutoff cutoff
              (alist-update 'resonance resonance
                state)))))))

  ;; Helper
  (define (alist-ref key alist)
    (let ((pair (assq key alist)))
      (if pair (cdr pair) #f)))

  (define (alist-update key value alist)
    (cons (cons key value)
          (filter (lambda (p) (not (eq? (car p) key))) alist)))

  (define (filter pred lst)
    (cond ((null? lst) '())
          ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
          (else (filter pred (cdr lst)))))

) ;; end module

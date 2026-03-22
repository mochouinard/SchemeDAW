;;; audio-dac.scm - Main entry point for Audio DAC electronic music DAW
;;;
;;; Phase 1: Starts the audio engine, plays a test tone to verify
;;; the full pipeline works (Scheme -> ring buffer -> C audio callback -> SDL2).

(import scheme
        (chicken base)
        (chicken process-context)
        (chicken format))

;; Include the C implementation directly for now (single-file compilation)
(foreign-declare "
#include \"ringbuffer.c\"
#include \"dsp-core.c\"
#include \"audio-backend.c\"
")

;; Re-declare the FFI bindings inline (avoid module system complexity for Phase 1)
(define backend-create
  (foreign-lambda c-pointer "backend_create" int int))

(define backend-start
  (foreign-lambda int "backend_start" c-pointer))

(define backend-stop
  (foreign-lambda void "backend_stop" c-pointer))

(define backend-destroy
  (foreign-lambda void "backend_destroy" c-pointer))

(define backend-send-command
  (foreign-lambda int "backend_send_command"
    c-pointer unsigned-byte unsigned-byte
    unsigned-byte unsigned-byte float))

;; Command constants
(define CMD_NOTE_ON       #x01)
(define CMD_NOTE_OFF      #x02)
(define CMD_SET_WAVEFORM  #x0C)
(define CMD_SET_VOLUME    #x04)

;; Waveform constants
(define WAVE_SINE     0)
(define WAVE_SAW      1)
(define WAVE_SQUARE   2)
(define WAVE_TRIANGLE 3)

(define (send! backend type track p1 p2 fval)
  (backend-send-command backend type track p1 p2 fval))

;; ---- Main ----

(define (main)
  (format #t "Audio DAC - Electronic Music DAW~%")
  (format #t "Phase 1: Audio Engine Test~%")
  (format #t "~%")

  ;; Create audio backend: 44100 Hz, 512 sample buffer
  (let ((backend (backend-create 44100 512)))
    (unless backend
      (format (current-error-port) "Error: failed to create audio backend~%")
      (exit 1))

    ;; Start audio
    (let ((result (backend-start backend)))
      (when (< result 0)
        (format (current-error-port) "Error: failed to start audio~%")
        (backend-destroy backend)
        (exit 1)))

    (format #t "Audio engine running at 44100 Hz~%")
    (format #t "~%")
    (format #t "Playing test sequence...~%")
    (format #t "Press Ctrl+C to exit~%")
    (format #t "~%")

    ;; Set track 0 to saw wave (nice for hearing the filter)
    (send! backend CMD_SET_WAVEFORM 0 WAVE_SAW 0 0.0)

    ;; Play a simple sequence: C minor arpeggio
    ;; MIDI notes: C3=48, Eb3=51, G3=55, C4=60
    (let loop ((notes '(48 51 55 60 55 51))
               (count 0))
      (when (< count 48) ;; play 8 loops of the pattern
        (let ((note (car notes))
              (rest (if (null? (cdr notes))
                        '(48 51 55 60 55 51)
                        (cdr notes))))

          ;; Note on with velocity 100
          (send! backend CMD_NOTE_ON 0 note 100 0.0)
          (format #t "  Note ON:  ~A (MIDI ~A)~%"
                  (note-name note) note)

          ;; Hold for 200ms
          (thread-sleep! 0.2)

          ;; Note off
          (send! backend CMD_NOTE_OFF 0 note 0 0.0)

          ;; Gap between notes
          (thread-sleep! 0.05)

          (loop rest (+ count 1)))))

    ;; Let the last note's release tail finish
    (format #t "~%Sequence complete. Waiting for release...~%")
    (thread-sleep! 1.0)

    ;; Clean up
    (backend-stop backend)
    (backend-destroy backend)
    (format #t "Done.~%")))

;; Helper: convert MIDI note number to name
(define (note-name midi-note)
  (let* ((names #("C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))
         (name (vector-ref names (modulo midi-note 12)))
         (octave (- (quotient midi-note 12) 1)))
    (string-append name (number->string octave))))

;; Helper for thread-sleep (uses SRFI-18 if available, otherwise busy-wait with SDL delay)
(foreign-declare "
#include <SDL2/SDL.h>
void c_delay_ms(int ms) { SDL_Delay(ms); }
")

(define c-delay-ms (foreign-lambda void "c_delay_ms" int))

(define (thread-sleep! seconds)
  (c-delay-ms (inexact->exact (round (* seconds 1000.0)))))

;; Run
(main)

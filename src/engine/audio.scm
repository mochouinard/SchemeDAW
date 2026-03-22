;;; audio.scm - FFI bindings to the C audio backend
;;;
;;; This module provides the Scheme interface to the SDL2-based audio engine.
;;; All audio processing happens in C on the SDL audio thread. This module
;;; sends commands via a lock-free ring buffer to control the engine from
;;; the Scheme thread safely.

(module audio-dac.engine.audio
  (;; Backend lifecycle
   backend-create
   backend-start
   backend-stop
   backend-destroy
   ;; Command sending
   backend-send!
   ;; Convenience wrappers
   note-on!
   note-off!
   all-notes-off!
   set-track-volume!
   set-track-pan!
   set-track-mute!
   set-track-solo!
   set-track-waveform!
   set-filter-cutoff!
   set-filter-resonance!
   set-filter-type!
   set-amp-envelope!
   set-filter-envelope!
   set-master-volume!
   ;; Command type constants
   CMD_NOTE_ON
   CMD_NOTE_OFF
   CMD_SET_PARAM
   CMD_SET_VOLUME
   CMD_SET_PAN
   CMD_SET_BPM
   CMD_LOAD_SAMPLE
   CMD_FX_PARAM
   CMD_MUTE_TRACK
   CMD_SOLO_TRACK
   CMD_ALL_NOTES_OFF
   CMD_SET_WAVEFORM
   CMD_SET_FILTER
   CMD_SET_ENVELOPE
   ;; Waveform constants
   WAVE_SINE
   WAVE_SAW
   WAVE_SQUARE
   WAVE_TRIANGLE
   WAVE_NOISE)

  (import scheme
          (chicken base)
          (chicken foreign)
          (chicken memory))

  ;; Include C headers
  (foreign-declare "
#include \"audio-backend.h\"
#include \"ringbuffer.h\"
#include \"dsp-core.h\"
")

  ;; ---- Command type constants ----
  (define CMD_NOTE_ON       #x01)
  (define CMD_NOTE_OFF      #x02)
  (define CMD_SET_PARAM     #x03)
  (define CMD_SET_VOLUME    #x04)
  (define CMD_SET_PAN       #x05)
  (define CMD_SET_BPM       #x06)
  (define CMD_LOAD_SAMPLE   #x07)
  (define CMD_FX_PARAM      #x08)
  (define CMD_MUTE_TRACK    #x09)
  (define CMD_SOLO_TRACK    #x0A)
  (define CMD_ALL_NOTES_OFF #x0B)
  (define CMD_SET_WAVEFORM  #x0C)
  (define CMD_SET_FILTER    #x0D)
  (define CMD_SET_ENVELOPE  #x0E)

  ;; ---- Waveform constants ----
  (define WAVE_SINE     0)
  (define WAVE_SAW      1)
  (define WAVE_SQUARE   2)
  (define WAVE_TRIANGLE 3)
  (define WAVE_NOISE    4)

  ;; ---- FFI bindings ----

  (define backend-create
    (foreign-lambda c-pointer "backend_create" int int))

  (define backend-start
    (foreign-lambda int "backend_start" c-pointer))

  (define backend-stop
    (foreign-lambda void "backend_stop" c-pointer))

  (define backend-destroy
    (foreign-lambda void "backend_destroy" c-pointer))

  (define backend-send-raw
    (foreign-lambda int "backend_send_command"
      c-pointer unsigned-byte unsigned-byte
      unsigned-byte unsigned-byte float))

  ;; Wrapper with error reporting
  (define (backend-send! backend type track p1 p2 fval)
    (let ((result (backend-send-raw backend type track p1 p2 fval)))
      (when (= result 0)
        (fprintf (current-error-port)
                 "Warning: ring buffer full, command dropped~%"))
      result))

  ;; ---- Convenience functions ----

  (define (note-on! backend track note velocity)
    (backend-send! backend CMD_NOTE_ON track note velocity 0.0))

  (define (note-off! backend track note)
    (backend-send! backend CMD_NOTE_OFF track note 0 0.0))

  (define (all-notes-off! backend track)
    (backend-send! backend CMD_ALL_NOTES_OFF track 0 0 0.0))

  (define (set-track-volume! backend track volume)
    (backend-send! backend CMD_SET_VOLUME track 0 0 volume))

  (define (set-track-pan! backend track pan)
    (backend-send! backend CMD_SET_PAN track 0 0 pan))

  (define (set-track-mute! backend track muted?)
    (backend-send! backend CMD_MUTE_TRACK track (if muted? 1 0) 0 0.0))

  (define (set-track-solo! backend track soloed?)
    (backend-send! backend CMD_SOLO_TRACK track (if soloed? 1 0) 0 0.0))

  (define (set-track-waveform! backend track waveform)
    (backend-send! backend CMD_SET_WAVEFORM track waveform 0 0.0))

  (define (set-filter-cutoff! backend track cutoff)
    (backend-send! backend CMD_SET_FILTER track 0 0 cutoff))

  (define (set-filter-resonance! backend track resonance)
    (backend-send! backend CMD_SET_FILTER track 1 0 resonance))

  (define (set-filter-type! backend track filter-type)
    (backend-send! backend CMD_SET_FILTER track 2 filter-type 0.0))

  (define (set-amp-envelope! backend track attack decay sustain release)
    (backend-send! backend CMD_SET_ENVELOPE track 0 0 attack)
    (backend-send! backend CMD_SET_ENVELOPE track 0 1 decay)
    (backend-send! backend CMD_SET_ENVELOPE track 0 2 sustain)
    (backend-send! backend CMD_SET_ENVELOPE track 0 3 release))

  (define (set-filter-envelope! backend track attack decay sustain release)
    (backend-send! backend CMD_SET_ENVELOPE track 1 0 attack)
    (backend-send! backend CMD_SET_ENVELOPE track 1 1 decay)
    (backend-send! backend CMD_SET_ENVELOPE track 1 2 sustain)
    (backend-send! backend CMD_SET_ENVELOPE track 1 3 release))

  (define (set-master-volume! backend volume)
    ;; Master volume uses track 255 as sentinel
    (backend-send! backend CMD_SET_VOLUME 255 0 0 volume))

) ;; end module

;;; api.scm - User-facing live coding API
;;;
;;; Provides short, ergonomic functions for live performance.
;;; These are designed to be typed quickly in the REPL during a
;;; live coding session.
;;;
;;; Examples:
;;;   (bpm! 140)                    ;; Set tempo to 140 BPM
;;;   (note! 0 60 100)              ;; Play C4 on track 0
;;;   (wave! 0 'saw)                ;; Set track 0 to saw wave
;;;   (cutoff! 0 2000)              ;; Set filter cutoff
;;;   (vol! 0 0.7)                  ;; Set track volume
;;;   (mute! 0)                     ;; Toggle mute on track 0
;;;   (solo! 0)                     ;; Toggle solo on track 0

(module audio-dac.live.api
  (;; Transport
   play! stop! bpm!
   ;; Notes
   note! note-off! silence!
   ;; Synth control
   wave! cutoff! reso! env!
   ;; Mixer
   vol! pan! mute! solo!
   ;; Pattern shorthand
   pat!
   ;; Setup
   live-setup!)

  (import scheme
          (chicken base)
          (chicken format))

  ;; The backend pointer and send function are set during initialization
  (define *backend* #f)
  (define *send-fn* #f)
  (define *playing* #f)
  (define *bpm* 120.0)
  (define *mute-state* (make-vector 16 #f))
  (define *solo-state* (make-vector 16 #f))

  ;; Command constants (matching ringbuffer.h)
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

  ;; Initialize the live API with a backend and send function
  ;; send-fn: (lambda (type track p1 p2 fval) ...)
  (define (live-setup! backend send-fn)
    (set! *backend* backend)
    (set! *send-fn* send-fn)
    (format #t "Live API ready!~%")
    (format #t "  (bpm! N)          - set tempo~%")
    (format #t "  (note! trk note vel) - play note~%")
    (format #t "  (wave! trk 'saw)  - set waveform~%")
    (format #t "  (cutoff! trk Hz)  - filter cutoff~%")
    (format #t "  (vol! trk 0.0-1.0) - track volume~%"))

  (define (send! type track p1 p2 fval)
    (when *send-fn*
      (*send-fn* *backend* type track p1 p2 fval)))

  ;; ---- Transport ----

  (define (play!)
    (set! *playing* #t)
    'playing)

  (define (stop!)
    (set! *playing* #f)
    ;; All notes off on all tracks
    (do ((i 0 (+ i 1))) ((>= i 16))
      (send! CMD_ALL_NOTES_OFF i 0 0 0.0))
    'stopped)

  (define (bpm! n)
    (set! *bpm* (exact->inexact n))
    *bpm*)

  ;; ---- Notes ----

  ;; Play a note. Can use MIDI number or note name symbol.
  ;; (note! 0 60 100)     ;; track 0, C4, velocity 100
  ;; (note! 0 'C4 100)    ;; same thing
  (define (note! track note #!optional (velocity 100))
    (let ((midi-note (if (symbol? note)
                         (note-symbol->midi note)
                         note)))
      (send! CMD_NOTE_ON track midi-note velocity 0.0)
      midi-note))

  (define (note-off! track note)
    (let ((midi-note (if (symbol? note)
                         (note-symbol->midi note)
                         note)))
      (send! CMD_NOTE_OFF track midi-note 0 0.0)))

  ;; All notes off on a track
  (define (silence! #!optional (track 'all))
    (if (eq? track 'all)
        (do ((i 0 (+ i 1))) ((>= i 16))
          (send! CMD_ALL_NOTES_OFF i 0 0 0.0))
        (send! CMD_ALL_NOTES_OFF track 0 0 0.0))
    'silent)

  ;; ---- Synth Control ----

  ;; Set waveform: (wave! 0 'saw) or (wave! 0 1)
  (define (wave! track waveform)
    (let ((wf (if (symbol? waveform)
                  (case waveform
                    ((sine sin) 0) ((saw sawtooth) 1)
                    ((square sqr) 2) ((triangle tri) 3)
                    ((noise nse) 4) (else 1))
                  waveform)))
      (send! CMD_SET_WAVEFORM track wf 0 0.0)
      wf))

  ;; Set filter cutoff
  (define (cutoff! track hz)
    (send! CMD_SET_FILTER track 0 0 (exact->inexact hz))
    hz)

  ;; Set filter resonance
  (define (reso! track amount)
    (send! CMD_SET_FILTER track 1 0 (exact->inexact amount))
    amount)

  ;; Set amp envelope: (env! 0 0.01 0.2 0.7 0.3)
  (define (env! track attack decay sustain release)
    (send! CMD_SET_ENVELOPE track 0 0 (exact->inexact attack))
    (send! CMD_SET_ENVELOPE track 0 1 (exact->inexact decay))
    (send! CMD_SET_ENVELOPE track 0 2 (exact->inexact sustain))
    (send! CMD_SET_ENVELOPE track 0 3 (exact->inexact release))
    'ok)

  ;; ---- Mixer ----

  (define (vol! track volume)
    (send! CMD_SET_VOLUME track 0 0 (exact->inexact volume))
    volume)

  (define (pan! track position)
    (send! CMD_SET_PAN track 0 0 (exact->inexact position))
    position)

  (define (mute! track)
    (let ((current (vector-ref *mute-state* track)))
      (vector-set! *mute-state* track (not current))
      (send! CMD_MUTE_TRACK track (if (not current) 1 0) 0 0.0)
      (not current)))

  (define (solo! track)
    (let ((current (vector-ref *solo-state* track)))
      (vector-set! *solo-state* track (not current))
      (send! CMD_SOLO_TRACK track (if (not current) 1 0) 0 0.0)
      (not current)))

  ;; ---- Pattern Shorthand ----

  ;; Quick pattern definition
  ;; (pat! '(C4 . C4 . E4 . G4 .)) => list of MIDI notes and rests
  (define (pat! pattern-list)
    (map (lambda (item)
           (cond
            ((eq? item '.) #f)  ;; rest
            ((symbol? item) (note-symbol->midi item))
            ((number? item) item)
            (else #f)))
         pattern-list))

  ;; ---- Note Name Parsing ----

  ;; Convert symbol like 'C4, 'D#3, 'Bb2 to MIDI note
  (define (note-symbol->midi sym)
    (let* ((str (symbol->string sym))
           (len (string-length str))
           (note-char (string-ref str 0))
           (base (case note-char
                   ((#\C) 0) ((#\D) 2) ((#\E) 4) ((#\F) 5)
                   ((#\G) 7) ((#\A) 9) ((#\B) 11)
                   (else 0)))
           (has-accidental (and (> len 1)
                                (or (char=? (string-ref str 1) #\#)
                                    (char=? (string-ref str 1) #\b))))
           (offset (if has-accidental
                       (if (char=? (string-ref str 1) #\#) 1 -1)
                       0))
           (octave-start (if has-accidental 2 1))
           (octave (string->number (substring str octave-start))))
      (+ base offset (* (+ octave 1) 12))))

) ;; end module

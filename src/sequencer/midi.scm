;;; midi.scm - MIDI utilities and note/CC definitions
;;;
;;; Provides MIDI constants, note number helpers, and CC definitions
;;; commonly used in electronic music production.

(module audio-dac.sequencer.midi
  (;; Note helpers
   midi-note
   note-name->midi
   midi->note-name
   midi->freq
   ;; Common drum map (General MIDI)
   KICK SNARE CLAP CLOSED-HH OPEN-HH
   RIM LOW-TOM MID-TOM HIGH-TOM CRASH RIDE
   ;; CC numbers
   CC_MOD_WHEEL CC_BREATH CC_VOLUME CC_PAN
   CC_EXPRESSION CC_SUSTAIN CC_FILTER_CUTOFF
   ;; Scale helpers
   scale-notes
   SCALE_MAJOR SCALE_MINOR SCALE_DORIAN SCALE_PHRYGIAN
   SCALE_MIXOLYDIAN SCALE_PENTATONIC_MAJOR SCALE_PENTATONIC_MINOR
   SCALE_BLUES SCALE_CHROMATIC)

  (import scheme (chicken base))

  ;; ---- Note name conversion ----

  (define note-names-vec #("C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))

  (define (midi->note-name midi-note)
    (let* ((name (vector-ref note-names-vec (modulo midi-note 12)))
           (octave (- (quotient midi-note 12) 1)))
      (string-append name (number->string octave))))

  (define (midi->freq note)
    (* 440.0 (expt 2.0 (/ (- note 69) 12.0))))

  ;; Parse note name like "C4", "D#3", "Bb2"
  (define (note-name->midi name-str)
    (let* ((len (string-length name-str))
           (note-char (string-ref name-str 0))
           (base (case note-char
                   ((#\C) 0) ((#\D) 2) ((#\E) 4) ((#\F) 5)
                   ((#\G) 7) ((#\A) 9) ((#\B) 11)
                   (else 0)))
           (has-accidental (and (> len 1)
                                (or (char=? (string-ref name-str 1) #\#)
                                    (char=? (string-ref name-str 1) #\b))))
           (offset (if has-accidental
                       (if (char=? (string-ref name-str 1) #\#) 1 -1)
                       0))
           (octave-start (if has-accidental 2 1))
           (octave (string->number (substring name-str octave-start))))
      (+ base offset (* (+ octave 1) 12))))

  ;; Shorthand: (midi-note 'C 4) => 60
  (define (midi-note name octave)
    (let ((base (case name
                  ((C) 0) ((C# Db) 1) ((D) 2) ((D# Eb) 3) ((E) 4) ((F) 5)
                  ((F# Gb) 6) ((G) 7) ((G# Ab) 8) ((A) 9) ((A# Bb) 10) ((B) 11)
                  (else 0))))
      (+ base (* (+ octave 1) 12))))

  ;; ---- General MIDI Drum Map (channel 10) ----

  (define KICK      36)
  (define SNARE     38)
  (define CLAP      39)
  (define CLOSED-HH 42)
  (define OPEN-HH   46)
  (define RIM       37)
  (define LOW-TOM   45)
  (define MID-TOM   47)
  (define HIGH-TOM  50)
  (define CRASH     49)
  (define RIDE      51)

  ;; ---- Common CC Numbers ----

  (define CC_MOD_WHEEL     1)
  (define CC_BREATH        2)
  (define CC_VOLUME        7)
  (define CC_PAN          10)
  (define CC_EXPRESSION   11)
  (define CC_SUSTAIN      64)
  (define CC_FILTER_CUTOFF 74)

  ;; ---- Scale Definitions (intervals from root) ----

  (define SCALE_MAJOR             '(0 2 4 5 7 9 11))
  (define SCALE_MINOR             '(0 2 3 5 7 8 10))
  (define SCALE_DORIAN            '(0 2 3 5 7 9 10))
  (define SCALE_PHRYGIAN          '(0 1 3 5 7 8 10))
  (define SCALE_MIXOLYDIAN        '(0 2 4 5 7 9 10))
  (define SCALE_PENTATONIC_MAJOR  '(0 2 4 7 9))
  (define SCALE_PENTATONIC_MINOR  '(0 3 5 7 10))
  (define SCALE_BLUES             '(0 3 5 6 7 10))
  (define SCALE_CHROMATIC         '(0 1 2 3 4 5 6 7 8 9 10 11))

  ;; Generate MIDI notes for a scale across octaves
  ;; (scale-notes 60 SCALE_MINOR 2) => notes for C minor across 2 octaves
  (define (scale-notes root scale num-octaves)
    (let loop ((oct 0) (result '()))
      (if (>= oct num-octaves)
          (reverse result)
          (loop (+ oct 1)
                (append (reverse
                         (map (lambda (interval)
                                (+ root (* oct 12) interval))
                              scale))
                        result)))))

) ;; end module

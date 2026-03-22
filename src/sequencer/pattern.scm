;;; pattern.scm - Pattern data structures for step sequencing
;;;
;;; A pattern is a fixed-length sequence of steps. Each step can contain
;;; multiple note events (for chords or simultaneous drum hits).
;;; Patterns are the core musical data structure of the DAW.

(module audio-dac.sequencer.pattern
  (make-pattern
   pattern-name pattern-name-set!
   pattern-length
   pattern-steps pattern-steps-set!
   pattern-swing pattern-swing-set!
   ;; Step events
   make-step-event
   step-event-note step-event-velocity
   step-event-duration step-event-probability
   ;; Pattern manipulation
   pattern-set-step!
   pattern-get-step
   pattern-clear!
   pattern-clear-step!
   ;; Convenience constructors
   pattern-from-notes
   pattern-from-grid
   ;; Note name helpers
   note-name->midi
   midi->note-name)

  (import scheme
          (chicken base)
          (chicken string)
          (chicken format))

  ;; ---- Step Event ----

  (define-record-type step-event
    (make-step-event note velocity duration probability)
    step-event?
    (note        step-event-note)         ;; MIDI note 0-127
    (velocity    step-event-velocity)     ;; 0-127
    (duration    step-event-duration)     ;; in steps (1.0 = one step)
    (probability step-event-probability)) ;; 0.0-1.0

  ;; ---- Pattern ----

  (define-record-type pattern
    (make-pattern* name length steps swing)
    pattern?
    (name   pattern-name pattern-name-set!)
    (length pattern-length)
    (steps  pattern-steps pattern-steps-set!)
    (swing  pattern-swing pattern-swing-set!))

  ;; Create a new empty pattern
  (define (make-pattern #!key (name "Pattern") (length 16) (swing 0.0))
    (make-pattern* name length (make-vector length '()) swing))

  ;; Set events at a step (list of step-events)
  (define (pattern-set-step! pat step-idx events)
    (when (and (>= step-idx 0) (< step-idx (pattern-length pat)))
      (vector-set! (pattern-steps pat) step-idx events)))

  ;; Get events at a step
  (define (pattern-get-step pat step-idx)
    (if (and (>= step-idx 0) (< step-idx (pattern-length pat)))
        (vector-ref (pattern-steps pat) step-idx)
        '()))

  ;; Clear all steps
  (define (pattern-clear! pat)
    (let ((steps (pattern-steps pat)))
      (do ((i 0 (+ i 1)))
          ((>= i (pattern-length pat)))
        (vector-set! steps i '()))))

  ;; Clear a single step
  (define (pattern-clear-step! pat step-idx)
    (pattern-set-step! pat step-idx '()))

  ;; ---- Convenience Constructors ----

  ;; Create pattern from a list of note values (or #f for rest)
  ;; e.g., (pattern-from-notes "Bass" '(36 #f 36 #f 38 #f 36 #f))
  (define (pattern-from-notes name notes #!key (velocity 100) (duration 1.0))
    (let* ((len (length notes))
           (pat (make-pattern name: name length: len)))
      (do ((i 0 (+ i 1))
           (ns notes (cdr ns)))
          ((null? ns))
        (let ((n (car ns)))
          (when n
            (pattern-set-step! pat i
              (list (make-step-event n velocity duration 1.0))))))
      pat))

  ;; Create pattern from a grid (list of lists)
  ;; Each inner list is a step containing (note velocity) pairs or just note numbers
  ;; e.g., (pattern-from-grid "Drums" '((36 42) () (38) () (36) () (38 42) ()))
  (define (pattern-from-grid name grid #!key (default-velocity 100) (duration 1.0))
    (let* ((len (length grid))
           (pat (make-pattern name: name length: len)))
      (do ((i 0 (+ i 1))
           (gs grid (cdr gs)))
          ((null? gs))
        (let ((step-data (car gs)))
          (when (not (null? step-data))
            (pattern-set-step! pat i
              (map (lambda (item)
                     (if (pair? item)
                         (make-step-event (car item) (cadr item) duration 1.0)
                         (make-step-event item default-velocity duration 1.0)))
                   step-data)))))
      pat))

  ;; ---- Note Name Helpers ----

  (define note-names #("C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))

  (define (midi->note-name midi-note)
    (let* ((name (vector-ref note-names (modulo midi-note 12)))
           (octave (- (quotient midi-note 12) 1)))
      (string-append name (number->string octave))))

  ;; Parse "C4", "D#3", "Bb2" etc. to MIDI note
  (define (note-name->midi name-str)
    (let* ((len (string-length name-str))
           (note-char (string-ref name-str 0))
           (base (case note-char
                   ((#\C) 0) ((#\D) 2) ((#\E) 4) ((#\F) 5)
                   ((#\G) 7) ((#\A) 9) ((#\B) 11)
                   (else 0)))
           (offset (if (and (> len 1)
                            (char=? (string-ref name-str 1) #\#))
                       1
                       (if (and (> len 1)
                                (char=? (string-ref name-str 1) #\b))
                           -1
                           0)))
           (octave-start (if (= offset 0) 1 2))
           (octave (string->number (substring name-str octave-start))))
      (+ base offset (* (+ octave 1) 12))))

) ;; end module

;;; sequencer.scm - Step sequencer engine
;;;
;;; The sequencer holds patterns per track and advances through them
;;; driven by the transport clock. On each step boundary, it sends
;;; note-on/off commands to the audio engine via the ring buffer.

(module audio-dac.sequencer.sequencer
  (make-sequencer
   sequencer-patterns sequencer-patterns-set!
   sequencer-current-step
   sequencer-set-pattern!
   sequencer-get-pattern
   sequencer-clear-track!
   sequencer-tick!
   sequencer-reset!)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken random))

  ;; We reference pattern types by convention (duck-typing) to avoid
  ;; circular module dependencies. Patterns must support:
  ;;   (pattern-length pat) -> int
  ;;   (pattern-get-step pat step-idx) -> list of step-events
  ;;   (step-event-note evt) -> int
  ;;   (step-event-velocity evt) -> int
  ;;   (step-event-duration evt) -> float
  ;;   (step-event-probability evt) -> float

  (define-record-type sequencer
    (make-sequencer* patterns current-step active-notes
                     ticks-per-step send-fn ppqn)
    sequencer?
    (patterns      sequencer-patterns sequencer-patterns-set!)
    (current-step  sequencer-current-step sequencer-current-step-set!)
    (active-notes  sequencer-active-notes sequencer-active-notes-set!)
    (ticks-per-step sequencer-ticks-per-step)
    (send-fn       sequencer-send-fn)
    (ppqn          sequencer-ppqn))

  ;; Create a sequencer
  ;; send-fn: (lambda (cmd-type track param1 param2 fvalue) ...)
  ;; num-tracks: number of track slots
  (define (make-sequencer send-fn #!key (num-tracks 16) (ppqn 96) (subdivision 4))
    (let ((tps (quotient ppqn subdivision)))  ;; ticks per step
      (make-sequencer*
       (make-vector num-tracks #f)  ;; patterns (or #f for empty)
       0                            ;; current step
       (make-vector num-tracks '()) ;; active notes per track
       tps
       send-fn
       ppqn)))

  ;; Assign a pattern to a track
  (define (sequencer-set-pattern! seq track-idx pattern)
    (when (and (>= track-idx 0)
               (< track-idx (vector-length (sequencer-patterns seq))))
      (vector-set! (sequencer-patterns seq) track-idx pattern)))

  ;; Get pattern for a track
  (define (sequencer-get-pattern seq track-idx)
    (if (and (>= track-idx 0)
             (< track-idx (vector-length (sequencer-patterns seq))))
        (vector-ref (sequencer-patterns seq) track-idx)
        #f))

  ;; Clear a track's pattern
  (define (sequencer-clear-track! seq track-idx)
    (sequencer-set-pattern! seq track-idx #f))

  ;; Reset sequencer to beginning
  (define (sequencer-reset! seq)
    (sequencer-current-step-set! seq 0)
    ;; Send note-offs for all active notes
    (let ((active (sequencer-active-notes seq))
          (send (sequencer-send-fn seq)))
      (do ((t 0 (+ t 1)))
          ((>= t (vector-length active)))
        (for-each
         (lambda (note)
           (send #x02 t note 0 0.0))  ;; CMD_NOTE_OFF
         (vector-ref active t))
        (vector-set! active t '()))))

  ;; Called every clock tick. Fires notes on step boundaries.
  (define (sequencer-tick! seq tick)
    (let ((tps (sequencer-ticks-per-step seq)))
      ;; Check if we're on a step boundary
      (when (= (modulo tick tps) 0)
        (let* ((step (quotient tick tps))
               (patterns (sequencer-patterns seq))
               (active (sequencer-active-notes seq))
               (send (sequencer-send-fn seq))
               (num-tracks (vector-length patterns)))

          ;; Update current step display
          (sequencer-current-step-set! seq step)

          ;; Process each track
          (do ((t 0 (+ t 1)))
              ((>= t num-tracks))
            (let ((pat (vector-ref patterns t)))
              (when pat
                ;; Send note-offs for previously active notes on this track
                (for-each
                 (lambda (note)
                   (send #x02 t note 0 0.0))  ;; CMD_NOTE_OFF
                 (vector-ref active t))
                (vector-set! active t '())

                ;; Get events for current step (wrapping around pattern length)
                (let* ((pat-len ((record-accessor (##sys#slot pat 0) 1) pat)) ;; pattern-length
                       (step-idx (modulo step pat-len))
                       (events ((record-accessor (##sys#slot pat 0) 2) pat))) ;; pattern-steps
                  (let ((step-events (vector-ref events step-idx)))
                    (for-each
                     (lambda (evt)
                       ;; Check probability
                       (let ((prob ((record-accessor (##sys#slot evt 0) 3) evt)) ;; probability
                             (note ((record-accessor (##sys#slot evt 0) 0) evt))  ;; note
                             (vel  ((record-accessor (##sys#slot evt 0) 1) evt))) ;; velocity
                         (when (or (>= prob 1.0)
                                   (< (/ (pseudo-random-integer 1000) 1000.0) prob))
                           ;; Send note-on
                           (send #x01 t note vel 0.0)  ;; CMD_NOTE_ON
                           ;; Track active note for later note-off
                           (vector-set! active t
                                        (cons note (vector-ref active t))))))
                     step-events)))))))))))

) ;; end module

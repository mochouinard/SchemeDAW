;;; clock.scm - Transport and clock system
;;;
;;; Provides BPM-driven timing with 96 PPQN (pulses per quarter note)
;;; resolution. The clock runs on a Scheme green thread and fires
;;; callbacks at each tick. Drift compensation ensures accurate timing.

(module audio-dac.engine.clock
  (make-transport
   transport-bpm transport-bpm-set!
   transport-ppqn
   transport-playing? transport-playing?-set!
   transport-tick transport-tick-set!
   transport-tick-callbacks transport-tick-callbacks-set!
   transport-start!
   transport-stop!
   transport-add-tick-callback!
   transport-remove-tick-callback!
   tick->step
   ticks-per-step
   current-beat
   current-bar)

  (import scheme
          (chicken base)
          (chicken time)
          (chicken format))

  ;; Transport state
  (define-record-type transport
    (make-transport* bpm ppqn playing? tick tick-callbacks)
    transport?
    (bpm            transport-bpm transport-bpm-set!)
    (ppqn           transport-ppqn)
    (playing?       transport-playing? transport-playing?-set!)
    (tick           transport-tick transport-tick-set!)
    (tick-callbacks transport-tick-callbacks transport-tick-callbacks-set!))

  (define (make-transport #!key (bpm 120.0) (ppqn 96))
    (make-transport* bpm ppqn #f 0 '()))

  ;; Register a callback to be called every tick
  ;; callback: (lambda (tick-number) ...)
  (define (transport-add-tick-callback! transport callback)
    (transport-tick-callbacks-set!
     transport
     (cons callback (transport-tick-callbacks transport))))

  (define (transport-remove-tick-callback! transport callback)
    (transport-tick-callbacks-set!
     transport
     (filter (lambda (cb) (not (eq? cb callback)))
             (transport-tick-callbacks transport))))

  ;; Convert tick count to step number (assuming 16th note steps)
  ;; At 96 PPQN: 16th note = 6 ticks, 8th note = 12 ticks
  (define (ticks-per-step transport #!key (subdivision 4))
    ;; subdivision: 4 = 16th notes, 2 = 8th notes, 1 = quarter notes
    (quotient (transport-ppqn transport) subdivision))

  (define (tick->step transport tick #!key (subdivision 4))
    (quotient tick (ticks-per-step transport subdivision: subdivision)))

  ;; Current beat (quarter note) number
  (define (current-beat transport)
    (quotient (transport-tick transport) (transport-ppqn transport)))

  ;; Current bar (assuming 4/4 time)
  (define (current-bar transport)
    (quotient (current-beat transport) 4))

  ;; Start the transport - begins ticking
  (define (transport-start! transport delay-fn time-fn)
    (transport-playing?-set! transport #t)
    (transport-tick-set! transport 0)
    (clock-loop transport delay-fn time-fn))

  ;; Stop the transport
  (define (transport-stop! transport)
    (transport-playing?-set! transport #f))

  ;; Internal clock loop with drift compensation
  (define (clock-loop transport delay-fn time-fn)
    (let* ((start-time (time-fn))
           (ppqn (transport-ppqn transport)))
      (let loop ((tick 0)
                 (expected-time start-time))
        (when (transport-playing? transport)
          ;; Calculate tick duration in milliseconds
          (let* ((bpm (transport-bpm transport))
                 (tick-duration-ms (/ 60000.0 (* bpm ppqn)))
                 (next-expected (+ expected-time tick-duration-ms)))

            ;; Fire all tick callbacks
            (for-each
             (lambda (callback)
               (callback tick))
             (transport-tick-callbacks transport))

            ;; Update tick counter
            (transport-tick-set! transport (+ tick 1))

            ;; Drift-compensated sleep
            (let* ((now (time-fn))
                   (sleep-ms (- next-expected now)))
              (when (> sleep-ms 0.5)
                (delay-fn (/ sleep-ms 1000.0)))

              (loop (+ tick 1) next-expected)))))))

) ;; end module

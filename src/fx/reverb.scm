;;; reverb.scm - Reverb effect wrapper

(module audio-dac.fx.reverb
  (make-reverb-params
   reverb-room-size reverb-damping reverb-mix reverb-width)

  (import scheme (chicken base))

  (define-record-type reverb-params
    (make-reverb-params* room-size damping mix width)
    reverb-params?
    (room-size reverb-room-size)
    (damping   reverb-damping)
    (mix       reverb-mix)
    (width     reverb-width))

  (define (make-reverb-params #!key
                              (room-size 0.7)
                              (damping 0.5)
                              (mix 0.3)
                              (width 1.0))
    (make-reverb-params* room-size damping mix width))

) ;; end module

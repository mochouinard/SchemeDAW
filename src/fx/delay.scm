;;; delay.scm - Delay effect wrapper

(module audio-dac.fx.delay
  (make-delay-params
   delay-time delay-feedback delay-mix)

  (import scheme (chicken base))

  (define-record-type delay-params
    (make-delay-params* time feedback mix)
    delay-params?
    (time     delay-time)
    (feedback delay-feedback)
    (mix      delay-mix))

  (define (make-delay-params #!key
                             (time 0.375)
                             (feedback 0.4)
                             (mix 0.3))
    (make-delay-params* time feedback mix))

) ;; end module

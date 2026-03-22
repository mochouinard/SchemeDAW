;;; distortion.scm - Distortion effect wrapper

(module audio-dac.fx.distortion
  (make-distortion-params
   distortion-drive distortion-tone distortion-mix distortion-output-gain)

  (import scheme (chicken base))

  (define-record-type distortion-params
    (make-distortion-params* drive tone mix output-gain)
    distortion-params?
    (drive       distortion-drive)
    (tone        distortion-tone)
    (mix         distortion-mix)
    (output-gain distortion-output-gain))

  (define (make-distortion-params #!key
                                  (drive 5.0)
                                  (tone 8000.0)
                                  (mix 0.5)
                                  (output-gain 0.5))
    (make-distortion-params* drive tone mix output-gain))

) ;; end module

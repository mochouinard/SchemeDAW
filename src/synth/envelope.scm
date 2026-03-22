;;; envelope.scm - ADSR envelope definitions

(module audio-dac.synth.envelope
  (make-env
   env-attack env-decay env-sustain env-release)

  (import scheme (chicken base))

  (define-record-type env
    (make-env* attack decay sustain release)
    env?
    (attack  env-attack)
    (decay   env-decay)
    (sustain env-sustain)
    (release env-release))

  (define (make-env #!key
                    (attack 0.01)
                    (decay 0.2)
                    (sustain 0.7)
                    (release 0.3))
    (make-env* attack decay sustain release))

) ;; end module

;;; wavetable.scm - Wavetable synthesizer template
;;;
;;; Wavetable synthesis reads through pre-computed waveform tables.
;;; Multiple tables can be morphed between. For Phase 2, this provides
;;; the Scheme-level definition; C-side wavetable loading will be extended later.

(module audio-dac.synth.wavetable
  (make-wavetable-synth
   apply-wavetable-synth!
   preset-wt-digital
   preset-wt-pad
   preset-wt-growl)

  (import scheme (chicken base))

  (define (make-wavetable-synth
           #!key
           (base-wave 1)          ;; saw as placeholder until wavetable loading
           (morph-position 0.0)   ;; 0.0-1.0 position between wavetables
           (filter-cutoff 6000.0)
           (filter-resonance 0.3)
           (amp-attack 0.01)
           (amp-decay 0.3)
           (amp-sustain 0.6)
           (amp-release 0.4)
           (filter-attack 0.01)
           (filter-decay 0.4)
           (filter-sustain 0.4)
           (filter-release 0.5)
           (filter-env-amount 3000.0))
    `((synth-type . wavetable)
      (base-wave . ,base-wave)
      (morph-position . ,morph-position)
      (filter-cutoff . ,filter-cutoff)
      (filter-resonance . ,filter-resonance)
      (amp-attack . ,amp-attack)
      (amp-decay . ,amp-decay)
      (amp-sustain . ,amp-sustain)
      (amp-release . ,amp-release)
      (filter-attack . ,filter-attack)
      (filter-decay . ,filter-decay)
      (filter-sustain . ,filter-sustain)
      (filter-release . ,filter-release)
      (filter-env-amount . ,filter-env-amount)))

  ;; Apply wavetable synth - currently uses subtractive-style application
  ;; since C-side wavetable support is pending
  (define (apply-wavetable-synth! send-fn track synth-def)
    (let ((wave   (cdr (assq 'base-wave synth-def)))
          (cutoff (cdr (assq 'filter-cutoff synth-def)))
          (reso   (cdr (assq 'filter-resonance synth-def)))
          (aa     (cdr (assq 'amp-attack synth-def)))
          (ad     (cdr (assq 'amp-decay synth-def)))
          (as     (cdr (assq 'amp-sustain synth-def)))
          (ar     (cdr (assq 'amp-release synth-def)))
          (fa     (cdr (assq 'filter-attack synth-def)))
          (fd     (cdr (assq 'filter-decay synth-def)))
          (fs     (cdr (assq 'filter-sustain synth-def)))
          (fr     (cdr (assq 'filter-release synth-def)))
          (fenv   (cdr (assq 'filter-env-amount synth-def))))
      (send-fn #x0C track wave 0 0.0)
      (send-fn #x0D track 0 0 cutoff)
      (send-fn #x0D track 1 0 reso)
      (send-fn #x0E track 0 0 aa)
      (send-fn #x0E track 0 1 ad)
      (send-fn #x0E track 0 2 as)
      (send-fn #x0E track 0 3 ar)
      (send-fn #x0E track 1 0 fa)
      (send-fn #x0E track 1 1 fd)
      (send-fn #x0E track 1 2 fs)
      (send-fn #x0E track 1 3 fr)
      (send-fn #x03 track 2 0 fenv)))

  ;; ---- Presets ----

  (define (preset-wt-digital)
    (make-wavetable-synth
     base-wave: 2               ;; square
     filter-cutoff: 5000.0
     filter-resonance: 0.4
     filter-env-amount: 4000.0
     amp-attack: 0.005
     amp-decay: 0.2
     amp-sustain: 0.5
     amp-release: 0.3))

  (define (preset-wt-pad)
    (make-wavetable-synth
     base-wave: 1               ;; saw
     filter-cutoff: 3000.0
     filter-resonance: 0.2
     filter-env-amount: 1500.0
     amp-attack: 0.8
     amp-decay: 0.5
     amp-sustain: 0.7
     amp-release: 1.5
     filter-attack: 0.6
     filter-decay: 0.8
     filter-sustain: 0.5
     filter-release: 1.5))

  (define (preset-wt-growl)
    (make-wavetable-synth
     base-wave: 1               ;; saw
     filter-cutoff: 1000.0
     filter-resonance: 0.6
     filter-env-amount: 5000.0
     amp-attack: 0.01
     amp-decay: 0.15
     amp-sustain: 0.6
     amp-release: 0.2
     filter-attack: 0.01
     filter-decay: 0.1
     filter-sustain: 0.3
     filter-release: 0.15))

) ;; end module

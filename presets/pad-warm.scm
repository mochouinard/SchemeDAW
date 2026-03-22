;;; pad-warm.scm - Warm evolving pad
;;; Slow attack saw wave with gentle filter sweep
(make-subtractive-synth
 osc1-wave: 1              ;; saw
 filter-cutoff: 2000.0
 filter-resonance: 0.2
 filter-env-amount: 1000.0
 amp-attack: 0.5
 amp-decay: 0.3
 amp-sustain: 0.8
 amp-release: 1.0
 filter-attack: 0.4
 filter-decay: 0.5
 filter-sustain: 0.5
 filter-release: 1.0)

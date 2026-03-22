;;; kick-808.scm - TR-808 style kick drum
;;; Sine wave with very fast pitch envelope and short decay
(make-subtractive-synth
 osc1-wave: 0              ;; sine
 filter-cutoff: 20000.0    ;; filter wide open
 filter-resonance: 0.0
 filter-env-amount: 0.0
 amp-attack: 0.001
 amp-decay: 0.4
 amp-sustain: 0.0
 amp-release: 0.2
 filter-attack: 0.001
 filter-decay: 0.05
 filter-sustain: 0.0
 filter-release: 0.05)

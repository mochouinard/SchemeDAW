;;; bass-acid.scm - Classic acid bass preset
;;; Resonant saw wave with short decay and heavy filter envelope
(make-subtractive-synth
 osc1-wave: 1              ;; saw
 filter-cutoff: 800.0
 filter-resonance: 0.7
 filter-env-amount: 6000.0
 amp-attack: 0.005
 amp-decay: 0.15
 amp-sustain: 0.0
 amp-release: 0.1
 filter-attack: 0.005
 filter-decay: 0.2
 filter-sustain: 0.0
 filter-release: 0.15)

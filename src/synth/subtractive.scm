;;; subtractive.scm - Subtractive synthesizer template
;;;
;;; A subtractive synth: oscillator(s) -> filter -> amp envelope.
;;; This module creates synth parameter sets that configure a track
;;; in the C engine for subtractive synthesis.

(module audio-dac.synth.subtractive
  (make-subtractive-synth
   apply-subtractive-synth!
   ;; Preset constructors
   preset-acid-bass
   preset-warm-pad
   preset-pluck
   preset-lead)

  (import scheme
          (chicken base)
          (chicken format))

  ;; We import the engine audio module inline to avoid circular deps
  ;; at compile time. In practice, the caller passes the backend pointer.

  ;; Synth definition as an alist
  (define (make-subtractive-synth
           #!key
           (osc1-wave 1)        ;; saw
           (osc1-detune 0.0)
           (filter-type 0)      ;; LP
           (filter-cutoff 4000.0)
           (filter-resonance 0.3)
           (amp-attack 0.01)
           (amp-decay 0.2)
           (amp-sustain 0.7)
           (amp-release 0.3)
           (filter-attack 0.01)
           (filter-decay 0.3)
           (filter-sustain 0.3)
           (filter-release 0.5)
           (filter-env-amount 2000.0))
    `((synth-type . subtractive)
      (osc1-wave . ,osc1-wave)
      (osc1-detune . ,osc1-detune)
      (filter-type . ,filter-type)
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

  ;; Apply synth params to a track via the backend send function
  ;; send-fn: (lambda (type track p1 p2 fval) ...)
  (define (apply-subtractive-synth! send-fn track synth-def)
    (for-each
     (lambda (pair)
       (let ((key (car pair))
             (val (cdr pair)))
         (case key
           ((osc1-wave)
            (send-fn #x0C track val 0 0.0))       ;; CMD_SET_WAVEFORM
           ((filter-cutoff)
            (send-fn #x0D track 0 0 val))          ;; CMD_SET_FILTER cutoff
           ((filter-resonance)
            (send-fn #x0D track 1 0 val))          ;; CMD_SET_FILTER resonance
           ((filter-type)
            (send-fn #x0D track 2 val 0.0))        ;; CMD_SET_FILTER type
           ((amp-attack)
            (send-fn #x0E track 0 0 val))          ;; CMD_SET_ENVELOPE amp A
           ((amp-decay)
            (send-fn #x0E track 0 1 val))          ;; CMD_SET_ENVELOPE amp D
           ((amp-sustain)
            (send-fn #x0E track 0 2 val))          ;; CMD_SET_ENVELOPE amp S
           ((amp-release)
            (send-fn #x0E track 0 3 val))          ;; CMD_SET_ENVELOPE amp R
           ((filter-attack)
            (send-fn #x0E track 1 0 val))          ;; CMD_SET_ENVELOPE filt A
           ((filter-decay)
            (send-fn #x0E track 1 1 val))          ;; CMD_SET_ENVELOPE filt D
           ((filter-sustain)
            (send-fn #x0E track 1 2 val))          ;; CMD_SET_ENVELOPE filt S
           ((filter-release)
            (send-fn #x0E track 1 3 val))          ;; CMD_SET_ENVELOPE filt R
           ((filter-env-amount)
            (send-fn #x03 track 2 0 val))          ;; CMD_SET_PARAM index 2
           )))
     synth-def))

  ;; ---- Presets ----

  (define (preset-acid-bass)
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
     filter-release: 0.15))

  (define (preset-warm-pad)
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
     filter-release: 1.0))

  (define (preset-pluck)
    (make-subtractive-synth
     osc1-wave: 2              ;; square
     filter-cutoff: 5000.0
     filter-resonance: 0.4
     filter-env-amount: 4000.0
     amp-attack: 0.001
     amp-decay: 0.3
     amp-sustain: 0.0
     amp-release: 0.2
     filter-attack: 0.001
     filter-decay: 0.3
     filter-sustain: 0.0
     filter-release: 0.2))

  (define (preset-lead)
    (make-subtractive-synth
     osc1-wave: 1              ;; saw
     filter-cutoff: 3000.0
     filter-resonance: 0.5
     filter-env-amount: 3000.0
     amp-attack: 0.01
     amp-decay: 0.1
     amp-sustain: 0.8
     amp-release: 0.2
     filter-attack: 0.01
     filter-decay: 0.2
     filter-sustain: 0.5
     filter-release: 0.3))

) ;; end module

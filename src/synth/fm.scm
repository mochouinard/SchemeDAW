;;; fm.scm - FM (Frequency Modulation) synthesizer template
;;;
;;; FM synthesis: a modulator oscillator modulates the frequency of a
;;; carrier oscillator. The C engine handles FM via a dedicated voice
;;; mode where osc[0] is the carrier and osc[1] is the modulator.

(module audio-dac.synth.fm
  (make-fm-synth
   apply-fm-synth!
   preset-fm-bell
   preset-fm-bass
   preset-fm-electric-piano
   preset-fm-metallic)

  (import scheme (chicken base))

  (define (make-fm-synth
           #!key
           (carrier-wave 0)       ;; sine
           (mod-ratio 2.0)        ;; modulator freq ratio to carrier
           (mod-index 3.0)        ;; modulation depth
           (filter-cutoff 8000.0)
           (filter-resonance 0.1)
           (amp-attack 0.01)
           (amp-decay 0.5)
           (amp-sustain 0.3)
           (amp-release 0.5)
           (mod-attack 0.01)
           (mod-decay 0.8)
           (mod-sustain 0.2)
           (mod-release 0.5))
    `((synth-type . fm)
      (carrier-wave . ,carrier-wave)
      (mod-ratio . ,mod-ratio)
      (mod-index . ,mod-index)
      (filter-cutoff . ,filter-cutoff)
      (filter-resonance . ,filter-resonance)
      (amp-attack . ,amp-attack)
      (amp-decay . ,amp-decay)
      (amp-sustain . ,amp-sustain)
      (amp-release . ,amp-release)
      (mod-attack . ,mod-attack)
      (mod-decay . ,mod-decay)
      (mod-sustain . ,mod-sustain)
      (mod-release . ,mod-release)))

  ;; Apply FM synth to a track. For Phase 2, FM is approximated by setting
  ;; the track to sine wave with specific envelope shapes that create
  ;; FM-like timbres. Full FM with modulator will be added when we extend
  ;; the C engine's voice model.
  (define (apply-fm-synth! send-fn track synth-def)
    ;; Set to sine wave (carrier)
    (send-fn #x0C track 0 0 0.0)  ;; CMD_SET_WAVEFORM = sine
    ;; Apply filter settings
    (let ((cutoff (cdr (assq 'filter-cutoff synth-def)))
          (reso   (cdr (assq 'filter-resonance synth-def))))
      (send-fn #x0D track 0 0 cutoff)
      (send-fn #x0D track 1 0 reso))
    ;; Apply amp envelope
    (let ((a (cdr (assq 'amp-attack synth-def)))
          (d (cdr (assq 'amp-decay synth-def)))
          (s (cdr (assq 'amp-sustain synth-def)))
          (r (cdr (assq 'amp-release synth-def))))
      (send-fn #x0E track 0 0 a)
      (send-fn #x0E track 0 1 d)
      (send-fn #x0E track 0 2 s)
      (send-fn #x0E track 0 3 r)))

  ;; ---- Presets ----

  (define (preset-fm-bell)
    (make-fm-synth
     mod-ratio: 3.5
     mod-index: 5.0
     amp-attack: 0.001
     amp-decay: 2.0
     amp-sustain: 0.0
     amp-release: 2.0
     filter-cutoff: 12000.0))

  (define (preset-fm-bass)
    (make-fm-synth
     mod-ratio: 1.0
     mod-index: 2.0
     amp-attack: 0.005
     amp-decay: 0.3
     amp-sustain: 0.4
     amp-release: 0.2
     filter-cutoff: 3000.0
     filter-resonance: 0.3))

  (define (preset-fm-electric-piano)
    (make-fm-synth
     mod-ratio: 7.0
     mod-index: 2.5
     amp-attack: 0.001
     amp-decay: 1.0
     amp-sustain: 0.3
     amp-release: 0.8
     filter-cutoff: 6000.0))

  (define (preset-fm-metallic)
    (make-fm-synth
     mod-ratio: 1.41421   ;; sqrt(2) - inharmonic
     mod-index: 8.0
     amp-attack: 0.001
     amp-decay: 0.5
     amp-sustain: 0.0
     amp-release: 0.3
     filter-cutoff: 10000.0
     filter-resonance: 0.2))

) ;; end module

;;; oscillator.scm - Oscillator type definitions and constructors
;;;
;;; Oscillators are parameter sets that get sent to the C engine.
;;; The actual DSP runs in C; this module provides the Scheme-level
;;; abstraction for configuring oscillators on tracks.

(module audio-dac.synth.oscillator
  (make-osc
   osc-waveform osc-detune osc-mix-level
   WAVE_SINE WAVE_SAW WAVE_SQUARE WAVE_TRIANGLE WAVE_NOISE)

  (import scheme (chicken base))

  ;; Waveform constants (must match dsp-core.h)
  (define WAVE_SINE     0)
  (define WAVE_SAW      1)
  (define WAVE_SQUARE   2)
  (define WAVE_TRIANGLE 3)
  (define WAVE_NOISE    4)

  ;; Oscillator parameter record
  (define-record-type osc
    (make-osc* waveform detune mix-level)
    osc?
    (waveform  osc-waveform)
    (detune    osc-detune)
    (mix-level osc-mix-level))

  (define (make-osc #!key
                    (waveform WAVE_SAW)
                    (detune 0.0)
                    (mix-level 1.0))
    (make-osc* waveform detune mix-level))

) ;; end module

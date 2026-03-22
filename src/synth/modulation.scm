;;; modulation.scm - LFO and modulation routing definitions

(module audio-dac.synth.modulation
  (make-lfo
   lfo-waveform lfo-rate lfo-depth lfo-destination
   MOD_DEST_CUTOFF MOD_DEST_PITCH MOD_DEST_PAN MOD_DEST_VOLUME)

  (import scheme (chicken base))

  ;; Modulation destinations
  (define MOD_DEST_CUTOFF  0)
  (define MOD_DEST_PITCH   1)
  (define MOD_DEST_PAN     2)
  (define MOD_DEST_VOLUME  3)

  (define-record-type lfo
    (make-lfo* waveform rate depth destination)
    lfo?
    (waveform    lfo-waveform)    ;; WAVE_SINE, WAVE_TRIANGLE, etc.
    (rate        lfo-rate)         ;; Hz
    (depth       lfo-depth)        ;; 0.0 - 1.0
    (destination lfo-destination)) ;; MOD_DEST_*

  (define (make-lfo #!key
                    (waveform 0)  ;; sine
                    (rate 2.0)
                    (depth 0.5)
                    (destination MOD_DEST_CUTOFF))
    (make-lfo* waveform rate depth destination))

) ;; end module

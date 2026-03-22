;;; filter.scm - Filter type definitions and constructors

(module audio-dac.synth.filter
  (make-filt
   filt-type filt-cutoff filt-resonance
   FILTER_LP FILTER_HP FILTER_BP)

  (import scheme (chicken base))

  ;; Filter type constants (must match dsp-core.h)
  (define FILTER_LP 0)
  (define FILTER_HP 1)
  (define FILTER_BP 2)

  (define-record-type filt
    (make-filt* type cutoff resonance)
    filt?
    (type      filt-type)
    (cutoff    filt-cutoff)
    (resonance filt-resonance))

  (define (make-filt #!key
                     (type FILTER_LP)
                     (cutoff 4000.0)
                     (resonance 0.3))
    (make-filt* type cutoff resonance))

) ;; end module

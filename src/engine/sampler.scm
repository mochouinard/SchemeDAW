;;; sampler.scm - Scheme FFI bindings to the C sample engine
;;;
;;; Provides sample loading, triggering, and management from Scheme.
;;; WAV loading happens on the Scheme thread (non-real-time).
;;; Triggering sends commands to the audio thread via the sample engine.

(module audio-dac.engine.sampler
  (sample-engine-create
   sample-engine-destroy
   sample-load!
   sample-unload!
   sample-trigger!
   sample-stop-voice!
   sample-stop-sample!
   sample-stop-all!)

  (import scheme
          (chicken base)
          (chicken foreign)
          (chicken format))

  (foreign-declare "
#include \"sample-engine.h\"
")

  ;; Create a new sample engine (caller must free with sample-engine-destroy)
  (define sample-engine-create-raw
    (foreign-lambda* c-pointer ((float sample_rate))
      "SampleEngine *se = (SampleEngine *)calloc(1, sizeof(SampleEngine));
       if (se) sample_engine_init(se, sample_rate);
       C_return(se);"))

  (define (sample-engine-create sample-rate)
    (let ((se (sample-engine-create-raw (exact->inexact sample-rate))))
      (unless se
        (error "Failed to create sample engine"))
      se))

  (define sample-engine-destroy-raw
    (foreign-lambda void "sample_engine_destroy" c-pointer))

  (define (sample-engine-destroy se)
    (sample-engine-destroy-raw se))

  ;; Load a WAV file into a slot
  ;; Returns slot index on success, #f on failure
  (define sample-load-raw
    (foreign-lambda int "sample_engine_load" c-pointer c-string int))

  (define (sample-load! se filename slot)
    (let ((result (sample-load-raw se filename slot)))
      (if (>= result 0)
          result
          (begin
            (fprintf (current-error-port)
                     "Warning: failed to load sample '~A'~%" filename)
            #f))))

  ;; Unload a sample
  (define sample-unload!
    (foreign-lambda void "sample_engine_unload" c-pointer int))

  ;; Trigger a sample
  ;; Returns voice index on success, #f on failure
  (define sample-trigger-raw
    (foreign-lambda int "sample_engine_trigger"
      c-pointer int float float float))

  (define (sample-trigger! se slot #!key (volume 1.0) (pan 0.0) (pitch 1.0))
    (let ((result (sample-trigger-raw se slot
                    (exact->inexact volume)
                    (exact->inexact pan)
                    (exact->inexact pitch))))
      (if (>= result 0) result #f)))

  ;; Stop functions
  (define sample-stop-voice!
    (foreign-lambda void "sample_engine_stop_voice" c-pointer int))

  (define sample-stop-sample!
    (foreign-lambda void "sample_engine_stop_sample" c-pointer int))

  (define sample-stop-all!
    (foreign-lambda void "sample_engine_stop_all" c-pointer))

) ;; end module

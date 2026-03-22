;;; host.scm - Scheme FFI bindings to the VST3 host
;;;
;;; Provides plugin scanning, loading, parameter control, and
;;; audio processing from Scheme.

(module audio-dac.vst3.host
  (vst3-host-create
   vst3-host-destroy
   vst3-scan!
   vst3-load!
   vst3-unload!
   vst3-activate!
   vst3-deactivate!
   vst3-param-count
   vst3-set-param!
   vst3-get-param
   vst3-send-note!
   ;; Common VST3 directories
   vst3-default-paths)

  (import scheme
          (chicken base)
          (chicken foreign)
          (chicken format))

  (foreign-declare "
#include \"vst3-host.h\"
")

  ;; Create a VST3 host (caller must free with vst3-host-destroy)
  (define vst3-host-create-raw
    (foreign-lambda* c-pointer ((float sample_rate) (int buffer_size))
      "Vst3Host *h = (Vst3Host *)calloc(1, sizeof(Vst3Host));
       if (h) vst3_host_init(h, sample_rate, buffer_size);
       C_return(h);"))

  (define (vst3-host-create sample-rate buffer-size)
    (let ((h (vst3-host-create-raw (exact->inexact sample-rate) buffer-size)))
      (unless h (error "Failed to create VST3 host"))
      h))

  ;; Destroy
  (define vst3-host-destroy-raw
    (foreign-lambda void "vst3_host_destroy" c-pointer))

  (define (vst3-host-destroy host)
    (vst3-host-destroy-raw host)
    (free host))

  (define free (foreign-lambda void "free" c-pointer))

  ;; Scan for plugins
  ;; Returns a list of (path . name) pairs
  (define (vst3-scan! directory)
    (let ((results '()))
      ;; We use a C callback that accumulates results
      ;; For simplicity, use the raw scan and collect via fprintf
      (let ((count ((foreign-lambda int "vst3_host_scan" c-string c-pointer c-pointer)
                    directory #f #f)))
        (format #t "Found ~A VST3 plugins in ~A~%" count directory)
        count)))

  ;; Load a plugin
  (define vst3-load-raw
    (foreign-lambda int "vst3_host_load" c-pointer c-string int))

  (define (vst3-load! host path slot)
    (let ((result (vst3-load-raw host path slot)))
      (if (>= result 0)
          (begin
            (format #t "Loaded VST3 plugin into slot ~A~%" result)
            result)
          (begin
            (format (current-error-port) "Failed to load VST3: ~A~%" path)
            #f))))

  ;; Unload
  (define vst3-unload!
    (foreign-lambda void "vst3_host_unload" c-pointer int))

  ;; Activate/Deactivate
  (define vst3-activate!
    (foreign-lambda int "vst3_host_activate" c-pointer int))

  (define vst3-deactivate!
    (foreign-lambda void "vst3_host_deactivate" c-pointer int))

  ;; Parameters
  (define vst3-param-count
    (foreign-lambda int "vst3_host_get_param_count" c-pointer int))

  (define vst3-set-param!
    (foreign-lambda void "vst3_host_set_param" c-pointer int int double))

  (define vst3-get-param
    (foreign-lambda double "vst3_host_get_param" c-pointer int int))

  ;; MIDI
  (define vst3-send-note!
    (foreign-lambda void "vst3_host_send_note" c-pointer int int int int))

  ;; Default VST3 plugin directories on Linux
  (define (vst3-default-paths)
    (list "/usr/lib/vst3"
          "/usr/local/lib/vst3"
          (string-append (or (get-environment-variable "HOME") "~")
                         "/.vst3")))

  ;; Get environment variable (simple helper)
  (define get-environment-variable
    (foreign-lambda c-string "getenv" c-string))

) ;; end module

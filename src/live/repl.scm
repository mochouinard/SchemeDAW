;;; repl.scm - Live coding REPL server
;;;
;;; Provides a TCP-based REPL that connects to the running DAW process.
;;; Users can connect with netcat, telnet, or a dedicated client to
;;; evaluate Scheme expressions that modify the live audio engine.
;;;
;;; Usage: connect with `rlwrap nc localhost 7770` for a REPL session.

(module audio-dac.live.repl
  (start-repl-server!
   stop-repl-server!
   repl-eval-string)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken io)
          (chicken tcp)
          (chicken port)
          (chicken condition))

  ;; REPL server state
  (define *repl-listener* #f)
  (define *repl-running* #f)

  ;; Start a simple TCP REPL server
  ;; When a client connects, it gets a read-eval-print loop
  (define (start-repl-server! #!key (port 7770) (env (interaction-environment)))
    (set! *repl-running* #t)
    (let ((listener (tcp-listen port)))
      (set! *repl-listener* listener)
      (fprintf (current-error-port) "REPL server listening on port ~A~%" port)

      ;; Accept connections in the background
      ;; Note: In the actual DAW, this would run on a green thread.
      ;; For now, we provide the function and it would be called from
      ;; a srfi-18 thread.
      (lambda ()
        (let accept-loop ()
          (when *repl-running*
            (condition-case
              (receive (in out) (tcp-accept listener)
                (fprintf (current-error-port) "REPL client connected~%")
                (handle-client in out env)
                (fprintf (current-error-port) "REPL client disconnected~%")
                (close-input-port in)
                (close-output-port out))
              ((exn)
               (fprintf (current-error-port)
                        "REPL error: ~A~%" (condition->string (current-exception-handler)))))
            (accept-loop))))))

  ;; Handle a single REPL client connection
  (define (handle-client in out env)
    (let loop ()
      (condition-case
        (begin
          (display "audio-dac> " out)
          (flush-output out)
          (let ((line (read-line in)))
            (when (and line (not (eof-object? line)))
              (let ((result (repl-eval-string line env)))
                (display result out)
                (newline out)
                (flush-output out)
                (loop)))))
        ((exn)
         (display "Error: " out)
         (display (condition->string (current-exception-handler)) out)
         (newline out)
         (flush-output out)
         (loop)))))

  ;; Evaluate a string in the given environment
  (define (repl-eval-string str #!optional (env (interaction-environment)))
    (condition-case
      (let* ((port (open-input-string str))
             (expr (read port)))
        (if (eof-object? expr)
            ""
            (let ((result (eval expr env)))
              (format #f "~S" result))))
      ((exn)
       (format #f "Error: ~A" (condition->string (current-exception-handler))))))

  ;; Stop the REPL server
  (define (stop-repl-server!)
    (set! *repl-running* #f)
    (when *repl-listener*
      (tcp-close *repl-listener*)
      (set! *repl-listener* #f)
      (fprintf (current-error-port) "REPL server stopped~%")))

  ;; Helper
  (define (condition->string exn)
    (with-output-to-string
      (lambda () (print-error-message exn))))

) ;; end module

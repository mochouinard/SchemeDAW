;;; arrangement.scm - Song arrangement (pattern chains and scenes)
;;;
;;; An arrangement organizes patterns into a linear song structure.
;;; Scenes group track patterns that should play together.
;;; The arrangement advances through scenes sequentially or loops.

(module audio-dac.sequencer.arrangement
  (make-scene
   scene-name scene-name-set!
   scene-patterns scene-patterns-set!
   scene-length scene-length-set!
   make-arrangement
   arrangement-scenes arrangement-scenes-set!
   arrangement-current-scene arrangement-current-scene-set!
   arrangement-loop? arrangement-loop?-set!
   arrangement-add-scene!
   arrangement-remove-scene!
   arrangement-next-scene!
   arrangement-goto-scene!
   arrangement-get-current-scene)

  (import scheme (chicken base))

  ;; A scene: a set of patterns to play simultaneously
  ;; patterns: alist of (track-index . pattern)
  (define-record-type scene
    (make-scene* name patterns length)
    scene?
    (name     scene-name scene-name-set!)
    (patterns scene-patterns scene-patterns-set!)  ;; alist: ((track . pattern) ...)
    (length   scene-length scene-length-set!))      ;; length in bars

  (define (make-scene #!key (name "Scene") (patterns '()) (length 4))
    (make-scene* name patterns length))

  ;; Arrangement: ordered list of scenes
  (define-record-type arrangement
    (make-arrangement* scenes current-scene loop?)
    arrangement?
    (scenes        arrangement-scenes arrangement-scenes-set!)
    (current-scene arrangement-current-scene arrangement-current-scene-set!)
    (loop?         arrangement-loop? arrangement-loop?-set!))

  (define (make-arrangement #!key (scenes '()) (loop? #t))
    (make-arrangement* scenes 0 loop?))

  (define (arrangement-add-scene! arr scene)
    (arrangement-scenes-set! arr
      (append (arrangement-scenes arr) (list scene))))

  (define (arrangement-remove-scene! arr index)
    (let ((scenes (arrangement-scenes arr)))
      (when (and (>= index 0) (< index (length scenes)))
        (arrangement-scenes-set! arr
          (append (take scenes index)
                  (drop scenes (+ index 1)))))))

  (define (arrangement-next-scene! arr)
    (let* ((scenes (arrangement-scenes arr))
           (current (arrangement-current-scene arr))
           (next (+ current 1)))
      (cond
       ((< next (length scenes))
        (arrangement-current-scene-set! arr next))
       ((arrangement-loop? arr)
        (arrangement-current-scene-set! arr 0))
       (else #f))))  ;; end of arrangement

  (define (arrangement-goto-scene! arr index)
    (when (and (>= index 0)
               (< index (length (arrangement-scenes arr))))
      (arrangement-current-scene-set! arr index)))

  (define (arrangement-get-current-scene arr)
    (let ((scenes (arrangement-scenes arr))
          (idx (arrangement-current-scene arr)))
      (if (< idx (length scenes))
          (list-ref scenes idx)
          #f)))

  ;; Helper: take/drop for lists
  (define (take lst n)
    (if (or (= n 0) (null? lst))
        '()
        (cons (car lst) (take (cdr lst) (- n 1)))))

  (define (drop lst n)
    (if (or (= n 0) (null? lst))
        lst
        (drop (cdr lst) (- n 1))))

) ;; end module

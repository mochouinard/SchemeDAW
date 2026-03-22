;;; fx-chain.scm - Effect chain management
;;;
;;; Manages an ordered list of effects per track. Effects are applied
;;; in series: the output of one feeds into the next.

(module audio-dac.fx.fx-chain
  (make-fx-chain
   fx-chain-effects
   fx-chain-add!
   fx-chain-remove!
   fx-chain-clear!
   EFFECT_DELAY EFFECT_REVERB EFFECT_DISTORTION)

  (import scheme (chicken base))

  ;; Effect type constants (match effects.h)
  (define EFFECT_DELAY      1)
  (define EFFECT_REVERB     2)
  (define EFFECT_DISTORTION 3)

  ;; An effect chain is a list of (type . params) pairs
  (define-record-type fx-chain
    (make-fx-chain* effects)
    fx-chain?
    (effects fx-chain-effects fx-chain-effects-set!))

  (define (make-fx-chain)
    (make-fx-chain* '()))

  (define (fx-chain-add! chain type params)
    (fx-chain-effects-set! chain
      (append (fx-chain-effects chain)
              (list (cons type params)))))

  (define (fx-chain-remove! chain index)
    (let ((effects (fx-chain-effects chain)))
      (when (and (>= index 0) (< index (length effects)))
        (fx-chain-effects-set! chain
          (append (take-list effects index)
                  (drop-list effects (+ index 1)))))))

  (define (fx-chain-clear! chain)
    (fx-chain-effects-set! chain '()))

  ;; List helpers
  (define (take-list lst n)
    (if (or (= n 0) (null? lst)) '()
        (cons (car lst) (take-list (cdr lst) (- n 1)))))

  (define (drop-list lst n)
    (if (or (= n 0) (null? lst)) lst
        (drop-list (cdr lst) (- n 1))))

) ;; end module

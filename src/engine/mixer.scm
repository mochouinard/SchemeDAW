;;; mixer.scm - Mixer and track topology management
;;;
;;; Provides the Scheme-level abstraction for the mixer: track volumes,
;;; panning, mute/solo, and routing. Commands are sent to the C engine.

(module audio-dac.engine.mixer
  (make-mixer
   mixer-tracks
   mixer-master-volume mixer-master-volume-set!
   mixer-track-volume mixer-track-volume-set!
   mixer-track-pan mixer-track-pan-set!
   mixer-track-mute! mixer-track-solo!
   mixer-track-name mixer-track-name-set!
   mixer-apply!)

  (import scheme (chicken base) (chicken format))

  ;; Track info (Scheme-side mirror of C engine state)
  (define-record-type mixer-track
    (make-mixer-track* name volume pan mute? solo?)
    mixer-track?
    (name   mixer-track-name mixer-track-name-set!)
    (volume mixer-track-volume mixer-track-volume-set!)
    (pan    mixer-track-pan mixer-track-pan-set!)
    (mute?  mixer-track-mute? mixer-track-mute?-set!)
    (solo?  mixer-track-solo? mixer-track-solo?-set!))

  ;; Mixer state
  (define-record-type mixer
    (make-mixer* tracks master-volume send-fn)
    mixer?
    (tracks        mixer-tracks)
    (master-volume mixer-master-volume mixer-master-volume-set!)
    (send-fn       mixer-send-fn))

  (define (make-mixer send-fn #!key (num-tracks 16) (master-volume 0.8))
    (let ((tracks (make-vector num-tracks #f)))
      (do ((i 0 (+ i 1)))
          ((>= i num-tracks))
        (vector-set! tracks i
          (make-mixer-track*
           (string-append "Track " (number->string (+ i 1)))
           0.8 0.0 #f #f)))
      (make-mixer* tracks master-volume send-fn)))

  ;; Set track volume and sync to engine
  (define (mixer-track-volume-set! mix track-idx volume)
    (let ((track (vector-ref (mixer-tracks mix) track-idx)))
      (mixer-track-volume-set!* track volume)
      ((mixer-send-fn mix) #x04 track-idx 0 0 volume)))

  ;; Internal setter (no engine sync)
  (define mixer-track-volume-set!*
    (record-mutator (##sys#slot (make-mixer-track* "" 0 0 #f #f) 0) 1))

  ;; Set track pan and sync
  (define (mixer-track-pan-set! mix track-idx pan)
    (let ((track (vector-ref (mixer-tracks mix) track-idx)))
      (mixer-track-pan-set!* track pan)
      ((mixer-send-fn mix) #x05 track-idx 0 0 pan)))

  (define mixer-track-pan-set!*
    (record-mutator (##sys#slot (make-mixer-track* "" 0 0 #f #f) 0) 2))

  ;; Mute/unmute a track
  (define (mixer-track-mute! mix track-idx muted?)
    (let ((track (vector-ref (mixer-tracks mix) track-idx)))
      (mixer-track-mute?-set! track muted?)
      ((mixer-send-fn mix) #x09 track-idx (if muted? 1 0) 0 0.0)))

  ;; Solo/unsolo a track
  (define (mixer-track-solo! mix track-idx soloed?)
    (let ((track (vector-ref (mixer-tracks mix) track-idx)))
      (mixer-track-solo?-set! track soloed?)
      ((mixer-send-fn mix) #x0A track-idx (if soloed? 1 0) 0 0.0)))

  ;; Apply all mixer state to engine (for initialization)
  (define (mixer-apply! mix)
    (let ((tracks (mixer-tracks mix))
          (send (mixer-send-fn mix)))
      (do ((i 0 (+ i 1)))
          ((>= i (vector-length tracks)))
        (let ((t (vector-ref tracks i)))
          (send #x04 i 0 0 (mixer-track-volume t))
          (send #x05 i 0 0 (mixer-track-pan t))
          (send #x09 i (if (mixer-track-mute? t) 1 0) 0 0.0)
          (send #x0A i (if (mixer-track-solo? t) 1 0) 0 0.0)))))

) ;; end module

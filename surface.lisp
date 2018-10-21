(in-package #:org.shirakumo.fraf.leaf)

(defstruct (block (:constructor make-block (l r)))
  (l 0 :type (unsigned-byte 16))
  (r 0 :type (unsigned-byte 16)))

(defun make-surface-blocks (t-s steps)
  (let ((blocks (make-array (+ 2 (* 2 (reduce #'+ steps)))))
        (i -1))
    (flet ((make (l r)
             (setf (aref blocks (incf i)) (make-block l r))))
      (make t-s t-s)
      (make 0 0)
      (loop for steps in '(1 2 3)
            do (loop for i from 0 below steps
                     for l = (* (/ i steps) *default-tile-size*)
                     for r = (* (/ (1+ i) steps) *default-tile-size*)
                     do (make (floor l) (floor r)))
            do (loop for i downfrom steps above 0
                     for l = (* (/ i steps) *default-tile-size*)
                     for r = (* (/ (1- i) steps) *default-tile-size*)
                     do (make (floor l) (floor r))))
      blocks)))

(defvar *default-surface-blocks* (make-surface-blocks *default-tile-size* '(1 2 3)))

(define-shader-entity surface (layer)
  ((blocks :initarg :blocks :accessor blocks))
  (:default-initargs
   :texture (asset 'leaf 'surface)
   :name :surface
   :blocks *default-surface-blocks*))

(defstruct (hit (:constructor make-hit (object time location normal)))
  (object NIL)
  (time 0.0 :type single-float)
  (location NIL :type vec2)
  (normal NIL :type vec2))

(defmethod paint :around ((surface surface) target)
  (when (unit :editor (scene (handler *context*)))
    (call-next-method)))

(defun aabb (seg-pos seg-vel aabb-pos aabb-size)
  (declare (type vec2 seg-pos seg-vel aabb-pos aabb-size))
  (sb-int:with-float-traps-masked (:overflow :underflow :inexact)
    (let* ((scale (vec2 (if (= 0 (vx seg-vel)) most-positive-single-float (/ (vx seg-vel)))
                        (if (= 0 (vy seg-vel)) most-positive-single-float (/ (vy seg-vel)))))
           (sign (vec2 (float-sign (vx seg-vel)) (float-sign (vy seg-vel))))
           (near (v* (v- (v- aabb-pos (v* sign aabb-size)) seg-pos) scale))
           (far  (v* (v- (v+ aabb-pos (v* sign aabb-size)) seg-pos) scale)))
      (unless (or (< (vy far) (vx near))
                  (< (vx far) (vy near)))
        (let ((t-near (max (vx near) (vy near)))
              (t-far (min (vx far) (vy far))))
          (when (and (< t-near 1)
                     (< 0 t-far))
            (let* ((time (alexandria:clamp t-near 0.0 1.0))
                   (normal (if (< (vy near) (vx near))
                               (vec (- (vx sign)) 0)
                               (vec 0 (- (vy sign))))))
              (unless (= 0 (v. normal seg-vel))
                ;; KLUDGE: This test is necessary in order to ignore vertical edges
                ;;         that seem to stick out of the blocks. I have no idea why.
                (unless (and (/= 0 (vy normal))
                             (<= (vx aabb-size) (abs (- (vx aabb-pos) (vx seg-pos)))))
                  (make-hit NIL time aabb-pos normal))))))))))

(defun vsqrdist2 (a b)
  (declare (type vec2 a b))
  (declare (optimize speed))
  (+ (expt (- (vx2 a) (vx2 b)) 2)
     (expt (- (vy2 a) (vy2 b)) 2)))

(defmethod scan ((surface surface) size loc vel)
  (let* ((t-s (tile-size surface))
         (x- 0) (y- 0) (x+ 0) (y+ 0)
         (size (v/ (v+ size t-s) 2))
         (result))
    ;; Figure out bounding region
    (if (< 0 (vx vel))
        (setf x- (floor (- (vx loc) (vx size)) t-s)
              x+ (ceiling (+ (vx loc) (vx vel)) t-s))
        (setf x- (floor (- (+ (vx loc) (vx vel)) (vx size)) t-s)
              x+ (ceiling (vx loc) t-s)))
    (if (< 0 (vy vel))
        (setf y- (floor (- (vy loc) (vy size)) t-s)
              y+ (ceiling (+ (vy loc) (vy vel)) t-s))
        (setf y- (floor (- (+ (vy loc) (vy vel)) (vy size)) t-s)
              y+ (ceiling (vy loc) t-s)))
    ;; Sweep AABB through tiles
    (destructuring-bind (w h) (size surface)
      (loop for x from (max 0 x-) to (min x+ (1- w))
            do (loop for y from (max 0 y-) to (min y+ (1- h))
                     for tile = (aref (tiles surface) (+ x (* y w)))
                     for hit = (when (/= 0 tile) (aabb loc vel (vec (+ (/ t-s 2) (* t-s x)) (+ (/ t-s 2) (* t-s y))) size))
                     do (when (and hit (or (not result)
                                           (< (hit-time hit) (hit-time result))
                                           (and (= (hit-time hit) (hit-time result))
                                                (< (vsqrdist2 loc (hit-location hit))
                                                   (vsqrdist2 loc (hit-location result))))))
                          (setf (hit-object hit) (aref (blocks surface) tile))
                          (setf result hit))))
      result)))
(in-package #:numpy-file-format)

(defconstant +endianness+
  #+little-endian :little-endian
  #+big-endian  :big-endian)

(defgeneric dtype-name (dtype))

(defgeneric dtype-endianness (dtype))

(defgeneric dtype-type (dtype))

(defgeneric dtype-code (dtype))

(defgeneric dtype-size (dtype))

(defparameter *dtypes* '())

(defclass dtype ()
  ((%type :initarg :type :reader dtype-type)
   (%code :initarg :code :reader dtype-code)
   (%size :initarg :size :reader dtype-size)
   (%endianness :initarg :endianness :reader dtype-endianness)))

(defmethod print-object ((dtype dtype) stream)
  (print-unreadable-object (dtype stream :type t)
    (prin1 (dtype-code dtype) stream)))

(defun dtype-from-code (code)
  (or (find code *dtypes* :key #'dtype-code :test #'string=)
      (error "Cannot find dtype for the code ~S." code)))

(defun dtype-from-type (type)
  (or (find-if
       (lambda (dtype)
         (and (eq (dtype-endianness dtype) +endianness+)
              (subtypep type (dtype-type dtype))))
       *dtypes*)
      (error "Cannot find dtype for type ~S." type)))

(defun define-dtype (code type size &optional (endianness +endianness+))
  (let ((dtype (make-instance 'dtype
                 :code code
                 :type type
                 :size size
                 :endianness endianness)))
    (pushnew dtype *dtypes* :key #'dtype-code :test #'string=)
    dtype))

(defun define-multibyte-dtype (code type size)
  (define-dtype (concatenate 'string "<" code) type size :little-endian)
  (define-dtype (concatenate 'string ">" code) type size :big-endian)
  (define-dtype code type size +endianness+)
  (define-dtype (concatenate 'string "|" code) type size)
  (define-dtype (concatenate 'string "=" code) type size +endianness+))

(define-dtype "O" 't 64)
(define-dtype "?" 'bit 1)
(define-dtype "b" '(unsigned-byte 8) 8)
(define-multibyte-dtype "i1" '(signed-byte 8) 8)
(define-multibyte-dtype "i2" '(signed-byte 16) 16)
(define-multibyte-dtype "i4" '(signed-byte 32) 32)
(define-multibyte-dtype "i8" '(signed-byte 64) 64)
(define-multibyte-dtype "u1" '(unsigned-byte 8) 8)
(define-multibyte-dtype "u2" '(unsigned-byte 16) 16)
(define-multibyte-dtype "u4" '(unsigned-byte 32) 32)
(define-multibyte-dtype "u8" '(unsigned-byte 64) 64)
(define-multibyte-dtype "f4" 'single-float 32)
(define-multibyte-dtype "f8" 'double-float 64)
(define-multibyte-dtype "c8" '(complex single-float) 64)
(define-multibyte-dtype "c16" '(complex double-float) 128)

;; Finally, let's sort *dtypes* such that type queries always find the most
;; specific entry first.
(setf *dtypes* (stable-sort *dtypes* #'subtypep :key #'dtype-type))

(declaim (inline mask-signed))
(defun mask-signed (x size)
  (declare (type fixnum x) (type (unsigned-byte 8) size))
  (logior x (- (mask-field (byte 1 (1- size)) x))))

(defmacro with-decoding ((endian) &body body)
  `(flet ((int8 (stream)
            (declare (optimize (speed 3))
                     (type stream stream))
            (mask-signed (read-byte stream) 8))
          (uint8 (stream)
            (declare (optimize (speed 3))
                     (type stream stream))
            (read-byte stream)))
     (declare (inline int8 uint8))
     (alexandria:eswitch (,endian)
       (:little-endian (flet ((float32 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (the single-float (nibbles:read-ieee-single/le stream)))
                              (float64 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (the double-float (nibbles:read-ieee-double/le stream)))
                              (int16 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-sb16/le stream))
                              (int32 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-sb32/le stream))
                              (int64 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-sb64/le stream))
                              (uint16 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-ub16/le stream))
                              (uint32 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-ub32/le stream))
                              (uint64 (stream)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:read-ub64/le stream)))
                         (declare (inline float32 float64
                                          uint16 uint32 uint64
                                          int16 int32 int64))
                         ,@body))
       (:big-endian (flet ((float32 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (the single-float (nibbles:read-ieee-single/be stream)))
                           (float64 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (the double-float (nibbles:read-ieee-double/be stream)))
                           (int16 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-sb16/be stream))
                           (int32 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-sb32/be stream))
                           (int64 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-sb64/be stream))
                           (uint16 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-ub16/be stream))
                           (uint32 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-ub32/be stream))
                           (uint64 (stream)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:read-ub64/be stream)))
                      (declare (inline float32 float64
                                       uint16 uint32 uint64
                                       int16 int32 int64))
                      ,@body)))))

(defmacro with-encoding ((endian) &body body)
  `(flet ((int8 (stream value)
            (declare (optimize (speed 3))
                     (type stream stream))
            (write-byte (logand #b11111111 value) stream))
          (uint8 (stream value)
            (declare (optimize (speed 3))
                     (type stream stream))
            (write-byte value stream)))
     (declare (inline int8 uint8))
     (alexandria:eswitch (,endian)
       (:little-endian (flet ((float32 (stream value)
                                (declare (optimize (speed 3))
                                         (type single-float value)
                                         (type stream stream))
                                (nibbles:write-ieee-single/le value stream))
                              (float64 (stream value)
                                (declare (optimize (speed 3))
                                         (type double-float value)
                                         (type stream stream))
                                (nibbles:write-ieee-double/le value stream))
                              (int16 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-sb16/le value stream))
                              (int32 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-sb32/le value stream))
                              (int64 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-sb64/le value stream))
                              (uint16 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-ub16/le value stream))
                              (uint32 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-ub32/le value stream))
                              (uint64 (stream value)
                                (declare (optimize (speed 3))
                                         (type stream stream))
                                (nibbles:write-ub64/le value stream)))
                         (declare (inline float32 float64
                                          uint16 uint32 uint64
                                          int16 int32 int64))
                         ,@body))
       (:big-endian (flet ((float32 (stream value)
                             (declare (optimize (speed 3))
                                      (type single-float value)
                                      (type stream stream))
                             (nibbles:write-ieee-single/be value stream))
                           (float64 (stream value)
                             (declare (optimize (speed 3))
                                      (type double-float value)
                                      (type stream stream))
                             (nibbles:write-ieee-double/be value stream))
                           (int16 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-sb16/be value stream))
                           (int32 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-sb32/be value stream))
                           (int64 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-sb64/be value stream))
                           (uint16 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-ub16/be value stream))
                           (uint32 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-ub32/be value stream))
                           (uint64 (stream value)
                             (declare (optimize (speed 3))
                                      (type stream stream))
                             (nibbles:write-ub64/be value stream)))
                      (declare (inline float32 float64
                                       uint16 uint32 uint64
                                       int16 int32 int64))
                      ,@body)))))

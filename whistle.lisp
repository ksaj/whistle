;;; Copyright (c) 2011, Peter Seibel.  All rights reserved.
;;;
;;; See LICENSE.txt for licensing information.

(in-package :whistle)

(defparameter *default-port* 9876)

(defvar *whistle-server* nil)

(defclass server ()
  ((root-directory :initarg :root-directory :accessor root-directory)
   (passwords      :initarg :passwords :initform () :accessor passwords)
   (realm          :initarg :realm :initform "Whistle" :accessor realm)
   (groups         :initarg :groups :initform () :accessor groups)
   (protections    :initarg :protections :initform () :accessor protections)
   (redirects      :initarg :redirects :initform () :accessor redirects)
   (urls           :initarg :urls :initform () :accessor urls)
-   (accept-log     :initarg :accept-log :initform "accept.log" :accessor accept-log)
   (message-log    :initarg :message-log :initform "messages.log" :accessor message-log)
   (ports          :initarg :ports :initform () :accessor ports)
   (acceptors      :initarg :acceptors :initform () :accessor acceptors)))


(defun default-handler (request)
  (let ((script-name (url-decode (script-name request))))
    (unless (safe-filename-p script-name)
      (abort-request-handler request +http-forbidden+))
    (let ((resolved (resolve-file script-name)))
      (break "here ~a ~a" resolved toot::*catch-errors-p*)
      (serve-file request resolved))))

(defun resolve-file (script-name)
  (merge-pathnames (subseq (add-index script-name) 1)))
  
(defun add-index (filename &key (extension "html"))
  (format nil "~a~@[index~*~@[.~a~]~]" filename (ends-with #\/ filename) extension))

(defun handled-p (result)
  (not (eql result 'not-handled)))

(defmethod toot::handle-request ((server server) request)
  (let ((*default-pathname-defaults* (merge-pathnames "content/" (root-directory server))))
    (with-redirects (request server)
      (with-authorization (request server)
        (maybe-handle
            (loop with script-name = (script-name request)
               for (pattern . fn) in (urls server)
               do (multiple-value-bind (match parts) (scan-to-strings pattern script-name)
                    (when (and match (handled-p (apply fn request (coerce parts 'list))))
                      (return)))))))))
  
(defun server-dir (server relative)
  (merge-pathnames relative (root-directory server)))

(defun content-file (server file)
  (merge-pathnames file (server-dir server "content/")))

(defun config-file (server file)
  (merge-pathnames file (server-dir server "config/")))

(defun make-server (dir)
  (let ((actual-dir (file-exists-p (pathname-as-directory dir))))
    (cond
      (actual-dir (make-instance 'server :root-directory actual-dir))
      (t (error "~a does not exist." dir)))))

(defun server-setup (dir)
  (let ((server (make-server dir)))
    (read-configuration-files server)
    server))

(defun read-configuration-files (server)
  (let ((*package* #.*package*))
    (load-ports "ports.sexp" server)
    (load-redirects "redirects.sexp" server)
    (load-passwords "passwords.sexp" server)
    (load-protections "protections.sexp" server)
    (load-urls "urls.sexp" server)))

(defun start-acceptors (server)
  (loop for (protocol port) in (ports server) do 
       (push (make-instance 'toot::acceptor :port port :handler server) (acceptors server)))
  (loop for acceptor in (acceptors server) do (start acceptor)))

(defun load-ports (file server)
  (setf (ports server) (file->list (config-file server file))))

(defun load-redirects (file server)
  (setf (redirects server) (file->list (config-file server file))))

(defun load-passwords (file server)
  (let ((passwords (file->list (config-file server file))))
    (setf (passwords server) (mapcar (lambda (x) (cons (first x) (second x))) passwords))
    (setf (groups server) 
          (let ((groups-map (make-hash-table)))
            (loop for (user password . groups) in passwords do
                 (loop for group in groups do
                      (push user (gethash group groups-map nil))))
            groups-map))))

(defun load-protections (file server)
  (setf (protections server) (file->list (config-file server file))))

(defun load-urls (file server)
  (setf (urls server) (file->list (config-file server file))))

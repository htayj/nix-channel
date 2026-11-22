;;; SPDX-License-Identifier: GPL-3.0-only
(in-package #:gened)

;;; The legacy Allegro/LispWorks entry points are not CLIM 2 interfaces.
(defmacro outl (&body body)
  `(spacing (:thickness 2)
     (outlining (:thickness 2)
       (spacing (:thickness 2) ,@body))))

(defun window-inside-size (stream)
  (bounding-rectangle-size (sheet-region stream)))

;;; McCLIM's Franz select-file ignores its directory and title arguments and
;;; reads from standard input.  GenEd has no input interactor, so use the
;;; portable accepting-values dialog instead, for every normal file operation.
(defun select-file (frame &key title directory)
  (let ((stream (frame-standard-output frame)))
    (accepting-values (stream :own-window t :label title)
      (accept 'pathname :stream stream :prompt "File"
              :default (translate-logical-pathname directory)))))

(defun confirm-operation (frame message &key style)
  (eq (clim:notify-user frame message :style style
                       :exit-boxes '((:yes "Yes") (:no "No")))
      :yes))

;;; The upstream menu changes its label after every editing operation.
;;; A menu item is not a command definition in McCLIM; leave the command
;;; registered in GENED and replace only its MANIPULATE-TABLE menu item.
(defun remove-undo-menu-item (command table)
  (let (names)
    (map-over-command-table-menu-items
     (lambda (name character item)
       (declare (ignore character))
       (when (and (eq (command-menu-item-type item) :command)
                  (equal (command-menu-item-value item) (list command)))
         (push name names)))
     table :inherited nil)
    (dolist (name names)
      (remove-menu-item-from-command-table table name))))

(defun add-undo-menu-item (command table &key menu)
  (apply #'add-menu-item-to-command-table
         table (first menu) :command (list command) (rest menu)))

;;; SPDX-License-Identifier: GPL-3.0-only
(in-package #:gened)

(defun main ()
  "Run the installed upstream editor on the current X display."
  (let* ((data-home (or (uiop:getenv "XDG_DATA_HOME")
                        (namestring (merge-pathnames ".local/share/"
                                                     (user-homedir-pathname)))))
         (state (merge-pathnames "gened/"
                                 (uiop:ensure-directory-pathname data-home)))
         (source (asdf:system-relative-pathname "gened" "src/")))
    ;; Installed example scenes, object libraries, and the label objects are
    ;; writable user assets.  Never replace an existing user file on launch.
    (dolist (kind '("objects" "scenes" "libraries" "prints"))
      (let ((directory (merge-pathnames (format nil "~a/" kind) state)))
        (ensure-directories-exist directory)
        (dolist (file (uiop:directory-files
                      (merge-pathnames (format nil "~a/" kind) source)))
          (let ((target (merge-pathnames (file-namestring file) directory)))
            (unless (probe-file target)
              (uiop:copy-file file target))))))
    (setf (logical-pathname-translations "gened")
          (list (list "**;*.*.*" (concatenate 'string (namestring state)
                                                "**/*.*"))))
    (let* ((port (find-port))
           (frame (make-application-frame 'gened :port port
                                          :pretty-name "GenEd"
                                          :width 1400 :height 900)))
      (setf *gened-frame* frame)
      (unwind-protect (run-frame-top-level frame)
        (when (frame-manager frame)
          (disown-frame (frame-manager frame) frame))))))

(export 'main)

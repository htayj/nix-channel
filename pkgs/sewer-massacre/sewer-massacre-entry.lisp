;;; SPDX-License-Identifier: GPL-3.0-or-later
(require :asdf)
(asdf:load-system :sewers)

(defun sewer-smoke ()
  ;; This is a real, isolated game, not a model or replacement renderer.
  ;; Only the smoke uses a fixed seed; START-GAME still seeds interactive games.
  (setf *random-state* (sb-ext:seed-random-state 729))
  (sewers::test-levels)
  (setf sewers::*allmessages* nil
        sewers::*messages* nil
        sewers::*timer* (make-instance 'sewers::timer)
        sewers::*monster-generator* (make-array 10 :initial-element nil)
        sewers::*item-generator* (make-array 10 :initial-element nil)
        sewers::*allmaps* (make-array 10 :initial-element nil)
        sewers::*debug-mode* nil
        sewers::*curlevel* 1
        sewers::*deepest-level* 1)
  (curses:connect-console)
  (unwind-protect
       (progn
         (assert (null (sewers::init-controls)))
         (sewers::go-to-level 1 :newgame t)
         ;; Move the original player through an actual unoccupied, passable
         ;; neighbor using the original action dispatcher and LOS update.
         (let* ((player sewers::*player*)
                (old-x (sewers::x player))
                (old-y (sewers::y player))
                (deltas (sewers::free-neighbor-deltas old-y old-x)))
           (assert deltas)
           ;; RUN-STACK normally pops this actor and binds *CURMONSTER* before
           ;; dispatch.  CAST temporarily pushes it for event awareness.
           (let ((delta (first deltas))
                 (sewers::*curmonster* player)
                 (sewers::*monsterstack*
                   (remove player sewers::*monsterstack* :key #'car)))
             (setf sewers::*cancelled* nil)
             (sewers::do-action player
                                (make-instance 'sewers::move-to
                                               :dy (car delta) :dx (cdr delta)))
             (assert (not sewers::*cancelled*))
             (assert (= (sewers::x player) (+ old-x (cdr delta))))
             (assert (= (sewers::y player) (+ old-y (car delta)))))
           ;; Exercise inventory plus CL-STORE's real CLOS serialization.  A
           ;; deliberately changed player is restored to the saved position,
           ;; health and money; compare content, not merely file existence.
           (let* ((saved-x (sewers::x player))
                  (saved-y (sewers::y player))
                  (saved-hp (sewers::hp player))
                  (item (make-instance 'sewers::knife)))
             (sewers::obtain player item)
             (setf (sewers::cash player) 7)
             (sewers::save-game "current.sav")
             (setf (sewers::cash player) 99
                   (sewers::hp player) 1
                   (sewers::inventory player) nil)
             (sewers::load-game "current.sav")
             (assert (= (sewers::x sewers::*player*) saved-x))
             (assert (= (sewers::y sewers::*player*) saved-y))
             (assert (= (sewers::hp sewers::*player*) saved-hp))
             (assert (= (sewers::cash sewers::*player*) 7))
             (assert (some (lambda (object) (typep object 'sewers::knife))
                           (sewers::inventory sewers::*player*)))
             (assert (eq (sewers::monster
                          (aref sewers::*map* saved-y saved-x))
                         sewers::*player*))))
         (sewers::redraw-screen)
         (curses:refresh)
         ;; Optional rendezvous for a live xterm/X11 screenshot.  The driver
         ;; captures actual pixels before releasing us; no text-to-PNG adapter.
         (let ((ready (uiop:getenv "SEWERS_CAPTURE_READY"))
               (done (uiop:getenv "SEWERS_CAPTURE_DONE")))
           (when (or ready done)
             (assert (and ready done))
             (with-open-file (stream ready :direction :output
                                          :if-exists :error)
               (write-line "gameplay-and-save-restore-ok" stream))
             (loop with deadline = (+ (get-internal-real-time)
                                      (* 20 internal-time-units-per-second))
                   until (probe-file done)
                   do (assert (< (get-internal-real-time) deadline))
                      (sleep 0.05)))))
    (curses:close-console))
  (format t "SEWERS_SMOKE_OK~%")
  (finish-output))

(let ((arguments uiop:*command-line-arguments*))
  (cond ((null arguments) (sewers::start-game))
        ((equal arguments '("--smoke")) (sewer-smoke))
        (t (error "Usage: sewer-massacre [--smoke]"))))

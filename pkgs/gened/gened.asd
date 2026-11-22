;;; SPDX-License-Identifier: GPL-3.0-only
;;; The order follows upstream src/gened-sysdcl.lisp, without CLASSIC.
(asdf:defsystem "gened"
  :description "GenEd visual notation editor"
  :license "GPL-3.0-only"
  :depends-on ("mcclim" "mcclim-franz")
  :serial t
  :components ((:file "src/gened-packages")
               (:file "gened-mcclim")
               (:file "src/values")
               (:file "src/classesxx")
               (:file "src/comtable")
               (:file "src/frame2")
               (:file "src/splines/spline3")
               (:file "src/geometry/newgeo13")
               (:file "src/helpaux")
               (:file "src/polyrep")
               (:file "src/transfor")
               (:file "src/draw")
               (:file "src/creator")
               (:file "src/cluster")
               (:file "src/handles")
               (:file "src/inout")
               (:file "src/copy")
               (:file "src/spatial5")
               (:file "src/inspect")
               (:file "src/delete")
               (:file "src/undo")
               (:file "src/main")
               (:file "src/rel-copy2")
               (:file "src/concepts")
               (:file "src/delta2")
               (:file "src/init2")
               (:file "gened-main")))

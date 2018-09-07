#!/usr/bin/env sh
# -*- wisp -*-
exec guile -L $(dirname $(dirname $(realpath "$0"))) --language=wisp -x .w -e '(examples downloadmesh)' -s "$0" "$@"
; !#

;;; downloadmesh --- multi-source swarming downloads via HTTP

;; This follows the Gnutella download mesh, and adds a parity option
;; to compensate variable upload speeds by clients.

define-module : examples downloadmesh
              . #:export : main

import
    only (srfi srfi-27) random-source-make-integers
      . make-random-source random-source-randomize!
    only (srfi srfi-1) first second third iota
    srfi srfi-11 ;; let-values
    srfi srfi-42
    ice-9 optargs
    ice-9 format
    ice-9 match
    ice-9 threads
    ice-9 pretty-print
    fibers web server


define : download-file url
    pretty-print url

define : server-file-download-handler request body
    values '((content-type . (text-plain)))
           . "Hello World!"

define : serve folder-path
    pretty-print folder-path
    run-server server-file-download-handler #:port 8083 ;; #:addr INADDR_ANY

define : help args
       format #t "Usage: ~a [options]

Options:
   [link [link ...]] download file(s)
   --serve <folder>  serve the files in FOLDER
   --help            show this message
" : first args

define : main args
 let : : arguments : cdr args
   cond
     : or (null? arguments) (member "--help" arguments) (member "-h" arguments)
       help args
     : and {(length arguments) > 1} : equal? "--server" : car arguments
       serve : second arguments
     else
       par-map download-file arguments


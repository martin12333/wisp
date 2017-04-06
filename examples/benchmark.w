#!/usr/bin/env sh
# -*- wisp -*-
exec guile -L $(dirname $(dirname $(realpath "$0"))) --language=wisp -e '(@@ (examples benchmark) main)' -l $(dirname $(realpath "$0"))/cholesky.w -l $(dirname $(realpath "$0"))/ensemble-estimation.w -s "$0" "$@"
; !#

define-module : examples benchmark

import : statprof
         ice-9 optargs
         ice-9 format
         srfi srfi-1
         srfi srfi-42 ; list-ec
         srfi srfi-43 ; vector-append
         ice-9 pretty-print
         system vm program



;; stddev from rosetta code: http://rosettacode.org/wiki/Standard_deviation#Scheme
define : stddev nums
    sqrt
        -
            / : apply + : map (lambda (i) (* i i)) nums
                length nums
            expt (/ (apply + nums) (length nums)) 2


define : stddev-unbiased-normal nums
    . "Approximated unbiased standard deviation for the normal distribution

    'for n = 3 the bias is equal to 1.3%, and for n = 9 the bias is already less than 0.1%.'
     - https://en.wikipedia.org/wiki/Standard_deviation#Unbiased_sample_standard_deviation
    "
    sqrt
        -
            / : apply + : map (lambda (i) (* i i)) nums
                - (length nums) 1.5
            expt (/ (apply + nums) (length nums)) 2


define : running-stddev nums
  define : running-stddev-2 num
      set! nums : cons num nums
      stddev nums
  . running-stddev-2

define* : benchmark-run-single fun #:key (min-seconds 0.1)
  ;; trigger garbage collection before stats collection to avoid polluting the data
  gc
  let profiler : (loop-num 4)
    let : : t : get-internal-real-time
      with-output-to-string
        lambda ()
          let lp : (i loop-num)
            : λ () : fun
            when (> i 0)
              lp (- i 1)
      let*
        : dt : - (get-internal-real-time) t
          seconds : / (exact->inexact dt) internal-time-units-per-second
        ;; pretty-print : list dt seconds loop-num
        if {seconds > min-seconds}
            /  seconds loop-num ;; this wastes less than {(4 * ((4^(i-1)) - 1)) / 4^i} fractional data but gains big in simplicity
            profiler (* 4 loop-num) ;; for fast functions I need to go up rapidly, for slow ones I need to avoid overshooting

;; Define targets for the data aquisition
define max-relative-uncertainty 0.3 ;; 3 sigma from 0
define max-absolute-uncertainty-seconds 1.e-3 ;; 1ms, required to ensure that the model uses the higher values (else they would have huge uncertainties). If you find you need more, use a smaller test case.
define min-aggregated-runtime-seconds 1.e-5 ;; 10μs ~ 30k cycles
define max-iterations 128 ;; at most 128 samples, currently corresponding to at least 1ms each, so a benchmark of a fast function should take at most 0.1 seconds.

define* : benchmark-run fun
    ;; pretty-print fun
    let lp : (min-seconds min-aggregated-runtime-seconds) (sampling-steps 4) ;; start with at least 3 sampling steps to make the approximations in stddev-unbiased-normal good enough
        let*
          : res : list-ec (: i sampling-steps) : benchmark-run-single fun #:min-seconds min-seconds
            std : stddev-unbiased-normal res
            mean : / (apply + res) sampling-steps
           ;; pretty-print : list mean '± std min-seconds sampling-steps
           if : or {sampling-steps > max-iterations} : and {std < {mean * max-relative-uncertainty}} {std < max-absolute-uncertainty-seconds}
              . mean
              lp (* 2 min-seconds) (* 2 sampling-steps) ;; should decrease σ by factor 2 or √2 (for slow functions)

define loopcost
  benchmark-run (λ() #f)


;; TODO: Simplify #:key setup -> . setup
define* : benchmark-fun fun #:key setup
  when setup
    setup
  - : benchmark-run fun
    . loopcost

define-syntax benchmark
  ;; one single benchmark
  lambda : x
    syntax-case x (:let :setup)
      : _ thunk :setup setup-thunk :let let-thunk args ...
        #' benchmark thunk :let let-thunk :setup setup-thunk args ... 
      : _ thunk :let let-thunk :setup setup-thunk args ...
        #' benchmark thunk :let let-thunk #:setup (lambda () setup-thunk) args ... 
      : _ thunk :setup setup-thunk args ...
        #' benchmark thunk #:setup (lambda () setup-thunk) args ... 
      : _ thunk :let let-thunk args ...
        #' let let-thunk
           benchmark thunk args ... 
      : _ thunk args ...
        #' benchmark-fun
         . (lambda () thunk) args ...

define : logiota steps start stepsize
    . "Create numbers evenly spread in log space"
    let*
        : logstart : log (+ start 1)
          logstep : / (- (log (+ start (* stepsize (- steps 1)))) logstart) (- steps 1)
        map inexact->exact : map round : map exp : iota steps logstart logstep 


;; interesting functions to benchmark:
;; - TODO: add to set/alist/hashmap
;; - TODO: retrieve from alist/hashmap
;; - TODO: sort
;; - ... see https://wiki.python.org/moin/TimeComplexity

;; operation benchmarks
;; - TODO: or #f #t
;; - TODO: and #t #f

;; List benchmarks:
;; - TODO: list-copy (py-copy)
;; - cons (py-push / py-append)
;; - car (py-pop)
;; - list-ref (py-get-item)
;; - TODO: list-set! (py-set-item)
;; - TODO: take + drop (py-get-slice)
;; - TODO: take-right + drop-right (py-get-slice)
;; - TODO: last
;; - TODO: append (py-extend)
;; - TODO: delete (py-delete-item)
;; - TODO: min (py-min)
;; - TODO: max (py-max)
;; - TODO: member (py-in)
;; - TODO: reverse (py-reversed)
;; - TODO: length (py-len)
define : bench-append param-list
  . "Test (append a b) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (append a b) :let ((a (iota N))(b (iota m)))
  zip param-list : map f param-list

define : bench-ref param-list
  . "Test (list-ref a b) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (list-ref a b) :let ((a (iota (max N m)))(b (- m 1)))
  zip param-list : map f param-list

define : bench-car param-list
  . "Test (coar a b) with element A and list B of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0))
            benchmark (car b) :let ((b (iota N)))
  zip param-list : map f param-list

define : bench-cdr param-list
  . "Test (cdr a b) with element A and list B of lengths from the param-list (note: this is really, really fast)."
  define : f x
     let : (N (list-ref x 0))
            benchmark (cdr b) :let ((b (iota N)))
  zip param-list : map f param-list

define : bench-sort param-list
  . "Test (sort a <) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0))
            benchmark (sort a <) :let ((a (iota N)))
  zip param-list : map f param-list

define : bench-cons param-list
  . "Test (cons a b) with element A and list B of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (cons b a) :let ((a (iota N))(b m))
  zip param-list : map f param-list

define : bench-copy param-list
  . "Test (cons a b) with element A and list B of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0))
            benchmark (list-copy a) :let ((a (iota N)))
  zip param-list : map f param-list

define : bench-set param-list
  . "Test (cons a b) with element A and list B of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (list-set! a b) :let ((a (iota N))(b m))
  zip param-list : map f param-list


;; VList benchmarks


;; String benchmarks
define : bench-append-string param-list
  . "Test (string-append a b) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (string-append a b) :let ((a (make-string N))(b (make-string m)))
  zip param-list : map f param-list

;; Vector benchmarks
define : bench-append-vector param-list
  . "Test (vector-append a b) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (vector-append a b) :let ((a (make-vector N 1))(b (make-vector m 1)))
  zip param-list : map f param-list

;; Map/set benchmarks
define : bench-assoc param-list
  . "Test (assoc a b) with lists of lengths from the param-list."
  define : f x
     let : (N (list-ref x 0)) (m (list-ref x 1))
            benchmark (assoc a b) :let ((a m)(b (reverse (fold (λ (x y z) (acons x y z)) '() (iota N 1) (iota N 1)))))
  zip param-list : map f param-list


;; prepare a multi-function fit
import 
    only : examples ensemble-estimation
         . EnSRF make-covariance-matrix-with-offdiagonals-using-stds 
         . standard-deviation-from-deviations x-deviations->y-deviations
         . x^steps
    only : ice-9 popen
         . open-output-pipe close-pipe

define-syntax-rule : or0 test c ...
    if test : begin c ...
            . 0

define-syntax-rule : define-quoted sym val
    ;; set the value to true using eval to break the symbol->variable barrier
    primitive-eval `(define ,sym val)

define* 
       H-N-m x pos #:key all const OlogN OsqrtN ON ONlogN ON²
                                 . Ologm Osqrtm Om Omlogm Om²
                                 . OlogNm ONlogm OmlogN ONm
                                 . ON²m Om²N
       . "Observation operator. It generates modelled observations from the input.

x are parameters to be optimized, pos is another input which is not optimized. For plain functions it could be the position of the measurement on the x-axis. We currently assume absolute knowledge about the position.
"
       when all
           let lp : (l '(const OlogN OsqrtN ON ONlogN ON² Ologm Osqrtm Om Omlogm Om² OlogNm ONlogm OmlogN ONm ON²m Om²N))
               when : not : null? l
                      define-quoted (car l) #t
                      lp : cdr l
       
       let : (N (first pos)) (m (second pos))
           +
             or0 const : list-ref x 0 ; constant value
             ;; pure N
             or0 OlogN  : * (list-ref x 1) : log (+ 1 N) ; avoid breakage at pos 0
             or0 OsqrtN : * (list-ref x 2) : sqrt N
             or0 ON     : * (list-ref x 3) N
             or0 ONlogN : * (list-ref x 4) : * N : log (+ 1 N)
             or0 ON²    : * (list-ref x 5) : expt N 2
             ;; pure m
             or0 Ologm  : * (list-ref x 6) : log (+ 1 m) ; avoid breakage at pos 0
             or0 Osqrtm : * (list-ref x 7) : sqrt m
             or0 Om     : * (list-ref x 8) m
             or0 Omlogm : * (list-ref x 9) : * m : log (+ 1 m)
             or0 Om²    : * (list-ref x 10) : expt m 2
             ;; mixed terms
             or0 OlogNm : * (list-ref x 11) : log (+ 1 N m)
             or0 ONlogm : * (list-ref x 12) : * N : log (+ 1 m)
             or0 OmlogN : * (list-ref x 13) : * m : log (+ 1 N)
             or0 ONm    : * (list-ref x 14) : * N m
             or0 ON²m   : * (list-ref x 15) : * (expt N 2) m
             or0 Om²N   : * (list-ref x 16) : * (expt m 2) N


define : interleave lx lz
  cond
    (null? lx) lz
    else
      cons : car lx
             interleave lz : cdr lx


define : print-fit x σ
    . "Print the big-O parameters which are larger than σ (their standard deviation)."
    let : : number-format "~,1,,,,,'ee±~,1,,,,,'ee"
      let big-O
        : names : list "" "log(N)" "sqrt(N)" "N log(N)" "N^2" "log(m)" "sqrt(m)" "m" "m log(m)" "m^2" "log(N + m)" "N log(m)" "m log(N)" "N m" "N^2 m" "m^2 N"
          x x
          σ σ
        cond
          : or (null? names) (null? x) (null? σ)
            newline
          : > (abs (car x)) (car σ)
            format #t : string-append number-format " " (car names) "  "
                      . (car x) (car σ)
            big-O (cdr names) (cdr x) (cdr σ)
          else
            big-O (cdr names) (cdr x) (cdr σ)


define : flatten li
         append-ec (: i li) i

;; TODO: add filename and title and fix the units
define* : plot-benchmark-result bench H #:key filename title
     let*
        : ensemble-member-count 32
          ensemble-member-plot-skip 8 ;; must not be zero!
          iterations 4
          y_0 : apply min : map car : map cdr bench
          y_m : * 0.25 : apply max : map car : map cdr bench
          nb : apply max : interleave (map car (map car bench)) (map car (map cdr (map car bench)))
          ;; "const" "log(N)" "sqrt(N)" "N" "N^2" "N^3" "log(m)" "sqrt(m)" "m" "m^2" "m^3" "log(N + m)" "N log(m)" "m log(N)" "N m" "N^2 m" "m^2 N"
          x^b : list y_0 (/ y_m (log nb)) (/ y_m (sqrt nb)) (/ y_m nb) (/ y_m nb nb) (/ y_m nb nb nb) (/ y_m (log nb)) (/ y_m (sqrt nb)) (/ y_m nb) (/ y_m nb nb) (/ y_m nb nb nb) (/ y_m nb nb) (/ y_m nb nb) (/ y_m nb nb nb) (/ y_m nb nb nb) (/ y_m nb nb nb nb) (/ y_m nb nb nb nb)  ; inital guess: constant starting at the first result
          x^b-std : list-ec (: i x^b) (* 2 i) ; inital guess: 200% uncertainty
          P : make-covariance-matrix-with-offdiagonals-using-stds x^b-std
          y⁰-pos : map car bench
          y⁰ : append-map cdr bench
          ;; several iterations to better cope with non-linearity, following http://journals.ametsoc.org/doi/abs/10.1175/MWR-D-11-00176.1 (but globally)
          y⁰-stds : list-ec (: i y⁰) : * (sqrt iterations) : min max-absolute-uncertainty-seconds {max-relative-uncertainty * i} ; enforcing 20% max std in benchmark-run
          R : make-covariance-matrix-with-offdiagonals-using-stds y⁰-stds
          optimized ;; iterate N times
              let lp : (N iterations) (x^b x^b) (P P)
                  let : : optimized : EnSRF H x^b P y⁰ R y⁰-pos ensemble-member-count
                      cond
                         : <= N 1
                            . optimized
                         else
                            let*
                              : x-opt : list-ref optimized 0
                                x-deviations : list-ref optimized 1
                                x-std ;; re-create the ensemble with the new std
                                    list-ec (: i (length x-opt))
                                        apply standard-deviation-from-deviations
                                            list-ec (: j x-deviations) : list-ref j i
                                P : make-covariance-matrix-with-offdiagonals-using-stds x-std
                              lp (- N 1) x-opt P
          x-opt : list-ref optimized 0
          x-deviations : list-ref optimized 1
          x-std 
                list-ec (: i (length x-opt))
                      apply standard-deviation-from-deviations : list-ec (: j x-deviations) : list-ref j i
          y-deviations : x-deviations->y-deviations H x-opt x-deviations y⁰-pos
          y-stds : list-ec (: i y-deviations) : apply standard-deviation-from-deviations i
          y-opt : map (λ (x) (H x-opt x)) y⁰-pos
          x^b-deviations-approx
              list-ec (: i ensemble-member-count)
                   list-ec (: j (length x^b))
                       * : random:normal
                           sqrt : list-ref (list-ref P j) j ; only for diagonal P!
          y^b-deviations : x-deviations->y-deviations H x^b x^b-deviations-approx y⁰-pos
          y-std
             apply standard-deviation-from-deviations
                flatten y-deviations
          y-stds : list-ec (: i y-deviations) : apply standard-deviation-from-deviations i
          y^b-stds : list-ec (: i y^b-deviations) : apply standard-deviation-from-deviations i
 
        ;; print-fit x-std
        when title
            display title
            newline
        print-fit x-opt x-std
        ;; TODO: minimize y-mismatch * y-uncertainty
        format #t "Model standard deviation (uncertainty): ~,4e\n" y-std
        ; now plot the result
        let : : port : open-output-pipe "python2"
          format port "import pylab as pl\nimport matplotlib as mpl\n"
          format port "y0 = [float(i) for i in '~A'[1:-1].split(' ')]\n" y⁰
          format port "ystds = [float(i) for i in '~A'[1:-1].split(' ')]\n" y⁰-stds
          format port "ypos1 = [float(i) for i in '~A'[1:-1].split(' ')]\n" : list-ec (: i y⁰-pos) : first i
          format port "ypos2 = [float(i) for i in '~A'[1:-1].split(' ')]\n" : list-ec (: i y⁰-pos) : second i
          format port "yinit = [float(i) for i in '~A'[1:-1].split(' ')]\n" : list-ec (: i y⁰-pos) : H x^b i
          format port "yinitstds = [float(i) for i in '~A'[1:-1].split(' ')]\n" y^b-stds
          format port "yopt = [float(i) for i in '~A'[1:-1].split(' ')]\n" : list-ec (: i y⁰-pos) : H x-opt i
          format port "yoptstds = [float(i) for i in '~A'[1:-1].split(' ')]\n" y-stds
          ;; format port "pl.errorbar(*zip(*sorted(zip(ypos1, yinit))), yerr=zip(*sorted(zip(ypos1, yinitstds)))[1], label='prior vs N')\n"
          format port "pl.errorbar(*zip(*sorted(zip(ypos1, yopt))), yerr=zip(*sorted(zip(ypos1, yoptstds)))[1], marker='H', mew=1, ms=10, linewidth=0.1, label='optimized vs N')\n"
          format port "eb=pl.errorbar(*zip(*sorted(zip(ypos1, y0))), yerr=ystds, alpha=0.6, marker='x', mew=2, ms=10, linewidth=0, label='measurements vs N')\neb[-1][0].set_linewidth(1)\n"
          ;; format port "pl.errorbar(*zip(*sorted(zip(ypos2, yinit))), yerr=zip(*sorted(zip(ypos2, yinitstds)))[1], label='prior vs. m')\n"
          format port "pl.errorbar(*zip(*sorted(zip(ypos2, yopt))), yerr=zip(*sorted(zip(ypos2, yoptstds)))[1], marker='h', mew=0, ms=10, linewidth=0.1, label='optimized vs. m')\n"
          format port "eb=pl.errorbar(*zip(*sorted(zip(ypos2, y0))), yerr=ystds, alpha=0.6, marker='x', mew=2, ms=10, linewidth=0, label='measurements vs. m')\neb[-1][0].set_linewidth(1)\n"
          format port "pl.plot(sorted(ypos1+ypos2), pl.log(sorted(ypos1+ypos2))*(max(y0) / pl.log(max(ypos1+ypos2))), label='log(x)')\n"
          format port "pl.plot(sorted(ypos1+ypos2), pl.sqrt(sorted(ypos1+ypos2))*(max(y0) / pl.sqrt(max(ypos1+ypos2))), label='sqrt(x)')\n"
          format port "pl.plot(sorted(ypos1+ypos2), pl.multiply(sorted(ypos1+ypos2), max(y0) / max(ypos1+ypos2)), label='x')\n"
          list-ec (: step 0 (length x^steps) 4)
               let : : members : list-ref x^steps (- (length x^steps) step 1)
                  list-ec (: member-idx 0 (length members) ensemble-member-plot-skip) ; reversed
                     let : : member : list-ref members member-idx
                       format port "paired = pl.get_cmap('Paired')
cNorm = mpl.colors.Normalize(vmin=~A, vmax=~A)
scalarMap = mpl.cm.ScalarMappable(norm=cNorm, cmap=paired)\n" 0 (length member)
                       list-ec (: param-idx 0 (length member) 4) ; step = 4
                          ;; plot parameter 0
                          let : (offset (/ (apply max (append y⁰ y-opt)) 2)) (spreading (/ (apply max (append y⁰ y-opt)) (- (apply max member) (apply min member)) 2))
                              format port "pl.plot(~A, ~A, marker='.', color=scalarMap.to_rgba(~A), linewidth=0, label='', alpha=0.6, zorder=-1)\n"
                                          . (/ step 1) (+ offset (* spreading (list-ref member param-idx))) param-idx
          format port "pl.legend(loc='upper left', fancybox=True, framealpha=0.5)\n"
          format port "pl.xlabel('position / arbitrary units')\n"
          format port "pl.ylabel('time / s')\n"
          format port "pl.title('''~A''')\n" : or title "Operation scaling behaviour"
          format port "pl.xscale('log')\n"
          ;; format port "pl.yscale('log')\n"
          if filename
              format port "pl.savefig('~A', bbox_inches='tight')\n" filename
              format port "pl.show()\n"
          format port "exit()\n"
          close-pipe port


define : main args
   let*
      : H : lambda (x pos) (H-N-m x pos #:const #t #:ON #t #:ONlogN #t #:OlogN #:Ologm #:Om #:Omlogm)
        steps 50
        pbr plot-benchmark-result
      let lp
        : N-start '(1    1    1    100)
          N-step  '(1000 1000 0    0)
          m-start '(1    100  1    1)
          m-step  '(0    0    1000 1000)
        cond
          : null? N-start
            . #t
          else
            let*
              : N : car N-start
                dN : car N-step
                m : car m-start
                dm : car m-step
                param-list : zip (logiota steps N dN) (logiota steps m dm)
              define : title description
                  string-append description
                    format #f ", ~a ~a"
                      if (equal? dN 0) N "N"
                      if (equal? dm 0) m "m"
              define : filename identifier
                  format #f "/tmp/benchmark-~a-~a-~a.png"
                      . identifier
                      if (equal? dN 0) N "N"
                      if (equal? dm 0) m "m"
              pbr (bench-ref param-list) H
                  . #:title : title "list-ref (iota (max m N)) (- m 1)"
                  . #:filename : filename "list-ref"
              when : equal? dm 0 ;; only over N
                  pbr (bench-car param-list) H
                      . #:title : title "car (iota N)"
                      . #:filename : filename "car"
                  pbr (bench-cdr param-list) H
                      . #:title : title "cdr (iota N)"
                      . #:filename : filename "cdr"
                  pbr (bench-sort param-list) H
                      . #:title : title "sort (iota N)"
                      . #:filename : filename "sort"
              pbr (bench-append param-list) H
                  . #:title : title "append (iota N) (iota m)"
                  . #:filename : filename "list-append"
              pbr (bench-append-string param-list) H
                  . #:title : title "string-append (make-string N) (make-string m)"
                  . #:filename : filename "string-append"
              pbr (bench-append-vector param-list) H
                  . #:title : title "vector-append (make-vector N 1) (make-vector m 1)"
                  . #:filename : filename "vector-append"
              pbr (bench-assoc param-list) H 
                  . #:title : title "assoc m '((1 . 1) (2 . 2) ... (N . N))"
                  . #:filename : filename "assoc"
              pbr (bench-cons param-list) H
                  . #:title : title "cons m (iota N)"
                  . #:filename : filename "cons"
            lp
                cdr N-start
                cdr N-step
                cdr m-start
                cdr m-step

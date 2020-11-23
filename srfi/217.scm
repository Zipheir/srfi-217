;;; Copyright (C) 2020 Wolfgang Corcoran-Mathe
;;;
;;; Permission is hereby granted, free of charge, to any person obtaining a
;;; copy of this software and associated documentation files (the
;;; "Software"), to deal in the Software without restriction, including
;;; without limitation the rights to use, copy, modify, merge, publish,
;;; distribute, sublicense, and/or sell copies of the Software, and to
;;; permit persons to whom the Software is furnished to do so, subject to
;;; the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be included
;;; in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
;;; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;;; IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;;; CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;;; TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(define-record-type <iset>
  (raw-iset trie)
  iset?
  (trie iset-trie))

;;;; Constructors

(define (iset . args)
  (list->iset args))

(define (list->iset ns)
  (raw-iset
   (fold (lambda (n t)
           (assume (valid-integer? n))
           (trie-insert t n))
         #f
         ns)))

(define (iset-unfold stop? mapper successor seed)
  (assume (procedure? stop?))
  (assume (procedure? mapper))
  (assume (procedure? successor))
  (let lp ((trie #f) (seed seed))
    (if (stop? seed)
        (raw-iset trie)
        (let ((n (mapper seed)))
          (assume (valid-integer? n))
          (lp (trie-insert trie n) (successor seed))))))

;; TODO: Bitmap compression will enable a much more efficient version
;; of this.
(define (make-iset-range low high)
  (assume (valid-integer? low))
  (assume (valid-integer? high))
  (assume (>= high low))
  (iset-unfold (lambda (i) (= i high))
               values
               (lambda (i) (+ i 1))
               low))

;;;; Predicates

(define (iset-contains? set n)
  (assume (iset? set))
  (assume (valid-integer? n))
  (trie-contains? (iset-trie set) n))

(define (iset-empty? set)
  (assume (iset? set))
  (not (iset-trie set)))

(define (iset-disjoint? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (trie-disjoint? (iset-trie set1) (iset-trie set2)))

;;;; Accessors

(define (iset-member set elt default)
  (if (iset-contains? set elt)
      elt
      default))

(define (iset-min set)
  (assume (iset? set))
  (let ((trie (iset-trie set)))
    (if (branch? trie)
        (%trie-find-leftmost
         (if (negative? (branch-branching-bit trie))
             (branch-right trie)
             (branch-left trie)))
        trie)))  ; #f or leaf

(define (iset-max set)
  (assume (iset? set))
  (let ((trie (iset-trie set)))
    (if (branch? trie)
        (%trie-find-rightmost
         (if (negative? (branch-branching-bit trie))
             (branch-left trie)
             (branch-right trie)))
        trie)))  ; #f or leaf

;;;; Updaters

;; FIXME: Not in the pre-SRFI, but should be added.
(define (iset-adjoin set n)
  (assume (iset? set))
  (assume (valid-integer? n))
  (raw-iset (trie-insert (iset-trie set) n)))

(define (iset-adjoin! set n) (iset-adjoin set n))

(define (iset-delete set n)
  (assume (iset? set))
  (assume (valid-integer? n))
  (raw-iset (trie-delete (iset-trie set) n)))

(define (iset-delete! set n) (iset-delete set n))

;; FIXME: Not in the pre-SRFI, but should be added.
;; Implement this in terms of set difference?
(define (iset-delete-all set ns)
  (assume (iset? set))
  (assume (or (pair? ns) (null? ns)))
  (raw-iset (trie-remove (lambda (m) (member m ns fx=?))
                         (iset-trie set))))

(define (iset-delete-all! set ns)
  (iset-delete-all set ns))

;;;; The whole iset

(define (iset-size set)
  (assume (iset? set))
  (let lp ((acc 0) (t (iset-trie set)))
    (cond ((not t) acc)
          ((integer? t) (+ acc 1))
          (else
           (lp (lp acc (branch-left t)) (branch-right t))))))

(define (iset-count pred set)
  (assume (procedure? pred))
  (iset-fold (lambda (n acc)
               (if (pred n) (+ 1 acc) acc))
             0
             set))

(define (iset-any? pred set)
  (assume (procedure? pred))
  (call-with-current-continuation
   (lambda (return)
     (iset-fold (lambda (n _)
                  (and (pred n) (return #t)))
                #f
                set))))

(define (iset-every? pred set)
  (assume (procedure? pred))
  (call-with-current-continuation
   (lambda (return)
     (iset-fold (lambda (n _)
                  (or (pred n) (return #f)))
                #t
                set))))

;;;; Mapping and folding

(define (iset-map proc set)
  (assume (procedure? proc))
  (raw-iset
   (iset-fold (lambda (n t)
                (let ((n* (proc n)))
                  (assume (valid-integer? n*))
                  (trie-insert t (proc n))))
              #f
              set)))

(define (unspecified)
  (if #f #f))

(define (iset-for-each proc set)
  (assume (procedure? proc))
  (iset-fold (lambda (n _)
               (proc n)
               (unspecified))
             (unspecified)
             set))

(define (iset-fold proc nil set)
  (assume (procedure? proc))
  (assume (iset? set))
  (letrec
   ((cata
     (lambda (b t)
       (cond ((not t) b)
             ((integer? t) (proc t b))
             (else
              (cata (cata b (branch-left t)) (branch-right t)))))))
    (let ((trie (iset-trie set)))
      (if (branch? trie)
          (if (negative? (branch-branching-bit trie))
              (cata (cata nil (branch-left trie)) (branch-right trie))
              (cata (cata nil (branch-right trie)) (branch-left trie)))
          (cata nil trie)))))

(define (iset-filter pred set)
  (assume (procedure? pred))
  (assume (iset? set))
  (raw-iset (trie-filter pred (iset-trie set))))

(define (iset-remove pred set)
  (assume (procedure? pred))
  (assume (iset? set))
  (raw-iset (trie-filter (lambda (n) (not (pred n))) (iset-trie set))))

;;;; Copying and conversion

(define (iset-copy set)
  (assume (iset? set))
  (raw-iset (copy-trie (iset-trie set))))

(define (iset->list set)
  (iset-fold cons '() set))

;;;; Comparison

(define (iset=? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (or (eqv? set1 set2)         ; quick check
      (trie=? (iset-trie set1) (iset-trie set2))))

(define (iset<? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (trie-proper-subset? (iset-trie set1) (iset-trie set2)))

(define (iset>? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (trie-proper-subset? (iset-trie set2) (iset-trie set1)))

(define (iset<=? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (and (memv (trie-subset-compare (iset-trie set1) (iset-trie set2))
             '(less equal))
       #t))

(define (iset>=? set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (and (memv (trie-subset-compare (iset-trie set1) (iset-trie set2))
             '(greater equal))
       #t))

;;;; Set theory operations

(define (iset-union set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (raw-iset (trie-merge trie-insert (iset-trie set1) (iset-trie set2))))

(define (iset-union! set1 set2) (iset-union set1 set2))

(define (iset-intersection set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (raw-iset (trie-intersection (iset-trie set1) (iset-trie set2))))

(define (iset-intersection! set1 set2) (iset-intersection set1 set2))

(define (iset-difference set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (raw-iset (trie-difference (iset-trie set1) (iset-trie set2))))

(define (iset-difference! set1 set2) (iset-difference set1 set2))

(define (iset-xor set1 set2)
  (assume (iset? set1))
  (assume (iset? set2))
  (if (eqv? set1 set2)  ; quick check
      (iset)
      (raw-iset
       (trie-merge trie-xor-insert (iset-trie set1) (iset-trie set2)))))

(define (iset-xor! set1 set2) (iset-xor set1 set2))

;;;; Subsets

(define (iset-range= set k)
  (if (iset-contains? set k) (iset k) (iset)))

;;; FIXME: The following procedures are implemented trivially in terms
;;; of iset-filter.  Better versions to come.

(define (iset-open-interval set low high)
  (assume (valid-integer? low))
  (assume (valid-integer? high))
  (assume (fx>=? high low))
  (raw-iset (subtrie-interval (iset-trie set) low high #f #f)))

(define (iset-closed-interval set low high)
  (assume (valid-integer? low))
  (assume (valid-integer? high))
  (assume (fx>=? high low))
  (raw-iset (subtrie-interval (iset-trie set) low high #t #t)))

(define (iset-open-closed-interval set low high)
  (assume (valid-integer? low))
  (assume (valid-integer? high))
  (assume (fx>=? high low))
  (raw-iset (subtrie-interval (iset-trie set) low high #f #t)))

(define (iset-closed-open-interval set low high)
  (assume (valid-integer? low))
  (assume (valid-integer? high))
  (assume (fx>=? high low))
  (raw-iset (subtrie-interval (iset-trie set) low high #t #f)))

(define (iset-range< set k)
  (assume (iset? set))
  (assume (valid-integer? k))
  (raw-iset (subtrie< (iset-trie set) k #f)))

(define (iset-range<= set k)
  (assume (iset? set))
  (assume (valid-integer? k))
  (raw-iset (subtrie< (iset-trie set) k #t)))

(define (iset-range> set k)
  (assume (iset? set))
  (assume (valid-integer? k))
  (raw-iset (subtrie> (iset-trie set) k #f)))

(define (iset-range>= set k)
  (assume (iset? set))
  (assume (valid-integer? k))
  (raw-iset (subtrie> (iset-trie set) k #t)))

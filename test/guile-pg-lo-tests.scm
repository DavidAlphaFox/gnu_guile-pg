;;    Guile-pg - A Guile interface to PostgreSQL
;;    Copyright (C) 1999-2000, 2002 Free Software Foundation, Inc.
;;
;;    This program is free software; you can redistribute it and/or modify
;;    it under the terms of the GNU General Public License as published by
;;    the Free Software Foundation; either version 2 of the License, or
;;    (at your option) any later version.
;;
;;    This program is distributed in the hope that it will be useful,
;;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;    GNU General Public License for more details.
;;
;;    You should have received a copy of the GNU General Public License
;;    along with this program; if not, write to the Free Software
;;    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
;;
;;    Guile-pg was written by Ian Grant <Ian.Grant@cl.cam.ac.uk>

(use-modules (database postgres))

;; Define some basic procedures

;; pg-exec-cmd CONN
;; Execute a command on CONN, return #t if OK, #f otherwise
(define (pg-exec-cmd conn sql)
  (let ((res (pg-exec conn sql)))
    (and res (eq? 'PGRES_COMMAND_OK (pg-result-status res)))))

;; pg-transaction CONN PROC ARGS
;; Return the result of evaluating PROC with arguments (cons CONN ARGS)
;;   within a postgres transaction, or #f in the event of an error
(define (pg-transaction conn proc . args)
  (and (pg-exec-cmd conn "BEGIN TRANSACTION")
       (let* ((res-apply (apply proc (cons conn args)))
              (res-end (pg-exec-cmd conn "END TRANSACTION")))
         (and res-end res-apply))))

;; eval-port PORT
;; Like (eval-string) but reads from PORT
(define (eval-port port)
  (define (iter result)
    (let ((form (read port)))
      (if (eof-object? form)
          result
          (iter (eval form)))))
  (iter #f))

;; We want to keep one connection hanging around for the duration of all the
;; tests

(define conn #f)

;; We also want to keep track of the OID
(define oid #f)

;; Test pg-connectdb
;; expect #t
(define (test:make-connection)
  (->bool (false-if-exception (set! conn (pg-connectdb "")))))

;; Test pg-exec
;; expect #f
(define (test:make-table)
  (pg-exec-cmd conn "CREATE TABLE test (col1 int4, col2 oid)"))

;; Tests nothing
;; expect a longish string containing valid scheme
(define test:data '("
;; This is a data file for use by guile-pg-lo-tests.scm
;;   it will be imported to a large onject and then
;;   evaluated directly from the large object

'(testing testing one two three)

;; End of test data"))

;; Tests nothing
;; expect #t
(define (test:make-data)
  (let ((fport (open-file "lo-tests-data-1" "w")))
    (and fport
         (begin
           (for-each (lambda (string) (write-line string fport)) test:data)
           (close-port fport)))))

;; Test pg-lo-import
;; expect #t
(define (test:lo-import)
  (and (pg-transaction conn
         (lambda (conn)
           (set! oid (pg-lo-import conn "lo-tests-data-1"))))
       (->bool oid)))

;; Test pg-lo-export
;; expect #t
(define (test:lo-export)
  (false-if-exception (delete-file "lo-tests-data-2"))
  (pg-transaction conn
    (lambda (conn)
      (and (pg-lo-export conn oid "lo-tests-data-2")
           (eq? 0 (system (format #f "~A ~A ~A >/dev/null 2>&1"
                                  *DIFF-PATH*
                                  "lo-tests-data-1"
                                  "lo-tests-data-2")))))))

;; Test pg-lo-open-read
;; expect #t
(define (test:lo-open-read)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-open conn oid "r")))
        (and lo-port
             (eq? conn (pg-lo-get-connection lo-port))
             (equal? (eval-port lo-port) '(testing testing one two three))
             (close-port lo-port))))))

;; Test pg-lo-creat
;; expect #t

(define nchars 100)
(define new-oid #f)

(define (write-chars n c lop)
  (do ((i 0 (1+ i)))
      ((= i n) #t)
    (write-char c lop)))

(define (test:lo-creat)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-creat conn "w")))
        (and lo-port
             (write-chars nchars #\a lo-port)
             (set! new-oid (pg-lo-get-oid lo-port))
             (close-port lo-port))))))

;; Test pg-lo-read
;; expect #t

(define (test:lo-read)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-open conn new-oid "r"))
            (data #f))
        (and lo-port
             (set! data (pg-lo-read 1 nchars lo-port))
             (close-port lo-port)
             (equal? data (make-string nchars #\a)))))))

;; Test read-line
;; expect #t

(define (test:read-line)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-open conn new-oid "r"))
            (data #f))
        (and lo-port
             (set! data (read-line lo-port))
             (close-port lo-port)
             (equal? data (make-string nchars #\a)))))))

;; Test pg-lo-seek
;; expect #t

(define (test:lo-seek)
  (pg-transaction conn
    (lambda (conn)
      (let* ((trace-port (open-file "test-lo-seek.log" "w"))
             (lo-port (pg-lo-open conn new-oid "w")))
        (and (pg-trace conn trace-port)
             lo-port
             (eq? (pg-lo-seek lo-port 1 SEEK_SET) 1)
             (write-char #\b lo-port)
             (force-output lo-port)
             (eq? (pg-lo-seek lo-port 3 SEEK_SET) 3)
             (write-char #\b lo-port)
             (force-output lo-port)
             (eq? (pg-lo-seek lo-port 0 SEEK_SET) 0)
             (close-port lo-port)
             (pg-untrace conn)
             (close-port trace-port))))))

;; Test pg-lo-seek pg-lo-read
;; expect "ababaa"

(define (test:lo-seek2)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-open conn new-oid "r"))
            (data #f))
        (and lo-port
             (set! data (pg-lo-read 1 6 lo-port))
             (close-port lo-port)
             data)))))

;; Test pg-lo-tell
;; expect #t

(define (test:lo-tell)
  (pg-transaction conn
    (lambda (conn)
      (let ((lo-port (pg-lo-open conn new-oid "r")))
        (and lo-port
             (eq? 0 (pg-lo-tell lo-port))
             (let ((data (pg-lo-read 1 1 lo-port)))
               (and (string? data)
                    (= 1 (string-length data))
                    (string=? "a" data)))
             (let ((location-after-read (pg-lo-tell lo-port)))
               (eq? 1 (pg-lo-seek lo-port 0 SEEK_CUR))
               (close-port lo-port)
               (eq? 1 location-after-read)))))))

(load-from-path (string-append *srcdir* "/testing.scm"))
(set! verbose #t)
(test-init "lo-tests" 13)
(test *VERSION* pg-guile-pg-version)
(test #t test:make-connection)
(test #t test:make-data)
(test #t test:make-table)
(test #t test:lo-import)
(test #t test:lo-export)
(test #t test:lo-open-read)
(test #t test:lo-creat)
(test #t test:lo-read)
(test #t test:read-line)
(test #t test:lo-seek)
(test "ababaa" test:lo-seek2)
(test #t test:lo-tell)
(for-each delete-file '("lo-tests-data-1" "lo-tests-data-2"))
(set! conn #f)
(test-report)

;; Local Variables:
;; eval: (put 'pg-transaction 'scheme-indent-function 1)
;; End:

;;; guile-pg-lo-tests.scm ends here
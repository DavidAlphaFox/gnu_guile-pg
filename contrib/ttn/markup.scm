;;; Copyright (C) 2003-2005 Thien-Thi Nguyen
;;; This program is provided under the terms of the GNU GPL, version 2.
;;; See http://www.fsf.org/copyleft/gpl.html for details.

(define-module (markup)
  #:use-module ((srfi srfi-13) #:select (string-join))
  #:use-module ((database postgres) #:select (pg-print
                                              pg-ntuples))
  #:use-module ((database postgres-table) #:select (pgtable-manager
                                                    where-clausifier))
  #:use-module ((ice-9 rdelim) #:select (write-line))
  #:use-module ((ice-9 pretty-print) #:select (pretty-print))
  #:use-module ((ice-9 common-list) #:select (pick-mappings)))

;;; version: 5

;; display utilities

(define (display-tree tree)
  (if (list? tree)
      (for-each display-tree tree)
      (display tree)))

(define (>>table heading manager)
  (format #t "TABLE: ~A\n" heading)
  (flush-all-ports)
  (pg-print ((manager #:select) "*"))
  (flush-all-ports))

;; markup table interface: extend pgtable-manager

(define (markup-table-manager db name key-types)
  (let* ((key-names (map (lambda (n)
                           (string->symbol (format #f "k~A" n)))
                         (iota (length key-types))))
         (key-match (string-join
                     (map (lambda (name)
                            (format #f "~A = '~A'" name "~A"))
                          key-names)
                     " AND "))
         (m (pgtable-manager
             db name
             ;;
             ;; table defs
             ;;
             `((raw   text)
               (mtype text)
               (mdata text)
               (seq   int4)             ; client sequence number
               ;; keys
               ,@(map list key-names key-types)))))

    (define (add ls keys . canonicalize)
      (let loop ((ls ls) (count 0))
        (or (null? ls)
            (let ((item (car ls)))
              (apply (m #:insert-col-values)
                     `(seq ,@key-names raw mtype mdata)
                     count
                     (append keys
                             (cond ((string? item) (list item #f #f))
                                   ((null? canonicalize) item)
                                   (else ((car canonicalize) item)))))
              (loop (cdr ls) (1+ count))))))

    (define (del keys)
      ((m #:delete-rows) (apply format #f key-match keys)))

    (define (upd ls keys . canonicalize)
      (del keys)                        ; ugh
      (add ls keys canonicalize))

    (define (->tree keys render)
      (let ((res ((m #:select) "*"
                  (where-clausifier (apply format #f key-match keys))
                  "ORDER BY seq")))
        (and (not (= 0 (pg-ntuples res)))
             (let ((alist ((m #:tuples-result->object-alist) res)))
               (map (lambda (raw mtype mdata)
                      (if (string=? "" mtype)
                          raw
                          (render raw (string->symbol mtype) mdata)))
                    (assq-ref alist 'raw)
                    (assq-ref alist 'mtype)
                    (assq-ref alist 'mdata))))))

    (lambda (choice)                    ; retval
      (case choice
        ((#:add) add)
        ((#:del) del)
        ((#:upd) upd)
        ((#:->tree) ->tree)
        (else (m choice))))))

;; play!

(define *db* (getenv "USER"))

(define *direct-fields* '((name    text)
                          (gnu     bool  "DEFAULT 'f'")
                          (license text)))

(define *markup-fields* '(description
                          location
                          maintainer
                          status
                          mailinglist
                          authors
                          requires))

(let ((m (markup-table-manager *db* "markup_play" '(text text)))
      (c (pgtable-manager *db* "client_play"
                          ;;
                          ;; table defs
                          ;;
                          `(,@ *direct-fields*
                            ,@ (map (lambda (field)
                                      (list field 'bool))
                                    *markup-fields*)))))

  (define (canonicalize-markup form)
    ;; Take one of:
    ;;   (url URL)
    ;;   (url URL TEXT)
    ;;   (email TEXT ADDR)
    ;; and return canonical form: (RAW MTYPE MDATA).
    ;; In the first case, the URL is taken to be both RAW and MDATA.
    (let ((type (car form)))
      (list (case type
              ((url) ((if (= 3 (length form)) caddr cadr) form))
              ((email) (cadr form))
              (else (error (format #f "bad form: ~A" form))))
            (symbol->string (car form))
            ((case type
               ((url) cadr)
               ((email) caddr))
             form))))

  (define (add-project ext)             ; external representation
    (let ((name (car (assq-ref ext 'name)))
          (license (cond ((assq-ref ext 'license) => car) (else #f))))
      (apply (c #:insert-col-values)
             `(name license ,@*markup-fields*)
             name license
             (map (lambda (field)
                    (cond ((assq-ref ext field)
                           => (lambda (data)
                                ((m #:add) data
                                 (list (symbol->string field) name)
                                 canonicalize-markup)))
                          (else #f)))
                  *markup-fields*))))

  (define (find-proj name)
    (let ((alist (car ((c #:tuples-result->alists)
                       ((c #:select) "*" (where-clausifier
                                          (format #f "name = '~A'" name)))))))
      (lambda (key) (assq-ref alist key))))

  (define (htmlize-markup raw mtype mdata)
    (case mtype
      ((url) (list "<A HREF=\"" mdata "\">" raw "</A>"))
      ((email) (list "<A HREF=\"mailto:" mdata "\">" raw "</A>"))
      (else (error (format #f "bad markup type: ~A" mtype)))))

  (define (>>html name)
    (format #t "spew: (~A) -- " name)
    (let ((get (find-proj name)))
      (display-tree
       (let* ((-tr (lambda x (list "<TR>" x "</TR>")))
              (-td (lambda x (list "<TD>" x "</TD>")))
              (-pair (lambda (x y) (-tr (-td x) (-td y)))))
         (list (-tr name)
               (pick-mappings (lambda (field)
                                (and (get field)
                                     (let ((sf (symbol->string field)))
                                       (-pair sf ((m #:->tree) (list sf name)
                                                  htmlize-markup)))))
                              *markup-fields*)))))
    (newline))

  (define (delete-project name)
    (for-each (lambda (field)
                ((m #:del) (list (symbol->string field) name)))
              *markup-fields*)
    ((c #:delete-rows) (format #f "name = '~A'" name)))

  (define (externalize-markup raw mtype mdata)
    (case mtype
      ((url) (if (string=? raw mdata)
                 (list mtype raw)
                 (list mtype mdata raw)))
      ((email) (list mtype raw mdata))
      (else (error (format #f "unexpected mtype: ~A" mtype)))))

  (define (dump-project name)
    (let* ((get (find-proj name))
           (name (get 'name)))
      (pretty-print
       `((name ,name)
         ,@(pick-mappings (lambda (field)
                            (and (get field)
                                 (cons field
                                       ((m #:->tree)
                                        (list (symbol->string field) name)
                                        externalize-markup))))
                          *markup-fields*)))))

  (define *samples*
    (list
     '((name "guile projects list maintenance")
       (description
        "This is the guile scheme code that maintains the "
        (url "http://www.glug.org/projects/list.html"
             "guile projects list")
        ".  There are configurations for glug.org as well for "
        (url "http://www.gnu.org/software/guile/gnu-guile-projects.html"
             "the gnu.org subset of the list") "."))
     '((name "guile-pg")
       (description
        "An interface to PostgreSQL from guile."))
     '((name "snd")
       (description "Snd is a sound editor.")
       (location
        (url "http://www-ccrma.stanford.edu/software/snd/")
        " is where you can find Snd."))
     '((name "hobbit")
       (description
        "The hobbit author is "
        (email "Tanel Tammet" "tammet@cs.chalmers.se") "."))))

  (define (*names* ls) (map (lambda (x) (car (assq-ref x 'name))) ls))

  ((m #:drop)) ((c #:drop))

  (write-line ((m #:create)))
  (write-line ((c #:create)))

  (for-each write-line (map add-project *samples*))

  (>>table "markup" m)
  (>>table "client" c)

  (for-each >>html (*names* *samples*))

  (write-line (delete-project (list-ref (*names* *samples*) 0)))
  (write-line (delete-project (list-ref (*names* *samples*) 1)))

  (>>table "markup" m)
  (>>table "client" c)

  (for-each dump-project (*names* (cddr *samples*)))

  (write-line ((c #:drop)))
  (write-line ((m #:drop))))

;;; markup.scm ends here

#|
 This file is a part of els-web
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:els-web)

(defun compile-edition-template (template output data)
  (with-open-file (stream output
                          :direction :output
                          :if-exists :supersede)
    (let ((*package* #.*package*)
          (target (plump:parse template)))
      (plump:serialize
       (clip:with-clipboard-bound (data)
         (clip:process-node target))
       stream))))

(defun prepare-path (path &key (if-exists :supersede))
  (when (probe-file path)
    (ecase if-exists
      (:supersede (delete-directory-tree path))
      (:error (error "Edition already exists."))
      ((NIL) (return-from prepare-path))))
  (ensure-directories-exist path))

(defun editions-data (current)
  (loop for edition in (editions)
        collect `(:record-type :edition
                  :year ,edition
                  :current ,(if (g= edition current) T NIL))))

(defun compile-edition (edition &key (if-exists :supersede)
                                     (template (template "index.ctml")))
  (let* ((edition (princ-to-string edition))
         (path (pathname-utils:subdirectory *output-dir* edition)))
    (when (prepare-path path :if-exists if-exists)
      (compile-edition-template
       template
       (merge-pathnames "index.html" path)
       (append (edition edition)
               (editions-data edition)))
      path)))

(defun compile-toplevel (&key (template (template "toplevel.ctml")))
  (compile-edition-template
   template
   (merge-pathnames "index.html" *output-dir*)
   (append (edition "toplevel")
           (editions-data (car (last (editions)))))))

(defun compile-all-editions (&key (if-exists :supersede)
                                  (template (template "index.ctml")))
  (compile-toplevel)
  (loop for edition in (editions)
        collect (compile-edition edition :if-exists if-exists
                                         :template template)))

(defun coerce-data (field entry)
  (etypecase field
    (keyword field)
    (symbol (getp entry field :test #'string-equal))
    (T field)))

(defun match-filter (filter entry)
  (if (eql T filter)
      T
      (ecase (first filter)
        (=
         (g=
          (coerce-data (second filter) entry)
          (coerce-data (third filter) entry)))
        (in
         (destructuring-bind (container item) (rest filter)
           (let ((container (coerce-data container entry))
                 (item (coerce-data item entry)))
             (etypecase container
               (list (member item container :test #'g=))
               (string (search item container :test #'g=))))))
        (and
         (loop for sub in (rest filter)
               always (match-filter sub entry)))
        (or
         (loop for sub in (rest filter)
               thereis (match-filter sub entry)))
        (not
         (not (match-filter (second filter) entry))))))

(defun query (record-type &optional (filter T) &key sort)
  (let ((data (loop for entry in (or (car (last clip:*clipboard-stack*))
                                     (edition (package-name *package*)))
                    when (match-filter `(and (= record-type ,record-type) ,filter)
                                       entry)
                    collect entry)))
    (if sort
        (sort data (ecase (second sort)
                     (:asc #'g<)
                     (:dsc #'g>))
              :key (lambda (a) (getp a (first sort))))
        data)))

(defun query1 (record-type &optional (filter T) &key sort)
  (first (query record-type filter :sort sort)))

(defun queryf (field record-type &optional (filter T) &key sort)
  (getp (query1 record-type filter :sort sort) field))

(defun query-text (filter)
  (queryf :text :text filter))

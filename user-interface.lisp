(in-package :elprep)

(defun run-best-practices-pipeline-intermediate-list (file-in file-out &key (sorting-order :keep) (filters '()) (filters2 '()) (gc-on 0) (timed nil))
  "Run the best practices pipeline. Version that uses an intermediate list so that sorting and mark-duplicates are supported."
  #+lispworks-32bit
  (declare (ignore gc-on))
  (let ((filtered-reads (make-sam))) ; where the result of run-pipeline will be stored
    #+lispworks-64bit
    (unless (= gc-on 2) (system:set-blocking-gen-num 0 :do-gc nil))
    (cond (timed
           (format t "Reading SAM into memory and applying filters.~%")
           (time (run-pipeline (current-pathname file-in) filtered-reads
                               :filters filters
                               :sorting-order sorting-order)))
          (t (run-pipeline (current-pathname file-in) filtered-reads
                           :filters filters
                           :sorting-order sorting-order)))
    #+lispworks-64bit
    (when (= gc-on 1) (system:marking-gc 0 :max-size 0))
    ; write to file
    (unless (check-stdout file-out)
      (ensure-directories-exist (current-pathname file-out)))
    (cond (timed
           (format t "Write to file.~%")
           (time (run-pipeline filtered-reads (current-pathname file-out)
                               :sorting-order (if (eq sorting-order :unsorted) :unsorted :keep) :filters filters2)))
          (t (run-pipeline filtered-reads (current-pathname file-out)
                           :sorting-order (if (eq sorting-order :unsorted) :unsorted :keep) :filters filters2)))))

(defun run-best-practices-pipeline (file-in file-out &key (sorting-order :keep) (filters '()) (gc-on 0) (timed nil))
  "Run the best practices pipeline. Version that doesn't use an intermediate list when neither sorting nor mark-duplicates are needed."
  #+lispworks-32bit
  (declare (ignore gc-on))
  #+lispworks-64bit
  (unless (= gc-on 2) (system:set-blocking-gen-num 0 :do-gc nil))
  (cond (timed
         (format t "Running pipeline.~%")
         (time (run-pipeline (current-pathname file-in) (current-pathname file-out)
                             :filters filters
                             :sorting-order sorting-order)))
        (t (run-pipeline (current-pathname file-in) (current-pathname file-out)
                         :filters filters
                         :sorting-order sorting-order))))

(defvar *program-name* "elPrep"
  "Name of the elprep binary.")

(defvar *program-version* "1.05"
  "Version of the elprep binary.")

(defvar *program-url* "http://github.com/exascience/elprep"
  "URL for more information about elprep.")

(defvar *program-help* "sam-file sam-output-file ~% [--replace-reference-sequences sam-file] ~% [--filter-unmapped-reads [strict]] ~% [--replace-read-group read-group-string]~% [--mark-duplicates [remove]] ~% [--sorting-order [keep | unknown | unsorted | queryname | coordinate]] ~% [--clean-sam] ~% [--nr-of-threads nr] ~% [--gc-on [0 | 1 | 2]] ~% [--timed] ~% [--reference-t fai-file] ~% [--reference-T fasta-file] ~%"
  "Help string for the elprep-script binary.")

(defun elprep-filter-script ()
  "Command line script for elprep filter script."
  (let ((cmd-line (rest sys:*line-arguments-list*))
        (sorting-order :keep)
        (nr-of-threads 1)
        (mark-duplicates-p nil)
        (gc-on 0)
        (timed nil)
        ; filters
        (replace-ref-seq-dct-filter nil)
        (ref-seq-dct nil)
        (remove-unmapped-reads-filter nil)
        (filter-unmapped-arg nil)
        (replace-read-group-filter nil)
        (read-group-string nil)
        (mark-duplicates-filter nil)
        (remove-duplicates-filter nil)
        (clean-sam-filter nil)
        (rename-chromosomes-filter nil)
        (reference-fai nil)
        (reference-fasta nil))
    (loop with entry while cmd-line do (setq entry (pop cmd-line))
          if (string= entry "-h") do
          (format t *program-help*)
          (return-from elprep-filter-script)
          else if (string= entry "--replace-reference-sequences")
          do (setf replace-ref-seq-dct-filter (list (replace-reference-sequence-dictionary-from-sam-file (setf ref-seq-dct (pop cmd-line)))))
          else if (string= entry "--filter-unmapped-reads")
          do (setf remove-unmapped-reads-filter (if (string= "strict" (first cmd-line))
                                                  (progn (setf filter-unmapped-arg (pop cmd-line)) (list 'filter-unmapped-reads-strict))
                                                  (list 'filter-unmapped-reads)))
          else if (string= entry "--replace-read-group")
          do (setf replace-read-group-filter (list (add-or-replace-read-group (parse-read-group-from-string (setf read-group-string (pop cmd-line))))))
          else if (string= entry "--mark-duplicates")
          do (setf mark-duplicates-filter (progn
                                            (setf mark-duplicates-p t)
                                            (if (string= "remove" (first cmd-line)) ; also add a filter to remove the duplicates
                                              (progn (pop cmd-line) (setf remove-duplicates-filter (list 'filter-duplicate-reads))
                                                (list 'mark-duplicates))
                                              (list 'mark-duplicates))))
          else if (string= entry "--sorting-order")
          do (let ((so (first cmd-line))) ; peek it
               (if (or (not so) (search "--" so)) ; if no sorting order or next option, use default sorting order = keep
                 (setq sorting-order :keep)
                 (progn
                   (pop cmd-line)
                   (setq sorting-order (intern (string-upcase so) :keyword))
                   (unless (member sorting-order '(:keep :unknown :unsorted :queryname :coordinate))
                     (format t "Invalid sorting-order ~A.~%" so)
                     (format t *program-help*)
                     (return-from elprep-filter-script)))))
          else if (string= entry "--clean-sam")
          do (setf clean-sam-filter (list 'clean-sam))
          else if (string= entry "--nr-of-threads")
          do (setf nr-of-threads (parse-integer (pop cmd-line)))
          else if (string= entry "--gc-on")
          do (let ((lvl (first cmd-line)))
               (if (or (not lvl) (search "--" lvl)) ; no sorting level given
                 (setf gc-on 0)
                 (progn (setf lvl (parse-integer (pop cmd-line) :junk-allowed t))
                   (if (and lvl (or (= lvl 0) (= lvl 1) (= lvl 2)))
                       (setf gc-on lvl)
                     (progn (format t "Invalid gc-on option ~A.~%" lvl)
                       (format t *program-help*)
                       (return-from elprep-filter-script))))))
          else if (string= entry "--timed")
          do (setf timed t)
          else if (string= entry "--reference-t")
          do (let ((ref (first cmd-line)))
               (cond ((or (not ref) (search "--" cmd-line)) ; no file given
                      (format t "Please provide reference file with --reference-t.~%")
                      (format t *program-help*)
                      (return-from elprep-filter-script))
                     (t (setf *reference-fai* (setf reference-fai (pop cmd-line))))))
          else if (string= entry "--reference-T")
          do (let ((ref (first cmd-line)))
               (cond ((or (not ref) (search "--" cmd-line)) ; no file given
                      (format t "Please provide reference file with --reference-T.~%")
                      (format t *program-help*))
                     (t (setf *reference-fasta* (setf reference-fasta (pop cmd-line))))))
          else if (string= entry "--rename-chromosomes")
          do (setf rename-chromosomes-filter (list 'rename-chromosomes))
          else collect entry into conversion-parameters ; main required parameters, input and output sam files
          finally
          (when (/= (length conversion-parameters) 2)
            (format t "Incorrect number of parameters: Expected 2, got ~S~@[ ~A~].~%"
                    (length conversion-parameters) conversion-parameters)
            (format t *program-help*)
            (return-from elprep-filter-script))
          ; print a warning when replacing ref seq dictionary and trying to keep the order
          (when (and replace-ref-seq-dct-filter (eq sorting-order :keep))
            (format t "WARNING: Requesting to keep the order of the input file while replacing the reference sequence dictionary may force an additional sorting phase to ensure the original sorting order is respected."))
          ; check that when cram is used, the reference dictionary is passed
          (when (and (eq (sam-file-kind (second conversion-parameters)) :cram)
                     (not reference-fai) (not reference-fasta))
            (format t "ERROR: Attempting to output to cram without specifying a reference file. Please add --reference-t or --reference-T to your call.~%")
            (format t *program-help*)
            (return-from elprep-filter-script))
          (let* ((cmd-string
                  (with-output-to-string (s)
                    (format s "~a ~a ~a" (first sys:*line-arguments-list*) (first conversion-parameters) (second conversion-parameters))
                    (when remove-unmapped-reads-filter (format s " --filter-unmapped-reads~@[ ~a~]" filter-unmapped-arg))
                    (when clean-sam-filter (format s " --clean-sam"))
                    (when replace-ref-seq-dct-filter (format s " --replace-reference-sequences ~a" ref-seq-dct))
                    (when replace-read-group-filter (format s " --replace-read-group ~s" read-group-string))
                    (when mark-duplicates-filter
                      (if remove-duplicates-filter
                        (format s " --mark-duplicates remove")
                        (format s " --mark-duplicates")))
                    (format s " --sorting-order ~(~a~) --gc-on ~a --nr-of-threads ~a" sorting-order gc-on nr-of-threads)
                    (when timed (format s " --timed"))
                    (when reference-fai (format s " --reference-t ~a" reference-fai))
                    (when reference-fasta (format s " --reference-T ~a" reference-fasta))))
                 ; optimal order for filters
                 (filters (nconc (list (add-pg-line (format nil "~A ~A" *program-name* *program-version*)
                                                    :pn *program-name*
                                                    :vn *program-version*
                                                    :ds *program-url*
                                                    :cl cmd-string))
                                 remove-unmapped-reads-filter
                                 rename-chromosomes-filter
                                 clean-sam-filter
                                 replace-ref-seq-dct-filter       
                                 replace-read-group-filter
                                 (when (or replace-ref-seq-dct-filter mark-duplicates-filter (member sorting-order '(:coordinate :queryname))) (list 'add-refid))
                                 mark-duplicates-filter
                                 (list 'filter-optional-reads)))
                 (filters2 remove-duplicates-filter)) ; only used in conjuction with filters that split up processing in multiple phases
            (format t "Executing command:~%  ~a~%" cmd-string)
            (let ((*number-of-threads* nr-of-threads))
              (push `(*number-of-threads* . ,nr-of-threads) mp:*process-initial-bindings*) ; make sure output threads see this binding
              (push `(*reference-fasta* . ,reference-fasta) mp:*process-initial-bindings*)
              (push `(*reference-fai* . ,reference-fai) mp:*process-initial-bindings*)
              (if (or mark-duplicates-p
                      (member sorting-order '(:coordinate :queryname))
                      (and replace-ref-seq-dct-filter (eq sorting-order :keep)))
                (let ((conversion-parameters
                       (nconc conversion-parameters
                              `(:sorting-order ,sorting-order
                                :filters ,filters :filters2 ,filters2 :gc-on ,gc-on :timed ,timed))))
                  (apply 'run-best-practices-pipeline-intermediate-list conversion-parameters))
                (let ((conversion-parameters
                       (nconc conversion-parameters
                              `(:sorting-order ,sorting-order
                                :filters ,filters :gc-on ,gc-on :timed ,timed))))
                  (apply 'run-best-practices-pipeline conversion-parameters))))))))

(defvar *split-program-help* "split sam-file /path/to/output/ ~% [--output-prefix name] ~% [--output-type [sam | bam | cram]] ~% [--nr-of-threads nr] ~%"
  "Help string for the elprep-split-script binary.")

(defun elprep-split-script ()
  "Command line script for elprep split script."
  (let ((cmd-line (rest (rest sys:*line-arguments-list*))) ; skip elprep split part of the command
        (input nil) (output-path nil) (output-prefix nil) (output-type :sam) (output-extension nil) (nr-of-threads 1))
    (loop with entry while cmd-line do (setq entry (pop cmd-line))
          if (string= entry "-h") do
          (format t *split-program-help*)
          (return-from elprep-split-script)
          else if (string= entry "--output-type")
          do (let ((output-kind (intern (string-upcase (first cmd-line)) :keyword)))
               (cond ((or (not output-kind) (search "--" cmd-line) (not (member output-kind '(:sam :bam :cram)))) ; no correct output type given
                      (format t "Please provide a valid output type.~%")
                      (format t *split-program-help*)
                      (return-from elprep-split-script))              
                     (t (pop cmd-line)
                        (setf output-type output-kind)
                        (setf output-extension (ecase output-type (:bam ".bam") (:sam ".sam") (:cram ".cram"))))))
          else if (string= entry "--output-prefix")
          do (let ((prefix (first cmd-line)))
               (cond ((or (not prefix) (search "--" cmd-line)) ; no prefix given
                      (format t "Please provide a valid output prefix.~%")
                      (format t *split-program-help*)
                      (return-from elprep-split-script))
                     (t 
                      (pop cmd-line) 
                      (setf output-prefix prefix))))
          else if (string= entry "--nr-of-threads")
          do (setf nr-of-threads (parse-integer (pop cmd-line)))
          else collect entry into io-parameters
          finally
          (when (/= (length io-parameters) 2) ; checks on input parameters
            (format t "Incorrect number of parameters: Expected 2, got ~S~@[ ~A~].~%"
                    (length io-parameters) io-parameters)
            (format t *split-program-help*)
            (return-from elprep-split-script))
          ; fill in defaults 
          (setf input (first io-parameters))
          (setf output-path (second io-parameters))
          (unless output-prefix (setf output-prefix (subseq input 0 (- (length input) 4))))
          (unless output-extension (setf output-extension (ecase (sam-file-kind input) (:bam ".bam") (:sam ".sam") (:cram ".cram"))))
          ; print feedback
          (let ((cmd-string
                 (with-output-to-string (s)
                   (format s "~a split ~a ~a " (first sys:*line-arguments-list*) (first io-parameters) (second io-parameters))
                   (format s "--output-prefix ~a " output-prefix)
                   (format s "--output-type ~(~a~)" output-type))))
            (format t "Executing command:~%  ~a~%" cmd-string))
          (let ((*number-of-threads* nr-of-threads))
            (push `(*number-of-threads* . ,nr-of-threads) mp:*process-initial-bindings*)
          (ensure-directories-exist (current-pathname output-path))
          (split-file-per-chromosome input output-path output-prefix output-extension)))))

(defvar *merge-program-help* "merge /path/to/input/ sam-output-file ~% [--nr-of-threads nr] ~%"
  "Help string for the elprep-merge-script binary.")
                    
(defun elprep-merge-script ()
  "Command line script for elprep merge script."
  (let ((cmd-line (rest (rest sys:*line-arguments-list*))) ; skip elprep merge part of the command
        (input-path nil) (output nil) (nr-of-threads 1))
    (loop with entry while cmd-line do (setq entry (pop cmd-line))
          if (string= entry "-h") do
          (format t *merge-program-help*)
          (return-from elprep-merge-script)
          else if (string= entry "--nr-of-threads")
          do (setf nr-of-threads (parse-integer (pop cmd-line)))
          else collect entry into io-parameters
          finally         
          (when (/= (length io-parameters) 2)
            (format t "Incorrect number of parameters: Expected 2, got ~S~@[ ~A~].~%"
                    (length io-parameters) io-parameters)
            (format t *merge-program-help*)
            (return-from elprep-merge-script))
          (setf input-path (first io-parameters))
          (setf output (second io-parameters))
          (let ((files-to-merge (directory input-path)))
            (cond ((not files-to-merge)
                   (format t "Given directory ~a does not exist. ~%" input-path)
                   (format t *merge-program-help*)
                   (return-from elprep-merge-script))
                  ((= (length files-to-merge) 1)
                   (format t "Given directory ~a does not contain any files to merge. ~%" input-path)
                   (format t *merge-program-help*)
                   (return-from elprep-merge-script)))
            ; extract the input prefix
            (let* ((header (with-open-stream (in (open-sam (first files-to-merge) :direction :input)) (parse-sam-header in)))
                   (first-file-name (file-namestring (first files-to-merge)))
                   (input-prefix (loop for sn-form in (sam-header-sq header)
                                       do (let* ((chrom (getf sn-form :SN))
                                                 (idx (search chrom first-file-name :from-end t)))
                                            (when idx (return (subseq first-file-name 0 (- idx 1)))))))
                   (input-extension (ecase (sam-file-kind first-file-name) (:bam ".bam") (:sam ".sam") (:cram ".cram"))))
              ; print feedback
              (let ((cmd-string
                     (with-output-to-string (s)
                       (format s "~a merge ~a ~a" (first sys:*line-arguments-list*) input-path output))))
                (format t "Executing command:~%  ~a~%" cmd-string))
              (let ((*number-of-threads* nr-of-threads))
                (push `(*number-of-threads* . ,nr-of-threads) mp:*process-initial-bindings*)
                (merge-sorted-files-split-per-chromosome input-path output input-prefix input-extension header)))))))

(defun elprep-script ()
  "Command line script for elPrep."
  (setf *debugger-hook* #'elprep-debugger-hook)
  ; change output to stderr
  (setq *standard-output* (system:make-stderr-stream))
  (format t "~A version ~A. See ~A for more information.~%"
          *program-name* *program-version* *program-url*)
  (let ((cmd-line (rest sys:*line-arguments-list*)))
    (when (null cmd-line)
      (format t "Incorrect number of parameters. ~%")
      (format t "Filter parameters: ~%")
      (format t *program-help*)
      (format t "Split parameters: ~%")
      (format t *split-program-help*)
      (format t "Merge parameters: ~%")
      (format t *merge-program-help*)
      (return-from elprep-script))
    (cond ((string= (first cmd-line) "split") (elprep-split-script))
          ((string= (first cmd-line) "merge") (elprep-merge-script))
          (t 
           (elprep-filter-script)))))
        

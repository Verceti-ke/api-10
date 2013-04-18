(in-package :tagit)

(defun get-files (dir &optional (ext ".js") exclude)
  "Recursively grap all files in the given directory, with the given extension,
   excluding the patterns given."
  (unless (cl-fad:directory-exists-p dir)
    (return-from get-files nil))
  (let* ((files (cl-fad:list-directory dir))
         (files (mapcar (lambda (file) (namestring file)) files))
         (ext-length (length ext))
         (files (remove-if (lambda (file)
                             (and (not (string= (subseq file (- (length file) ext-length))
                                                ext))
                                  (not (cl-fad:directory-exists-p file))))
                           files))
         (files (remove-if (lambda (file)
                             (block do-remove
                               (dolist (ex exclude)
                                 (when (search ex file)
                                   (return-from do-remove t)))))
                           files))
         (final nil))
    (dolist (file files)
      (if (cl-fad:directory-exists-p file)
          (setf final (append final (get-files file ext exclude)))
          (push file final)))
    (sort final #'string<)))

(defun make-scripts (stream files)
  "Given a stream and list of files, print a <script ...></script> tag for each
   file onto the stream."
  (format stream "~%")
  (dolist (file files)
    (let* ((search-pos (search "webroot/" file))
           (search-pos (when search-pos
                         (+ (1- (length "webroot/")) search-pos)))
           (search-pos (or search-pos 0))
           (file (subseq file search-pos)))
      (format stream "<script src=\"~a\"></script>~%" file))))

(defun make-css (stream files)
  "Given a stream and list of files, print a <link ...> css tag for each
   file on the stream."
  (format stream "~%")
  (dolist (file files)
    (let* ((search-pos (search "webroot/" file))
           (search-pos (when search-pos
                         (+ (1- (length "webroot/")) search-pos)))
           (search-pos (or search-pos 0))
           (file (subseq file search-pos)))
      (format stream "<link rel=\"stylesheet\" href=\"~a\">~%" file))))

(defun generate-templates (stream view-dir)
  "Make a bunch of pre-cached javascript templates as <script> tags."
  (format stream "~%")
  (let ((files (get-files view-dir ".html")))
    (dolist (file files)
      (let* ((contents (file-contents file))
             (contents (cl-ppcre:regex-replace-all "</script>" contents "</%script%>"))
             (contents (cl-ppcre:regex-replace-all "<script" contents "<%script%"))
             (name (subseq file (1+ (length view-dir))))
             (name (subseq name 0 (position #\. name :from-end t))))
        (format stream "<script type=\"text/x-lb-tpl\" name=\"~a\">~%" name)
        (write-string contents stream)
        (format stream "</script>~%")))))

;; TODO: cache me!
(deflayout default (data :stream-var s :top-level t)
  (:html
    (:head
      (:meta :http-equiv "Content-Type" :content "test/html; charset=utf-8")
      (:meta :http-equiv "Content-Language" :content "en")
      (:title "tag.it")
      (:link :rel "stylesheet" :href "/css/reset.css")
      (:link :rel "stylesheet" :href "/css/template.css")
      (:link :rel "stylesheet" :href "/css/general.css")
      (make-css s (get-files "./webroot/css" ".css"
                             '("template.css" "reset.css" "general.css")))
      (:link :rel "shortcut icon" :href "/favicon.png" :type "image/png")
      (:script :src "/library/mootools-1.4.1.js")
      (:script :src "/library/composer/composer.js")
      (:script :src "/library/composer/composer.relational.js")
      (:script :src "/library/composer/composer.filtercollection.js")
      (:script :src "/library/composer/composer.keyboard.js")
      (:script "Composer.suppress_warnings = true;")

      (make-scripts s '("/config/config.js"
                        "/config/auth.js"
                        "/config/routes.js"))
      (make-scripts s (get-files "./webroot/library" ".js"
                                 '("ignore" "plupload" "mootools-" "composer" "uservoice")))
      (:script :src "/tagit.js")
      (make-scripts s (get-files "./webroot/tagit"))
      (make-scripts s (get-files "./webroot/handlers"))
      (make-scripts s (get-files "./webroot/controllers"))
      (make-scripts s (get-files "./webroot/models"))
      
      (:script
        (format s "~%var __site_url = '~a';" *site-url*)
        (format s "~%var __api_url = '~a';" *api-url*)
        (format s "~%var __api_key = '~a';" *api-key*)))
    (:body :class "initial"
      (:div :id "wrap-modal"
        (:div :id "wrap"
          (:header :class "clear"
            (:h1 (:a :href "/" "tag<span>.</span>it"))
            (:div :class "loading"
              (:img :src "/images/site/icons/load_42x11.gif")))
          (:div :id "main" :class "maincontent")))

      (:div :id "footer"
        (:footer
          (:div :class "gutter"
            (str (conc "Copyright &copy; "
                       (write-to-string (nth-value 5 (decode-universal-time (get-universal-time))))
                       " "))
            (:a :href "http://www.lyonbros.com" :target "_blank"
              "Lyon Bros. Enterprises, LLC."))))
      (generate-templates s (format nil "~awebroot/views" (namestring *root*))))))


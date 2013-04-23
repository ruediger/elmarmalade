;;; elmarmalade.el --- the marmalade repository in emacs-lisp

;; Copyright (C) 2013  Nic Ferrier

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; marmalade-repo.org is an Emacs package repository originally by
;; Nathan Wiezenbaum in node.js.

;; This is a rewrite of marmalade-repo in Emacs-Lisp using Elnode.

;;; Code:

(elnode-app marmalade-dir marmalade-archive)

(defconst marmalade-cookie-name "marmalade-user"
  "The name of the cookie we use for auth.")

(elnode-defauth 'marmalade-auth
  :auth-test 'marmalade-auth-func
  :cookie-name marmalade-cookie-name)

(defun marmalade/explode-package-string (package-name)
  (string-match
   "\\(.+\\)-\\([0-9.]+\\)+\\.\\(el\\|tar\\)"
   package-name)
  (list 
   (match-string 1 package-name)
   (match-string 2 package-name)
   (match-string 3 package-name)))

(defun marmalade/package-name->filename (package-name)
  "Convert a package-name to a local filename.

The package root dir is not considered, this is just a structural
transformation of the filename."
  (destructuring-bind (name version type)
      (marmalade/explode-package-string package-name)
    (format
     "%s/%s/%s-%s.%s"
     name
     version
     name version type)))

(defun marmalade/downloader (httpcon)
  "Download a specific package."
  (flet ((elnode-http-mapping (httpcon which)
           (let* ((package (elnode--http-mapping-impl httpcon which))
                  (file (marmalade/package-name->filename package)))
             file)))
    (elnode-docroot-for
        marmalade-package-store-dir
        with target-package
        on httpcon
        do
        (with-current-buffer
            (let ((enable-local-variables nil))
              (find-file-noselect target-package))
          (elnode-http-start httpcon 200 '("Content-type" . "text/elisp"))
          (elnode-http-return httpcon (buffer-string))))))

(defun marmalade/package-handle (package-file)
  "Return package-info on the package."
  (cond
    ((string-match "\\.el$" package-file)
     (with-temp-buffer
       (insert-file-contents-literally package-file)
       (buffer-string) ; leave it in so it's easy to debug
       (package-buffer-info)))
    ((string-match "\\.tar$" package-file)
     (package-tar-file-info package-file))
    (t (error "Unrecognized extension `%s'"
              (file-name-extension package-file)))))

(defun marmalade/upload (httpcon)
  "Handle uploaded packages."
  ;; FIXME Need to check we have auth here
  (with-elnode-auth httpcon 'marmalade-auth
    (let* ((upload-file (elnode-http-param httpcon "file"))
           (upload-file-name
            (get-text-property 0 :elnode-filename upload-file))
           (package-file-name
            (concat
             (file-name-as-directory
              marmalade-package-store-dir) "/"
              (file-name-nondirectory upload-file-name))))
      ;; We need to parse the file for version and stuff.
      (condition-case err
          (let ((package-info
                 (progn
                   (with-temp-file package-file-name (insert upload-file))
                   (marmalade/package-handle package-file-name))))
            (elnode-send-json httpcon '("Ok")))
        (error (progn
                 (message "marmalade/upload ERROR!")
                 (elnode-send-400
                  httpcon
                  "something went wrong uploading the package")))))))

(defun marmalade-auth-func (username)
  "What is the token for the USERNAME?"
  (let ((user (db-get username marmalade/user-db)))
    (when user
      (aget user token))))

(defun marmalade/package-handler (httpcon)
  "Dispatch to the appropriate handler on method."
  (elnode-method httpcon
    (GET (marmalade/downloader httpcon))
    (POST (marmalade/upload httpcon))))

(defun marmalade/packages-index (httpcon)
  "Show a package index in HTML or JSON?"
  (elnode-send-html httpcon "<H1>marmalade repo</H1>"))

(defun marmalade-router (httpcon)
  (elnode-hostpath-dispatcher
   httpcon
   '(("^[^/]+//packages/archive-contents" . marmalade-archive-handler)
     ;; We don't really want to send 404's for these if we have them
     ("^[^/]+//packages/.*-readme.txt" . elnode-send-404)
     ("^[^/]+//packages/\\(.*\\)\\.\\(el\\|tar\\)" . marmalade/package-handler)
     ("^[^/]+//packages/" . marmalade/packages-index))
   :log-name "marmalade"
   :auth-test marmalade-auth))

(provide 'marmalade-service)

;;; marmalade-s.el ends here

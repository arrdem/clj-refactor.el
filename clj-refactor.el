;;; clj-refactor.el --- A collection of clojure refactoring functions

;; Copyright (C) 2012 Magnar Sveen <magnars@gmail.com>

;; Author: Magnar Sveen <magnars@gmail.com>
;; Version: 0.2.0
;; Keywords: convenience
;; Package-Requires: ((s "1.3.1") (dash "1.0.3") (yasnippet "0.6.1"))

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; ## Installation
;;
;; I highly recommended installing clj-refactor through elpa.
;;
;; It's available on [marmalade](http://marmalade-repo.org/) and
;; [melpa](http://melpa.milkbox.net/):
;;
;;     M-x package-install clj-refactor
;;
;; You can also install the dependencies on your own, and just dump
;; clj-refactor in your path somewhere:
;;
;;  - <a href="https://github.com/magnars/s.el">s.el</a>
;;  - <a href="https://github.com/magnars/dash.el">dash.el</a>
;;

;; ## Setup
;;
;;     (require 'clj-refactor)
;;     (add-hook 'clojure-mode-hook (lambda ()
;;                                    (clj-refactor-mode 1)
;;                                    ;; insert keybinding setup here
;;                                    ))
;;
;; You'll also have to set up the keybindings in the lambda. Read on.

;; ## Setup keybindings
;;
;; All functions in clj-refactor have a two-letter mnemonic shortcut. You
;; get to choose how those are bound. Here's how:
;;
;;     (cljr-add-keybindings-with-prefix "C-c C-m")
;;     ;; eg. rename files with `C-c C-m rf`.
;;
;; If you would rather have a modifier key, instead of a prefix, do:
;;
;;     (cljr-add-keybindings-with-modifier "C-s-")
;;     ;; eg. rename files with `C-s-r C-s-f`.
;;
;; If neither of these appeal to your sense of keyboard layout aesthetics, feel free
;; to pick and choose your own keybindings with a smattering of:
;;
;;     (define-key clj-refactor-map (kbd "C-x C-r") 'cljr-rename-file)

;; ## Use
;;
;; This is it so far:
;;
;;  - `rf`: rename file, update ns-declaration, and then query-replace new ns in project.
;;  - `ar`: add :require to namespace declaration, then jump back
;;  - `au`: add :use to namespace declaration, then jump back
;;  - `ai`: add :import to namespace declaration, then jump back
;;
;; Combine with your keybinding prefix/modifier.

;; ## Automatic insertion of namespace declaration
;;
;; When you open a blank `.clj`-file, clj-refactor inserts the namespace
;; declaration for you.
;;
;; It will also add the relevant `:use` clauses in test files, normally
;; using `clojure.test`, but if you're depending on midje in your
;; `project.clj` it uses that instead.
;;
;; Like clojure-mode, clj-refactor presumes that you are postfixing your
;; test files with `_test`.
;;
;; Prefer to insert your own ns-declarations? Then:
;;
;; (setq clj-add-ns-to-blank-clj-files nil)

;;; Code:

(require 'dash)
(require 's)
(require 'yasnippet)

(defvar cljr-add-ns-to-blank-clj-files t)

(defvar clj-refactor-map (make-sparse-keymap) "")

(defun cljr--fix-special-modifier-combinations (key)
  (case key
    ("C-s-i" "s-TAB")
    ("C-s-m" "s-RET")
    (otherwise key)))

(defun cljr--key-pairs-with-modifier (modifier keys)
  (->> (string-to-list keys)
    (--map (cljr--fix-special-modifier-combinations
            (concat modifier (char-to-string it))))
    (s-join " ")
    (read-kbd-macro)))

(defun cljr--key-pairs-with-prefix (prefix keys)
  (read-kbd-macro (concat prefix " " keys)))

(defun cljr--add-keybindings (key-fn)
  (define-key clj-refactor-map (funcall key-fn "rf") 'cljr-rename-file)
  (define-key clj-refactor-map (funcall key-fn "au") 'cljr-add-use-to-ns)
  (define-key clj-refactor-map (funcall key-fn "ar") 'cljr-add-require-to-ns)
  (define-key clj-refactor-map (funcall key-fn "ai") 'cljr-add-import-to-ns))

;;;###autoload
(defun cljr-add-keybindings-with-prefix (prefix)
  (cljr--add-keybindings (-partial 'cljr--key-pairs-with-prefix prefix)))

;;;###autoload
(defun cljr-add-keybindings-with-modifier (modifier)
  (cljr--add-keybindings (-partial 'cljr--key-pairs-with-modifier modifier)))

(defun cljr--project-dir ()
  (file-truename
   (locate-dominating-file default-directory "project.clj")))

(defun cljr--project-file ()
  (expand-file-name "project.clj" (cljr--project-dir)))

(defun cljr--project-files ()
  (split-string (shell-command-to-string
                 (format "find %s -type f \\( %s \\) %s | head -n %s"
                         (cljr--project-dir)
                         (format "-name \"%s\"" "*.clj")
                         "-not -regex \".*svn.*\""
                         1000))))

(defun cljr--rename-file (filename new-name)
  (let ((old-ns (clojure-find-ns)))
    (rename-file filename new-name 1)
    (rename-buffer new-name)
    (set-visited-file-name new-name)
    (clojure-update-ns)
    (save-window-excursion
      (save-excursion
        (ignore-errors
          (tags-query-replace old-ns (clojure-expected-ns) nil
                              '(cljr--project-files)))))
    (save-buffer)
    (save-some-buffers)))

;;;###autoload
(defun cljr-rename-file ()
  "Renames current buffer and file it is visiting."
  (interactive)
  (let ((name (buffer-name))
        (filename (buffer-file-name)))
    (if (not (and filename (file-exists-p filename)))
        (error "Buffer '%s' is not visiting a file!" name)
      (let ((new-name (read-file-name "New name: " filename)))
        (if (get-buffer new-name)
            (error "A buffer named '%s' already exists!" new-name)
          (cljr--rename-file filename new-name)
          (message "File '%s' successfully renamed to '%s'"
                   name (file-name-nondirectory new-name)))))))

(defun cljr--goto-ns ()
  (goto-char (point-min))
  (if (re-search-forward clojure-namespace-name-regex nil t)
      (search-backward "(")
    (error "No namespace declaration found")))

(defun cljr--insert-in-ns (type)
  (cljr--goto-ns)
  (let ((bound (save-excursion (forward-list 1) (point))))
    (if (search-forward (concat "(" type " ") bound t)
        (progn
          (search-backward "(")
          (forward-list 1)
          (forward-char -1)
          (newline-and-indent))
      (forward-list 1)
      (forward-char -1)
      (newline-and-indent)
      (insert "(" type " )")
      (forward-char -1))))

(defun cljr--project-depends-on (package)
  (save-window-excursion
    (find-file (cljr--project-file))
    (goto-char (point-min))
    (search-forward package nil t)))

(defun cljr--add-test-use-declarations ()
  (save-excursion
    (let ((ns (clojure-find-ns)))
      (cljr--insert-in-ns ":use")
      (insert (s-chop-suffix "-test" ns))
      (cljr--insert-in-ns ":use")
      (insert (if (cljr--project-depends-on "midje") "midje.sweet" "clojure.test")))))

(defun cljr--add-ns-if-blank-clj-file ()
  (ignore-errors
    (when (and cljr-add-ns-to-blank-clj-files
               (s-ends-with? ".clj" (buffer-file-name))
               (= (point-min) (point-max)))
      (clojure-insert-ns-form)
      (newline 2)
      (when (clojure-in-tests-p)
        (cljr--add-test-use-declarations)))))

(add-hook 'find-file-hook 'cljr--add-ns-if-blank-clj-file)

;;;###autoload
(defun cljr-add-require-to-ns ()
  (interactive)
  (push-mark)
  (cljr--insert-in-ns ":require")
  (cljr--pop-mark-after-yasnippet)
  (yas/expand-snippet "[$1 :as $2]"))

;;;###autoload
(defun cljr-add-use-to-ns ()
  (interactive)
  (push-mark)
  (cljr--insert-in-ns ":use")
  (cljr--pop-mark-after-yasnippet)
  (yas/expand-snippet "${1:[$2 :only ($3)]}"))

;;;###autoload
(defun cljr-add-import-to-ns ()
  (interactive)
  (push-mark)
  (cljr--insert-in-ns ":import")
  (cljr--pop-mark-after-yasnippet)
  (yas/expand-snippet "$1"))

(defun cljr--pop-mark-after-yasnippet ()
  (add-hook 'yas/after-exit-snippet-hook 'cljr--pop-mark-after-yasnippet-1 nil t))

(defun cljr--pop-mark-after-yasnippet-1 (&rest ignore)
  (pop-to-mark-command)
  (remove-hook 'yas/after-exit-snippet-hook 'cljr--pop-mark-after-yasnippet-1 t))

;;;###autoload
(define-minor-mode clj-refactor-mode
  "A mode to keep the clj-refactor keybindings."
  nil " cljr" clj-refactor-map)

(provide 'clj-refactor)
;;; clj-refactor.el ends here

(require 'button)

(defface company-coq-features/goal-diffs-added-face
  '((t :foreground "green"))
  "Face used to highlight the ‘new hypothesis’ marker."
  :group 'company-coq-faces)

(defface company-coq-features/goal-diffs-changed-face
  '((t :foreground "orange"))
  "Face used to highlight the ‘changed hypothesis’ marker."
  :group 'company-coq-faces)

(defface company-coq-features/goal-diffs-hyp-highlight-face
  '((t :underline t))
  "Face used to highlight new or edited hypotheses."
  :group 'company-coq-faces)

(defun company-coq-features/goal-diffs--type= (t1 t2)
  "Check if two strings T1 and T2 represent the same Coq type."
  (or (string= t1 t2)
      (string= (replace-regexp-in-string "[ \r\n\t]+" " " t1)
               (replace-regexp-in-string "[ \r\n\t]+" " " t2))))

(defun company-coq-features/goal-diffs--hyp-status (hyps hyp)
  "Compute the status of HYP against a collection of HYPS.
Return `added', `changed', or `unchanged', depending on the status
of HYP wrt HYPS."
  (catch 'found
    (dolist (other-hyp hyps)
      (when (string= (company-coq-hypothesis-names hyp)
                     (company-coq-hypothesis-names other-hyp))
        (if (company-coq-features/goal-diffs--type=
             (company-coq-hypothesis-type hyp)
             (company-coq-hypothesis-type other-hyp))
            (throw 'found 'unchanged)
          (throw 'found 'changed))))
    (throw 'found 'added)))

(defun company-coq-features/goal-diffs--make-annot-1 (str face status)
  "Annotate STR with FACE and a help message based on STATUS."
  (propertize
   str 'face face
   'help-echo (format "A hypothesis on this line was just %s." status)))

(defun company-coq-features/goal-diffs--make-annot (statuses)
  "Construct an annotation from STATUSES.
This annotation is then prepended to the hypotheses in the
display of the goal."
  (concat (if (memq 'added statuses)
              (company-coq-features/goal-diffs--make-annot-1
               "+" 'company-coq-features/goal-diffs-added-face 'added)
            "")
          (if (memq 'changed statuses)
              (company-coq-features/goal-diffs--make-annot-1
               "!" 'company-coq-features/goal-diffs-changed-face 'changed)
            "")))

(defun company-coq-features/goal-diffs--annotate-1 (multi-hyp statuses)
  "Annotate MULTI-HYP based on the STATUSES of its sub-hypotheses."
  (let ((names-pos (company-coq-hypothesis-names-position multi-hyp))
        (annot (company-coq-features/goal-diffs--make-annot statuses)))
    (when (> (length annot) 0)
      (put-text-property (+ names-pos -2) (+ names-pos -2 (length annot))
                         'display annot))))

(defun company-coq-features/goal-diffs--highlight-1 (hyp status)
  "Highlight HYP (if STATUS isn't `unchanged')."
  (unless (eq status 'unchanged)
    (let* ((start (company-coq-hypothesis-names-position hyp))
           (end (+ start (length (company-coq-hypothesis-names hyp))))
           (ov (make-overlay start end)))
      (overlay-put ov 'company-coq t)
      (overlay-put ov 'face 'company-coq-features/goal-diffs-hyp-highlight-face)
      (overlay-put ov 'help-echo (format "This hypothesis was just %s." status)))))

(defun company-coq-features/goal-diffs-hyperlink-action (_btn)
  "Handle a click on the “full diff” button."
  (company-coq-diff-goals)
  (message "%s" (substitute-command-keys "Press q to close this diff. Next time, you can use \\<company-coq-map>\\[company-coq-diff-dwim] to open it faster.")))

(defun company-coq-features/goal-diffs--add-hyperlink ()
  "Add hyperlink to full goal diff after (ID ...)."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "(ID \\([0-9]+\\))" nil t)
      (goto-char (match-end 1))
      (let ((inhibit-read-only t))
        (insert "; ")
        (insert-text-button
         "diff to previous"
         'follow-link t
         'action #'company-coq-features/goal-diffs-hyperlink-action
         'help-echo "Compare this goal to the previous one in a separate diff buffer")))))

(defun company-coq-features/goal-diffs-annotate ()
  "Annotate the goals in the proof buffer.
Assumes that both `company-coq--current-context-parse' and
`company-coq--current-context-parse' are up-to-date."
  (interactive)
  (when (and (consp company-coq--previous-context-parse)
             (consp company-coq--current-context-parse))
    (company-coq-with-current-buffer-maybe proof-goals-buffer
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (overlay-get ov 'company-coq)
          (delete-overlay ov)))
      (pcase-let* ((`(,old-multi-hyps . ,old-goals) company-coq--previous-context-parse)
                   (`(,multi-hyps . ,goals) company-coq--current-context-parse)
                   (old-hyps (company-coq--split-merged-hypotheses old-multi-hyps))
                   (inhibit-read-only t))
        (dolist (multi-hyp multi-hyps)
          (let* ((hyps (company-coq--split-merged-hypothesis multi-hyp))
                 (statuses (mapcar (apply-partially #'company-coq-features/goal-diffs--hyp-status old-hyps) hyps)))
            (company-coq-features/goal-diffs--annotate-1 multi-hyp statuses)
            (pcase-dolist (`(,hyp . ,status) (-zip-pair hyps statuses))
              (company-coq-features/goal-diffs--highlight-1 hyp status)))))
      (company-coq-features/goal-diffs--add-hyperlink))))

(defun company-coq-features/goal-diffs--annotate-new-output ()
  "Annotate contents of goals buffer if appropriate."
  (unless (memq 'no-goals-display proof-shell-delayed-output-flags)
    (company-coq-features/goal-diffs-annotate)))

(define-minor-mode company-coq-goal-diffs
  "Render Coq goals using LaTeX."
  :lighter " ⁺∕₋"
  (if company-coq-goal-diffs
      (add-hook 'proof-shell-handle-delayed-output-hook
                ;; Must append to ensure we run after the context update code
                #'company-coq-features/goal-diffs--annotate-new-output t)
    (remove-hook 'proof-shell-handle-delayed-output-hook
                 #'company-coq-features/goal-diffs--annotate-new-output)))

(company-coq-goal-diffs)
(provide 'company-coq-goal-diffs)

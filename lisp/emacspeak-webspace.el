;;; emacspeak-webspace.el --- Webspaces In Emacspeak
;;; $Id$
;;; $Author: tv.raman.tv $
;;; Description: WebSpace provides smart updates from the Web.
;;; Keywords: Emacspeak, Audio Desktop webspace
;;{{{ LCD Archive entry:

;;; LCD Archive Entry:
;;; emacspeak| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;; $Date: 2007-05-03 18:13:44 -0700 (Thu, 03 May 2007) $ |
;;; $Revision: 4532 $ |
;;; Location undetermined
;;;

;;}}}
;;{{{ Copyright:
;;;Copyright (C) 1995 -- 2007, T. V. Raman
;;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;;; All Rights Reserved.
;;;
;;; This file is not part of GNU Emacs, but the same permissions apply.
;;;
;;; GNU Emacs is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 2, or (at your option)
;;; any later version.
;;;
;;; GNU Emacs is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNWEBSPACE FOR A PARTICULAR PURPOSE. See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Emacs; see the file COPYING. If not, write to
;;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;;}}}
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;{{{ introduction

;;; Commentary:
;;; WEBSPACE == Smart Web Gadgets For The Emacspeak Desktop

;;}}}
;;{{{ Required modules

(require 'cl)
(declaim (optimize (safety 0) (speed 3)))
(require 'emacspeak-preamble)
(require 'ring)
(require 'derived)
(require 'gfeeds)
;;}}}
;;{{{ WebSpace Mode:

;;; Define a derived-mode called WebSpace that is generally useful for hypetext display.

(define-derived-mode emacspeak-webspace-mode fundamental-mode
  "Webspace Interaction"
  "Major mode for Webspace interaction.\n\n
\\{emacspeak-webspace-mode-map")

(declaim (special emacspeak-webspace-mode-map))

(loop for k in 
      '(
        ("q" bury-buffer)
        ("t" emacspeak-webspace-transcode)
        ("\C-m" emacspeak-webspace-open)
        ("." emacspeak-webspace-filter)
        ("n" next-line)
        ("p" previous-line))
      do
      (emacspeak-keymap-update  emacspeak-webspace-mode-map k))

(defsubst emacspeak-webspace-act-on-link (action &rest args)
  "Apply action to link  under point."
  (let ((link (get-text-property (point) 'link)))
    (if link
        (apply action  link args)
      (message "No link under point."))))

;;;###autoload
(defun emacspeak-webspace-transcode ()
  "Transcode headline at point by following its link property."
  (interactive)
  (emacspeak-webspace-act-on-link 'emacspeak-webutils-transcode-this-url-via-google))

;;;###autoload
(defun emacspeak-webspace-open ()
  "Open headline at point by following its link property."
  (interactive)
  (emacspeak-webspace-act-on-link 'browse-url))

;;;###autoload
(defun emacspeak-webspace-filter ()
  "Open headline at point by following its link property and filter for content."
  (interactive)
  (emacspeak-webspace-act-on-link 'emacspeak-we-xslt-filter
                                  "//p|ol|ul|dl|h1|h2|h3|h4|h5|h6|blockquote|div" 'speak))

;;}}}
;;{{{ WebSpace Display:

(global-set-key [C-return] 'emacspeak-webspace-headlines-view)

;;;###autoload
(defun emacspeak-webspace-headlines-view ()
  "Display all cached headlines in a special interaction buffer."
  (interactive)
  (declare (special emacspeak-webspace))
  (let ((buffer (get-buffer-create "Headlines"))
        (inhibit-read-only t))
    (save-excursion
      (set-buffer buffer)
      (erase-buffer)
      (setq buffer-undo-list t)
      (mapc
       #'(lambda (r)
           (insert (format "%s\n" r)))
       (ring-elements
        (emacspeak-webspace-fs-titles emacspeak-webspace))))
    (switch-to-buffer buffer)
    (setq buffer-read-only t)
    (emacspeak-webspace-mode)
    (goto-char (point-min))
    (emacspeak-auditory-icon 'open-object)
    (emacspeak-speak-line)))

(defsubst emacspeak-webspace-display (infolet)
  "Displays specified infolet.
Infolets use the same structure as mode-line-format and header-line-format.
Generates auditory and visual display."
  (declare (special header-line-format))
  (setq header-line-format infolet)
  (dtk-speak (format-mode-line header-line-format))
  (emacspeak-auditory-icon 'progress))
;;;###autoload
(define-prefix-command 'emacspeak-webspace 'emacspeak-webspace-keymap)

(declaim (special emacspeak-webspace-keymap))

(loop for k in
      '(
        ("w" emacspeak-webspace-weather)
        ("h" emacspeak-webspace-headlines)
        )
      do
      (define-key emacspeak-webspace-keymap (first k) (second k)))

;;}}}
;;{{{ Headlines:

(defcustom emacspeak-webspace-feeds nil
  "Collection of ATOM and RSS feeds."
  :type '(repeat
                (string :tag "URL"))
  :group  'emacspeak-webspace)

;;; Encapsulate collection feeds, headlines, timer, and  recently updated feed.-index

(defstruct emacspeak-webspace-fs
  feeds titles
   timer slow-timer index )

(defvar emacspeak-webspace-headlines nil
  "Feedstore  structure to use a continuously updating ticker.")

(defsubst emacspeak-webspace-headlines-fetch ( feed)
  "Add headlines from specified feed to our cache."
  (let ((last-update (get-text-property 0 'last-update feed))
	(titles  (emacspeak-webspace-fs-titles emacspeak-webspace-headlines)))
    (when (or (null last-update)
	      (time-less-p '(0 1800 0)	; 30 minutes 
			   (time-since last-update)))
      (put-text-property 0 1 'last-update (current-time) feed)
      (mapc
       #'(lambda (h) (ring-insert titles h ))
       (gfeeds-titles feed)))))

(defsubst emacspeak-webspace-fs-next (fs)
  "Return next feed and increment index for fs."
  (let ((feed-url (aref
		   (emacspeak-webspace-fs-feeds fs)
		   (emacspeak-webspace-fs-index fs))))
    (setf (emacspeak-webspace-fs-index fs)
	  (% (1+ (emacspeak-webspace-fs-index fs))
	     (length (emacspeak-webspace-fs-feeds fs))))
    feed-url))

(defun emacspeak-webspace-headlines-populate ()
  "populate fs with headlines from all feeds."
  (declare (special emacspeak-webspace-headlines))
  (dotimes (i (length (emacspeak-webspace-fs-feeds emacspeak-webspace-headlines)))
   (emacspeak-webspace-headlines-fetch (emacspeak-webspace-fs-next emacspeak-webspace-headlines))))

(defsubst emacspeak-webspace-headlines-refresh ()
  "Update headlines."()
  (declare (special emacspeak-webspace-headlines))
  (emacspeak-webspace-headlines-fetch (emacspeak-webspace-fs-next emacspeak-webspace-headlines))
  (emacspeak-auditory-icon 'working))

(defun emacspeak-webspace-update-headlines ()
  "Setup  news updates.
Updated headlines found in emacspeak-webspace-headlines."
  (interactive)
  (declare (special emacspeak-webspace-headlines))
  (let ((timer nil)
	(slow-timer nil))
    (setq timer 
	  (run-with-idle-timer
           30 t 'emacspeak-webspace-headlines-refresh))
    (setq slow-timer 
	  (run-with-idle-timer
           3600 
           t 'emacspeak-webspace-headlines-populate))
    (setf (emacspeak-webspace-fs-timer emacspeak-webspace-headlines) timer)
    (setf (emacspeak-webspace-fs-slow-timer emacspeak-webspace-headlines) slow-timer)))

(defun emacspeak-webspace-next-headline ()
  "Return next headline to display."
  (declare (special emacspeak-webspace-headlines))
  (let ((titles (emacspeak-webspace-fs-titles emacspeak-webspace-headlines)))
    (when (ring-empty-p titles)
      (emacspeak-webspace-headlines-refresh)
      "No News Is Good News")
    (let ((h (ring-remove titles 0)))
      (ring-insert-at-beginning titles h)
      h)))


;;;###autoload
(defun emacspeak-webspace-headlines ()
  "Speak current news headline."
  (interactive)
  (declare (special emacspeak-webspace-headlines))
  (unless emacspeak-webspace-headlines
    (setq emacspeak-webspace-headlines
          (make-emacspeak-webspace-fs
           :feeds (apply 'vector emacspeak-webspace-feeds)
           :titles (make-ring (* 10 (length emacspeak-webspace-feeds)))
           :index 0)))
  (unless (emacspeak-webspace-fs-timer emacspeak-webspace-headlines)
    (call-interactively 'emacspeak-webspace-update-headlines))
  (emacspeak-webspace-display '((:eval (emacspeak-webspace-next-headline)))))

;;}}}
;;{{{ Weather:

(defvar emacspeak-webspace-weather-url-template
"http://www.wunderground.com/auto/rss_full/%s.xml"
  "URL template for weather feed.")

(defun emacspeak-webspace-weather-conditions ()
  "Return weather conditions for `emacspeak-url-template-weather-city-state'."
  (declare (special emacspeak-url-template-weather-city-state
                    emacspeak-webspace-weather-url-template))
  (when (and emacspeak-webspace-weather-url-template
             emacspeak-url-template-weather-city-state)
    (with-local-quit
    (first
     (gfeeds-titles
      (format emacspeak-webspace-weather-url-template
              emacspeak-url-template-weather-city-state))))))

(defvar emacspeak-webspace-current-weather nil
  "Holds cached value of current weather conditions.")

(defvar emacspeak-webspace-weather-timer nil
  "Timer holding our weather update timer.")
(defun emacspeak-webspace-weather-get ()
  "Get weather."
  (declare (special emacspeak-webspace-current-weather))
  (setq emacspeak-webspace-current-weather
        (emacspeak-webspace-weather-conditions)))

(defun emacspeak-webspace-update-weather ()
  "Setup periodic weather updates.
Updated weather is found in `emacspeak-webspace-current-weather'."
  (interactive)
  (declare (special emacspeak-webspace-weather-timer))
  (unless emacspeak-url-template-weather-city-state
    (error
     "First set option emacspeak-url-template-weather-city-state to your city/state."))
  (emacspeak-webspace-weather-get)
  (setq emacspeak-webspace-weather-timer
        (run-with-idle-timer 600 'repeat
         'emacspeak-webspace-weather-get )))

;;;###autoload
(defun emacspeak-webspace-weather ()
  "Speak current weather."
  (interactive)
  (declare (special emacspeak-webspace-current-weather
                    emacspeak-webspace-weather-timer))
  (unless emacspeak-webspace-weather-timer
    (call-interactively 'emacspeak-webspace-update-weather))
  (emacspeak-webspace-display 'emacspeak-webspace-current-weather))

;;}}}
(provide 'emacspeak-webspace)
;;{{{ end of file

;;; local variables:
;;; folded-file: t
;;; byte-compile-dynamic: t
;;; end:

;;}}}

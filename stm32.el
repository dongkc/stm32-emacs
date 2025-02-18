;;; stm32.el --- Support for the STM32 mircocontrollers programming
;; 
;; Filename: stm32.el
;; Description: GDB, CubeMX and flash functionality based on cmake-ide
;; Author: Alexander Lutsai <s.lyra@ya.ru>
;; Maintainer: Alexander Lutsai <s.lyra@ya.ru>
;; Created: 05 Sep 2016
;; Version: 0.01
;; Package-Requires: ()
;; Last-Updated: 11 Sep 2016
;;           By: Alexander Lutsai
;;     Update #: 0
;; URL: https://github.com/SL-RU/stm32-emacs
;; Doc URL: https://github.com/SL-RU/stm32-emacs
;; Keywords: stm32 emacs
;; Compatibility: emacs cmake-ide
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Commentary:
;;
;; Required:
;; 1) cmake-ide
;; 2) python
;; 3) cmake
;; 4) st-link https://github.com/texane/stlink
;; 5) clang
;; //4) https://github.com/SL-RU/STM32CubeMX_cmake
;;
;; 1) (require 'stm32)
;; 2) Create STM32CubeMx project and generate it for SW4STM32 toolchain
;; 3) M-x stm32-new-project RET *select CubeMX project path*
;; 4) open main.c
;; 5) M-x cmake-ide-compile to compile
;; 6) connect stlink to your PC
;; 7) stm32-run-st-util to start gdb server
;; 8) start GDB debugger with stm32-start-gdb
;; 9) in gdb) "load" to upload file to MC and "cont" to run.For more see https://github.com/texane/stlink
;; 5) good luck!
;;
;; To load that project after restart you need to (stm32-load-project).Or you can add to your init file (stm32-load-all-projects) for automatic loading.
;;
;; For normal file & header completion you need to (global-semantic-idle-scheduler-mode 1) in your init file.
;;
;; After CubeMx project regeneration or adding new libraries or new sources you need to do stm32-cmake-build
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Change Log:
;; 
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;; 
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Code:

(defgroup stm32 nil
  "STM32 projects integration"
  :group 'development)

(defcustom stm32-st-util-command "st-util"
  "The command to use to run st-util."
  :group 'stm32
  :type 'string)

(defun stm32-run-st-util ()
  "Run st-util gdb server."
  (interactive)
  (let ((p (get-buffer-process "*st-util*")))
    (when p
      (if (y-or-n-p "Kill currently running st-util? ")
	  (interrupt-process p)
	(user-error "St-util already running!"))))
  
  (sleep-for 1) ;wait for st-util being killed
  
  (with-temp-buffer "*st-util*"
		    (async-shell-command stm32-st-util-command
					 "*st-util*"
					 "*Messages*")
		    ))

(defun stm32-start-gdb ()
  "Strart gud arm-none-eabi-gdb and connect to st-util."
  (interactive)
  (let ((dir (stm32-get-project-build-dir))
	(name (stm32-get-project-name))
	(p (get-buffer-process "*st-util*")))
    (when (not p)
      (stm32-run-st-util))
    (when dir
      (let ((pth (concat dir "/" name ".elf")))
	(when (file-exists-p pth)
	  (progn
	    (message pth)
	    (gud-gdb (concat stm32-gdb-start pth))))))))


(defcustom stm32-gdb-start
  "arm-none-eabi-gdb -iex \"target extended-remote localhost:4242\" -i=mi "
  "Command to run gdb for gud."
  :group 'stm32
  :type 'string)

(defcustom stm32-build-dir
  "BUILD/ARCH_MAX/GCC_ARM"
  "Directory for mbed build."
  :group 'stm32
  :type 'string)

(require 'cl-lib)
(require 'gdb-mi)
(require 'gud)

(defun stm32-get-project-root-dir ()
  "Return root path of current project."
  (if (ffip-get-project-root-directory)
      (let
	  ((dir (expand-file-name (ffip-get-project-root-directory))))
	(if (file-exists-p dir)
	    (progn (message (concat "Project dir: "
				    dir))
		   dir) ;return dir
	  (progn
	    (message "No root. Build directory must be /build/")
	    (message dir))))))

(defun stm32-get-project-build-dir ()
  "Return path to build dir of current project."
  (if (stm32-get-project-root-dir)
      (let ((dir (concat
		  (stm32-get-project-root-dir)
		  stm32-build-dir)))
	(if (file-exists-p dir)
	    (progn (message (concat "Project build dir: "
				    dir))
		   dir) ;return dir
          (message "No build dir")))))

(defun stm32-get-project-name ()
  "Return path of current project."
  (if (stm32-get-project-root-dir)
      (let* ((pth (substring (stm32-get-project-root-dir) 0 -1))
	     (name (car (last (split-string pth "/")))))
	(message (concat "Project name: " name))
	name)
    (message "Wrong root directory")))

(defun stm32-flash-to-mcu()
  "Upload compiled binary to stm32 through gdb."
  (interactive)
  (let ((p (get-buffer-process "*st-util*")))
    (when (not p)
      (stm32-start-gdb))
    (sleep-for 4) ;wait for gdb being started
    (gdb-io-interrupt)
    (gud-basic-call "load")
    (gud-basic-call "cont")))

(defun stm32-kill-gdb()
  "Insert fix of vfpcc register in old versions of cmsis.  In cmsis_gcc.h.  Remove __set_FPSCR and __get_FPSCR functions."
  (interactive)
  (kill-process (get-buffer-process "*st-util*"))
  (kill-process (get-buffer-process "*gud-target extended-remote localhost:4242*"))
  (sleep-for 1)
  (kill-buffer "*st-util*")
  (kill-buffer "*gud-target extended-remote localhost:4242*")
)

(provide 'stm32)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; stm32.el ends here

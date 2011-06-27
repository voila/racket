#lang racket/base

(require racket/class racket/port racket/list racket/match
         racket/gui/base mrlib/switchable-button
         racket/unit drracket/tool)

(require (prefix-in tr: typed-scheme/typed-reader)
         typed-scheme/optimizer/logging)

(provide performance-report-drracket-button
         tool@)

;; DrRacket tool for reporting missed optimizations in the editor.

(define reverse-content-bitmap
  (let* ((bmp (make-bitmap 16 16))
         (bdc (make-object bitmap-dc% bmp)))
    (send bdc erase)
    (send bdc set-smoothing 'smoothed)
    (send bdc set-pen "black" 1 'transparent)
    (send bdc set-brush "blue" 'solid)
    (send bdc draw-ellipse 2 2 8 8)
    (send bdc set-brush "red" 'solid)
    (send bdc draw-ellipse 6 6 8 8)
    (send bdc set-bitmap #f)
    bmp))

(define highlights '())

;; performance-report-callback : drracket:unit:frame<%> -> void
(define (performance-report-callback drr-frame)
  (define defs     (send drr-frame get-definitions-text)) ; : text%
  (define portname (send defs      get-port-name))
  (define input    (open-input-text-editor defs))
  (port-count-lines! input)
  (define log '())
  (with-intercepted-tr-logging
   (lambda (l)
     (set! log (cons (cdr (vector-ref l 2)) ; log-entry struct
                     log)))
   (lambda ()
     (parameterize ([current-namespace  (make-base-namespace)]
                    [read-accept-reader #t])
       (expand (tr:read-syntax portname input)))))
  (set! log (reverse log))
  (define (highlight-irritant i)
    (let ([res (list (sub1 (syntax-position i))
                     (sub1 (+ (syntax-position i) (syntax-span i)))
                     "red" #f 'high 'hollow-ellipse)])
      (send defs highlight-range . res)
      res))
  ;; highlight
  (define new-highlights
    (for/list ([l (in-list log)])
      (match l
        [(log-entry msg raw-msg stx (app sub1 pos) irritants)
         (let* ([end  (+ pos (syntax-span stx))]
                [opt? (regexp-match #rx"^TR opt:" msg)] ;; opt or missed opt?
                [color (if opt? "lightgreen" "pink")])
           (send defs highlight-range pos end color)
           (send defs set-clickback pos end
                 (lambda (ed start end)
                   (message-box "Performance Report" raw-msg)))
           (list (list pos end color) ; record highlights to undo them later
                 (if irritants
                     (map highlight-irritant irritants)
                     '())))])))
  (set! highlights (append (apply append new-highlights) highlights)))

(define remove-highlights-mixin
  (mixin ((class->interface text%)) ()
    (inherit begin-edit-sequence
             end-edit-sequence
             insert
             get-text)
    (define (clear-highlights)
      (for ([h (in-list highlights)])
        (match h
          [(list start end color)
           (send this unhighlight-range . h)
           (send this remove-clickback start end)])))
    (define/augment (after-insert start len)
      (clear-highlights))
    (define/augment (after-delete start len)
      (clear-highlights))
    (super-new)))

(define-unit tool@
  (import drracket:tool^)
  (export drracket:tool-exports^)
  (define (phase1) (void))
  (define (phase2) (void))
  (drracket:get/extend:extend-definitions-text remove-highlights-mixin))

(define performance-report-drracket-button
  (list
   "Performance Report"
   reverse-content-bitmap
   performance-report-callback))
;;;; Copyright (c) 2017 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

(in-package :mezzano.compiler.backend.x86-64)

;;; Wrapper around an arbitrary x86 instruction.
(defclass x86-instruction (ir:backend-instruction)
  ((%inputs :initarg :inputs :reader ir:instruction-inputs)
   (%outputs :initarg :outputs :reader ir:instruction-outputs)
   (%opcode :initarg :opcode :reader x86-instruction-opcode)
   (%operands :initarg :operands :reader x86-instruction-operands)
   (%clobbers :initarg :clobbers :reader x86-instruction-clobbers)
   (%early-clobber :initarg :early-clobber :reader x86-instruction-early-clobber)
   (%prefix :initarg :prefix :reader x86-instruction-prefix))
  (:default-initargs :clobbers '() :early-clobber nil :prefix nil))

(defmethod ra:instruction-clobbers ((instruction x86-instruction) (architecture sys.c:x86-64-target))
  (x86-instruction-clobbers instruction))

(defmethod ra:instruction-inputs-read-before-outputs-written-p ((instruction x86-instruction) (architecture sys.c:x86-64-target))
  (not (x86-instruction-early-clobber instruction)))

(defmethod ir:replace-all-registers ((instruction x86-instruction) substitution-function)
  (setf (slot-value instruction '%inputs) (mapcar substitution-function (slot-value instruction '%inputs)))
  (setf (slot-value instruction '%outputs) (mapcar substitution-function (slot-value instruction '%outputs)))
  (setf (slot-value instruction '%operands)
        (loop
           for operand in (slot-value instruction '%operands)
           collect (cond ((typep operand 'ir:virtual-register)
                          (funcall substitution-function operand))
                         ((and (consp operand)
                               (not (member (first operand) '(:constant :function))))
                          ;; Replace 2 levels to catch indexed memory accesses.
                          (loop
                             for thing in operand
                             collect (if (consp thing)
                                         (mapcar substitution-function thing)
                                         (funcall substitution-function thing))))
                         (t operand)))))

(defmethod ir:print-instruction ((instruction x86-instruction))
  (format t "   ~S~%"
          `(:x86 ,(x86-instruction-opcode instruction) ,(x86-instruction-operands instruction))))

;;; Similar to x86-instruction, it presents a three operand (dest, src1, src2) representation
;;; for two operand (dest/src1, src2) instructions.
;;; Used to preserve SSA form, gets lowered to a move & x86-instruction just before register allocation.
(defclass x86-fake-three-operand-instruction (ir:backend-instruction)
  ((%opcode :initarg :opcode :reader x86-instruction-opcode)
   (%result :initarg :result :accessor x86-fake-three-operand-result)
   (%lhs :initarg :lhs :accessor x86-fake-three-operand-lhs)
   (%rhs :initarg :rhs :accessor x86-fake-three-operand-rhs)
   (%imm :initarg :imm :accessor x86-fake-three-operand-imm)
   (%clobbers :initarg :clobbers :reader x86-instruction-clobbers)
   (%early-clobber :initarg :early-clobber :reader x86-instruction-early-clobber))
  (:default-initargs :clobbers '() :early-clobber nil :imm nil))

(defmethod ra:instruction-clobbers ((instruction x86-fake-three-operand-instruction) (architecture sys.c:x86-64-target))
  (x86-instruction-clobbers instruction))

(defmethod ra:instruction-inputs-read-before-outputs-written-p ((instruction x86-fake-three-operand-instruction) (architecture sys.c:x86-64-target))
  (not (x86-instruction-early-clobber instruction)))

(defmethod ir:instruction-inputs ((instruction x86-fake-three-operand-instruction))
  (list (x86-fake-three-operand-lhs instruction)
        (x86-fake-three-operand-rhs instruction)))

(defmethod ir:instruction-outputs ((instruction x86-fake-three-operand-instruction))
  (list (x86-fake-three-operand-result instruction)))

(defmethod ir:replace-all-registers ((instruction x86-fake-three-operand-instruction) substitution-function)
  (setf (x86-fake-three-operand-result instruction) (funcall substitution-function (x86-fake-three-operand-result instruction)))
  (setf (x86-fake-three-operand-lhs instruction) (funcall substitution-function (x86-fake-three-operand-lhs instruction)))
  (setf (x86-fake-three-operand-rhs instruction) (funcall substitution-function (x86-fake-three-operand-rhs instruction))))

(defmethod ir:print-instruction ((instruction x86-fake-three-operand-instruction))
  (format t "   ~S~%"
          `(:x86-fake-three-operand ,(x86-instruction-opcode instruction)
                                    ,(x86-fake-three-operand-result instruction)
                                    ,(x86-fake-three-operand-lhs instruction)
                                    ,(x86-fake-three-operand-rhs instruction)
                                    ,@(when (x86-fake-three-operand-imm instruction)
                                        (list (x86-fake-three-operand-imm instruction))))))

;;; Wrapper around x86 branch instructions.
(defclass x86-branch-instruction (ir:terminator-instruction)
  ((%opcode :initarg :opcode :accessor x86-instruction-opcode)
   (%true-target :initarg :true-target :accessor x86-branch-true-target)
   (%false-target :initarg :false-target :accessor x86-branch-false-target)))

(defmethod ir:successors (function (instruction x86-branch-instruction))
  (list (x86-branch-true-target instruction)
        (x86-branch-false-target instruction)))

(defmethod ir:instruction-inputs ((instruction x86-branch-instruction))
  '())

(defmethod ir:instruction-outputs ((instruction x86-branch-instruction))
  '())

(defmethod ir:replace-all-registers ((instruction x86-branch-instruction) substitution-function)
  )

(defmethod ir:print-instruction ((instruction x86-branch-instruction))
  (format t "   ~S~%"
          `(:x86-branch ,(x86-instruction-opcode instruction) ,(x86-branch-true-target instruction) ,(x86-branch-false-target instruction))))

;;; SSE/MMX (un)boxing instructions.

(defclass box-mmx-vector-instruction (ir:box-instruction)
  ())

(defmethod ir:box-type ((instruction box-mmx-vector-instruction))
  'mezzano.simd:mmx-vector)

(defmethod ir:print-instruction ((instruction box-mmx-vector-instruction))
  (format t "   ~S~%"
          `(:box-mmx-vector
            ,(ir:box-destination instruction)
            ,(ir:box-source instruction))))

(defclass unbox-mmx-vector-instruction (ir:unbox-instruction)
  ())

(defmethod ir:box-type ((instruction unbox-mmx-vector-instruction))
  'mezzano.simd:mmx-vector)

(defmethod ir:print-instruction ((instruction unbox-mmx-vector-instruction))
  (format t "   ~S~%"
          `(:unbox-mmx-vector
            ,(ir:unbox-destination instruction)
            ,(ir:unbox-source instruction))))

(defclass box-sse-vector-instruction (ir:box-instruction)
  ())

(defmethod ir:box-type ((instruction box-sse-vector-instruction))
  'mezzano.simd:sse-vector)

(defmethod ir:print-instruction ((instruction box-sse-vector-instruction))
  (format t "   ~S~%"
          `(:box-sse-vector
            ,(ir:box-destination instruction)
            ,(ir:box-source instruction))))

(defclass unbox-sse-vector-instruction (ir:unbox-instruction)
  ())

(defmethod ir:box-type ((instruction unbox-sse-vector-instruction))
  'mezzano.simd:sse-vector)

(defmethod ir:print-instruction ((instruction unbox-sse-vector-instruction))
  (format t "   ~S~%"
          `(:unbox-sse-vector
            ,(ir:unbox-destination instruction)
            ,(ir:unbox-source instruction))))

(defun lower-complicated-box-instructions (backend-function)
  (do* ((inst (ir:first-instruction backend-function) next-inst)
        (next-inst (ir:next-instruction backend-function inst) (if inst (ir:next-instruction backend-function inst))))
       ((null inst))
    (multiple-value-bind (box-function box-register)
        (typecase inst
          (ir:box-unsigned-byte-64-instruction
           (values 'mezzano.runtime::%%make-unsigned-byte-64-rax :rax))
          (ir:box-signed-byte-64-instruction
           (values 'mezzano.runtime::%%make-signed-byte-64-rax :rax))
          (ir:box-double-float-instruction
           (values 'sys.int::%%make-double-float-rax :rax))
          (box-mmx-vector-instruction
           (values 'mezzano.simd::%%make-mmx-vector-rax :rax))
          (box-sse-vector-instruction
           (values 'mezzano.simd::%%make-sse-vector-xmm0 :xmm0)))
      (when box-function
        (let* ((value (ir:box-source inst))
               (result (ir:box-destination inst)))
          (ir:insert-before
           backend-function inst
           (make-instance 'ir:move-instruction
                          :destination box-register
                          :source value))
          (ir:insert-before
           backend-function inst
           (make-instance 'x86-instruction
                          :opcode 'lap:mov64
                          :operands (list :r13 `(:function ,box-function))
                          :inputs (list)
                          :outputs (list :r13)
                          :clobbers '(:r13)))
          (ir:insert-before
           backend-function inst
           (make-instance 'x86-instruction
                          :opcode 'lap:call
                          :operands (list `(:object :r13 ,sys.int::+fref-entry-point+))
                          :inputs (list :r13 box-register)
                          :outputs (list :r8)
                          :clobbers '(:rax :rcx :rdx :rsi :rdi :rbx :r8 :r9 :r10 :r11 :r12 :r13 :r14 :r15
                                      :mm0 :mm1 :mm2 :mm3 :mm4 :mm5 :mm6 :mm7
                                      :xmm0 :xmm1 :xmm2 :xmm3 :xmm4 :xmm5 :xmm6 :xmm7 :xmm8
                                      :xmm9 :xmm10 :xmm11 :xmm12 :xmm13 :xmm14 :xmm15)))
          (ir:insert-before
           backend-function inst
           (make-instance 'ir:move-instruction
                          :destination result
                          :source :r8))
          (ir:remove-instruction backend-function inst))))))

(defun lower-fake-three-operand-instructions (backend-function)
  "Lower x86-fake-three-operand-instructions to a move & x86-instruction.
The resulting code is not in SSA form so this pass must be late in the compiler."
  (ir:do-instructions (inst backend-function)
    (when (typep inst 'x86-fake-three-operand-instruction)
      (ir:insert-before backend-function inst
                        (make-instance 'ir:move-instruction
                                       :destination (x86-fake-three-operand-result inst)
                                       :source (x86-fake-three-operand-lhs inst)))
      (change-class inst 'x86-instruction
                    :operands (if (x86-fake-three-operand-imm inst)
                                  (list (x86-fake-three-operand-result inst) (x86-fake-three-operand-rhs inst) (x86-fake-three-operand-imm inst))
                                  (list (x86-fake-three-operand-result inst) (x86-fake-three-operand-rhs inst)))
                    :inputs (list (x86-fake-three-operand-result inst) (x86-fake-three-operand-rhs inst))
                    :outputs (list (x86-fake-three-operand-result inst))
                    :prefix nil))))

(defmethod ir:perform-target-lowering (backend-function (target sys.c:x86-64-target))
  (lower-builtins backend-function))

(defmethod ir:perform-target-lowering-post-ssa (backend-function (target sys.c:x86-64-target))
  (lower-complicated-box-instructions backend-function)
  (lower-fake-three-operand-instructions backend-function))

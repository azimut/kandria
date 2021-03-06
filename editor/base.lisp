(in-package #:org.shirakumo.fraf.leaf)

(defclass editor-ui (ui)
  ())

(defclass base-editor (alloy:observable-object trial:entity)
  ((flare:name :initform :editor)
   (marker :initform (make-instance 'trial::lines) :accessor marker)
   (ui :initform (make-instance 'editor-ui) :accessor ui)
   (entity :initform NIL :accessor entity)
   (tool :accessor tool)
   (alt-tool :accessor alt-tool)
   (toolbar :accessor toolbar)
   (history :initform (make-instance 'linear-history) :accessor history)))

(alloy:define-observable (setf entity) (entity alloy:observable))

(defmethod compute-resources :after ((editor base-editor) resources readying traversal)
  (vector-push-extend (ui editor) resources))

(defmethod initialize-instance :after ((editor base-editor) &key)
  (let* ((ui (ui editor))
         (focus (make-instance 'alloy:focus-list :focus-parent (alloy:focus-tree ui)))
         (layout (make-instance 'alloy:border-layout :layout-parent (alloy:layout-tree ui)))
         (menu (make-instance 'editmenu))
         (toolbar (make-instance 'toolbar :editor editor :entity NIL))
         (entity (make-instance 'entity-widget :editor editor :side :west)))
    (setf (alt-tool editor) (make-instance 'browser :editor editor))
    (setf (toolbar editor) toolbar)
    (alloy:observe 'entity editor (lambda (value object) (setf (entity entity) value)))
    (alloy:enter menu layout :place :north)
    (alloy:enter menu focus)
    (alloy:enter toolbar layout :place :south)
    (alloy:enter toolbar focus)
    (alloy:enter entity layout :place :west :size (alloy:un 300))
    (alloy:enter entity focus)
    (alloy:register ui ui)))

(defmethod register-object-for-pass :after ((pass per-object-pass) (editor base-editor))
  (register-object-for-pass pass (maybe-finalize-inheritance 'editor))
  (register-object-for-pass pass (maybe-finalize-inheritance 'chunk-editor))
  (register-object-for-pass pass (maybe-finalize-inheritance 'trial::lines)))

(defmethod update-instance-for-different-class :after (previous (editor base-editor) &key)
  (reinitialize-instance (toolbar editor) :editor editor :entity (entity editor))
  (setf (tool editor) (make-instance (default-tool editor) :editor editor)))

(defmethod (setf active-p) (value (editor base-editor))
  (with-buffer-tx (light (asset 'leaf 'light-info))
    (setf (active-p light) (if value 0 1)))
  (cond (value
         (pause-game T editor)
         (handle (make-instance 'resize :width (width *context*) :height (height *context*))
                 (ui editor))
         (change-class editor (editor-class (entity editor))))
        (T
         (change-class editor 'inactive-editor)
         (unpause-game T editor))))

(defmethod default-tool :around ((editor base-editor))
  (or (default-tool (entity editor))
      (call-next-method)))

(defmethod default-tool ((editor base-editor))
  'browser)

(defmethod undo ((editor base-editor) region)
  (undo (history editor) region))

(defmethod redo ((editor base-editor) region)
  (redo (history editor) region))

(defmethod register :after ((editor base-editor) (scene scene))
  (add-handler editor scene))

(defmethod handle ((event event) (editor base-editor)))

(defmethod handle ((event toggle-editor) (editor base-editor))
  (setf (active-p editor) (not (active-p editor))))

(defclass inactive-editor (base-editor)
  ())

(defmethod active-p ((editor inactive-editor)) NIL)

import PencilKit
import SwiftUI
import UIKit

@MainActor
final class CanvasActions: ObservableObject {
    weak var canvas: PKCanvasView?
    var replaced: ((PKDrawing) -> Void)?
    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    func clear() { replace(with: PKDrawing()) }
    private func replace(with drawing: PKDrawing) {
        guard let canvas else { return }
        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self) { $0.replace(with: previous) }
        canvas.undoManager?.setActionName("Clear Canvas")
        canvas.drawing = drawing
        replaced?(drawing)
    }
}

struct InkCanvas: UIViewControllerRepresentable {
    let drawingData: Data
    let fingerDrawing: Bool
    let actions: CanvasActions
    let changed: (Data) -> Void
    let interaction: (Bool) -> Void

    func makeUIViewController(context: Context) -> InkController {
        InkController(data: drawingData, fingerDrawing: fingerDrawing, actions: actions, changed: changed, interaction: interaction)
    }
    func updateUIViewController(_ controller: InkController, context: Context) {
        controller.changed = changed
        controller.interaction = interaction
        controller.setFingerDrawing(fingerDrawing)
    }
}

/// PKCanvasView supplies native tiled ink, selection/lasso, ruler, erasers,
/// Pencil interaction, scrolling, and the system tool picker.
final class InkController: UIViewController, PKCanvasViewDelegate {
    let canvas = PKCanvasView()
    private let picker = PKToolPicker()
    private let initialData: Data
    private let actions: CanvasActions
    private var configured = false
    private var updatingExtent = false
    private var logicalHeight: CGFloat = 2048
    private var lastWidth: CGFloat = 0
    private var fingerDrawing: Bool
    var changed: (Data) -> Void
    var interaction: (Bool) -> Void

    init(data: Data, fingerDrawing: Bool, actions: CanvasActions, changed: @escaping (Data) -> Void, interaction: @escaping (Bool) -> Void) {
        initialData = data
        self.fingerDrawing = fingerDrawing
        self.actions = actions
        self.changed = changed
        self.interaction = interaction
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use the drawing initializer") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(white: 25.0 / 255, alpha: 1) : .white }
        view.backgroundColor = background
        canvas.backgroundColor = background
        canvas.isOpaque = true
        canvas.tintColor = .label
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 220, right: 0)
        canvas.verticalScrollIndicatorInsets = UIEdgeInsets(top: 100, left: 0, bottom: 0, right: 0)
        canvas.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        canvas.drawing = (try? NoteExporter.drawing(initialData)) ?? PKDrawing()
        canvas.delegate = self
        view.addSubview(canvas)
        setFingerDrawing(fingerDrawing)
        actions.canvas = canvas
        actions.replaced = { [weak self] ink in
            self?.changed(ink.dataRepresentation())
            self?.extendIfNeeded()
        }
        picker.addObserver(canvas)
        configured = true
        canvas.accessibilityIdentifier = "continuousCanvas"
        canvas.accessibilityLabel = "Continuous handwriting canvas"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        picker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }
    override func viewWillDisappear(_ animated: Bool) {
        picker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
        interaction(false)
        super.viewWillDisappear(animated)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard canvas.bounds.width > 0 else { return }
        if abs(canvas.bounds.width - lastWidth) > 0.5 {
            let oldScale = max(canvas.zoomScale, 0.01)
            let logicalOffset = max(0, canvas.contentOffset.y / oldScale)
            lastWidth = canvas.bounds.width
            let fit = canvas.bounds.width / CanvasGeometry.width
            canvas.minimumZoomScale = min(canvas.minimumZoomScale, fit)
            canvas.maximumZoomScale = max(canvas.maximumZoomScale, fit)
            canvas.setZoomScale(fit, animated: false)
            canvas.minimumZoomScale = fit
            canvas.maximumZoomScale = fit
            extendIfNeeded()
            canvas.contentOffset = CGPoint(x: 0, y: logicalOffset == 0 ? -100 : logicalOffset * fit)
        }
        extendIfNeeded()
    }
    func setFingerDrawing(_ enabled: Bool) {
        fingerDrawing = enabled
        canvas.drawingPolicy = enabled ? .anyInput : .pencilOnly
        canvas.panGestureRecognizer.minimumNumberOfTouches = enabled ? 2 : 1
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard configured else { return }
        changed(canvasView.drawing.dataRepresentation())
        extendIfNeeded()
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { interaction(true) }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { interaction(false) }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { interaction(true) }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { interaction(false) }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { interaction(false) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { extendIfNeeded() }

    private func extendIfNeeded() {
        guard configured, !updatingExtent, canvas.bounds.width > 0 else { return }
        updatingExtent = true
        defer { updatingExtent = false }
        let scale = max(canvas.zoomScale, 0.01)
        let visibleBottom = max(0, canvas.contentOffset.y + canvas.bounds.height) / scale
        let inkBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        logicalHeight = max(logicalHeight, visibleBottom + 1536, inkBottom + 1536)
        let desired = CGSize(width: canvas.bounds.width, height: ceil(logicalHeight * scale))
        if abs(canvas.contentSize.height - desired.height) > 1 || abs(canvas.contentSize.width - desired.width) > 1 {
            canvas.contentSize = desired
        }
    }
}

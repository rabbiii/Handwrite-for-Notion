import PencilKit
import SwiftUI
import UIKit

@MainActor
final class CanvasActions: ObservableObject {
    weak var canvas: PKCanvasView?
    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
}

struct InkCanvas: UIViewControllerRepresentable {
    let drawingData: Data
    let fingerDrawing: Bool
    let actions: CanvasActions
    let changed: (Data) -> Void

    func makeUIViewController(context: Context) -> InkController {
        InkController(data: drawingData, fingerDrawing: fingerDrawing, actions: actions, changed: changed)
    }
    func updateUIViewController(_ controller: InkController, context: Context) {
        controller.changed = changed
        controller.setFingerDrawing(fingerDrawing)
    }
}

final class InkController: UIViewController, PKCanvasViewDelegate, UIScrollViewDelegate {
    let canvas = PKCanvasView()
    private let scroll = UIScrollView()
    private let paper = UIView(frame: NoteExporter.pageRect)
    private let picker = PKToolPicker()
    private let initialData: Data
    private let actions: CanvasActions
    private var configured = false
    private var lastViewport: CGSize = .zero
    var changed: (Data) -> Void
    private var fingerDrawing: Bool

    init(data: Data, fingerDrawing: Bool, actions: CanvasActions, changed: @escaping (Data) -> Void) {
        self.initialData = data
        self.fingerDrawing = fingerDrawing
        self.actions = actions
        self.changed = changed
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(data:fingerDrawing:actions:changed:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.secondarySystemBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.delegate = self
        // Only fingers navigate; Pencil touches belong to the drawing recognizer.
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scroll.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scroll.maximumZoomScale = 3
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = NoteExporter.pageSize
        scroll.addSubview(paper)
        view.addSubview(scroll)
        paper.backgroundColor = .white
        paper.clipsToBounds = true
        canvas.frame = paper.bounds
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.isScrollEnabled = false
        canvas.contentSize = NoteExporter.pageSize
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.drawing = (try? NoteExporter.drawing(initialData)) ?? PKDrawing()
        // The model validates PKDrawing before this controller is ever displayed.
        canvas.delegate = self
        paper.addSubview(canvas)
        setFingerDrawing(fingerDrawing)
        actions.canvas = canvas
        picker.addObserver(canvas)
        configured = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        picker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        picker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scroll.bounds.size != lastViewport, scroll.bounds.width > 0 else { return }
        let wasFitted = abs(scroll.zoomScale - scroll.minimumZoomScale) < 0.02 || lastViewport == .zero
        lastViewport = scroll.bounds.size
        let fit = min(1, max(0.1, (scroll.bounds.width - 32) / NoteExporter.pageSize.width))
        scroll.minimumZoomScale = fit
        if wasFitted { scroll.setZoomScale(fit, animated: false) }
        centerPaper()
    }

    func setFingerDrawing(_ enabled: Bool) {
        fingerDrawing = enabled
        canvas.drawingPolicy = enabled ? .anyInput : .pencilOnly
        scroll.panGestureRecognizer.minimumNumberOfTouches = enabled ? 2 : 1
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard configured else { return }
        changed(canvasView.drawing.dataRepresentation())
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { paper }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPaper() }
    private func centerPaper() {
        scroll.contentInset = UIEdgeInsets(top: 16,
            left: max(16, (scroll.bounds.width - scroll.contentSize.width) / 2),
            bottom: 80, right: 16)
    }
}

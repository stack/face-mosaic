//
//  ViewController.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/1/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa
import Metal
import MetalKit

fileprivate let ImageCollectionViewItemIdentifier = NSUserInterfaceItemIdentifier(rawValue: "ImageCollectionViewItem")

fileprivate let ImagesMainSection = 0

fileprivate enum ExportType: CustomStringConvertible {
    case png
    case tiff

    // FIXME: For Swift 4.2, use CaseIterable instead
    static var allCases: [ExportType] {
        return [.png, .tiff]
    }
    
    var fileExtension: String {
        switch self {
        case .png:
            return kUTTypePNG as String
        case .tiff:
            return kUTTypeTIFF as String
        }
    }
    
    var description: String {
        switch self {
        case .png:
            return NSLocalizedString("PNG", comment: "PNG Export Description")
        case .tiff:
            return NSLocalizedString("TIFF", comment: "TIFF Export Description")
        }
    }
}

class ViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate {

    // MARK: - Properties
    
    @IBOutlet weak var imageCollectionView: NSCollectionView!
    
    @IBOutlet weak var addImageButton: NSButton!
    @IBOutlet weak var removeImageButton: NSButton!
    
    @IBOutlet weak var maxRotationLabel: NSTextField!
    @IBOutlet weak var maxRotationSlider: NSSlider!
    
    @IBOutlet weak var iterationsLabel: NSTextField!
    @IBOutlet weak var iterationsSlider: NSSlider!
    
    @IBOutlet weak var scaleLabel: NSTextField!
    @IBOutlet weak var scaleSlider: NSSlider!
    
    @IBOutlet weak var backgroundColorLabel: NSTextField!
    @IBOutlet weak var backgroundColorButton: ColorPickerButton!
    private var backgroundColorPanel: NSColorPanel = NSColorPanel()
    
    @IBOutlet weak var resolutionLabel: NSTextField!
    @IBOutlet weak var resolutionWidthTextField: NSTextField!
    @IBOutlet weak var resolutionHeightTextField: NSTextField!
    
    @IBOutlet weak var seedLabel: NSTextField!
    @IBOutlet weak var seedTextField: NSTextField!
    
    @IBOutlet weak var exportButton: NSButton!
    
    @IBOutlet weak var metalView: MTKView!
    
    var faces: [Face] = []
    
    var renderer: Renderer!
    
    private var importQueue: DispatchQueue = DispatchQueue(label: "Import")
    
    private var exportPanel: NSSavePanel? = nil
    private var exportType: ExportType = .png
    private var exportQueue: DispatchQueue = DispatchQueue(label: "Export")
    
    // MARK: - Actions
    
    func addFace(from url: URL) {
        addFaces(from: [url])
    }
    
    func addFaces(from urls: [URL]) {
        // Disable the UI for processing
        toggleAvailability(enabled: false)
        
        // Dispatch to the import thread
        importQueue.async {
            // Build faces for each url
            let faces = urls.map { Face(url: $0) }
            
            // Send the faces to the renderer
            self.renderer.addFaces(faces: faces) { (loadingError) in
                DispatchQueue.main.sync {
                    if let error = loadingError {
                        // An error, so show it and don't add the faces to the interface
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = NSLocalizedString("Failed to load one or more of the provided images", comment: "Image loading failure message")
                        alert.informativeText = "\(error)"
                        
                        guard let window = self.view.window else {
                            fatalError("Failed to load one or more images and no window to present this fact")
                        }
                        
                        alert.beginSheetModal(for: window, completionHandler: { _ in
                            self.toggleAvailability(enabled: true)
                        })
                    } else {
                        // Append the faces to the collection
                        let insertRange = self.faces.count ..< (self.faces.count + faces.count)
                        self.faces.append(contentsOf: faces)
                        
                        var paths: Set<IndexPath> = []
                        for item in insertRange {
                            paths.insert(IndexPath(item: item, section: ImagesMainSection))
                        }
                        
                        self.imageCollectionView.insertItems(at: paths)
                        
                        self.toggleAvailability(enabled: true)
                    }
                }
            }
        }
    }
    
    @IBAction func addImage(_ sender: Any?) {
        guard let window = view.window else {
            fatalError("Cannot add an image when there's no window for the view")
        }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = [kUTTypePNG as String];
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        panel.beginSheetModal(for: window) { (response) in
            if response == .OK {
                self.addFaces(from: panel.urls)
            }
        }
    }
    
    @IBAction func export(_ sender: Any?) {
        // Ensure we have a window
        guard let window = view.window else {
            fatalError("No window for the view")
        }
        
        // Build the file type selection menu
        let label = NSTextField(labelWithString: NSLocalizedString("Format", comment: "Save Format Label"))
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let popUpButton = NSPopUpButton(frame: .zero)
        popUpButton.action = #selector(ViewController.exportChangedExtension(_:))
        popUpButton.target = self
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
        
        for type in ExportType.allCases {
            popUpButton.addItem(withTitle: type.description)
        }

        popUpButton.selectItem(at: 0)
        exportType = ExportType.allCases[0]
        
        let stackView = NSStackView(views: [label, popUpButton])
        stackView.orientation = .horizontal
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let wrapperView = NSView(frame: .zero)
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        
        wrapperView.addSubview(stackView)
        
        wrapperView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=8)-[stack]-(>=8)-|", options: [], metrics: nil, views: ["stack": stackView]))
        wrapperView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(>=8)-[stack]-(>=8)-|", options: [], metrics: nil, views: ["stack": stackView]))
        wrapperView.addConstraint(NSLayoutConstraint(item: stackView, attribute: .centerX, relatedBy: .equal, toItem: wrapperView, attribute: .centerX, multiplier: 1.0, constant: 0.0))
        wrapperView.addConstraint(NSLayoutConstraint(item: stackView, attribute: .centerY, relatedBy: .equal, toItem: wrapperView, attribute: .centerY, multiplier: 1.0, constant: 0.0))
        
        // Build the panel
        let panel = NSSavePanel()
        panel.accessoryView = wrapperView
        panel.allowedFileTypes = [exportType.fileExtension]
        panel.canCreateDirectories = true
        panel.canSelectHiddenExtension = true
        panel.title = NSLocalizedString("Export Mosaic", comment: "Export Mosaic Save Dialog Title")
        
        exportPanel = panel
        
        // Run the panel
        panel.beginSheetModal(for: window) { (result) in
            guard result == .OK else {
                return
            }
            
            guard let url = panel.url else {
                return
            }
            
            self.toggleAvailability(enabled: false)
            self.export(to: url, type: self.exportType) {
                self.toggleAvailability(enabled: true)
            }
        }
    }
    
    private func export(to url: URL, type: ExportType, completionHandler: @escaping () -> Void) {
        exportQueue.async {
            let startDate = Date()
            
            // Blit the data to memory
            let imageBuffer = self.renderer.makeImageBuffer()
            
            // Convert data to a data provider
            var rawData = [UInt8](repeating: 0, count: imageBuffer.length)
            memcpy(&rawData, imageBuffer.contents(), imageBuffer.length)
            
            let dataProvider = CGDataProvider(dataInfo: nil, data: &rawData, size: rawData.count) { _,_,_ in }!
            
            // Generate the image from the data
            let image = CGImage(
                width: Int(self.renderer.canvasSize.x),
                height: Int(self.renderer.canvasSize.y),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(self.renderer.canvasSize.x) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),  CGBitmapInfo.byteOrder32Little],
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
            
            // Write the image to the filesystem
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type.fileExtension as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            
            let result = CGImageDestinationFinalize(destination)
            if !result {
                print("Failed to finalize image destination")
            }
            
            let endDate = Date()
            
            let duration = endDate.timeIntervalSinceReferenceDate - startDate.timeIntervalSinceReferenceDate
            
            print("Export took \(duration) seconds")
            
            DispatchQueue.main.sync {
                completionHandler()
            }
        }
    }
    
    @IBAction func exportChangedExtension(_ sender: Any?) {
        guard let popUpButton = sender as? NSPopUpButton else {
            return
        }
        
        guard popUpButton.indexOfSelectedItem >= 0 else {
            return
        }
        
        // Save the extension
        exportType = ExportType.allCases[popUpButton.indexOfSelectedItem]
        
        // Apply the extension to the save panel
        guard let panel = exportPanel else {
            return
        }
        
        panel.allowedFileTypes = [exportType.fileExtension]
    }

    @IBAction func interationsChanged(_ sender: Any?) {
        let iterations = Int(iterationsSlider.integerValue)
        renderer.iterations = iterations
        
        let template = NSLocalizedString("Iterations: %i", comment: "Iterations Label Template")
        iterationsLabel.stringValue = String(format: template, iterations)
    }
    
    @IBAction func maxRotationChanged(_ sender: Any?) {
        let value = maxRotationSlider.floatValue / 360.0
        renderer.maxRotation = value
        
        let template = NSLocalizedString("Max Rotation: %iº", comment: "Max Rotation Label Template")
        maxRotationLabel.stringValue = String(format: template, Int(maxRotationSlider.floatValue))
        
        if value == 0.0 {
            tickFeedback()
        }
    }
    
    @IBAction func removeImage(_ sender: Any?) {
        let faces = imageCollectionView.selectionIndexPaths.map { self.faces[$0.item] }
        removeFaces(faces: faces)
    }
    
    func removeFaces(faces: [Face]) {
        toggleAvailability(enabled: false)
        
        importQueue.async {
            self.renderer.removeFaces(faces: faces, completionHandler: { (removalError) in
                DispatchQueue.main.sync {
                    if let error = removalError {
                        // An error, so show it and don't add the faces to the interface
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = NSLocalizedString("Failed to remove one or more of the provided images", comment: "Image loading failure message")
                        alert.informativeText = "\(error)"
                        
                        guard let window = self.view.window else {
                            fatalError("Failed to remove one or more images and no window to present this fact")
                        }
                        
                        alert.beginSheetModal(for: window, completionHandler: { _ in
                            self.toggleAvailability(enabled: true)
                        })
                    } else {
                        for face in faces {
                            self.faces.removeAll(where: { $0 == face })
                        }
                        
                        self.imageCollectionView.deleteItems(at: self.imageCollectionView.selectionIndexPaths)
                        
                        self.toggleAvailability(enabled: true)
                    }
                }
            })
        }
        
        /*
        let sortedIndexes = indexes
            .sorted()
            .reversed()
         for index in sortedIndexes {
         images.remove(at: index.item)
         renderer.removeFace(at: index.item)
         }
         
         imageCollectionView.deleteItems(at: indexes)
        */
    }
    
    @IBAction func scaleChanged(_ sender: Any?) {
        let value = scaleSlider.floatValue
        renderer.scale = value / 100.0
        
        let template = NSLocalizedString("Scale: %i%%", comment: "Scale Label Template")
        scaleLabel.stringValue = String(format: template, Int(value))
        
        if value == 50.0 {
            tickFeedback()
        }
    }
    
    @IBAction func toggleBackgroundColorPicker(_ sender: Any?) {
        if backgroundColorPanel.isVisible {
            backgroundColorPanel.close()
        } else {
            backgroundColorPanel.color = backgroundColorButton.selectedColor
            backgroundColorPanel.title = NSLocalizedString("Background Color Picker", comment: "Background Color Picker Title")
            backgroundColorPanel.showsAlpha = true
            
            backgroundColorPanel.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - NSViewController Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Prepare the renderer
        metalView.device = MTLCreateSystemDefaultDevice()
        
        renderer = IterationRenderer(metalView: metalView)
        renderer.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
        
        metalView.delegate = renderer
        metalView.framebufferOnly = true
        
        // Listen for color changes from the background color picker
        NotificationCenter.default.addObserver(forName: NSColorPanel.colorDidChangeNotification, object: backgroundColorPanel, queue: nil) { (notification) in
            self.backgroundColorButton.selectedColor = self.backgroundColorPanel.color
            self.renderer.backgroundColor = self.backgroundColorPanel.color
        }
        
        // Update the initial UI elements
        setRemoveButtonState()
        
        // Remove the background from the collection view
        self.imageCollectionView.backgroundColors = [.clear]
    }
    
    
    // MARK: - Protocols
    
    // MARK: <NSCollectionViewDataSource>
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ImageCollectionViewItemIdentifier, for: indexPath)
        
        guard let imageItem = item as? ImageCollectionViewItem else {
            return item
        }
        
        imageItem.image = NSImage(byReferencing: faces[indexPath.item].url)
        
        return imageItem
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return faces.count
    }
    
    // MARK: <NSCollectionViewDelegate>
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        setRemoveButtonState()
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        setRemoveButtonState()
    }
    
    // MARK: <NSTextFieldDelegate>
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }
        
        if textField == resolutionWidthTextField || textField == resolutionHeightTextField {
            let width = resolutionWidthTextField.integerValue
            let height = resolutionHeightTextField.integerValue
            
            guard width > 0, height > 0 else {
                return
            }
            
            let size = float2(Float(width), Float(height))
            renderer.canvasSize = size
        } else if textField == seedTextField {
            let seed = seedTextField.stringValue.isEmpty ? "Seed" : seedTextField.stringValue
            let data = seed.data(using: .utf8)!
            
            renderer.seedData = data
        }
    }
    
    // MARK: - Utilities
    
    private func tickFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    
    private func toggleAvailability(enabled: Bool) {
        addImageButton.isEnabled = enabled
        
        if enabled {
            setRemoveButtonState()
        } else {
            removeImageButton.isEnabled = false
        }
        
        maxRotationSlider.isEnabled = enabled
        iterationsSlider.isEnabled = enabled
        scaleSlider.isEnabled = enabled
        backgroundColorButton.isEnabled = enabled
        resolutionWidthTextField.isEnabled = enabled
        resolutionHeightTextField.isEnabled = enabled
        seedTextField.isEnabled = enabled
        exportButton.isEnabled = enabled
    }
    
    private func setRemoveButtonState() {
        if imageCollectionView.selectionIndexes.isEmpty {
            removeImageButton.isEnabled = false
        } else {
            removeImageButton.isEnabled = true
        }
    }

}


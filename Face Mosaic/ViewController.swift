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
    
    @IBOutlet weak var seedTextField: NSTextField!
    
    @IBOutlet weak var metalView: MTKView!
    
    var imageURLs: [URL] = []
    
    var renderer: Renderer!
    
    
    // MARK: - Actions
    
    @IBAction func addImage(_ sender: Any?) {
        guard let window = view.window else {
            fatalError("Cannot add an image when there's no window for the view")
        }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = [kUTTypePNG as String];
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        panel.beginSheetModal(for: window) { (response) in
            if response == .OK {
                if let url = panel.url {
                    self.imageURLs.append(url)
                    
                    let path = IndexPath(item: self.imageURLs.count - 1, section: ImagesMainSection)
                    let items: Set<IndexPath> = [path]
                    self.imageCollectionView.insertItems(at: items)
                    
                    self.renderer.addFace(url: url)
                }
            }
        }
    }

    @IBAction func interationsChanged(_ sender: Any?) {
        let iterations = UInt(iterationsSlider.integerValue)
        renderer.iterations = iterations
        
        let template = NSLocalizedString("Iterations: %i", comment: "Iterations Label Template")
        iterationsLabel.stringValue = String(format: template, iterations)
    }
    
    @IBAction func maxRotationChanged(_ sender: Any?) {
        let value = maxRotationSlider.floatValue / 360.0
        renderer.maxRotation = value
        
        let template = NSLocalizedString("Max Rotation: %iº", comment: "Max Rotation Label Template")
        maxRotationLabel.stringValue = String(format: template, Int(maxRotationSlider.floatValue))
    }
    
    @IBAction func removeImage(_ sender: Any?) {
        let indexes = imageCollectionView.selectionIndexPaths
        let sortedIndexes = indexes
            .sorted()
            .reversed()
        
        for index in sortedIndexes {
            imageURLs.remove(at: index.item)
            renderer.removeFace(at: index.item)
        }
        
        imageCollectionView.deleteItems(at: indexes)
    }
    
    @IBAction func scaleChanged(_ sender: Any?) {
        let value = scaleSlider.floatValue
        renderer.scale = value / 100.0
        
        let template = NSLocalizedString("Scale: %i%%", comment: "Scale Label Template")
        scaleLabel.stringValue = String(format: template, Int(value))
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
        
        // renderer = OriginalRenderer(metalView: metalView)
        renderer = IterationRenderer(metalView: metalView)
        renderer.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
        metalView.delegate = renderer
        
        // Listen for color changes from the background color picker
        NotificationCenter.default.addObserver(forName: NSColorPanel.colorDidChangeNotification, object: backgroundColorPanel, queue: nil) { (notification) in
            self.backgroundColorButton.selectedColor = self.backgroundColorPanel.color
            self.renderer.backgroundColor = self.backgroundColorPanel.color
        }
        
        // Update the initial UI elements
        setRemoveButtonState()
    }
    
    
    // MARK: - Protocols
    
    // MARK: <NSCollectionViewDataSource>
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ImageCollectionViewItemIdentifier, for: indexPath)
        
        guard let imageItem = item as? ImageCollectionViewItem else {
            return item
        }
        
        imageItem.url = imageURLs[indexPath.item]
        
        return imageItem
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageURLs.count
    }
    
    // MARK: <NSCollectionViewDelegate>
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        setRemoveButtonState()
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        setRemoveButtonState()
    }
    
    // MARK: <NSTextFieldDelegate>
    
    override func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }
        
        if textField == resolutionWidthTextField || textField == resolutionHeightTextField {
            let width = resolutionWidthTextField.integerValue
            let height = resolutionHeightTextField.integerValue
            
            guard width > 0, height > 0 else {
                return
            }
            
            let size = CGSize(width: width, height: height)
            renderer.canvasSize = size
        } else if textField == seedTextField {
            let seed = seedTextField.stringValue.isEmpty ? "Seed" : seedTextField.stringValue
            let data = seed.data(using: .utf8)!
            
            renderer.seedData = data
        }
    }
    
    // MARK: - Utilities
    
    private func setRemoveButtonState() {
        if imageCollectionView.selectionIndexes.isEmpty {
            removeImageButton.isEnabled = false
        } else {
            removeImageButton.isEnabled = true
        }
    }

}


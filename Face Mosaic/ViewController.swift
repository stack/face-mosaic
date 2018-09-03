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

class ViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {

    // MARK: - Properties
    
    @IBOutlet weak var imageCollectionView: NSCollectionView!
    
    @IBOutlet weak var addImageButton: NSButton!
    @IBOutlet weak var removeImageButton: NSButton!
    
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
    
    
    // MARK: - NSViewController Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Prepare the renderer
        metalView.device = MTLCreateSystemDefaultDevice()
        
        renderer = Renderer(metalView: metalView)
        renderer.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
        metalView.delegate = renderer
        
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
    
    
    // MARK: - Utilities
    
    private func setRemoveButtonState() {
        if imageCollectionView.selectionIndexes.isEmpty {
            removeImageButton.isEnabled = false
        } else {
            removeImageButton.isEnabled = true
        }
    }

}


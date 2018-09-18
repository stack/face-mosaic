//
//  Window.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/9/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

fileprivate let AcceptableTypes: [String] = [
    kUTTypePNG as String
]

@objc protocol WindowDelegate {
    func window(_ window: Window, receivedURLs urls: [URL])
}

class Window: NSWindow, NSDraggingDestination {

    // MARK: - Properties
    
    @IBOutlet var windowDelegate: WindowDelegate? = nil
    
    // MARK: - Initialization
    
    override func awakeFromNib() {
        registerForDraggedTypes([.fileURL, .png])
    }
    
    // MARK: - Protocols
    
    // MARK: <NSDraggingDestination>
    
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        
        for object in objects {
            let url = object as! URL
            if !urlIsAcceptable(url: url) {
                return []
            }
        }
        
        return .copy
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) else {
            return false
        }
        
        let urls = objects.map { $0 as! URL }
        windowDelegate?.window(self, receivedURLs: urls)
        
        return true
    }
    
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) else {
            return false
        }
        
        for object in objects {
            let url = object as! URL
            if !urlIsAcceptable(url: url) {
                return false
            }
        }
        
        return true
    }
    
    private func urlIsAcceptable(url: URL) -> Bool {
        do {
            let type = try NSWorkspace.shared.type(ofFile: url.path)
            return AcceptableTypes.contains(type)
        } catch {
            return false
        }
    }
}

//
//  WindowController.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/9/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate, WindowDelegate {
    
    func open(files: [String]) {
        guard let viewController = contentViewController as? ViewController else {
            return
        }
        
        let urls = files.map { URL(fileURLWithPath: $0) }
        viewController.addFaces(from: urls)
    }
    
    func window(_ window: Window, receivedURLs urls: [URL]) {
        guard let viewController = contentViewController as? ViewController else {
            return
        }
        
        viewController.addFaces(from: urls)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
}

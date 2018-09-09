//
//  WindowController.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/9/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController {
    
    func open(file path: String) {
        guard let viewController = contentViewController as? ViewController else {
            return
        }
        
        let url = URL(fileURLWithPath: path)
        viewController.addImage(from: url)
    }
}

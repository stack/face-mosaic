//
//  ColorPickerButton.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/6/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import AppKit

@IBDesignable
class ColorPickerButton: NSButton {
    
    @IBInspectable var selectedColor: NSColor = .black {
        didSet { needsDisplay = true }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.0, yRadius: 3.0)
        
        selectedColor.setFill()
        path.fill()
        
        NSColor.black.setStroke()
        path.stroke()
    }
}

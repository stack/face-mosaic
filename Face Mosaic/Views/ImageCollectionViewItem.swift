//
//  ImageCollectionViewItem.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/1/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

fileprivate let backgroundColor = NSColor.clear.cgColor
fileprivate let selectedBackgroundColor = NSColor.alternateSelectedControlColor.cgColor

class ImageCollectionViewItem: NSCollectionViewItem {

    var image: NSImage? {
        didSet {
            imageView?.image = image
        }
    }
    
    override var isSelected: Bool {
        didSet {
            if isSelected {
                view.layer?.backgroundColor = selectedBackgroundColor
            } else {
                view.layer?.backgroundColor = backgroundColor
            }
        }
    }
    
    private func commonInit() {
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor
    }
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
}

//
//  ImageCollectionViewItem.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/1/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

fileprivate let backgroundColor = NSColor.clear.cgColor
fileprivate let selectedBackgroundColor = NSColor.selectedControlColor.cgColor

class ImageCollectionViewItem: NSCollectionViewItem {

    var path: String? {
        didSet {
            if let value = path {
                imageView?.image = NSImage(contentsOfFile: value)
            } else {
                imageView?.image = nil
            }
        }
    }
    
    var url: URL? {
        didSet {
            if let value = url {
                imageView?.image = NSImage(contentsOf: value)
            } else {
                imageView?.image = nil
            }
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

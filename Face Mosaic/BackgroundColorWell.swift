//
//  BackgroundColorWell.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/6/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import AppKit

class BackgroundColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.showsAlpha = true
        super.activate(exclusive)
    }
}

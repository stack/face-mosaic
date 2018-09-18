//
//  Face.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/17/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Foundation

struct Face: Equatable {
    let uuid: UUID
    let url: URL
    
    init(url: URL) {
        uuid = UUID()
        self.url = url
    }
    
    static func ==(lhs: Face, rhs: Face) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

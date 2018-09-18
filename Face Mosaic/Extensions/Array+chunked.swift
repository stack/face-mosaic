//
//  Array+chunked.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/16/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Foundation

extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        return stride(from: 0, to: count, by: size).map {
            self[$0 ..< Swift.min($0 + size, count)]
        }
    }
}

//
//  Item.swift
//  someai
//
//  Created by rocky on 2026/2/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

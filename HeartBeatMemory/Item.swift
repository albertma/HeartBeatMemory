//
//  Item.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/9.
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

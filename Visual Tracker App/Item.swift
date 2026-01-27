//
//  Item.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
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

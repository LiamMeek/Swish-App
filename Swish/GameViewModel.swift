//
//  GameViewModel.swift
//  Swish
//
//  Created by Liam Meek on 10/7/25.
//

import SwiftUI
import Foundation
import Combine

final class GameViewModel: ObservableObject {
    // Session stats
    @Published var madeShots: Int = 0
    @Published var missedShots: Int = 0

    // Tracking state
    @Published var isTracking: Bool = false

    // Derived stats
    var totalShots: Int {
        madeShots + missedShots
    }

    var fieldGoalPercentage: Int {
        let total = totalShots
        guard total > 0 else { return 0 }
        return Int((Double(madeShots) / Double(total)) * 100.0)
    }

    // Actions
    func startGame() {
        // Initialize/reset session as needed
        madeShots = 0
        missedShots = 0
        isTracking = false
    }

    func backToMenu() {
        // Hook up to navigation state if/when you add it
        isTracking = false
    }
}

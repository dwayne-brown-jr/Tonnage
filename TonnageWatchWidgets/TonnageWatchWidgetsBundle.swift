//
//  TonnageWatchWidgetsBundle.swift
//  TonnageWatchWidgets
//
//  watchOS widget extension entry point — hosts the Tonnage complication.
//

import WidgetKit
import SwiftUI

@main
struct TonnageWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonnageWatchComplication()
    }
}

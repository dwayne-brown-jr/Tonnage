//
//  TonnageWidgetsBundle.swift
//  TonnageWidgets
//
//  iOS widget extension entry point: the home-screen "Next Session" widget plus the
//  rest-timer Live Activity (Lock Screen + Dynamic Island).
//

import WidgetKit
import SwiftUI

@main
struct TonnageWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonnageHomeWidget()
        TonnageWidgetsLiveActivity()
    }
}

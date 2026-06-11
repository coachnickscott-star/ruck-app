//
//  RugbyLiveActivityWidgetBundle.swift
//  RugbyLiveActivityWidget (Widget Extension target)
//
//  The @main entry point for the widget extension. A `WidgetBundle` can hold several
//  widgets; here it hosts only the Live Activity. If you later add a Home Screen
//  widget, add it to the `body` alongside `RugbyLiveActivitiesWidget()`.
//
//  TARGET MEMBERSHIP: "RugbyLiveActivityWidget" target ONLY.
//

import SwiftUI
import WidgetKit

@main
struct RugbyLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            RugbyLiveActivitiesWidget()
        }
    }
}

//
//  ContentView.swift
//  Echo
//
//  Root view — delegates to HomeView which owns the NavigationStack.
//

import SwiftUI
import EchoCore

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
}

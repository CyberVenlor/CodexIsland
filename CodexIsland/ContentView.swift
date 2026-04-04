//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var islandController = IslandController()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.99),
                    Color(red: 0.86, green: 0.90, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                IslandView(controller: islandController)
                    .padding(.top, 42)

                Picker("Collapsed Mode", selection: $islandController.collapsedMode) {
                    ForEach(CollapsedIslandMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.horizontal, 24)

                Text("Hover over the notch to expand the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 500, height: 420)
    }
}

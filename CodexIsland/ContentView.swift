//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: IslandController

    var body: some View {
        ZStack(alignment: .top) {
            IslandView(controller: controller)
        }
        .padding(.horizontal, IslandOverlayLayout.horizontalPadding)
        .padding(.top, IslandOverlayLayout.topPadding)
        .padding(.bottom, IslandOverlayLayout.bottomPadding)
        .background(Color.clear)
        .ignoresSafeArea()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(controller: IslandController())
            .environmentObject(CodexSessionController())
            .environmentObject(SettingsConfigStore())
            .padding(40)
            .background(Color(red: 0.93, green: 0.95, blue: 0.98))
    }
}

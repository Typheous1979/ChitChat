import SwiftUI
import ChitChatCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }

            AdvancedFeaturesView()
                .tabItem {
                    Label("Advanced", systemImage: "wand.and.stars")
                }

            TranscriptionSettingsView()
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }

            VoiceTrainingView()
                .tabItem {
                    Label("Training", systemImage: "brain.head.profile")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .environment(appState)
        .frame(width: 520, height: 400)
    }
}

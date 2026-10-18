import SwiftUI
import GoogleSignInSwift

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: GoogleAuthStore
    @ObservedObject var history: ListeningHistoryStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Your music, connected") {
                    if auth.isSignedIn {
                        Label(auth.displayName, systemImage: "person.crop.circle.fill")
                        Text("YouTube Music supplies your Home recommendations, liked music, and song radio.")
                        Button("Sign out") { auth.signOut() }
                        Button("Disconnect Google and clear listening history", role: .destructive) {
                            history.clear()
                            Task { await auth.disconnect() }
                        }
                    } else {
                        Text("Sign in to connect your liked music and get personalized picks. You can browse trending without an account.")
                        GoogleSignInButton { Task { await auth.signIn() } }.disabled(auth.isBusy)
                    }
                    if auth.isBusy { ProgressView() }
                    if let error = auth.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                if auth.isSignedIn {
                    Section("Listening history") {
                        Text("Recently played is saved on this device for your Google account. It does not import YouTube watch history.")
                        Button("Clear recently played", role: .destructive) { history.clear() }
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

import Foundation
import AVFAudio

enum AudioSessionManager {
    static func configureForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("Audio session configuration failed:", error.localizedDescription)
            #endif
        }
    }

    static func deactivateAfterPlayback() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("Audio session deactivation failed:", error.localizedDescription)
            #endif
        }
    }
}

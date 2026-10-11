import SwiftUI
import TonnageCore

/// Surfaces a failed SwiftData save (posted by `saveOrReport`) as an alert, in every build.
/// A save that silently fails is a set the lifter thinks they logged.
struct SaveFailureAlert: ViewModifier {
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .tonnageSaveFailed)) { note in
                guard message == nil else { return }   // one alert at a time
                message = note.userInfo?["message"] as? String ?? ""
                Haptics.warning()
            }
            .alert("Couldn't save", isPresented: Binding(get: { message != nil },
                                                         set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text("Your last change didn't save. Check your storage and iCloud, then try again."
                     + ((message ?? "").isEmpty ? "" : "\n\n\(message ?? "")"))
            }
    }
}

extension View {
    func saveFailureAlert() -> some View { modifier(SaveFailureAlert()) }
}

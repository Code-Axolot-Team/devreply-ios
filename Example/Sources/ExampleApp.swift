import DevReply
import SwiftUI

/// Pushes: hand the APNs device token to DevReply. DevReply asks for permission itself (never forced)
/// and, since this app has no notification delegate of its own, handles taps and foreground pushes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        DevReply.registerPush(deviceToken)
    }
}

@main
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Your app's iOS public key from the DevReply dashboard (safe to ship). Set it with the
        // DEVREPLY_PK build setting (project.yml, or `xcodebuild DEVREPLY_PK=pk_…`); UI tests may pass
        // DEVREPLY_PK in the environment instead.
        let key = ProcessInfo.processInfo.environment["DEVREPLY_PK"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "DevReplyPublicKey") as? String) ?? ""
        DevReply.configure(key)
        // The chat follows the device's language; an app with its own language setting passes it on.
        if let locale = ProcessInfo.processInfo.environment["DEVREPLY_LOCALE"] { DevReply.setLocale(locale) }
        // What the app knows about this user shows up next to them in the dashboard.
        DevReply.setAttributes(["demo_app": true, "build": 1])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // DevReply's email button opens devreplyexample://devreply?devreply=<conversation>.
                .onOpenURL { url in _ = DevReply.handle(url) }
        }
    }
}

struct ContentView: View {
    @State private var showMessenger = false
    @Environment(\.scenePhase) private var scenePhase
    private let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
    private let lemon = Color(red: 0.96, green: 0.92, blue: 0.22)
    private let pink = Color(red: 1.0, green: 0.37, blue: 0.64)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("DEMO APP")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(lemon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ink)
            Text("Talk to the\ndeveloper.")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(ink)
            Text("This is a blank app with one button. It opens DevReply's native chat.")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ink)
            Spacer()
            Button {
                showMessenger = true
            } label: {
                HStack {
                    Text("Message the developer")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(ink)
                .padding(.horizontal, 20)
                .frame(height: 62)
                .background(pink)
                .overlay(Rectangle().strokeBorder(ink, lineWidth: 3))
                .background(Rectangle().fill(ink).offset(x: 6, y: 6))
                .overlay(alignment: .topTrailing) {
                    if DevReply.unreadCount > 0 {
                        Text("\(DevReply.unreadCount)")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(ink)
                            .frame(minWidth: 28, minHeight: 28)
                            .background(lemon)
                            .overlay(Rectangle().strokeBorder(ink, lineWidth: 2.5))
                            .offset(x: 10, y: -12)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openMessenger")
            .padding(.bottom, 24)
        }
        .padding(24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(lemon)
        .devReplyMessenger(isPresented: $showMessenger)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await DevReply.refresh() } }
        }
    }
}

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
        let env = ProcessInfo.processInfo.environment
        let key = env["DEVREPLY_PK"] ?? (Bundle.main.object(forInfoDictionaryKey: "DevReplyPublicKey") as? String) ?? ""
        if env["DEVREPLY_STUB"] == "1" {
            // UI tests and screenshots without an account: an in-process fake of the API (StubAPI.swift).
            StubAPI.install()
            DevReply.configure("pk_stub", apiURL: StubAPI.baseURL)
        } else {
            DevReply.configure(key)
        }
        // Dark mode: DevReply's own dark look whenever the app is dark (without it the chat stays light).
        DevReply.darkTheme = .dark
        if env["DEVREPLY_THEME"] == "custom" {
            // Your colours; the rest follows (UI tests: DEVREPLY_THEME=custom).
            DevReply.theme = DevReplyTheme(
                primary: Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255),
                accent: Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
            )
        }
        // Your analytics: what happens in the chat.
        DevReply.addEventListener { event in EventLog.shared.add(event) }
        // The chat follows the device's language; an app with its own language setting passes it on.
        if let locale = ProcessInfo.processInfo.environment["DEVREPLY_LOCALE"] { DevReply.setLocale(locale) }
        // What the app knows about this user shows up next to them in the dashboard.
        DevReply.setAttributes(["demo_app": true, "build": 1])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // UI tests pick the appearance: DEVREPLY_APPEARANCE=dark|light.
                .preferredColorScheme(Self.appearance)
                // DevReply's email button opens devreplyexample://devreply?devreply=<conversation>.
                .onOpenURL { url in _ = DevReply.handle(url) }
        }
    }

    private static var appearance: ColorScheme? {
        switch ProcessInfo.processInfo.environment["DEVREPLY_APPEARANCE"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

/// The chat's events, shown small at the bottom of the demo (and read by the UI tests).
@MainActor @Observable
final class EventLog {
    static let shared = EventLog()
    private(set) var lines: [String] = []

    func add(_ event: DevReplyEvent) {
        switch event {
        case .messengerOpened: lines.append("opened")
        case .messengerClosed: lines.append("closed")
        case .conversationStarted(_, let category): lines.append("started(\(category?.rawValue ?? "none"))")
        case .messageSent: lines.append("sent")
        }
    }
}

struct ContentView: View {
    @State private var showMessenger = false
    @State private var chatOff = false
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

            // Straight into a bug report, with a draft and context for the team (e.g. from a paywall).
            Button {
                let message = ProcessInfo.processInfo.environment["DEVREPLY_PREFILL"] ?? "The paywall didn't load: "
                chatOff = !DevReply.present(category: .bug, message: message, attributes: ["source": "paywall"])
            } label: {
                Text(chatOff ? "Chat is switched off" : "Report a bug from the paywall")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
                    .underline()
            }
            .accessibilityIdentifier("reportBug")

            Text(EventLog.shared.lines.suffix(6).joined(separator: " · "))
                .font(.system(size: 12, weight: .medium).monospaced())
                .foregroundStyle(ink)
                .accessibilityIdentifier("eventLog")
                .padding(.bottom, 12)
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

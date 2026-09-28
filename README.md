# DevReply for iOS

The in-app chat between your app's users and you: a native "message the developer" screen in SwiftUI,
answered from the [DevReply dashboard](https://app.devreply.com). No dependencies.

- Home with start buttons (bug, billing, idea, question), the user's conversations, and the chat.
- Photos and files, name first, optional email, "we got it" with your reply time, a long drag hides the keyboard.
- Push for replies (never forced), an in-app banner, and an unread bubble over your app.
- Your colours, or DevReply's own look. Forward compatible: a newer server never breaks an app already shipped.

Requires iOS 17, Swift 6 / Xcode 16 or later.

## Install

Swift Package Manager: `https://github.com/Code-Axolot-Team/devreply-ios`, product `DevReply`, "Up to Next Major" from `0.3.1`.

```swift
// Package.swift
.package(url: "https://github.com/Code-Axolot-Team/devreply-ios", from: "0.3.1")
```

Using a coding agent? Give it your app's setup guide from the dashboard (Settings → Add DevReply to your app):
it has your keys and does these steps for you.

## Use

```swift
import DevReply

// Once, at launch (your iOS public key from the dashboard; it's safe to ship)
DevReply.configure("pk_…")

// From any button
DevReply.present()                    // or present(category: .bug)

// Optional
DevReply.setUser(name: "Ana", email: "ana@example.com")
DevReply.setAttributes(["plan": "pro", "trial": false])
DevReply.theme = DevReplyTheme(primary: .yellow, accent: .pink)
DevReply.showsUnreadBubble = false    // if you show DevReply.unreadCount yourself
```

SwiftUI: `.devReplyMessenger(isPresented: $showChat)`.

**Push:** pass the device token from your app delegate with `DevReply.registerPush(deviceToken)`. If your app has
its own `UNUserNotificationCenterDelegate`, forward with `DevReply.presentationOptions(for:)` and
`DevReply.handleNotificationResponse(_:)`. Upload your APNs key in the dashboard.

Never put a secret key (`sk_…`) in an app.

## Example app and tests

```sh
cd Example && xcodegen
xcodebuild -scheme DevReplyExample DEVELOPMENT_TEAM=<your team> DEVREPLY_PK=pk_… -destination 'generic/platform=iOS' build
xcodebuild -scheme DevReply -destination 'platform=iOS Simulator,name=iPhone 17' test   # from the package root
```

## License

MIT, see [LICENSE](LICENSE). Issues and ideas welcome: see [CONTRIBUTING](CONTRIBUTING.md).

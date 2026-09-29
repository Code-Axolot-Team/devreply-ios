# DevReply for iOS

The in-app chat between your app's users and you: a native "message the developer" screen in SwiftUI,
answered from the [DevReply dashboard](https://app.devreply.com). No dependencies.

- Home with start buttons (bug, billing, idea, question), the user's conversations, and the chat.
- Photos and files, name first, optional email, "we got it" with your reply time, a long drag hides the keyboard.
- Push for replies (never forced), an in-app banner, and an unread bubble over your app.
- Your colours, or DevReply's own look. Forward compatible: a newer server never breaks an app already shipped.

Requires iOS 17, Swift 6 / Xcode 16 or later.

## Install

Swift Package Manager: `https://github.com/Code-Axolot-Team/devreply-ios`, product `DevReply`, "Up to Next Major" from `0.4.3`.

```swift
// Package.swift
.package(url: "https://github.com/Code-Axolot-Team/devreply-ios", from: "0.4.3")
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
DevReply.setLocale("es")              // your app's own language setting; nil follows the device
```

Each reply shows who wrote it (the teammate's name, title and photo) and the header shows your app icon. The chat
speaks the device's language (15 languages: English, Spanish, Portuguese, French, German, Italian, Dutch, Polish,
Russian, Ukrainian, Turkish, Greek, Japanese, Korean, Chinese).

**Replies from email:** DevReply emails users replies they haven't read, with a "Reply in the app" button that opens
`yourapp://devreply?devreply=<conversation>`. Add a URL scheme and pass links to DevReply first:

```swift
.onOpenURL { url in
    if DevReply.handle(url) { return }
    // your own links
}
```

Then set `yourapp://devreply` as the deep link in the dashboard (the app → Settings).

SwiftUI: `.devReplyMessenger(isPresented: $showChat)`.

**Push:** pass the device token from your app delegate with `DevReply.registerPush(deviceToken)`. DevReply never
takes over your notification handling: it sets its own delegate only when your app has none. If your app has its
own `UNUserNotificationCenterDelegate`, forward with `DevReply.presentationOptions(for:)` and
`DevReply.handleNotificationResponse(_:)`. If a push library (Firebase Messaging…) hands you a tapped notification's
data, pass it with `DevReply.handleNotificationOpened(userInfo:)` (false for your own). Upload your APNs key in the
dashboard; the push card shows "✓ Taps open the chat" once a tap opened a conversation.

Never put a secret key (`sk_…`) in an app.

## Sign-in, sign-out and account deletion

If your app has accounts:

```swift
DevReply.login(userID: account.id)     // after sign-in: your own id for the user, never an email or a secret
DevReply.logout()                      // on every sign-out and account switch
let ok = await DevReply.deleteUser()   // in your delete-account flow; false if DevReply couldn't be reached
```

- `login` labels the user for your team (the dashboard shows it as "User ID (your app)") and lets your backend
  delete them by it. It doesn't merge chats across devices: the id isn't verified, so it never gives one device
  another's conversations. If another id was signed in on this device, DevReply logs out first.
- `logout` revokes this install and its push token; the device forgets the chat and the next person starts empty.
  The conversations stay with your team.
- `deleteUser` deletes the user's name, email, attributes, conversations, messages and files, then logs out.
  Apple requires account deletion in the app.
- A reinstall starts clean: the Keychain outlives the app, and the SDK tells a reinstall from a launch.

Your backend can delete a user too, with a read-and-write secret key (never in an app):

```sh
curl -X DELETE "https://api.devreply.com/v1/project/users?user_id=<your id>" \
  -H "Authorization: Bearer $DEVREPLY_SECRET_KEY"
# {"deleted": 1}: every DevReply user with that id, on every device. ?id=<DevReply's user id> for one user.
```

Your team can also delete a user in the dashboard (the inbox's user panel → Delete user).

## Example app and tests

```sh
cd Example && xcodegen
xcodebuild -scheme DevReplyExample DEVELOPMENT_TEAM=<your team> DEVREPLY_PK=pk_… -destination 'generic/platform=iOS' build
xcodebuild -scheme DevReply -destination 'platform=iOS Simulator,name=iPhone 17' test   # from the package root
```

## License

MIT, see [LICENSE](LICENSE). Issues and ideas welcome: see [CONTRIBUTING](CONTRIBUTING.md).

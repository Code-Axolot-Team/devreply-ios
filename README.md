# DevReply for iOS

The in-app chat between your app's users and you: a native "message the developer" screen in SwiftUI,
answered from the [DevReply dashboard](https://app.devreply.com). No dependencies.

- Home with start buttons (bug, billing, idea, question), the user's conversations, and the chat.
- Photos and files, name first, optional email, "we got it" with your reply time, a long drag hides the keyboard.
- Push for replies (never forced), an in-app banner, and an unread bubble over your app.
- Your colours, or DevReply's own look. Forward compatible: a newer server never breaks an app already shipped.

Requires iOS 17, Swift 6 / Xcode 16 or later.

## Install

Swift Package Manager: `https://github.com/Code-Axolot-Team/devreply-ios`, product `DevReply`, "Up to Next Major" from `0.5.0`.

```swift
// Package.swift
.package(url: "https://github.com/Code-Axolot-Team/devreply-ios", from: "0.5.0")
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
DevReply.darkTheme = .dark            // dark mode (off by default: the chat stays light)
DevReply.showsUnreadBubble = false    // if you show DevReply.unreadCount yourself
DevReply.setLocale("es")              // your app's own language setting; nil follows the device
```

Each reply shows who wrote it (the teammate's name, title and photo) and the header shows your app icon. The chat
speaks the device's language: 34 languages, every one iOS itself ships in, including Hebrew and Arabic, which lay
out right to left (English otherwise).

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

**A draft and context:** open a new conversation with text already in the composer (the user sees it and can edit it
before sending; nothing is sent on its own) and context for your team, shown with that conversation only:

```swift
DevReply.present(category: .bug, message: "The export failed: ", attributes: ["screen": "export", "items": 42])
```

`present` returns `false` and shows nothing when DevReply isn't configured or your team switched the chat off in the
dashboard. `DevReply.isAvailable` tells you up front (to hide your own "Contact us" button, say). While it's off, the
unread bubble and banners stay hidden too; login, logout, deleteUser, push and attributes keep working.

`askName: false` skips "Before we start" (the name form) while that messenger is open, for a screen where one tap to
the message matters more than a name, like a failed purchase. The email ask after the first message stays:

```swift
DevReply.present(category: .billing, message: "My purchase didn't go through", askName: false)
```

**Events** for your analytics:

```swift
let subscription = DevReply.addEventListener { event in
    switch event {
    case .messengerOpened, .messengerClosed: break
    case .conversationStarted(let id, let category): analytics.log("support_started", id, category)
    case .messageSent(let id): analytics.log("support_message", id)
    }
}
subscription.cancel()                 // when you no longer need it
```

**Dark mode:** set `DevReply.darkTheme` (`.dark` is DevReply's own dark look, or your own `DevReplyTheme`) and the
chat follows the app's appearance, including `overrideUserInterfaceStyle`. Without it the chat stays light.

Both themes take the same six colours: `primary` (header and highlights), `accent` (buttons that act), `userBubble`,
`userBubbleText`, `background` and `ink` (text and outlines). Everything else is worked out from them: in dark, the
cards, secondary text, shadows and the text on buttons (dark or white, whichever reads better).

```swift
DevReply.darkTheme = DevReplyTheme(primary: .purple, accent: .orange, background: Color(white: 0.08), ink: .white)
```

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
let deleted = await DevReply.deleteUser()   // in your delete-account flow; false = queued, retried until done
```

- `login` labels the user for your team (the dashboard shows it as "User ID (your app)") and lets your backend
  delete them by it. It doesn't merge chats across devices: the id isn't verified, so it never gives one device
  another's conversations. If another id was signed in on this device, DevReply logs out first.
- `logout` revokes this install and its push token; the device forgets the chat and the next person starts empty.
  The conversations stay with your team.
- `deleteUser` deletes the user's name, email, attributes, conversations, messages and files, then logs out.
  Apple requires account deletion in the app. It never gives up: if DevReply can't be reached, the device forgets
  the user at once and returns `false`, and the SDK retries the deletion (with the old install's token, kept in the
  Keychain) at every launch and return to the foreground until the server confirms. `true` = deleted now.
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

The example's UI tests need a throwaway app's key (`TEST_RUNNER_DEVREPLY_TEST_PK=pk_…`), except `V044UITests`: they run
the example against an in-process fake of the API (`DEVREPLY_STUB=1`, `Example/Sources/StubAPI.swift`) and need no
account. `TEST_RUNNER_DEVREPLY_SHOTS=<folder>` also saves their screenshots there.

## License

MIT, see [LICENSE](LICENSE). Issues and ideas welcome: see [CONTRIBUTING](CONTRIBUTING.md).

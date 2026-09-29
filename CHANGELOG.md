# Changelog

Released versions stay supported: the API only grows, and every released version's requests are replayed
against the server on every change. Features added later may be missing in an older version; nothing it
uses breaks.

## 0.4.3

* Signed-in users: `DevReply.login(userID:)` after sign-in (your own id for the user; the team sees it, your
  backend can delete the user by it), `DevReply.logout()` on every sign-out (the device forgets the chat; the
  next person starts empty), `await DevReply.deleteUser()` in your delete-account flow (deletes the user's
  data, then logs out; `false` if DevReply couldn't be reached).
* A reinstall starts clean: the Keychain outlives the app, so the SDK forgets the previous install on a
  fresh install.
* Notification taps from a push library (Firebase, expo-notifications, notifee):
  `DevReply.handleNotificationOpened(userInfo:)` opens the conversation (`false` for your own). DevReply
  never takes over your notification handling; it handles notifications itself only when the app has no
  `UNUserNotificationCenterDelegate`. A tap that launches the app opens the conversation once `configure` runs.
* The privacy manifest declares everything the SDK collects (name, email, user and device ids, photos,
  files, device details, custom attributes) and the UserDefaults reason.

## 0.4.0

* Replies show who wrote them: the teammate's name, title and photo, once per group of replies.
* The app's icon in the chat's header; the team's faces on the chat's home screen.
* Links from DevReply's emails ("Reply in the app") open the right conversation: `DevReply.handle(url)`.
* A refused public key isn't retried in a loop.
* The chat speaks the user's language (15 languages, the device's by default); `DevReply.setLocale("es")`.
* Reply times are presets, translated in the chat.

## 0.3.0 – 0.3.2

* The first releases: the native chat in SwiftUI (home with start buttons, conversations, photos and
  files, name first, optional email, "we got it" with the reply time), the unread bubble, push
  notifications for replies, `setUser`, `setAttributes`, `unreadCount`, `theme`.

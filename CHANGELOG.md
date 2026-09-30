# Changelog

Released versions stay supported: the API only grows, and every released version's requests are replayed
against the server on every change. Features added later may be missing in an older version; nothing it
uses breaks.

## 0.5.0

- 34 languages (adds Arabic, Catalan, Croatian, Czech, Danish, Finnish, Hebrew, Hindi, Hungarian, Indonesian, Malay,
  Norwegian, European Portuguese, Romanian, Slovak, Swedish, Thai, Vietnamese, Traditional Chinese). Hebrew and Arabic
  lay the chat out right to left.
- `present(…, askName: false)`: no name form while that messenger is open (e.g. from a failed purchase); the chat
  goes straight to the composer. The email ask after the first message stays.
- Builds on Xcode 26.2: the unread bubble's fade used an expression that compiler finds ambiguous.
- Swift 6 language mode: `DevReply.defaultAPIURL` is `nonisolated`, so it works as `configure`'s default argument.
- Replies from the team and agents in Markdown (the `markdown` block, `min_sdk` 0.5.0): bold, italic, strike, code,
  links (open in the browser), headings, lists, code blocks and quotes, drawn natively. Older versions show the
  plain-text fallback.
- Fixed: in a chat longer than the screen, dragging the history up at the newest message pulled the whole sheet
  down. The thread is now a regular scroll view that opens at, and follows, the newest message.
- Button replies (the `buttons` block, `min_sdk` 0.5.0): the team's question in Markdown with 2 to 5 answers as
  buttons; a tap sends the label with `answer`, the chosen one stays highlighted, the others go quiet (a 409, already
  answered, reloads the thread); the composer stays. Older versions show the numbered plain-text fallback.
- Same device after logout: a random device key (256 bits, Keychain, kept through `logout()` and `deleteUser()`) goes
  with each install registration; when `login` gets the earlier user back (`restored: true`), the chat reloads.
- Live updates: while the messenger is open, new messages arrive over a WebSocket (`POST /v1/live`, resume with
  `after`, reconnect 1–30 s with ±20% jitter, polling after 5 failures in a row or a 503); the 3 s poll runs only while it's down.
- The unread bubble wears DevReply's new logo: the "Tilt" star on a black circle with a pink shadow.

## 0.4.4

* `DevReply.present(category:message:attributes:)`: `message` prefills the composer of the new conversation
  (never sent on its own; the user can edit it), `attributes` go to the team as that conversation's context
  (text, number or true/false; up to 20). Returns `false` and shows nothing when DevReply isn't configured
  or the chat is switched off; the old `present()` / `present(category:)` calls keep compiling.
* `await DevReply.deleteUser()` never gives up: if DevReply can't be reached, the device forgets the user at
  once and the deletion is retried (with the old install's token, kept in the Keychain) at every launch and
  return to the foreground until the server confirms. `true` = deleted now, `false` = queued.
* The chat on/off switch from the dashboard: `DevReply.isAvailable`. While off, `present` returns `false`,
  the unread bubble and banners stay hidden and an open messenger closes; everything else keeps working.
* Events for your analytics: `DevReply.addEventListener { event in … }` with `.messengerOpened`,
  `.messengerClosed`, `.conversationStarted(conversationID:category:)`, `.messageSent(conversationID:)`;
  `cancel()` the returned subscription to stop.
* Dark mode, opt-in: `DevReply.darkTheme = .dark` (DevReply's own "Deep blue" look) or a `DevReplyTheme` with
  your six colours. Without it the chat stays light, exactly as before. Every colour in the chat, its menus and
  pickers, the unread bubble and the in-app banner follows the theme; the category icons have dark artwork.

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

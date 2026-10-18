# Optional Google sign-in

Search, suggestions, charts, and song radio now use native YouTubeSDK and need no developer API key or backend. The old `YOUTUBE_GUEST_API_KEY` setting is no longer read by the app and may be removed from your local configuration.

To retain Google account sign-in:

1. In Google Cloud Console, select your project and open **Google Auth Platform → Branding**. Configure the app name and support email.
2. Open **Audience**. While the app is in Testing, add the exact Google email addresses you will use under **Test users**.
3. Open **Data Access → Add or remove scopes** and add `https://www.googleapis.com/auth/youtube.readonly`.
4. Open **Clients → Create client → iOS**. Use bundle ID `niwong.MusoStarter`. Keep your existing iOS client if already configured.
5. In Finder, open `Config` inside this project. If `Google.local.xcconfig` does not already exist, copy `Google.local.xcconfig.example` beside itself and rename the copy to `Google.local.xcconfig`. This file is ignored by Git.
6. Set `GOOGLE_CLIENT_ID` to your iOS client ID and `GOOGLE_REVERSED_CLIENT_ID` to its reversed callback scheme. Keep existing values if sign-in already works. Do not put credentials in the shared `Google.xcconfig`.
7. Rebuild. Sign in from Account, grant the read-only scope, and refresh Home.

The GoogleSignIn SDK manages refresh tokens. Muso passes only the refreshed access token directly to YouTube Music through YouTubeSDK's networking client. It does not copy browser cookies or use the SDK's embedded browser login. YouTube Music is a private API; accepting the Google sign-in grant does not guarantee these endpoints accept that grant. Verify Home and liked songs on a signed-in device. Rejection surfaces as an account/discovery error; signed-out catalogue features do not require Google setup.

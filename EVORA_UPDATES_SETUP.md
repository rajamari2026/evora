# Evora controlled app updates — setup

This implementation is for the existing Flutter Android APK distribution. GitHub stays private. GitHub Actions prepares a candidate APK; the admin panels upload that APK to a public Supabase Storage bucket and publish release metadata only when an administrator chooses **Publish to everyone**.

## What this patch adds

- `lib/app_updates.dart`: published-release lookup, version comparison, APK download, Android installer launch, in-app release admin UI.
- `lib/backend.dart`: server-verified admin check and authenticated update/storage requests using the existing Supabase session.
- `lib/main.dart`: Updates tab and update check on app launch/resume.
- `pubspec.yaml`: `package_info_plus` and `open_filex` dependencies.
- `tool/ci.py`: version-name/version-code support and Android install-package permission.
- `.github/workflows/prepare-release.yml`: manual candidate-release workflow; does not run on every push.
- `supabase/migrations/202611230001_evora_app_updates.sql`: release tables, admin authorization, APK bucket policies, and the future FCM device registry.
- `supabase/functions/notify-release/index.ts`: secure FCM HTTP v1 sender; requires Firebase secrets and registered device tokens.
- `supabase/config.toml`: disables gateway JWT verification only for this function because it verifies the user JWT and admin membership itself.
- `Evora-Website/admin.html` and `admin.js`: separate website admin panel at `/admin.html`.

## 1. Apply Supabase migration

1. Open the existing Supabase project for Evora.
2. Open SQL Editor and run `supabase/migrations/202611230001_evora_app_updates.sql`.
3. In Authentication → Users, find your own Evora account and copy its UUID.
4. Run this SQL with your UUID:

```sql
insert into public.app_admins(user_id)
values ('YOUR_AUTH_USER_UUID');
```

Only manually allowlisted accounts can administer releases. Never insert an admin row from the public signup flow.

## 2. Prepare a candidate APK

1. Push these changes to your private `gallery` repository.
2. Open GitHub → Actions → **Prepare Evora Release** → Run workflow.
3. Enter a new version name (example `1.0.1`), and an Android version code higher than every previous release (example `2`).
4. Download the `Evora-Candidate-*` artifact from the workflow run. GitHub also creates a private draft release for internal record keeping.
5. The GitHub draft is not the user download URL. Do not put a private GitHub URL into the release table.

The existing push workflow can continue to build test artifacts. Those builds do not become user updates unless you upload and publish one from an admin panel.

## 3. Publish to users

1. Install the candidate APK on a test Android phone first.
2. Open Evora and sign in with the administrator account.
3. Open the **Updates** tab.
4. Enter version name, version code and release notes; select the candidate APK; choose whether it is mandatory; press **Upload APK and prepare**.
5. Verify the release appears as `PREPARED`.
6. Only when ready, choose **Publish to all users**.

The separate website panel is available at `https://YOUR-EVORA-WEBSITE-DOMAIN/admin.html`. Sign in with the same allowlisted account. It uses the same database and permissions as the in-app panel.

## 4. Android installer behaviour

Evora downloads the APK and opens Android's package installer. Users may need to enable **Allow from this source** for Evora in Android settings. Android requires user confirmation for ordinary sideloaded APK updates; this app does not silently install APKs.

The current app uses a keystore shipped in `tool/debug.keystore`. Do not replace or regenerate it until you verify the signing certificate of the APK already installed on user phones. If the certificate changes, Android will reject the update as an incompatible package. This patch deliberately does not rotate the key.

## 5. Firebase push notifications are a separate pending step

Firebase has not yet been created, so this patch provides update discovery when Evora opens/resumes and the Updates tab. It does not yet send push notifications while Evora is closed.

To enable push:

1. Create a Firebase project named Evora.
2. Add an Android app with application ID `com.eventroll.event_roll` only after confirming the generated `android/app/build.gradle` applicationId in a prepared build. Do not guess the Firebase package name; the current CI helper generates Android project files dynamically.
3. Download `google-services.json` and add it to the generated Android app path through a change to `tool/ci.py` (the `android/` directory is generated during CI and is not committed).
4. Configure FlutterFire and add `firebase_core` and `firebase_messaging` dependencies plus the generated `firebase_options.dart`.
5. Add the Flutter token-registration code and register each signed-in user's FCM token in `user_devices`; this table is already created by the migration and RLS restricts each user to their own rows.
6. Deploy `supabase/functions/notify-release` and set its secrets: `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_JSON` (the full Firebase service-account JSON). The Supabase project already provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions; verify those environment values are present. The admin panels call this function after publication.

Do not put Firebase service-account JSON, a Firebase private key, or a Supabase service-role key in Flutter, website JavaScript, or GitHub-tracked source files.

## 6. Important release rules

- Never reuse an Android `version_code`.
- Use the same Android application ID and signing certificate as existing installations.
- Upload APKs only to the `evora-apk` bucket; anyone with a public APK URL can download that app binary.
- `prepared` does not show to users; `published` does.
- `paused` and `withdrawn` are not returned by the public update check.
- Test optional and mandatory updates on a spare device before publishing to everyone.

## 7. Verification

After applying the patch, run `flutter pub get`, then `flutter analyze`, then build a release APK using the same signing identity as the current app. The ZIP patch was assembled from the uploaded source, but a Flutter/Android build has not been run in this environment.

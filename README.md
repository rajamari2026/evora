# Evora (Android app)

Private photo sharing for events: photos grouped by day, events, Liquid Glass design,
WhatsApp batches of 100, chat-style sharing with accept-before-view, optional end-to-end encryption.

## Where the files go
This package is the **app repository** (your `gallery` repo). Upload everything inside it to the repo root:

    .github/workflows/build.yml
    lib/            (all the app code)
    tool/           (build helper, icons, signing key)
    pubspec.yaml
    supabase_setup.sql, supabase_hardening.sql
    README.md, .gitignore

Delete any other workflow files in `.github/workflows/` (for example `my-workflow.yml`, `static.yml`).
The website is a different package (Evora-Website.zip) for the `evora` repo.

## Build the APK
1. Commit the files. Open the **Actions** tab; the build starts by itself.
2. When it is green, open the run and download **Evora-APK** from **Artifacts**.
3. If a build fails, copy the "Error lines" box at the top of the run page and send it to Claude.
   The build repairs known problems on its own (Android SDK versions, memory, file_picker).
4. Every build uses the same signing key, so a new APK installs over the old one.

## Database (Supabase)
- `supabase_setup.sql` created the sharing tables (already applied to your project).
- Encryption tables are already applied too.
- `supabase_hardening.sql` is NOT applied yet. Run it once in the Supabase SQL Editor.

## Private sharing (end-to-end encryption)
Turn it on in the Shared tab. Photos are locked on your phone with a key only you and the receiver have.
Your encryption passcode unlocks your key on a new phone or on the website. If you forget it, private photos cannot be recovered.
The share title, sender, receiver and photo count are not encrypted. Keys are not verified between people.

## Notes
- View only hides the save button and uses a lower-quality copy. Anyone who can see a photo on screen could still capture it.
- Shared photos are re-encoded before upload, which removes location and camera data.
- Delete in the gallery uses Android's own trash (Android 11 or newer).

## Controlled app updates

See [`EVORA_UPDATES_SETUP.md`](EVORA_UPDATES_SETUP.md) for the complete setup of:
- Admin-only release preparation and publishing (inside the app and at the separate website's `/admin.html`).
- Supabase release metadata and public APK download storage.
- The manual **Prepare Evora Release** GitHub Actions workflow.
- Android APK installation requirements and signing-key precautions.
- The pending Firebase Cloud Messaging setup for push alerts.

The existing push workflow may still build test APK artifacts after commits. Those builds are **not** sent to users. Only a release manually uploaded and changed to `published` by an authorized administrator appears in Evora's update checker.

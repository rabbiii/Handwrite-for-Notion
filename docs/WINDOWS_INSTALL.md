# Build on GitHub, install from Windows

This keeps PencilNotes as a native iPad app. GitHub supplies a macOS/Xcode build machine; your Windows PC runs AltServer to sign and install the output using your Apple account. Swift Playground is not involved. No Apple account, password, Notion token, signing certificate, or paid developer membership is needed in GitHub for this build.

The delivered Windows build kit contains source and build instructions, **not an already compiled IPA**. The first successful GitHub Actions run performs the Apple SDK compilation and produces the installable-after-signing package. The Apple SDK build has now passed in [run 43120058457](https://github.com/rabbiii/Handwrite-for-Notion/actions/runs/43120058457), which supplies the unsigned IPA artifact. Personal signing and device installation remain to be tested. If SideStore is already installed and configured, use it to import the IPA; you do not need to set up AltStore as well.

## First check: AltStore on your particular iPadOS version

Before spending time on the cloud build, install and launch **AltStore Classic** on your iPad using the steps below. That confirms the sideloading tool can run on your device. Compatibility with your reported **iPadOS 27.2** has not been established: the retrieved official Windows release notes document fixes through iOS 26.4, not a verification of 27.2. Successful AltStore installation is a prerequisite, not proof that PencilNotes itself works yet.

Use **Classic**, which supports personal IPA sideloading; AltStore PAL is a different distribution route.

## 1. Set up AltServer on Windows

1. Start with a Windows PC, your iPad, a USB data cable, internet access, a GitHub account, and an Apple account.
2. Visit the [official AltStore site](https://altstore.io/) and choose **AltStore Classic → Windows / AltServer**. Follow its current [Windows installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Its source is also available [on GitHub](https://github.com/altstoreio/faq/blob/main/altstore-world/how-to-install-altstore-windows.md).
3. The retrieved guide requires **iTunes and iCloud downloaded directly from Apple**, rather than the Microsoft Store versions. Use the official guide's Apple download links; do not fetch Apple drivers from a third-party download site. If you already depend on the Store version of iCloud, read AltStore's documented alternative before changing your installation.
4. Install AltServer, start it as the guide directs, and allow access on your private network if Windows asks. Its icon appears in the notification area near the clock.
5. Connect the unlocked iPad by USB. Accept **Trust This Computer** on the iPad. Confirm iTunes sees it and enable its **Sync with this iPad over Wi-Fi** option, then apply/sync if prompted.
6. Click AltServer's notification-area icon → **Install AltStore → your iPad**. Enter your Apple credentials only in the official tool's sign-in prompt and complete any required authentication. Do not upload them to GitHub or send them in chat.
7. On iPad, use **Settings → General → VPN & Device Management** (wording can vary) to trust the developer entry associated with your Apple account if prompted.
8. Enable **Settings → Privacy & Security → Developer Mode** if required, restart as prompted, and confirm enabling it after restart. The option may appear only after attempting a development-app installation.
9. Open AltStore Classic successfully. If this stage fails on iPadOS 27.2, resolve the specific AltServer/AltStore error first; rebuilding PencilNotes cannot establish sideloading compatibility.

## 2. Put the build kit on GitHub

1. Download **PencilNotes-Windows-build-kit.zip** from the workspace delivery and extract it on Windows. Do not upload the ZIP itself: GitHub Actions needs the extracted directory structure.
2. Open `https://github.com/rabbiii/Handwrite-for-Notion` and sign in. For an empty repository, use the **uploading an existing file** link. Otherwise use **Add file → Upload files**.
3. Upload these extracted folders: **PencilNotes.swiftpm**, **MacBuild**, **Tests**, **scripts**, and **docs**. Also upload the root **Package.swift**, **README.md**, and optionally **.gitignore**. Upload their contents at the repository root, not inside an extra `PencilNotes-Windows-build-kit` parent folder. Commit to the default branch, normally `main`.
4. Create the workflow separately so a hidden-folder upload cannot omit it: **Add file → Create new file**, enter **`.github/workflows/build-ios.yml`** as its full name, then paste the complete contents of that file from the extracted kit. Commit to the default branch.
5. Verify GitHub now shows the source folders and workflow. These GitHub commits publish source to your repository; publishing a Codex environment does not perform this step.

For a public repository, GitHub currently provides standard hosted runners without usage charges under its Actions terms. A private repository consumes your plan's included minutes/storage and can incur charges beyond them. Check Actions availability and billing settings before running; this workflow uses `macos-latest`, requests no paid larger runner, and retains its artifact for three days. No secrets are required for it.

## 3. Build and download the IPA

1. Open the repository's **Actions** tab and enable workflows if GitHub asks.
2. Choose **Build iPad app → Run workflow**, select your default branch, then confirm **Run workflow**. The workflow supports manual runs and automatically runs when app/build inputs are pushed to main.
3. Wait for the run to finish. It executes the portable tests, regenerates the native Xcode project from the existing App/Core sources, and calls Xcode's iPadOS device compiler. It does not use the App Playground manifest to build the app.
4. If the run is green, open it and scroll to **Artifacts → PencilNotes-unsigned-iPad**. Download that artifact ZIP and extract **PencilNotes-unsigned.ipa** and its SHA-256 checksum. A GitHub sign-in may be required to download artifacts.
5. If the run is red, open the failed step and copy the first compiler/build error. A failed run is not a successful IPA build. In particular, **Compile and package unsigned IPA** is the Apple SDK validation that Linux could not perform.

“Unsigned” is intentional: no Apple credentials are in the build machine. The IPA cannot be installed merely by tapping it in Files. AltStore signs it using your personal development account during installation.

## 4. Install PencilNotes

1. Save the extracted **PencilNotes-unsigned.ipa** to a Files location accessible on your iPad, such as iCloud Drive. Alternatively download the GitHub artifact directly in Safari on iPad and extract it in Files.
2. Keep AltServer running on Windows. Keep the iPad connected by USB for the first attempt, or ensure both devices are on the same private Wi-Fi network with Wi-Fi syncing working.
3. Open **AltStore Classic → My Apps → +** on iPad and choose **PencilNotes-unsigned.ipa** from Files. Sign in using the same Apple account if AltStore asks.
4. Allow AltStore/AltServer to sign and install it, then open **PencilNotes** from the Home Screen. Developer trust and Developer Mode prompts may need completion as above.
5. Test writing, saving/reopening, and exports with a disposable note before entering your Notion token. Then follow [NOTION_SETUP.md](NOTION_SETUP.md) and [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md).

No JIT enablement, jailbreak, web-app conversion, paid signing service, or Swift Playground runtime is required by this design.

## 5. Keep the app usable

With a free Apple account, sideloaded apps normally expire after **seven days**. In **AltStore → My Apps**, use **Refresh All** while AltServer is reachable before expiry. Background refresh may help, but check the expiration dates yourself. You do not have to rebuild the source just to refresh a signature.

The free account normally allows three active sideloaded apps, including AltStore, leaving two other app slots. Other Apple account/App ID limits can also affect installs. If an installation expires, refresh through AltStore/AltServer rather than deleting PencilNotes as a first step. Export editable `.pencilnote` backups regularly and keep the same account/app identity when updating; do not rely on reinstalling to preserve notes.

## Files provided for this route

- `MacBuild/PencilNotes.xcodeproj`: standalone native iPad app target, reading the existing 12 App/Core Swift files.
- `MacBuild/Info.plist`: app metadata, generated without App Playground tooling.
- `scripts/generate_xcode_project.py`: deterministic project generation when sources change.
- `scripts/build_ios_unsigned.sh`: macOS/Xcode-only device build and IPA packaging.
- `.github/workflows/build-ios.yml`: manual macOS workflow, portable tests, and artifact download.

The project, scheme, plist, source references, workflow structure, and packaging can be checked here. Apple SDK compilation passed in the linked run. Personal signing and iPadOS 27.2 runtime compatibility still require on-device validation.

## Sources

- [Official AltStore Windows installation guide source](https://github.com/altstoreio/faq/blob/main/altstore-world/how-to-install-altstore-windows.md).
- [Official getting-started guide: expiration and app limits](https://github.com/altstoreio/faq/blob/main/altstore-world/your-altstore.md).
- [Official AltServer release notes](https://github.com/altstoreio/faq/blob/main/release-notes/altserver.md).
- [AltStore Classic versus PAL](https://github.com/altstoreio/faq/blob/main/altstore-pal-v.-altstore-classic.md).
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

The official AltStore guide repository was retrieved at commit `6b558bd75ce46c39a355b1206d69313046816e8b`. The documentation website itself was policy-blocked in the cloud; the official GitHub source above was readable. Current iPadOS 27.2 support was not established from those sources.

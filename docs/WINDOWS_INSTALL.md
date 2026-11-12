# Install from Windows

Download `PencilNotes-unsigned.ipa` from the project's GitHub Releases page. The accompanying SHA-256 file can be used to verify the download with PowerShell `Get-FileHash`.

Use a compatible signing tool such as AltStore Classic. Follow its current [Windows installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), then import the IPA. Enter Apple credentials only into your chosen trusted signing tool, never into PencilNotes or a GitHub issue.

Free-account provisioning normally expires after seven days and must be refreshed. Downloading an IPA alone does not install it. Availability and signing requirements can change.

Before updating, export editable backups to Files. Install updates using the same signing identity and bundle identifier. Avoid uninstalling the app, which can remove local notes.

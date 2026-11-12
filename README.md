<img src="PencilNotes.swiftpm/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="PencilNotes app icon">

# PencilNotes

A small notebook for your next big idea. Write on your iPad with Apple Pencil and send your notes to Notion as images.

[Download the latest release](https://github.com/rabbiii/Handwrite-for-Notion/releases/latest) ? [Installation](docs/WINDOWS_INSTALL.md) ? [Connect Notion](docs/NOTION_SETUP.md) ? [Send feedback](mailto:mar.rabbi40@gmail.com)

## Your notebook

- A continuous canvas with PencilKit drawing tools, undo, and redo.
- Search, sort, and pin notes in the sidebar.
- Choose from 60 note icons. The open note animates gently, respecting Reduce Motion.
- Rename, share, and select multiple notes. Recover removed notes from Recently Deleted.
- Export images for sharing and editable backups for safekeeping.
- Optional one-way Notion sync updates the image linked to your note.

## Get started

1. Install the IPA using your signing tool. Releases are unsigned and cannot install directly from Safari.
2. Tap **New Note** and start writing. Notion is optional.
3. To sync, connect an internal integration in Settings, choose a destination, and tap Sync.
4. Export an **Editable Backup** to Files regularly, especially before updates or reinstalling.

Tap a note icon to customize it. Tap the selected note's minus button to save and return Home. Use the Library menu for sorting and Recently Deleted. Long-press a note to pin it.

## Privacy and safety

Editable handwriting stays in the app's local storage. The app has no analytics or advertising SDK. Your Notion integration token is stored in Apple's Keychain. When you sync, the rendered image, title, and identifying link metadata are sent to Notion over HTTPS. Notion's own data policies then apply.

Local saves use atomic replacement and retain a previous readable copy. These protections reduce risk but cannot guarantee recovery after device loss, storage failure, or uninstalling. Recently Deleted stays on the same device and is not an independent backup. Permanently deleting a note removes its local recovery copies; its Notion image remains.

Notion sync is one-way. Editing or deleting the image in Notion does not edit local handwriting. Image exports do not contain editable strokes. Use `.pencilnote` backups to preserve editable content. There is no app-specific end-to-end encryption or independent security audit.

External links open their respective services. Never post integration tokens, private notes, or personal screenshots in public issues.

## Installation and updates

An iPad and a compatible signing method are required. Free-account signing requires periodic renewal. Keep the same signing identity and bundle identifier when updating, and export backups first. See the [Windows installation guide](docs/WINDOWS_INSTALL.md) and [iPad guide](docs/IPAD_SETUP.md).

## Open source

Made with love by **Morsalin Islam**. Licensed under the [MIT License](LICENSE), including commercial reuse under its terms. PencilNotes is an independent project and is not affiliated with Apple or Notion.

[Report an issue](https://github.com/rabbiii/Handwrite-for-Notion/issues) ? [Development guide](docs/ARCHITECTURE.md) ? [Validation](docs/VALIDATION.md) ? [Changelog](CHANGELOG.md)

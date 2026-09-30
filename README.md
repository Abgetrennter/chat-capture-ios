# ChatCapture for iOS

ChatCapture captures copied WeChat conversations as either an ordered ZIP archive containing text and available media, or a plain-text file that joins text nodes and omits media payloads. The text already present in a message node, such as an image placeholder, is preserved.

## Requirements

- iOS 16 or later
- Xcode 16 or later
- No third-party packages

## Build and run

Open `ChatCapture.xcodeproj` in Xcode, choose a signing team in **Signing & Capabilities**, select an iPhone or simulator, and run the `ChatCapture` scheme. For a device build, set a bundle identifier that is available to your Apple Developer team.

To build an unsigned IPA and run the archive-format checks from the command line on macOS:

```sh
bash build-unsigned.sh
```

The output is written to `build/`. An unsigned IPA must be signed before it can be installed on a device.

## Privacy

- The app reads the pasteboard only after the user taps an export button.
- Capture and export are performed on the device. The app has no network client, analytics, or third-party SDKs.
- Exported files are saved in the app's `Documents/Captures` folder and may be included in device backups according to the user's iOS backup settings. The app does not send or share them automatically; the user chooses a destination in the iOS share sheet.
- A full ZIP can contain private conversation text and media. Review the selected file and destination before sharing it.

## License

GNU Affero General Public License v3.0 only. See [LICENSE](LICENSE).

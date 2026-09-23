# Scanora (scanora)

Document scanner app — scan, OCR, merge ID cards and edit documents on device.

## Features

- Document scanner with editor
- OCR text recognition
- ID-card merge
- Document management and settings

## Tech Stack

- Flutter (Dart)
- GetX for state management and routing
- On-device scanning/OCR

## Getting Started

```bash
flutter pub get
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

## Project Structure

```
lib/
├── app/modules/   # Home, scanner, OCR, editor, documents
├── services/      # File/scan services
└── main.dart      # App entry point
```

## Notes

- App label: "scanora" (Android)
- No secrets, keystores or Firebase configs are committed to this repository.

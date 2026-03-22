# Contributing to libre_location

Thank you for your interest in contributing! This project is built for the privacy-focused community, and we welcome contributions of all kinds.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/libre-location.git`
3. Create a branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Run tests: `flutter test`
6. Run analysis: `flutter analyze`
7. Submit a pull request

## Development Setup

```bash
# Get dependencies
flutter pub get

# Run the example app
cd example
flutter run
```

## Guidelines

### Code Style
- Follow the [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter analyze` to check for issues
- Write dartdoc comments for public APIs

### Platform Code
- **Android:** Kotlin only. No Java.
- **iOS:** Swift only. No Objective-C.
- **ZERO Google Play Services.** Do not import or depend on any GMS libraries. This is a hard rule.

### Commits
- Use clear, descriptive commit messages
- Reference issue numbers when applicable

### Testing
- Add unit tests for new Dart code
- Test on both Android and iOS when possible
- Test on degoogled devices (GrapheneOS, CalyxOS) if you have access

### Pull Requests
- Keep PRs focused on a single change
- Update documentation if your change affects the public API
- Add a CHANGELOG entry

## Reporting Issues

- Use GitHub Issues
- Include device info, OS version, and steps to reproduce
- Logs are helpful — include `adb logcat` output for Android issues

## Code of Conduct

Be respectful, constructive, and inclusive. We're all here to build something useful.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

# OMMessenger Mobile

![Build Status](https://github.com/NotEduCo342/OMMessenger-mobile/workflows/Build%20Android%20APK/badge.svg)

A modern Flutter messaging application with offline-first capabilities, real-time sync, and automatic update system.

## 🚀 Features

- ✨ Real-time messaging via WebSocket
- 📴 Offline-first architecture with local database
- 🔄 Automatic background sync when connectivity restored
- 📱 Update notification system with "Remind Me Later"
- 🌙 Dark mode support
- 🔐 Secure authentication with JWT
- 📊 Message status tracking (pending, sent, delivered, read)
- 👥 User search and conversation management

## 📋 Prerequisites

- Flutter 3.10.4 or higher
- Dart SDK 3.10.4 or higher
- Android Studio / VS Code with Flutter extensions
- Java 17 (for Android builds)

## 🛠️ Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/NotEduCo342/OMMessenger-mobile.git
   cd OMMessenger-mobile
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate code (Drift database):**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Configure backend URL:**
   Edit `lib/config/constants.dart` and set your backend URL:
   ```dart
   static const String baseUrl = 'https://api-om.wexun.tech';
   static const String wsUrl = 'wss://api-om.wexun.tech/ws';
   ```

5. **Run the app:**
   ```bash
   flutter run
   ```

## 🏗️ Building

### Local Build (if your laptop can handle it)

**Debug build:**
```bash
flutter build apk --debug
```

**Release build:**
```bash
flutter build apk --release --split-per-abi
```

APKs will be in: `build/app/outputs/flutter-apk/`

### Cloud Build (Recommended - via GitHub Actions)

Your laptop crashes during builds? Use GitHub Actions!

#### Option 1: Automatic Build
Just push your code and GitHub will build automatically:
```bash
git add .
git commit -m "your changes"
git push
```

Wait ~5-10 minutes, then download APKs from: **Actions → Your Workflow Run → Artifacts**

#### Option 2: Manual Build
1. Go to [Actions](https://github.com/NotEduCo342/OMMessenger-mobile/actions)
2. Click **"Build Android APK"**
3. Click **"Run workflow"** dropdown
4. Select build type (release/debug)
5. Click **"Run workflow"**
6. Download APKs from Artifacts after ~5-10 minutes

#### Option 3: Create Production Release
1. Go to [Actions](https://github.com/NotEduCo342/OMMessenger-mobile/actions)
2. Click **"Create Production Release"**
3. Click **"Run workflow"**
4. Fill in the form:
   - **Version:** e.g., `1.0.1`
   - **Build number:** e.g., `2`
   - **Changelog:** Your release notes
   - **Force update:** Check if mandatory
   - **Min supported build:** Minimum version still supported
5. Click **"Run workflow"**
6. APKs will be published to [Releases](https://github.com/NotEduCo342/OMMessenger-mobile/releases)

## 📦 APK Architectures

- **arm64-v8a** - 64-bit ARM (recommended for most devices, 2019+)
- **armeabi-v7a** - 32-bit ARM (older devices, 2015-2019)
- **x86_64** - Intel-based Android (emulators, rare tablets)

## 🧪 Testing

Run tests:
```bash
flutter test
```

Run tests with coverage:
```bash
flutter test --coverage
```

## 🔍 Code Quality

Format code:
```bash
dart format lib/ test/
```

Analyze code:
```bash
flutter analyze
```

## 📱 Architecture

```
lib/
├── config/          # App configuration
├── database/        # Drift database (SQLite)
├── models/          # Data models
├── providers/       # State management (Provider)
├── screens/         # UI screens
├── services/        # API, WebSocket, offline queue
└── widgets/         # Reusable UI components
```

### Key Services

- **ApiService** - HTTP REST API communication
- **WebSocketService** - Real-time messaging
- **ConnectivityService** - Network status monitoring
- **OfflineQueueService** - Queue messages when offline
- **UpdateService** - Check for app updates

### Database (Drift/SQLite)

- Local-first storage for messages and conversations
- Automatic conflict resolution
- Background sync when connectivity restored

## 🔄 Update System

The app checks for updates on:
- App startup
- Returning from background
- Manual refresh

Users can:
- Update now (opens browser to download)
- Remind me later (24 hours)
- Skip (if not forced)

Force updates block the app until user updates.

## 🌐 Backend Integration

This mobile app requires the OMMessenger backend server:
- Repository: [OMMessenger-backend](https://github.com/NotEduCo342/OMMessenger-backend)
- API docs: See backend repository

## 📝 Version Management

Versions are defined in `pubspec.yaml`:
```yaml
version: 1.0.0+1  # 1.0.0 is version name, 1 is build number
```

When creating a release via GitHub Actions, the version is automatically updated.

## 🐛 Troubleshooting

### Build fails with "No resource found..."
```bash
flutter clean
flutter pub get
flutter build apk
```

### WebSocket connection fails
- Check backend URL in `constants.dart`
- Ensure backend is running and accessible
- Check network permissions in `AndroidManifest.xml`

### Database errors
```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### GitHub Actions build fails
- Check workflow logs for specific errors
- Ensure `pubspec.yaml` is valid
- Verify all dependencies are available

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is private and proprietary.

## 🔗 Links

- [Backend Repository](https://github.com/NotEduCo342/OMMessenger-backend)
- [GitHub Actions Workflows](https://github.com/NotEduCo342/OMMessenger-mobile/actions)
- [Releases](https://github.com/NotEduCo342/OMMessenger-mobile/releases)

## 💡 Support

For issues or questions:
1. Check the [Issues](https://github.com/NotEduCo342/OMMessenger-mobile/issues) page
2. Review the troubleshooting section above
3. Create a new issue with detailed information

---

**Built with ❤️ using Flutter**

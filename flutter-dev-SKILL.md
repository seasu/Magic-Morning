---
name: flutter-dev
description: >
  Flutter app development skill for Claude Code. Use this skill whenever the user wants to create,
  modify, debug, or architect a Flutter/Dart application. Triggers include: any mention of 'Flutter',
  'Dart', 'widget', 'pubspec', '.dart files', 'StatefulWidget', 'StatelessWidget', 'Provider',
  'Riverpod', 'Bloc', 'GetX', 'go_router', or mobile app development with cross-platform intent.
  Also trigger when the user asks about app navigation, state management, theming, responsive layouts,
  platform channels, or building/releasing Flutter apps. Even if the user just says "build me an app"
  or "mobile app" without specifying Flutter, consider triggering this skill if the project context
  suggests Flutter. This skill is optimized for mobile-first Claude Code workflows (e.g., using
  Claude Code on a phone to develop apps).
---

# Flutter Development Skill

## Quick Reference: Project Commands

```bash
# Create new project
flutter create --org com.example my_app

# Run checks
dart analyze
dart format .

# Build
flutter build apk --release
flutter build ios --release
flutter build web
```

## 1. Project Structure Convention

Always follow this structure for any non-trivial Flutter app:

```
lib/
├── main.dart                  # Entry point, app-level config
├── app.dart                   # MaterialApp / router setup
├── core/
│   ├── constants/             # App-wide constants, colors, strings
│   ├── theme/                 # ThemeData, text styles, color schemes
│   ├── utils/                 # Helpers, extensions, formatters
│   └── services/              # Shared services (http, storage, auth)
├── features/
│   └── <feature_name>/
│       ├── models/            # Data classes, DTOs
│       ├── repositories/      # Data access layer
│       ├── providers/         # State management (or bloc/, cubit/)
│       ├── screens/           # Full-page widgets
│       └── widgets/           # Feature-specific reusable widgets
├── shared/
│   └── widgets/               # Cross-feature reusable widgets
└── l10n/                      # Localization (optional)
```

**Key rules:**
- One widget per file. File name matches class name in snake_case.
- Feature folders are self-contained. No cross-feature imports except through `shared/` or `core/`.
- Keep `main.dart` minimal: just `runApp()` and top-level providers.

## 2. State Management Guide

Choose based on project complexity:

| Complexity | Recommended | When to use |
|---|---|---|
| Simple / learning | `setState` + `InheritedWidget` | Prototypes, <5 screens |
| Medium | **Riverpod** (recommended default) | Most apps, good testability |
| Medium | Provider | If team already knows it |
| Complex / enterprise | Bloc/Cubit | Heavy event-driven flows |
| Rapid prototyping | GetX | Quick MVPs (less testable) |

### Riverpod Quick Patterns (Default Recommendation)

```dart
// pubspec.yaml: flutter_riverpod: ^2.5.0, riverpod_annotation: ^2.3.0

// Simple state
final counterProvider = StateProvider<int>((ref) => 0);

// Async data
final userProvider = FutureProvider<User>((ref) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchCurrentUser();
});

// Complex state with Notifier
class TodoListNotifier extends Notifier<List<Todo>> {
  @override
  List<Todo> build() => [];

  void add(Todo todo) => state = [...state, todo];
  void remove(String id) => state = state.where((t) => t.id != id).toList();
}
final todoListProvider = NotifierProvider<TodoListNotifier, List<Todo>>(
  TodoListNotifier.new,
);
```

## 3. Navigation

Use **go_router** for declarative routing:

```dart
// pubspec.yaml: go_router: ^14.0.0

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/detail/:id', builder: (_, state) =>
      DetailScreen(id: state.pathParameters['id']!)),
    ShellRoute(
      builder: (_, __, child) => ScaffoldWithNavBar(child: child),
      routes: [ /* nested routes */ ],
    ),
  ],
);

// In app.dart
MaterialApp.router(routerConfig: router);
```

## 4. Widget Best Practices

### Composition over inheritance
```dart
// GOOD: Small, composable widgets
class UserAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  const UserAvatar({required this.imageUrl, this.radius = 24});

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundImage: NetworkImage(imageUrl),
  );
}

// BAD: Giant build methods with deeply nested widget trees
```

### Key rules:
- Extract widgets when `build()` exceeds ~50 lines.
- Use `const` constructors everywhere possible.
- Prefer `StatelessWidget` unless you need `initState`, `dispose`, or `AnimationController`.
- Always add `Key` parameter support for list items.
- Use `Widget` type for child params, not concrete types.

## 5. Theming & Styling

```dart
// core/theme/app_theme.dart
class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ),
    textTheme: _textTheme,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    ),
    textTheme: _textTheme,
  );
}

// Usage: always use theme tokens, never hardcoded colors
Text('Hello', style: Theme.of(context).textTheme.titleLarge)
Container(color: Theme.of(context).colorScheme.primaryContainer)
```

## 6. Data Layer Pattern

```dart
// models/user.dart — use freezed for complex models
class User {
  final String id;
  final String name;
  final String email;

  const User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

// repositories/user_repository.dart
class UserRepository {
  final Dio _dio; // or http.Client
  UserRepository(this._dio);

  Future<User> getUser(String id) async {
    final response = await _dio.get('/users/$id');
    return User.fromJson(response.data);
  }
}
```

**Recommended packages for data layer:**
- HTTP: `dio` (feature-rich) or `http` (lightweight)
- Local storage: `shared_preferences` (KV), `hive` or `isar` (NoSQL), `drift` (SQL)
- Serialization: `json_serializable` + `freezed` for immutable models
- Firebase: `cloud_firestore`, `firebase_auth`, etc.

## 7. Error Handling

```dart
// Sealed class for results
sealed class Result<T> {
  const Result();
}
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}
class Failure<T> extends Result<T> {
  final String message;
  final Object? error;
  const Failure(this.message, [this.error]);
}

// In repository
Future<Result<User>> getUser(String id) async {
  try {
    final response = await _dio.get('/users/$id');
    return Success(User.fromJson(response.data));
  } on DioException catch (e) {
    return Failure('Network error: ${e.message}', e);
  } catch (e) {
    return Failure('Unexpected error', e);
  }
}
```

## 8. Testing Essentials

```dart
// Unit test
test('User.fromJson creates correct instance', () {
  final json = {'id': '1', 'name': 'Test', 'email': 'test@example.com'};
  final user = User.fromJson(json);
  expect(user.name, 'Test');
});

// Widget test
testWidgets('Counter increments', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: CounterScreen()));
  expect(find.text('0'), findsOneWidget);
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump();
  expect(find.text('1'), findsOneWidget);
});
```

## 9. Performance Checklist

- Use `const` widgets to prevent unnecessary rebuilds.
- Use `ListView.builder` / `GridView.builder` for long lists (never `Column` with many children).
- Avoid `Opacity` widget for hiding — use `Visibility` or conditional rendering.
- Profile with `flutter run --profile` and DevTools.
- Use `RepaintBoundary` around heavy subtrees that don't change often.
- Minimize `setState` scope — rebuild only what changes.
- Cache network images: `cached_network_image` package.

## 10. Common pubspec.yaml Starter

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.0
  go_router: ^14.0.0
  dio: ^5.4.0
  shared_preferences: ^2.2.0
  cached_network_image: ^3.3.0
  intl: ^0.19.0
  gap: ^3.0.1               # Cleaner spacing than SizedBox
  flutter_animate: ^4.5.0   # Easy animations

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.0
  json_serializable: ^6.7.0
  mocktail: ^1.0.0
```

## 11. Mobile-First Claude Code Workflow Tips

When developing via Claude Code on a phone:

1. **Work in small, testable increments.** Ask Claude Code to create/modify one file at a time.
2. **Use feature-based requests:** "Create the login feature with screen, model, and repository" is better than describing the entire app at once.
3. **Run `dart analyze` frequently** to catch issues early without needing to launch the app.
4. **Keep a TODO.md** in the project root to track what's done and what's next — helps maintain context across sessions.
5. **Use `dart format .`** to keep code clean without manual formatting.
6. **Commit often** with descriptive messages so you can roll back if something breaks.

## 12. Platform-Specific Notes

### Android
- Set `minSdkVersion` ≥ 21 in `android/app/build.gradle`
- For permissions: edit `AndroidManifest.xml`
- Signing: create `key.properties` for release builds

### iOS
- Set deployment target ≥ 13.0 in Xcode
- For permissions: edit `Info.plist` with usage descriptions
- CocoaPods: run `cd ios && pod install` after adding native dependencies

### Web
- Not all plugins support web — check pub.dev compatibility
- Use `kIsWeb` for platform-conditional code

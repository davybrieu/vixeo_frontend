import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/device/layout.dart';
import 'package:vixeo/core/features.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focus_navigation.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/hero.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/messages/messages.dart';
import 'package:vixeo/features/notifications/inbox.dart';
import 'package:vixeo/features/shell/app_shell.dart';

// Navigation with the arrows of a TV remote (D-pad) or a keyboard: core/widgets/focus_navigation.dart
// and the rail of shell/app_shell.dart.

class _Session extends SessionController {
  @override
  SessionState build() =>
      SessionState(status: SessionStatus.signedIn, token: 't', profile: const Profile(id: 1, name: 'Davy'));
}

/// No unread notification, nothing asked to the server.
class _NoUnread extends UnreadNotifications {
  @override
  Future<void> refresh({bool force = false}) async {}
}

/// No unread message, nothing asked to the server.
class _NoUnreadMessages extends UnreadMessages {
  @override
  Future<void> refresh({bool force = false}) async {}
}

/// The app's keys and navigation around [home].
Widget _app(Widget home) => ProviderScope(
  overrides: [
    sessionProvider.overrideWith(_Session.new),
    liveTvProvider.overrideWithValue(false),
    unreadNotificationsProvider.overrideWith(_NoUnread.new),
    unreadMessagesProvider.overrideWith(_NoUnreadMessages.new),
  ],
  child: MaterialApp(
    theme: buildVixeoTheme(),
    shortcuts: remoteShortcuts,
    actions: remoteActions,
    builder: (context, child) => RemoteNavigation(child: child!),
    home: home,
  ),
);

/// A page in the shell, as go_router places it (its own navigator, beside the rail).
Widget _shell(Widget page, {String location = '/parametres'}) => AppShell(
  location: location,
  child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Scaffold(body: page))),
);

Widget _button(String label, {bool autofocus = false, double height = 60}) => VxFocusable(
  onPressed: () {},
  autofocus: autofocus,
  semanticLabel: label,
  child: SizedBox(width: 240, height: height, child: Text(label)),
);

String? _focused() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void _largeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Left from a page: the current destination of the rail; Right: back where the focus was', (
    tester,
  ) async {
    _largeScreen(tester);
    await tester.pumpWidget(
      _app(
        _shell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_button('Premier', autofocus: true), _button('Deuxième'), _button('Troisième')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_focused(), 'Premier');

    // Up from the top of the page: nothing above in the page, the focus doesn't jump to the rail.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'Premier');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'Deuxième');

    // Left: « Paramètres » (the page shown), not the item level with « Deuxième ».
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(), 'Navigation /parametres');

    // Up and Down stay in the rail.
    for (var i = 0; i < 7; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused(), startsWith('Mon profil'));
    for (var i = 0; i < 8; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused(), anyOf(startsWith('Navigation'), startsWith('Mon profil')));
    }

    // Right: back to « Deuxième », whatever the item of the rail.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'Deuxième');
  });

  testWidgets('Right from the rail before anything was focused in the page: its first element', (tester) async {
    _largeScreen(tester);
    await tester.pumpWidget(
      _app(_shell(Column(children: [_button('Premier'), _button('Deuxième')]), location: '/recherche')),
    );
    await tester.pumpAndSettle();
    // The rail has the focus, nothing of the page had it.
    final railItem = tester
        .widget<Focus>(
          find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'Navigation /recherche'),
        )
        .focusNode!;
    railItem.requestFocus();
    await tester.pump();
    expect(_focused(), 'Navigation /recherche');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'Premier');
  });

  testWidgets('text fields: Left / Right move the caret, Up / Down leave a one-line field', (tester) async {
    _largeScreen(tester);
    final field = TextEditingController();
    final notes = TextEditingController();
    final fieldFocus = FocusNode(debugLabel: 'Recherche');
    final notesFocus = FocusNode(debugLabel: 'Commentaire');
    addTearDown(() {
      field.dispose();
      notes.dispose();
      fieldFocus.dispose();
      notesFocus.dispose();
    });
    await tester.pumpWidget(
      _app(
        _shell(
          Column(
            children: [
              SizedBox(
                width: 300,
                child: TextField(controller: field, focusNode: fieldFocus),
              ),
              _button('Valider'),
              SizedBox(
                width: 300,
                child: TextField(controller: notes, focusNode: notesFocus, maxLines: 4),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    fieldFocus.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'orbite');
    await tester.pump();
    expect(field.selection.baseOffset, 6);

    // Left in a field of a page: the caret moves, the focus stays (no jump to the rail).
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(), 'Recherche');
    expect(field.selection.baseOffset, 5);

    // Down leaves the one-line field.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'Valider');

    // In a longer field, Up / Down go from line to line.
    notesFocus.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'une\ndeux');
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'Commentaire');
    expect(notes.selection.baseOffset, lessThan(4));
  });

  testWidgets('TV: one smooth scroll to the focused element, no jump first', (tester) async {
    DeviceInfo.isTv = true;
    addTearDown(() => DeviceInfo.isTv = false);
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              for (var i = 1; i <= 6; i++) _button('Ligne $i', autofocus: i == 1, height: 400),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_focused(), 'Ligne 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focused(), 'Ligne 2');
    // Flutter alone would jump to show « Ligne 2 » (half off screen), then the animation moved it
    // again: now the list hasn't moved yet, it slides once.
    expect(scroll.offset, 0);
    await tester.pumpAndSettle();
    // « Ligne 2 » (400 to 800) a bit above the middle: 400 − 0.42 × (600 − 400).
    expect(scroll.offset, closeTo(400 - RemoteNavigation.alignment * 200, 0.5));
  });

  testWidgets('a held key: the hero waits for the focus to stop instead of following every card', (tester) async {
    MediaItem title(int id) => MediaItem(id: id, type: MediaType.movie, title: 'Titre $id');
    final hero = HeroSelection();
    addTearDown(hero.dispose);
    addTearDown(() => RemoteKeys.repeating = false);

    hero.select(title(1));
    expect(hero.item.value?.id, 1, reason: 'one press: at once');

    RemoteKeys.repeating = true;
    hero.select(title(2));
    hero.select(title(3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(hero.item.value?.id, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(hero.item.value?.id, 3);
  });

  test('the remote keys: repeating while a key is held', () {
    const key = PhysicalKeyboardKey.arrowRight;
    const arrow = LogicalKeyboardKey.arrowRight;
    RemoteKeys.onKey(const KeyDownEvent(physicalKey: key, logicalKey: arrow, timeStamp: Duration.zero));
    expect(RemoteKeys.repeating, isFalse);
    RemoteKeys.onKey(const KeyRepeatEvent(physicalKey: key, logicalKey: arrow, timeStamp: Duration(milliseconds: 500)));
    expect(RemoteKeys.repeating, isTrue);
    RemoteKeys.onKey(const KeyUpEvent(physicalKey: key, logicalKey: arrow, timeStamp: Duration(milliseconds: 600)));
    expect(RemoteKeys.repeating, isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'backend.dart';
import 'pages.dart';
import 'selection.dart';
import 'share_service.dart';
import 'shared_pages.dart';
import 'store.dart';
import 'widgets.dart';
import 'app_updates.dart';

/// Selection state of the Library tab (shared with the bottom bar).
final libSel = SelectionController();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EvoraApp());
  store.init(); // loads photos in the background
  backend.load(); // restores sign-in if sharing is set up
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF0A84FF),
  );
  final bg = dark ? Colors.black : Colors.white;
  final text = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    headlineMedium: GoogleFonts.inter(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9,
      color: dark ? Colors.white : Colors.black,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: dark ? Colors.white : Colors.black,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
  );
}

/// iOS-style bouncing scroll everywhere.
class _Bouncy extends MaterialScrollBehavior {
  const _Bouncy();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class EvoraApp extends StatelessWidget {
  const EvoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evora',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      scrollBehavior: const _Bouncy(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _checkingUpdate = false;
  DateTime? _lastUpdateCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || _checkingUpdate) return;
    final now = DateTime.now();
    if (_lastUpdateCheck != null &&
        now.difference(_lastUpdateCheck!) < const Duration(minutes: 2)) {
      return;
    }
    _checkingUpdate = true;
    _lastUpdateCheck = now;
    try {
      await AppUpdateService.checkAndPrompt(context);
    } finally {
      _checkingUpdate = false;
    }
  }

  void _go(int i) {
    if (i == tabIndex.value) return;
    HapticFeedback.selectionClick();
    libSel.clear();
    tabIndex.value = i;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([tabIndex, libSel, backend]),
      builder: (context, _) {
        final tab = tabIndex.value;
        final selecting = tab == 0 && libSel.active;
        final Widget page;
        switch (tab) {
          case 0:
            page = LibraryPage(key: const ValueKey('library'), sel: libSel);
          case 1:
            page = const EventsPage(key: ValueKey('events'));
          case 2:
            page = const SharedTab(key: ValueKey('shared'));
          default:
            page = const AppUpdatesPage(key: ValueKey('updates'));
        }

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              if (tab != 0) const Positioned.fill(child: AmbientBackground()),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOut,
                child: page,
              ),
            ],
          ),
          bottomNavigationBar: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: selecting
                ? SelectionBar(
                    key: const ValueKey('selbar'),
                    sel: libSel,
                    onWhatsApp: () => ShareService.sendSelected(context, store,
                        store.selectedAssets(libSel.selected), libSel),
                    onInApp: () => ShareComposer.open(
                        context, store.selectedAssets(libSel.selected),
                        onDone: libSel.clear),
                    onAddToEvent: () => showAddToEventSheet(
                        context, libSel.selected.toList(),
                        onDone: libSel.clear),
                    onMarkSent: () {
                      store.markSentIds(libSel.selected);
                      libSel.clear();
                    },
                    onClearSent: () {
                      store.clearSentIds(libSel.selected);
                      libSel.clear();
                    },
                    onDelete: () => deleteSelected(
                        context, store.selectedAssets(libSel.selected), libSel),
                  )
                : GlassBar(
                    key: const ValueKey('navbar'),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _NavItem(
                          icon: Icons.photo_library_rounded,
                          label: 'Library',
                          selected: tab == 0,
                          onTap: () => _go(0),
                        ),
                        _NavItem(
                          icon: Icons.photo_album_rounded,
                          label: 'Events',
                          selected: tab == 1,
                          onTap: () => _go(1),
                        ),
                        _NavItem(
                          icon: Icons.people_alt_rounded,
                          label: 'Shared',
                          selected: tab == 2,
                          badge: backend.requests.length,
                          onTap: () => _go(2),
                        ),
                        _NavItem(
                          icon: Icons.system_update_alt_rounded,
                          label: 'Updates',
                          selected: tab == 3,
                          onTap: () => _go(3),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final idle = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6);
    final color = selected ? accent : idle;
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: selected ? 1.1 : 1,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  child: Icon(icon, color: color, size: 25),
                ),
                if (badge > 0)
                  Positioned(
                    right: -9,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text('$badge',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

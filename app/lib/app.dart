import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/widgets/privacy_cover.dart';
import 'ui/widgets/toast_host.dart';

/// Makes [AppState] available to every screen without a state-management
/// package. The app is small and single-user; an InheritedNotifier is enough.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For callbacks that only need to act, not rebuild.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class BillApp extends StatefulWidget {
  final AppState state;
  const BillApp({super.key, required this.state});

  @override
  State<BillApp> createState() => _BillAppState();
}

class _BillAppState extends State<BillApp> with WidgetsBindingObserver {
  /// Starts locked. Set once the right PIN is entered, cleared whenever the
  /// app leaves the foreground, so putting the phone down re-locks it.
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_onChange);
    super.dispose();
  }

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _lifecycle = state;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        _unlocked = false;
      }
    });
  }

  /// Android photographs the app as it leaves the foreground to draw the
  /// thumbnail in the task switcher, and that photograph sits there for
  /// anyone who picks the phone up. Covering the screen the moment the app
  /// stops being frontmost means the thumbnail is of the cover.
  ///
  /// Only when a PIN is set, because that is the user saying they want this;
  /// doing it unasked would be a confusing flicker on every app switch.
  bool get _coverForPrivacy =>
      widget.state.settings.pinOn &&
      widget.state.settings.hasPin &&
      _lifecycle != AppLifecycleState.resumed;

  void _onChange() => setState(() {});

  bool get _locked {
    final s = widget.state.settings;
    return s.pinOn && s.hasPin && !_unlocked;
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.state.settings.dark;
    final c = dark ? BillColors.dark : BillColors.light;

    // The handoff asks for the status bar to follow the theme too.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: c.bg,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: c.bg,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Split the Bill',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark),
        home: const HomeScreen(),
        // The lock goes OVER everything, rather than being the bottom route.
        //
        // It used to be expressed as `home:`, which is only the root of the
        // navigator stack. Anything pushed on top of it - a group, a receipt,
        // the summary with every figure in it - stayed on screen when the app
        // re-locked, so the PIN only blocked the app if you happened to be on
        // the home screen when you put the phone down. Everywhere else it
        // blocked nothing at all.
        //
        // As an overlay it also keeps the user's place: unlocking puts them
        // back on the screen they were reading, instead of at the beginning.
        builder: (context, child) => ToastHost(
          // Expand explicitly: with the app's screens offstage there is no
          // unpositioned child left to give the Stack a size, and it
          // collapsed to nothing - which left the lock screen painted but
          // zero-sized, so its keypad could not be tapped.
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Offstage rather than merely covered: while the app is locked
              // the screens underneath are not painted, not hit-tested and
              // not read out by a screen reader, and they cannot appear for a
              // frame during a transition. Their state and the navigator
              // stack survive, so unlocking returns the user to the screen
              // they were on.
              Offstage(offstage: _locked, child: child!),
              if (_locked)
                LockScreen(
                  verify: widget.state.verifyPin,
                  onUnlocked: () => setState(() => _unlocked = true),
                ),
              if (_coverForPrivacy) const PrivacyCover(),
            ],
          ),
        ),
      ),
    );
  }
}

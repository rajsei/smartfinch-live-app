import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:birdnet_live/l10n/app_localizations.dart';

import 'core/theme/app_theme.dart';
import 'features/live/live_screen.dart';
import 'shared/providers/app_providers.dart';
import 'shared/services/quick_action_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Resolve the UI locale from the platform/app preference list.
///
/// Flutter's generated locale list is alphabetized, so relying on the default
/// fallback can land unsupported languages on Czech because `cs` is first.
/// Prefer an exact language match from the user's locale list, otherwise fall
/// back to English explicitly.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  final supported = supportedLocales.toList();
  for (final preferred in preferredLocales ?? const <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == preferred.languageCode) return candidate;
    }
  }

  return supported.firstWhere(
    (locale) => locale.languageCode == 'en',
    orElse: () => supported.first,
  );
}

/// Root application widget.
///
/// Configures theme, localization, and the initial route based on
/// whether onboarding and policy acceptance have been completed.
class App extends ConsumerWidget {
  const App({super.key, this.launchQuickAction});

  /// A Quick Listen widget tap that started the app, read before the first
  /// frame so the app can open on Live mode rather than painting Home and then
  /// navigating off it.
  final String? launchQuickAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final useDynamicColor = ref.watch(dynamicColorProvider);
    final useHighContrastTheme = ref.watch(highContrastThemeProvider);
    final locale = ref.watch(localeProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Use the platform's dynamic palette when the user has opted in
        // and the OS provides one. Otherwise fall back to the brand theme.
        final ThemeData lightTheme;
        final ThemeData darkTheme;

        if (useHighContrastTheme) {
          lightTheme = AppTheme.highContrastLight();
          darkTheme = AppTheme.highContrastDark();
        } else if (useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null) {
          lightTheme = AppTheme.fromColorScheme(lightDynamic.harmonized());
          darkTheme = AppTheme.fromColorScheme(darkDynamic.harmonized());
        } else {
          lightTheme = AppTheme.light();
          darkTheme = AppTheme.dark();
        }

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,

          // Theme
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,

          // Localization
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          localeListResolutionCallback: resolveAppLocale,
          localeResolutionCallback:
              (locale, supportedLocales) => resolveAppLocale(
                locale == null ? null : <Locale>[locale],
                supportedLocales,
              ),
          // Initial screen based on app state
          home: _QuickActionListener(
            launchAction: launchQuickAction,
            child: const _AppGate(),
          ),
        );
      },
    );
  }
}

/// Listens for the Quick Listen home-screen widget's launch action and
/// jumps straight to Live Mode with recording auto-started, on both cold
/// start (app was killed) and warm start (app already running).
class _QuickActionListener extends ConsumerStatefulWidget {
  const _QuickActionListener({required this.child, this.launchAction});

  final Widget child;

  /// A widget tap that was already waiting when the app started, read before
  /// the first frame so this listener can open Live Mode without the user
  /// watching Home appear first.
  final String? launchAction;

  @override
  ConsumerState<_QuickActionListener> createState() =>
      _QuickActionListenerState();
}

class _QuickActionListenerState extends ConsumerState<_QuickActionListener> {
  bool _handlingQuickAction = false;

  /// The Live Mode route this handler last pushed. Self-invalidating: once the
  /// user leaves that screen the route is no longer `isActive`.
  Route<void>? _pushedLiveRoute;

  final _LaunchFrameHold _launchFrame = _LaunchFrameHold();

  @override
  void initState() {
    super.initState();
    QuickActionService.setNativeActionHandler(_onNativeAction);
    if (widget.launchAction != null) _launchFrame.hold();
    unawaited(_takePendingNativeAction());
  }

  @override
  void dispose() {
    _launchFrame.release();
    QuickActionService.setNativeActionHandler(null);
    super.dispose();
  }

  Future<void> _takePendingNativeAction() async {
    try {
      // A tap that launched the app was already drained before the first frame;
      // the native queue only still holds one when that read did not happen or
      // did not find it.
      final launchAction = widget.launchAction;
      if (launchAction != null) {
        await _handleQuickAction(launchAction, fromLaunch: true);
        return;
      }
      final action = await QuickActionService.takePendingNativeAction();
      if (!mounted || action == null) return;
      await _handleQuickAction(action);
    } catch (error, stackTrace) {
      debugPrint(
        'Quick Listen could not read the pending native action: '
        '$error\n$stackTrace',
      );
    } finally {
      // Never keep the launch waiting on a read that threw before it could
      // settle on a destination.
      _launchFrame.release();
    }
  }

  void _onNativeAction(String action) {
    if (!mounted) return;
    unawaited(_handleQuickAction(action));
  }

  Future<void> _handleQuickAction(
    String action, {
    bool fromLaunch = false,
  }) async {
    if (action != QuickActionService.startListeningAction ||
        _handlingQuickAction) {
      // Only the launch delivery owns the hold. A cold start also replays the
      // tap through the channel buffer, and that duplicate lands here while the
      // real one is still deciding — it must not let the app paint early.
      if (fromLaunch) _launchFrame.release();
      return;
    }
    _handlingQuickAction = true;

    try {
      // A fresh install must still complete onboarding and accept the terms;
      // a widget is not a path around either gate.
      final onboardingComplete = ref.read(onboardingCompleteProvider);
      final termsAccepted = ref.read(termsAcceptedProvider);
      if (!onboardingComplete || !termsAccepted) return;

      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;

      // With Live as the only mode, nothing can be running that a widget tap
      // must not interrupt: a mounted Live screen is reused rather than
      // blocked. The workflow probe that arbitrated between Live, Point Count,
      // Survey, ARU and File Analysis went with those modes (transition 0.3).

      // Reuse a mounted Live screen. Replacing it would cancel its duration
      // warning timer and disable its wakelock while the app-wide controller
      // kept recording.
      //
      // [_pushedLiveRoute] covers the gap before a screen this handler pushed
      // has built and registered itself: a cold start can deliver the same
      // action twice — once as the drained pending action, once as the channel
      // message the engine buffered before Dart attached a handler — and
      // without it the second delivery would stack a second Live Mode screen.
      final liveRoute = LiveScreenPresence.mountedRoute ?? _pushedLiveRoute;
      // `isActive` and the navigator identity check matter: `popUntil` with a
      // predicate nothing satisfies pops the stack down to the first route, so
      // a route that has already been removed (or never belonged here) must
      // fall through to a fresh push instead.
      if (liveRoute != null &&
          liveRoute.isActive &&
          identical(liveRoute.navigator, navigator)) {
        if (!liveRoute.isCurrent) {
          navigator.popUntil((route) => identical(route, liveRoute));
        }
        // A no-op for a route that has not registered yet — that screen
        // auto-starts on its own via `forceAutoStart`.
        LiveScreenPresence.requestStartListening(liveRoute);
        return;
      }

      // Preserve the current workflow under Live Mode. In particular, never
      // remove a route without giving its normal PopScope/finalization path a
      // chance to run.
      //
      // A tap that launched the app has nothing to animate away from: Home has
      // never been on screen, and is only underneath so Back has somewhere
      // to go.
      final route =
          fromLaunch
              ? _InstantMaterialPageRoute<void>(
                builder: (_) => const LiveScreen(forceAutoStart: true),
              )
              : MaterialPageRoute<void>(
                builder: (_) => const LiveScreen(forceAutoStart: true),
              );
      _pushedLiveRoute = route;
      unawaited(navigator.push(route));
    } catch (error, stackTrace) {
      debugPrint('Quick Listen action failed: $error\n$stackTrace');
    } finally {
      _handlingQuickAction = false;
      // Every path above has settled on what the first frame should show —
      // Live Mode, or the screen the user has to deal with first.
      _launchFrame.release();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Keeps the system launch screen up while a hand-off that started the app
/// works out where to go.
///
/// A widget tap or a shared file has to clear the same readiness check before
/// it can open a screen, and on a cold start that check reads storage. Without
/// this, the user watches Home paint and then get navigated away from. Frames
/// are still built and laid out while held — only compositing waits — so the
/// work that decides the destination proceeds normally.
class _LaunchFrameHold {
  bool _held = false;
  Timer? _timeout;

  /// Starts holding. Only valid before the first frame — that is, from a
  /// listener's [State.initState]. Calling it later stalls a running app
  /// instead of delaying a launch.
  void hold() {
    if (_held) return;
    _held = true;
    WidgetsBinding.instance.deferFirstFrame();
    // Nothing on the path that follows is slow, but none of it is worth a
    // launch that never paints either. Give up after a beat and let the
    // ordinary push-over-Home behavior take over.
    _timeout = Timer(const Duration(seconds: 5), release);
  }

  /// Lets the app paint. Safe to call repeatedly, and when never held.
  void release() {
    if (!_held) return;
    _held = false;
    _timeout?.cancel();
    _timeout = null;
    WidgetsBinding.instance.allowFirstFrame();
  }
}

/// A [MaterialPageRoute] that arrives without a transition, but still leaves on
/// one.
///
/// For a route pushed before the app's first frame: there is no previous screen
/// to animate away from, and animating one in would put the screen we are
/// bypassing on display for the length of the transition. Going back from it is
/// an ordinary navigation, so that keeps the ordinary animation.
class _InstantMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _InstantMaterialPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

/// Gate widget that routes to onboarding or the home screen.
class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingComplete = ref.watch(onboardingCompleteProvider);
    final termsAccepted = ref.watch(termsAcceptedProvider);

    // The onboarding flow now also captures acceptable-use acceptance, so a
    // completed onboarding implies accepted policy. We still gate on both
    // independently so a future settings reset of either flag re-shows the
    // onboarding flow.
    if (!onboardingComplete || !termsAccepted) {
      return const OnboardingScreen();
    }

    return const HomeScreen();
  }
}

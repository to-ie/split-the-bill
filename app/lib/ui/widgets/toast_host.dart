import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../theme/tokens.dart';

/// The bottom toast pill from the handoff: navy, red dot, auto-dismiss at
/// about 2.8 seconds. Used only for refusals, never for confirmations.
class ToastHost extends StatefulWidget {
  final Widget child;
  const ToastHost({super.key, required this.child});

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  Timer? _timer;
  String _shown = '';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (app.toast.isNotEmpty && app.toast != _shown) {
      _shown = app.toast;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2800), () {
        _shown = '';
        if (mounted) app.clearToast();
      });
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 20,
          right: 20,
          bottom: 28,
          child: IgnorePointer(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: app.toast.isEmpty ? const Offset(0, 0.6) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: app.toast.isEmpty ? 0 : 1,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.navy,
                      borderRadius: BorderRadius.circular(R.pill),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 17,
                          height: 17,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Brand.error,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '!',
                            style: ui(11, 900, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            app.toast.isEmpty ? _shown : app.toast,
                            style: ui(12.5, 800, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

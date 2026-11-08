import 'dart:async';

import 'package:flutter/material.dart';

enum AutoExitAction { delay, closeLive, exitApplication }

class AutoExitDialog extends StatefulWidget {
  const AutoExitDialog({super.key});

  @override
  State<AutoExitDialog> createState() => _AutoExitDialogState();
}

class _AutoExitDialogState extends State<AutoExitDialog> {
  int _remainingSeconds = 10;
  late final Timer _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds <= 1) {
        _finish(AutoExitAction.exitApplication);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _finish(AutoExitAction action) {
    if (!mounted || _finished) return;
    _finished = true;
    _timer.cancel();
    Navigator.of(context).pop(action);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('定时关闭'),
        content: Text('$_remainingSeconds 秒后关闭应用'),
        actions: [
          TextButton(
            onPressed: () => _finish(AutoExitAction.closeLive),
            child: const Text('关闭直播'),
          ),
          TextButton(
            onPressed: () => _finish(AutoExitAction.delay),
            child: const Text('延迟'),
          ),
        ],
      ),
    );
  }
}

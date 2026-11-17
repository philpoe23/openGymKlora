// The rest countdown between sets (the rest half of frontend/src/store/useUI.js: startRest,
// addRest, stopRest and the tick). It belongs to the app, not to the workout screen: leave the
// logger mid-rest and it is still counting when you come back.
//
// The count runs off `endsAt`, so a phone that slept or an app that was in the background picks
// up exactly where the clock is. With the app in the background the end is a local notification
// booked for `endsAt`; coming back takes it down.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'workout_device.dart';

/// The longest a rest runs (+15 s stops here): 15:00.
const int kRestMax = 15 * 60;

class RestTimer extends ChangeNotifier with WidgetsBindingObserver {
  RestTimer({DateTime Function()? clock, WorkoutDevice? device}) : _clock = clock ?? DateTime.now, _device = device;

  /// The app's rest timer.
  static RestTimer instance = RestTimer();

  final DateTime Function() _clock;
  final WorkoutDevice? _device;
  WorkoutDevice get device => _device ?? WorkoutDevice.instance;

  DateTime? _endsAt;
  int _total = 0;
  int _left = 0;
  bool _ready = false;
  bool _switch = false;
  int? forIdx;
  int? forSet;
  Timer? _tick;
  bool _observing = false;
  bool _background = false;
  bool _booked = false;

  /// A rest is on screen: counting, or over and showing "Next set".
  bool get active => _endsAt != null || _ready;

  /// Counting down.
  bool get running => _endsAt != null && !_ready;
  bool get ready => _ready;
  bool get switchSides => _switch;
  int get left => _left;
  int get total => _total;
  DateTime? get endsAt => _endsAt;

  int _secondsTo(DateTime end) => ((end.difference(_clock()).inMilliseconds) / 1000).round().clamp(0, 1 << 30);

  /// Starts a rest of [sec] seconds for set [set] of entry [idx]; a rest of 0 (timer Off) only
  /// stops the one running.
  void start(num sec, {int? idx, int? set, bool switchSides = false}) {
    _stopTicking();
    _cancelBooked();
    final s = sec.round();
    if (s <= 0) {
      _clear();
      notifyListeners();
      return;
    }
    _total = s;
    _left = s;
    _ready = false;
    _switch = switchSides;
    forIdx = idx;
    forSet = set;
    _endsAt = _clock().add(Duration(seconds: s));
    _run();
    notifyListeners();
  }

  /// ±[sec] seconds (`addRest`): past the end it is over; on a finished rest a plus starts it
  /// again; +15 never runs it past [kRestMax].
  void add(int sec) {
    if (!active) return;
    if (_ready) {
      if (sec > 0) {
        start(sec > kRestMax ? kRestMax : sec, idx: forIdx, set: forSet);
      } else {
        stop();
      }
      return;
    }
    var by = sec;
    if (by > 0) by = by.clamp(0, (kRestMax - _left).clamp(0, kRestMax));
    if (by == 0) return;
    final left = _left + by;
    if (left <= 0) {
      stop();
      return;
    }
    _left = left;
    _total = _total > left ? _total : left;
    _endsAt = _endsAt!.add(Duration(seconds: by));
    if (_booked) unawaited(device.scheduleRestEnd(_endsAt!));
    notifyListeners();
  }

  /// Skip / dismiss: the rest is gone, and so is its notification.
  void stop() {
    if (!active && !_booked) return;
    _stopTicking();
    _cancelBooked();
    _clear();
    notifyListeners();
  }

  /// A list change moved the exercise this rest belongs to (`shiftRestOwner`).
  void shiftOwner(int from, int by) {
    final f = forIdx;
    if (f != null && f >= from) forIdx = f + by;
  }

  /// Recomputes from the clock now (each tick, and on coming back to the app).
  @visibleForTesting
  void tick() {
    final end = _endsAt;
    if (end == null || _ready) return;
    final left = _secondsTo(end);
    if (left == _left && left > 0) return;
    _left = left;
    if (left <= 0) {
      _stopTicking();
      if (!_background) device.restOverBuzz();
      if (_switch) {
        _clear();
      } else {
        _ready = true;
        _endsAt = null;
      }
    }
    notifyListeners();
  }

  void _run() {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
  }

  void _clear() {
    _endsAt = null;
    _ready = false;
    _switch = false;
    _left = 0;
    _total = 0;
    forIdx = null;
    forSet = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  void _cancelBooked() {
    if (!_booked) return;
    _booked = false;
    unawaited(device.cancelRestEnd());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_background) return;
      _background = true;
      if (running && !_booked) {
        _booked = true;
        unawaited(device.scheduleRestEnd(_endsAt!));
      }
    } else if (state == AppLifecycleState.resumed) {
      // A rest that ran out while away already had its notification: no buzz on return.
      _cancelBooked();
      tick();
      _background = false;
    }
  }

  @override
  void dispose() {
    _stopTicking();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// The rest timer on its own: the countdown off its end time, ±15 s, Skip, the buzz at zero, and
// the background notification booked on leaving the app and taken down on coming back.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/ui/workout/rest_timer.dart';
import 'package:klora_app/ui/workout/workout_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late FakeWorkoutDevice device;
  late RestTimer timer;

  setUp(() {
    now = DateTime(2026, 11, 13, 10);
    device = FakeWorkoutDevice();
    timer = RestTimer(clock: () => now, device: device);
  });

  tearDown(() => timer.dispose());

  test('counts down from its end time and is over at zero, with a buzz', () {
    timer.start(90, idx: 0, set: 1);
    expect(timer.running, isTrue);
    expect(timer.left, 90);
    expect(timer.forIdx, 0);
    expect(timer.forSet, 1);
    now = now.add(const Duration(seconds: 30));
    timer.tick();
    expect(timer.left, 60);
    now = now.add(const Duration(seconds: 61));
    timer.tick();
    expect(timer.ready, isTrue);
    expect(timer.running, isFalse);
    expect(timer.active, isTrue);
    expect(device.calls, contains('buzz'));
    timer.stop();
    expect(timer.active, isFalse);
  });

  test('±15 s moves the end; taking off more than is left ends it; +15 stops at 15:00', () {
    timer.start(30);
    timer.add(15);
    expect(timer.left, 45);
    expect(timer.total, 45);
    timer.add(-15);
    expect(timer.left, 30);
    timer.add(-45);
    expect(timer.active, isFalse);

    timer.start(kRestMax - 5);
    timer.add(15);
    expect(timer.left, kRestMax);
  });

  test('a rest of 0 (timer off) starts nothing', () {
    timer.start(0);
    expect(timer.active, isFalse);
  });

  test('leaving the app books the end as a notification; coming back takes it down', () {
    timer.start(90);
    timer.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(device.booked, now.add(const Duration(seconds: 90)));
    // +15 while away moves the booking with it.
    timer.add(15);
    expect(device.booked, now.add(const Duration(seconds: 105)));
    timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(device.booked, isNull);
    expect(device.calls.where((c) => c == 'cancel'), hasLength(1));

    // Over while away: no buzz on return (the notification already said so), just "Next set".
    timer.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(timer.ready, isTrue);
    expect(device.calls, isNot(contains('buzz')));
  });

  test('Skip takes the booked notification down too', () {
    timer.start(60);
    timer.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(device.booked, isNotNull);
    timer.stop();
    expect(device.booked, isNull);
  });
}

// Port of frontend/src/lib/exercises.clip-ext.test.js. vi.stubEnv('VITE_CLIP_EXT') becomes
// configureExerciseMedia(clipExt: …).
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/exercises.dart';

void main() {
  group('gifSrc and VITE_CLIP_EXT', () {
    tearDown(() => configureExerciseMedia(clipExt: 'mp4'));
    const ex = {'id': '0025', 'img': '0025.webp', 'gif': '0025.mp4', 'fv': '9025'};

    test('names MP4 loops by default', () {
      expect(gifSrc(ex, 'male'), 'exercise-media/clip/0025.mp4');
      expect(gifSrc(ex, 'female'), 'exercise-media/clip/9025.mp4');
      expect(isVideoSrc(gifSrc(ex, 'male')), isTrue);
    });

    test('names animated WebP images in the Android release', () {
      configureExerciseMedia(clipExt: 'webp');
      expect(gifSrc(ex, 'male'), 'exercise-media/clip/0025.webp');
      expect(gifSrc(ex, 'female'), 'exercise-media/clip/9025.webp');
      expect(isVideoSrc(gifSrc(ex, 'male')), isFalse);
      expect(imgSrc(ex, 'male'), 'exercise-media/still/0025.webp');
      expect(gifSrc({...ex, 'gif': '0025.gif', 'fv': null}, 'male'), 'exercise-media/clip/0025.gif');
    });
  });
}

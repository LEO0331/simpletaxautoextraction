import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/utils/source_fingerprint.dart';

void main() {
  test('SHA-256 standard vectors and multi-block padding', () {
    expect(
      SourceFingerprint.sha256([]),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      SourceFingerprint.text('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      SourceFingerprint.text(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test('rejects invalid byte inputs', () {
    expect(() => SourceFingerprint.sha256([256]), throwsArgumentError);
  });
}

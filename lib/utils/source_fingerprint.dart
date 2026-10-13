import 'dart:convert';

/// SHA-256 of the actual source bytes. No source text is retained or logged.
/// Operations are unsigned 32-bit so Flutter web and native agree.
class SourceFingerprint {
  static String text(String value) => sha256(utf8.encode(value));

  static int _rotate(int value, int bits) =>
      ((value >>> bits) | (value << (32 - bits))) & 0xffffffff;

  static String sha256(List<int> bytes) {
    if (bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('Source must contain bytes.');
    }
    final data = [...bytes, 0x80];
    while (data.length % 64 != 56) {
      data.add(0);
    }
    final bitLength = BigInt.from(bytes.length) * BigInt.from(8);
    for (var i = 7; i >= 0; i--) {
      data.add(((bitLength >> (i * 8)) & BigInt.from(255)).toInt());
    }
    final hash = [
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19,
    ];
    const constants = [
      0x428a2f98,
      0x71374491,
      0xb5c0fbcf,
      0xe9b5dba5,
      0x3956c25b,
      0x59f111f1,
      0x923f82a4,
      0xab1c5ed5,
      0xd807aa98,
      0x12835b01,
      0x243185be,
      0x550c7dc3,
      0x72be5d74,
      0x80deb1fe,
      0x9bdc06a7,
      0xc19bf174,
      0xe49b69c1,
      0xefbe4786,
      0x0fc19dc6,
      0x240ca1cc,
      0x2de92c6f,
      0x4a7484aa,
      0x5cb0a9dc,
      0x76f988da,
      0x983e5152,
      0xa831c66d,
      0xb00327c8,
      0xbf597fc7,
      0xc6e00bf3,
      0xd5a79147,
      0x06ca6351,
      0x14292967,
      0x27b70a85,
      0x2e1b2138,
      0x4d2c6dfc,
      0x53380d13,
      0x650a7354,
      0x766a0abb,
      0x81c2c92e,
      0x92722c85,
      0xa2bfe8a1,
      0xa81a664b,
      0xc24b8b70,
      0xc76c51a3,
      0xd192e819,
      0xd6990624,
      0xf40e3585,
      0x106aa070,
      0x19a4c116,
      0x1e376c08,
      0x2748774c,
      0x34b0bcb5,
      0x391c0cb3,
      0x4ed8aa4a,
      0x5b9cca4f,
      0x682e6ff3,
      0x748f82ee,
      0x78a5636f,
      0x84c87814,
      0x8cc70208,
      0x90befffa,
      0xa4506ceb,
      0xbef9a3f7,
      0xc67178f2,
    ];
    for (var offset = 0; offset < data.length; offset += 64) {
      final words = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        final start = offset + i * 4;
        words[i] =
            (data[start] << 24) |
            (data[start + 1] << 16) |
            (data[start + 2] << 8) |
            data[start + 3];
      }
      for (var i = 16; i < 64; i++) {
        final x = words[i - 15];
        final y = words[i - 2];
        final s0 = _rotate(x, 7) ^ _rotate(x, 18) ^ (x >>> 3);
        final s1 = _rotate(y, 17) ^ _rotate(y, 19) ^ (y >>> 10);
        words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & 0xffffffff;
      }
      var a = hash[0], b = hash[1], c = hash[2], d = hash[3];
      var e = hash[4], f = hash[5], g = hash[6], h = hash[7];
      for (var i = 0; i < 64; i++) {
        final s1 = _rotate(e, 6) ^ _rotate(e, 11) ^ _rotate(e, 25);
        final choice = (e & f) ^ ((~e) & g);
        final t1 = (h + s1 + choice + constants[i] + words[i]) & 0xffffffff;
        final s0 = _rotate(a, 2) ^ _rotate(a, 13) ^ _rotate(a, 22);
        final majority = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + majority) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      final state = [a, b, c, d, e, f, g, h];
      for (var i = 0; i < 8; i++) {
        hash[i] = (hash[i] + state[i]) & 0xffffffff;
      }
    }
    return hash.map((value) => value.toRadixString(16).padLeft(8, '0')).join();
  }
}

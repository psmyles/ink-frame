// Same cases as central/tests/links_test.ts, so the page and the app agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/frame_link.dart';

const u1 = 'https://vrhsxzedzhvujnirsuhg.supabase.co';
const u2 = 'https://abcdefghijklmnopqrst.supabase.co';
const k1 = 'sb_publishable_AbCdEf0123456789_xyz';
const k2 = 'sb_publishable_ZyXwVu9876543210_abc';
const pages = 'https://psmyles.github.io/ink-frame';

void main() {
  test('https invite link', () {
    final l = FrameLink.parse('$pages/join#u=${Uri.encodeQueryComponent(u1)}&k=$k1&c=ABCDE-FGHJK')!;
    expect(l.frames, [const FrameAddress(u1, k1)]);
    expect(l.code, 'ABCDE-FGHJK');
    expect(l.isInvite, isTrue);
    expect(l.frames.single.ref, 'vrhsxzedzhvujnirsuhg');
  });

  test('app link and /join/ both work', () {
    expect(FrameLink.parse('inkframe://join?u=$u1&k=$k1&c=ABCDE-FGHJK')?.code, 'ABCDE-FGHJK');
    expect(FrameLink.parse('  $pages/join/#u=$u1&k=$k1\n')?.frames.length, 1);
  });

  test('another-device link with two frames', () {
    final l = FrameLink.parse('$pages/join#u=$u1&k=$k1&u=$u2/&k=$k2')!;
    expect(l.frames, [const FrameAddress(u1, k1), const FrameAddress(u2, k2)]);
    expect(l.isInvite, isFalse);
  });

  test('round trip through toHttps', () {
    const link = FrameLink([FrameAddress(u1, k1), FrameAddress(u2, k2)]);
    final back = FrameLink.parse(link.toHttps(pages))!;
    expect(back.frames, link.frames);
    expect(FrameLink.parse(const FrameLink([FrameAddress(u1, k1)], 'ABCDE-FGHJK').toHttps(pages))?.code, 'ABCDE-FGHJK');
  });

  test('legacy anon JWT keys', () {
    const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.sig_abc-DEF';
    expect(FrameLink.parse('$pages/join#u=$u1&k=$jwt')?.frames.single.key, jwt);
  });

  test('broken links are rejected', () {
    for (final bad in [
      '',
      'ABCDE-FGHJK', // a bare code
      '$pages/join',
      '$pages/join#u=$u1',
      '$pages/join#u=$u1&k=$k1&k=$k2',
      '$pages/join#u=https://evil.example.com&k=$k1',
      '$pages/join#u=http://vrhsxzedzhvujnirsuhg.supabase.co&k=$k1',
      '$pages/join#u=$u1&k=javascript:alert(1)',
      '$pages/join#u=$u1&k=$k1&c=<script>',
      '$pages/join#u=$u1&k=$k1&u=$u2&k=$k2&c=ABCDE-FGHJK',
      '$pages/join#u=$u1&k=$k1&c=ABCDE-FGHJK&c=OTHER-CODE1',
      'http://psmyles.github.io/ink-frame/join#u=$u1&k=$k1',
      '$pages/other#u=$u1&k=$k1',
      'inkframe://other?u=$u1&k=$k1',
    ]) {
      expect(FrameLink.parse(bad), isNull, reason: bad);
    }
  });
}

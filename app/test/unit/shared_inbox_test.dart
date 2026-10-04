import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/shared_inbox.dart';

void main() {
  late Directory inbox;

  setUp(() => inbox = Directory.systemTemp.createTempSync('inbox'));
  tearDown(() => inbox.deleteSync(recursive: true));

  void share(String folder, Map<String, List<int>> files) {
    final d = Directory('${inbox.path}/$folder')..createSync();
    files.forEach((name, bytes) => File('${d.path}/$name').writeAsBytesSync(bytes));
  }

  test('oldest share first, photos in the order shared, original names', () async {
    share('0001759600000000-bbbbbbbb', {'001-IMG_2.HEIC': [3], '000-IMG_1.jpg': [2]});
    share('0001759500000000-aaaaaaaa', {'000-first.png': [1], '.DS_Store': [0]});

    final photos = await SharedInbox.takeFrom(inbox);

    expect([for (final (name, _) in photos) name], ['first.png', 'IMG_1.jpg', 'IMG_2.HEIC']);
    expect([for (final (_, bytes) in photos) bytes.single], [1, 2, 3]);
    expect(inbox.listSync(), isEmpty, reason: 'taken photos are removed');
  });

  test('no inbox yet: nothing', () async {
    expect(await SharedInbox.takeFrom(Directory('${inbox.path}/missing')), isEmpty);
  });
}

// Signing out and back in during one run: the frame shows again without a restart,
// and photos, people and settings use the new session, not the one thrown away.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/providers.dart';

import '../widget/fake_frame_api.dart';
import '../widget/frame_screen_test.dart' show alice, kitchen, priya;

class FakeConnection extends FrameConnection {
  FakeConnection(super.address, super.store, this.summary);

  final FrameSummary summary;
  var _signedIn = false;

  @override
  bool get isSignedIn => _signedIn;
  @override
  Future<bool> restore() async => _signedIn;
  @override
  Future<void> signIn(Credential credential) async => _signedIn = true;
  @override
  Future<void> signOut() async => _signedIn = false;
  @override
  Future<bool> isGone() async => false;
  @override
  Future<FrameSummary> loadSummary() async =>
      _signedIn ? summary : throw const ApiException(ApiException.signedOut, 'Not signed in.');
}

void main() {
  test('sign out, sign back in: the frame shows again and everything uses the new session', () async {
    final store = MemoryStore();
    final summary = FakeFrameApi().view(alice, priya).summary!;
    final repo = FramesRepository(store, connect: (a, s) => FakeConnection(a, s, summary));
    final container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), framesRepositoryProvider.overrideWithValue(repo)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    const credential = PasswordCredential('alice@dev.test', 'secret1');
    Future<FrameView> view() => container.read(frameViewProvider(kitchen).future);

    await repo.signInAll([kitchen], credential);
    await container.read(framesProvider.future);
    // Home is open, so its card keeps listening to the frame throughout.
    container.listen(frameViewProvider(kitchen), (_, _) {});
    container.listen(frameApiProvider(kitchen), (_, _) {});
    expect((await view()).summary?.frame.name, 'Kitchen');

    await container.read(framesProvider.notifier).signOutAll();
    expect((await view()).error?.code, ApiException.signedOut);
    final apiWhileSignedOut = container.read(frameApiProvider(kitchen));

    await repo.signInAll([kitchen], credential);
    await container.read(framesProvider.notifier).signedIn([kitchen]);
    expect((await view()).summary?.frame.name, 'Kitchen');
    expect(container.read(connectionProvider(kitchen)).isSignedIn, isTrue);
    expect(identical(container.read(connectionProvider(kitchen)), repo.connection(kitchen)), isTrue);
    expect(identical(container.read(frameApiProvider(kitchen)), apiWhileSignedOut), isFalse);
  });
}

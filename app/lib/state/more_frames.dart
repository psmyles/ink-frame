import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/frame_connection.dart';
import '../data/frame_link.dart';
import 'providers.dart';

/// Frames on your account in the directory that aren't on this device yet: set up
/// or joined on another device since you signed in here (app-flow §1.4). Read at
/// start and on refresh; empty without a directory sign-in or a connection.
final moreFramesProvider = AsyncNotifierProvider<MoreFrames, List<FrameAddress>>(MoreFrames.new);

class MoreFrames extends AsyncNotifier<List<FrameAddress>> {
  /// Put away with "Not now", until the app starts again.
  final _hidden = <String>{};

  @override
  Future<List<FrameAddress>> build() async {
    final here = {for (final f in await ref.watch(framesProvider.future)) f.url};
    final all = await ref.read(frameDirectoryProvider).list() ?? const [];
    return [for (final f in all) if (!here.contains(f.url) && !_hidden.contains(f.url)) f];
  }

  /// Signs in to them with [credential] (Google or Apple, as on the other device)
  /// and puts them on this device. Frames you're no longer on are dropped from the
  /// directory instead.
  Future<void> add(Credential credential) async {
    final frames = state.value ?? const [];
    if (frames.isEmpty) return;
    ref.read(lastCredentialProvider.notifier).set(credential);
    final skipped = await ref.read(framesRepositoryProvider).signInAll(frames, credential);
    unawaited(ref.read(frameDirectoryProvider).remove(skipped));
    await ref.read(framesProvider.notifier).signedIn(frames);
  }

  void hide() {
    _hidden.addAll([for (final f in state.value ?? const <FrameAddress>[]) f.url]);
    state = const AsyncData([]);
  }
}

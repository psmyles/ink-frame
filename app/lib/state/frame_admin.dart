import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/frame_api.dart';
import '../data/frame_link.dart';
import '../data/models.dart';
import 'providers.dart';

/// Overridable for tests.
final frameApiProvider = Provider.family<FrameApi, FrameAddress>(
  (ref, a) => FrameApi(ref.watch(connectionProvider(a))),
);

/// Everyone on the frame (People).
final membersProvider = FutureProvider.family<List<Member>, FrameAddress>(
  (ref, a) => ref.watch(frameApiProvider(a)).members(),
);

/// Active invites (owner only).
final invitesProvider = FutureProvider.family<List<Invite>, FrameAddress>(
  (ref, a) => ref.watch(frameApiProvider(a)).invites(),
);

/// Storage use (Storage screen, and the "getting full" notice on the Frame screen).
final usageProvider = FutureProvider.family<Usage, FrameAddress>(
  (ref, a) => ref.watch(frameApiProvider(a)).usage(),
);

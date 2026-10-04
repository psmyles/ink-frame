// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ink Frame';

  @override
  String get tagline => 'Your family\'s photos on e-ink frames.';

  @override
  String get invited => 'I\'ve been invited';

  @override
  String get setUpFrame => 'Set up a frame';

  @override
  String get joinWithInvite => 'Join with an invite';

  @override
  String get continueAction => 'Continue';

  @override
  String get tryAgain => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get back => 'Back';

  @override
  String get joinTitle => 'Join a frame';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get pasteLinkLabel => 'Invite link';

  @override
  String get pasteLinkHint => 'https://…/join#…';

  @override
  String get paste => 'Paste';

  @override
  String get joinLinkHelp =>
      'Paste the link you were sent. A code on its own isn\'t enough, because the app also needs the frame\'s address.';

  @override
  String get signInLinkHelp =>
      'Paste the link from \"Use on another device\" on your other phone or computer, or any invite link.';

  @override
  String get invalidLink =>
      'That doesn\'t look like an Ink Frame link. Copy the whole link and try again.';

  @override
  String get signInExplain =>
      'Your account is only used to recognise you, and to find your frames when you sign in on a new device.';

  @override
  String get findingFrames => 'Looking for your frames…';

  @override
  String get noFramesOnAccount =>
      'There are no frames on this account yet. Set up your own frame, or join one with the invite you were sent. If you used a different account before, try that one.';

  @override
  String get differentAccount => 'Use a different account';

  @override
  String get findOffline =>
      'Can\'t look for your frames right now. Check your internet connection and try again.';

  @override
  String get findFailed =>
      'Couldn\'t look for your frames. Try again, or use a link or QR code.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get appleHint =>
      'Use Google if you also want to use Ink Frame on Android or a computer.';

  @override
  String get devSignIn => 'Developer sign-in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get noSignInMethods =>
      'Sign-in isn\'t set up in this build. Turn on developer mode in Account to sign in with email and password.';

  @override
  String get nameHeading => 'What should the others see?';

  @override
  String get nameLabel => 'Your name';

  @override
  String get join => 'Join';

  @override
  String get inviteInvalid =>
      'This invite has expired or was already used. Ask for a new one.';

  @override
  String get somethingWrong => 'Something went wrong. Try again.';

  @override
  String get offline =>
      'Can\'t reach the frame. Check your internet connection.';

  @override
  String get firstTip =>
      'Add photos with the + button. The frame checks for new photos once a day, or press its green button to check now.';

  @override
  String get gotIt => 'Got it';

  @override
  String get noFramesOnLink =>
      'You\'re not on any of the frames in that link any more.';

  @override
  String skippedFrames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You\'re no longer on $count frames from that link, so they were skipped.',
      one: 'You\'re no longer on one frame from that link, so it was skipped.',
    );
    return '$_temp0';
  }

  @override
  String get noFramesYet => 'No frames yet';

  @override
  String get loadingFrames => 'Loading your frames…';

  @override
  String get loading => 'Loading…';

  @override
  String get noFramesBody =>
      'Set up your own frame, or join one with the invite link you were sent.';

  @override
  String setUpBy(String name) {
    return 'Set up by $name';
  }

  @override
  String get frames => 'Frames';

  @override
  String get setUpOrJoin => 'Set up or join';

  @override
  String get chooseFrame => 'Choose a frame';

  @override
  String statusUpToDate(String ago) {
    return 'Up to date · last checked $ago';
  }

  @override
  String statusChangesWaiting(String time) {
    return 'Changes waiting · next check around $time';
  }

  @override
  String get statusChangesWaitingSoon => 'Changes waiting · next check soon';

  @override
  String get statusFirstCheck => 'Connected · waiting for its first check';

  @override
  String get statusNotConnected => 'Not connected yet';

  @override
  String statusNotCheckedIn(String when) {
    return 'Hasn\'t checked in since $when. Check the frame\'s Wi-Fi and battery.';
  }

  @override
  String batteryLow(int pct) {
    return 'Battery low ($pct %)';
  }

  @override
  String get checkHint =>
      'To show changes now, press the green button on the frame.';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String daysAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String asleepOwner(String frame) {
    return '$frame\'s photo storage is asleep because it wasn\'t used for a while. The frame keeps showing its photos.';
  }

  @override
  String asleepOther(String frame, String owner) {
    return '$frame is asleep because it wasn\'t used for a while. Ask $owner to open Ink Frame to wake it up. The frame keeps showing its photos.';
  }

  @override
  String get asleepShort => 'Asleep';

  @override
  String get asleepJoin =>
      'This frame is asleep because it wasn\'t used for a while. Ask the person who set it up to open Ink Frame to wake it up, then try again.';

  @override
  String get theOwner => 'the person who set it up';

  @override
  String get removedFromFrame => 'You\'re no longer on this frame.';

  @override
  String get removeFromDevice => 'Remove from this device';

  @override
  String frameGone(String frame) {
    return '$frame no longer exists: its photo storage was deleted.';
  }

  @override
  String get frameGoneShort => 'No longer exists';

  @override
  String get frameGoneJoin =>
      'This frame no longer exists: its photo storage was deleted.';

  @override
  String get signedOutOfFrame => 'You were signed out of this frame.';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get unknownFrame => 'A frame';

  @override
  String get noPhotosYet => 'No photos yet';

  @override
  String get setupExplain =>
      'Your frame\'s photos are kept in your own free Supabase account, and you\'ll be the frame\'s owner. A free account can run 2 frames. Nobody else, including us, can see the photos.';

  @override
  String get setupConnectTitle => 'Connect your Supabase account';

  @override
  String get connectSupabase => 'Connect Supabase';

  @override
  String get connectSupabaseHint =>
      'Opens Supabase in your browser. No account yet? You can make a free one there.';

  @override
  String get supabaseConnected => 'Connected';

  @override
  String get usePersonalToken => 'Use an access token instead';

  @override
  String get personalTokenTitle => 'Supabase access token';

  @override
  String get connectFailed => 'Couldn\'t connect to Supabase. Try again.';

  @override
  String get setupModelTitle => 'Which frame do you have?';

  @override
  String modelSize(int width, int height) {
    return '$width × $height';
  }

  @override
  String get setupNameTitle => 'Name it';

  @override
  String get frameNameHint => 'Kitchen, Grandma\'s…';

  @override
  String setUpNamed(String name) {
    return 'Set up $name';
  }

  @override
  String settingUp(String name) {
    return 'Setting up $name';
  }

  @override
  String get stageStorage => 'Getting its photo storage ready';

  @override
  String get stageStorageHint => 'Usually under a minute';

  @override
  String get stageSignIn => 'Turning on sign-in';

  @override
  String get stageOwner => 'Signing you in';

  @override
  String get ownerSignInHint =>
      'Sign in with the account you use Ink Frame with. You\'ll be the frame\'s owner.';

  @override
  String setupStopped(String name) {
    return 'Setting up $name stopped before it finished.';
  }

  @override
  String get continueSetup => 'Continue';

  @override
  String get cancelSetup => 'Cancel setup';

  @override
  String cancelSetupConfirm(String name) {
    return 'Cancel setting up $name? What was made in your Supabase account is deleted.';
  }

  @override
  String get setupLimit =>
      'Your free Supabase account already runs 2 projects. Someone else in the family can set up this frame with their own free account, or you can delete a project you don\'t need.';

  @override
  String get openSupabase => 'Open Supabase';

  @override
  String get setupReconnect => 'Your Supabase account needs connecting again.';

  @override
  String get setupOffline =>
      'Can\'t reach Supabase. Check your internet connection.';

  @override
  String get setupSignInFailed =>
      'Couldn\'t sign you in to the new frame. Try again.';

  @override
  String get sectionOwner => 'Owner tools';

  @override
  String get supabaseAccount => 'Supabase account';

  @override
  String get supabaseNotHere =>
      'Not connected on this device. Connect it to update, wake up or delete the frame.';

  @override
  String get connect => 'Connect';

  @override
  String updateReady(String frame) {
    return 'An update for $frame is ready';
  }

  @override
  String get updateHint => 'Takes a few seconds';

  @override
  String get update => 'Update';

  @override
  String updatingFrame(String frame) {
    return 'Updating $frame…';
  }

  @override
  String updated(String frame) {
    return '$frame is up to date';
  }

  @override
  String updateFailed(String frame) {
    return 'Couldn\'t update $frame. Try again.';
  }

  @override
  String get deleteFrame => 'Delete this frame';

  @override
  String deleteFrameConfirm(String frame) {
    return 'Delete $frame? All its photos and everyone\'s access go, and its storage in your Supabase account is deleted. The frame keeps showing its last photos until it\'s reset.';
  }

  @override
  String typeToConfirm(String word) {
    return 'Type $word to confirm';
  }

  @override
  String deletingFrame(String frame) {
    return 'Deleting $frame…';
  }

  @override
  String deleteFrameFailed(String frame) {
    return 'Couldn\'t delete $frame. Try again.';
  }

  @override
  String wrongSupabaseAccount(String frame) {
    return 'This Supabase account can\'t reach $frame. Connect the account it was set up with.';
  }

  @override
  String get wakeUp => 'Wake up';

  @override
  String wakingUp(String frame) {
    return 'Waking up $frame… This takes about 3 minutes.';
  }

  @override
  String wakeUpFailed(String frame) {
    return 'Couldn\'t wake up $frame. Try again.';
  }

  @override
  String get changeModel => 'Change';

  @override
  String changeModelConfirm(int count, String frame, String model, String old) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Switch $frame to the $model? All $count photos will be removed, because they were made for the $old screen.',
      one:
          'Switch $frame to the $model? Its photo will be removed, because it was made for the $old screen.',
      zero: 'Switch $frame to the $model?',
    );
    return '$_temp0';
  }

  @override
  String get switchModel => 'Switch';

  @override
  String frameReady(String name) {
    return '$name is ready';
  }

  @override
  String get frameReadyBody =>
      'Connect the frame now, or add photos first: it gets them once it\'s connected.';

  @override
  String get account => 'Account';

  @override
  String get onThisDevice => 'Frames on this device';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirm =>
      'Sign out of every frame on this device? You can sign in again with a link from another device or an invite.';

  @override
  String version(String v) {
    return 'Version $v';
  }

  @override
  String get developerMode => 'Developer mode';

  @override
  String get developerModeOn => 'Developer mode is on';

  @override
  String get developerModeBody =>
      'Email and password sign-in on dev projects, and extra details.';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get noPhotosBody =>
      'Add some and the frame will show them after it next checks.';

  @override
  String get prepareTitle => 'Prepare';

  @override
  String uploadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Upload $count',
      one: 'Upload',
    );
    return '$_temp0';
  }

  @override
  String get original => 'Original';

  @override
  String get prepareHint =>
      'How they\'ll look on the frame. Tap one to adjust.';

  @override
  String get edit => 'Edit';

  @override
  String get addMore => 'Add more photos';

  @override
  String photoOfCount(int index, int count) {
    return 'Photo $index of $count';
  }

  @override
  String get previousPhoto => 'Previous photo';

  @override
  String get nextPhoto => 'Next photo';

  @override
  String get moveHintTouch => 'Drag the photo to move it. Pinch to zoom.';

  @override
  String get moveHintMouse => 'Drag the photo to move it. Scroll to zoom.';

  @override
  String get viewOriginal => 'View original';

  @override
  String get viewOriginalHint => 'Hold to see the original photo';

  @override
  String get startOver => 'Start over';

  @override
  String get leaveTitle => 'Leave without uploading?';

  @override
  String get leaveBody =>
      'The photos you picked and your changes won\'t be kept.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get leave => 'Leave';

  @override
  String get rotate => 'Rotate';

  @override
  String get removePhoto => 'Remove this photo';

  @override
  String get automatic => 'Automatic';

  @override
  String get automaticHint =>
      'Makes the photo look as close to the original as the frame\'s colours allow.';

  @override
  String get brightness => 'Brightness';

  @override
  String get contrast => 'Contrast';

  @override
  String get colour => 'Colour';

  @override
  String get moreOptions => 'More options';

  @override
  String get dotPattern => 'Dot pattern';

  @override
  String get patternFine => 'Fine';

  @override
  String get patternSmooth => 'Smooth';

  @override
  String get patternCrisp => 'Crisp';

  @override
  String get patternGrid => 'Grid';

  @override
  String get patternGrainy => 'Grainy';

  @override
  String get reset => 'Reset';

  @override
  String get useForAll => 'Use for all';

  @override
  String get appliedToAll => 'Applied to all photos';

  @override
  String get cantOpenPhoto => 'Couldn\'t open this photo.';

  @override
  String cantOpenPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t open $count photos.',
      one: 'Couldn\'t open 1 photo.',
    );
    return '$_temp0';
  }

  @override
  String get openingPhotos => 'Opening photos…';

  @override
  String dropHere(String frame) {
    return 'Drop photos to add them to $frame';
  }

  @override
  String get preparing => 'Preparing…';

  @override
  String get updating => 'Updating…';

  @override
  String get uploading => 'Uploading…';

  @override
  String get waiting => 'Waiting…';

  @override
  String get retry => 'Retry';

  @override
  String get uploadFailed => 'Couldn\'t upload this photo.';

  @override
  String get retryAll => 'Retry all';

  @override
  String uploadsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos couldn\'t be added.',
      one: '1 photo couldn\'t be added.',
    );
    return '$_temp0';
  }

  @override
  String alreadyOnFrame(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos were already on the frame.',
      one: '1 photo was already on the frame.',
    );
    return '$_temp0';
  }

  @override
  String storageFull(String frame) {
    return '$frame\'s storage is full. Delete some photos to add more.';
  }

  @override
  String addedBy(String name, String when) {
    return 'Added by $name · $when';
  }

  @override
  String get someoneWhoLeft => 'someone who left';

  @override
  String get you => 'you';

  @override
  String selected(int count) {
    return '$count selected';
  }

  @override
  String get delete => 'Delete';

  @override
  String deleteConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count photos from the frame?',
      one: 'Delete this photo from the frame?',
    );
    return '$_temp0';
  }

  @override
  String get cantDeleteOthers =>
      'You can only delete your own photos. The frame\'s owner can delete any.';

  @override
  String get noReEdit =>
      'To change the crop or look, delete the photo and add it again.';

  @override
  String get reorder => 'Change order';

  @override
  String get reorderHint =>
      'Drag photos to change the order the frame shows them in.';

  @override
  String get done => 'Done';

  @override
  String photoOf(int n, int total) {
    return 'Photo $n of $total';
  }

  @override
  String photoLabel(String name, String date) {
    return 'Photo added by $name on $date';
  }

  @override
  String get couldntLoad => 'Couldn\'t load this photo.';

  @override
  String get settings => 'Settings';

  @override
  String get people => 'People';

  @override
  String get storage => 'Storage';

  @override
  String get frameName => 'Name';

  @override
  String get renameTitle => 'Rename the frame';

  @override
  String get save => 'Save';

  @override
  String get sectionPhotos => 'Photos';

  @override
  String get sectionChecking => 'Checking for new photos';

  @override
  String get sectionBattery => 'Battery';

  @override
  String get sectionHardware => 'The frame';

  @override
  String get changePhotoEvery => 'Change photo every';

  @override
  String get order => 'Order';

  @override
  String get orderShuffle => 'Shuffle';

  @override
  String get orderInOrder => 'In order';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get quietHoursHint =>
      'The frame won\'t change photos during these hours.';

  @override
  String get quietFrom => 'From';

  @override
  String get quietTo => 'To';

  @override
  String get timeZone => 'Time zone';

  @override
  String get searchTimeZones => 'Search for a city';

  @override
  String get checkForNewPhotos => 'Check for new photos';

  @override
  String get checkMoreOftenHint => 'More often uses more battery.';

  @override
  String get lowBatteryWarning => 'Low battery warning';

  @override
  String get lowBatteryHint =>
      'Shows a warning when the battery drops below this.';

  @override
  String get off => 'Off';

  @override
  String percent(int value) {
    return '$value %';
  }

  @override
  String get frameModel => 'Model';

  @override
  String hardwareConnected(String version) {
    return 'Connected · software $version';
  }

  @override
  String get hardwareConnectedNoVersion => 'Connected';

  @override
  String get hardwareNotConnected => 'Not connected yet';

  @override
  String batteryNow(int value) {
    return 'Battery now: $value %';
  }

  @override
  String onlyOwnerChanges(String name) {
    return 'Only $name can change these settings.';
  }

  @override
  String get saved => 'Saved';

  @override
  String get savedNextCheck => 'Saved · the frame gets it at its next check';

  @override
  String get couldntSave => 'Couldn\'t save. Try again.';

  @override
  String hoursCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get inviteSomeone => 'Invite someone';

  @override
  String get inviteTitle => 'Invite someone to add photos';

  @override
  String get inviteExplain =>
      'They scan this with their phone\'s camera, or open the link.';

  @override
  String get shareLink => 'Share link';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyCode => 'Copy code';

  @override
  String get copied => 'Copied';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get inviteOptions => 'Options';

  @override
  String get worksFor => 'Works for';

  @override
  String get onePerson => '1 person';

  @override
  String get upToTen => 'Up to 10 people';

  @override
  String get expiresIn => 'Expires in';

  @override
  String inviteShareText(String frame, String link) {
    return 'Join $frame on Ink Frame to add photos: $link';
  }

  @override
  String get makingInvite => 'Making an invite…';

  @override
  String get activeInvites => 'Invites';

  @override
  String inviteForOne(String date) {
    return 'For 1 person · expires $date';
  }

  @override
  String inviteForMany(int used, int max, String date) {
    return '$used of $max joined · expires $date';
  }

  @override
  String get revoke => 'Revoke';

  @override
  String get justYou => 'Just you so far';

  @override
  String get ownerBadge => 'Owner';

  @override
  String get youBadge => 'You';

  @override
  String get removePerson => 'Remove';

  @override
  String removePersonConfirm(String name, String frame) {
    return 'Remove $name from $frame? Their photos stay; you can delete them.';
  }

  @override
  String get leaveFrame => 'Leave this frame';

  @override
  String leaveFrameConfirm(String frame) {
    return 'Leave $frame? You\'ll stop seeing its photos. Photos you added stay.';
  }

  @override
  String storageUsed(String used, String limit) {
    return '$used of $limit';
  }

  @override
  String get freePlan => 'Free Supabase plan';

  @override
  String photoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get storageNote => 'The frame\'s own downloads aren\'t counted here.';

  @override
  String get storageByPerson => 'By person';

  @override
  String storageGettingFull(String frame, int value) {
    return '$frame\'s storage is getting full ($value %).';
  }

  @override
  String get seeStorage => 'See storage';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHint => 'What the others see, on every frame you\'re on.';

  @override
  String get nameUpdated => 'Name updated';

  @override
  String nameUpdateFailed(String frames) {
    return 'Couldn\'t update your name on $frames.';
  }

  @override
  String get anotherDevice => 'Use on another device';

  @override
  String get anotherDeviceExplain =>
      'On your other phone or computer, sign in with the same account: your frames come back by themselves. If they don\'t, choose “I\'ve been invited” there and scan this.';

  @override
  String get deleteAccount => 'Delete my account';

  @override
  String get deleteAccountBody =>
      'You\'ll leave these frames and your account on them is deleted:';

  @override
  String get deletePhotosToo => 'Also delete my photos';

  @override
  String get deleteOwnedBody =>
      'These frames you set up are deleted, with all their photos and everyone\'s access, and their storage in your Supabase account:';

  @override
  String get typeDelete => 'Type DELETE to confirm';

  @override
  String get deleteWord => 'DELETE';

  @override
  String get deleteAccountButton => 'Delete account';

  @override
  String deleteFailed(String frames) {
    return 'Couldn\'t delete your account on $frames. Try again.';
  }

  @override
  String get scanQr => 'Scan QR code';

  @override
  String get scanHint => 'Point the camera at the invite\'s QR code.';

  @override
  String get notAnInvite => 'That QR code isn\'t an Ink Frame link.';

  @override
  String get connectFrame => 'Connect the frame';

  @override
  String get connectLater => 'Later — add photos first';

  @override
  String get connectFrameTitle => 'Connect the frame';

  @override
  String get connectReadyTitle => 'Get the frame ready';

  @override
  String get connectReadyBody =>
      'Hold the green button on the frame for 3 seconds, until it shows a 6-digit code. A new frame shows the code when it\'s switched on.';

  @override
  String connectReplaces(String name) {
    return 'The frame connected to $name now stops showing photos once this one is connected. The photos stay.';
  }

  @override
  String get findFrame => 'Find the frame';

  @override
  String get openSettings => 'Open settings';

  @override
  String get connectWithCode => 'Connect with a code (developer)';

  @override
  String get lookingForFrame => 'Looking for the frame…';

  @override
  String get lookingHint =>
      'Keep it close, with the code showing on its screen.';

  @override
  String get whichFrame => 'Which frame?';

  @override
  String get whichFrameHint =>
      'Pick the one whose 4 characters match the frame\'s screen.';

  @override
  String get isThisYourFrame => 'Is this your frame?';

  @override
  String get matchFrameHint =>
      'Check that the frame\'s screen shows the same 4 characters.';

  @override
  String get yesConnect => 'Yes, connect';

  @override
  String get notThisOne => 'Not this one? Look again';

  @override
  String pairingNamed(String name) {
    return 'Connecting to $name…';
  }

  @override
  String connectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String get pairingTitle => 'Connecting to the frame…';

  @override
  String get pairingHint =>
      'When asked, type the 6-digit code shown on the frame.';

  @override
  String get startAgain => 'Start again';

  @override
  String modelMismatch(String device, String frame, String model) {
    return 'This frame is a $device, but $frame is set up for a $model.';
  }

  @override
  String get wifiTitle => 'Which Wi-Fi should the frame use?';

  @override
  String get wifiHint => 'The frame needs a 2.4 GHz network.';

  @override
  String get otherNetwork => 'Other network…';

  @override
  String get wifiScanning => 'Looking for networks…';

  @override
  String get scanAgain => 'Look again';

  @override
  String get networkName => 'Network name';

  @override
  String get wifiPassword => 'Wi-Fi password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get connectAction => 'Connect';

  @override
  String connectingNamed(String name) {
    return 'Connecting $name';
  }

  @override
  String stageJoinWifi(String ssid) {
    return 'Joining $ssid';
  }

  @override
  String stageLinking(String name) {
    return 'Linking to $name';
  }

  @override
  String get stageGettingPhotos => 'Getting photos';

  @override
  String frameConnected(String name) {
    return '$name is connected';
  }

  @override
  String get frameConnectedBody =>
      'It shows a photo in a moment. Photos you add appear at its next check, or press its green button to check now.';

  @override
  String get bluetoothOff =>
      'Turn on Bluetooth on this device, then try again.';

  @override
  String get bluetoothDenied =>
      'Ink Frame needs permission to use Bluetooth to find the frame. Allow it in Settings, then try again.';

  @override
  String get noBluetooth =>
      'This device can\'t use Bluetooth. Connect the frame from your phone instead.';

  @override
  String get noFrameFound => 'Couldn\'t find the frame.';

  @override
  String get noFrameTipCode => 'Check that it shows a 6-digit code.';

  @override
  String get noFrameTipCloser => 'Move closer to the frame.';

  @override
  String get noFrameTipButton =>
      'No code? Hold its green button for 3 seconds.';

  @override
  String get wrongCode =>
      'The code didn\'t match. Check the frame\'s screen and try again.';

  @override
  String get pairingCancelled => 'Connecting was cancelled.';

  @override
  String get linkedElsewhere =>
      'This frame is still linked to another Ink Frame. Hold its green button for 10 seconds to reset it, then start again.';

  @override
  String wifiWrongPassword(String ssid) {
    return 'Couldn\'t join $ssid: the password didn\'t work.';
  }

  @override
  String wifiNotFound(String ssid) {
    return 'The frame couldn\'t find $ssid. It needs a 2.4 GHz network, close enough to the router.';
  }

  @override
  String wifiFailed(String ssid) {
    return 'Couldn\'t join $ssid. Check the password, that it\'s a 2.4 GHz network, and that the frame is close enough to the router.';
  }

  @override
  String frameNoInternet(String ssid) {
    return 'The frame joined $ssid but couldn\'t reach the internet. Try another network, or check the router.';
  }

  @override
  String get phoneOffline =>
      'This device is offline. Connect it to the internet and try again.';

  @override
  String get connectionLost => 'Lost the connection to the frame.';

  @override
  String get devCodeExplain =>
      'Run this in tools/frame_sim. The frame shows as connected once it has claimed its place.';

  @override
  String codeExpires(String time) {
    return 'The code works until $time, once.';
  }

  @override
  String get copy => 'Copy';

  @override
  String get waitingForFrame => 'Waiting for the frame…';

  @override
  String get newCode => 'New code';

  @override
  String get connectNewHardware => 'Connect new hardware';

  @override
  String get disconnectFrame => 'Disconnect';

  @override
  String disconnectConfirm(String name) {
    return 'Disconnect the frame? It clears its photos and settings at its next check. The photos stay in $name, ready for new hardware.';
  }

  @override
  String get disconnected =>
      'Disconnected. The frame clears itself at its next check.';

  @override
  String moreFrames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more frames are on your account',
      one: '1 more frame is on your account',
    );
    return '$_temp0';
  }

  @override
  String moreFramesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'They were added on another device. Sign in again to see them here too.',
      one: 'It was added on another device. Sign in again to see it here too.',
    );
    return '$_temp0';
  }

  @override
  String get addToDevice => 'Add to this device';

  @override
  String get notNow => 'Not now';

  @override
  String get moreFramesElsewhere =>
      'Your account uses Sign in with Apple, which this device doesn\'t have. Use Account → Use on another device on your iPhone or Mac instead.';

  @override
  String get moreFramesFailed =>
      'Couldn\'t add them. Check your internet connection and try again.';

  @override
  String batteryLowTitle(String name) {
    return '$name\'s battery is low';
  }

  @override
  String batteryLowBody(int pct) {
    return '$pct % left. Charge it soon so it keeps showing new photos.';
  }

  @override
  String get batteryChannel => 'Low battery';

  @override
  String get notifyLowBattery => 'Notify me when it\'s low';

  @override
  String get notifyLowBatteryHint => 'On this phone.';

  @override
  String get notifyBlocked =>
      'Notifications are off for Ink Frame on this phone. Allow them in the phone\'s settings.';

  @override
  String get notifyWarningOff => 'Turn on the low battery warning first.';

  @override
  String get notifyNeedsUpdateOwner =>
      'Needs the frame update in Owner tools first.';

  @override
  String notifyNeedsUpdate(String owner) {
    return 'Needs $owner to update the frame first.';
  }

  @override
  String get connectedNotifyNote =>
      'This phone will tell you when its battery is low.';

  @override
  String get checkBatteriesNow => 'Check batteries now';

  @override
  String get checkBatteriesNowBody =>
      'Runs the background low-battery check once.';

  @override
  String get checkedBatteries =>
      'Checked. Frames with a low battery get a notification (once).';

  @override
  String get stepDone => 'done';

  @override
  String get stepRunning => 'in progress';

  @override
  String get stepFailed => 'didn\'t work';

  @override
  String get stepWaiting => 'not started yet';
}

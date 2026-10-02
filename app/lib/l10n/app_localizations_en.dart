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
  String get alreadyUse => 'Already use Ink Frame? Sign in';

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
      'Your account is only used to recognise you on this frame.';

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
  String get signedOutOfFrame => 'You were signed out of this frame.';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get unknownFrame => 'A frame';

  @override
  String get noPhotosYet => 'No photos yet';

  @override
  String get setUpComing =>
      'Setting up a frame arrives in a later build. For now, join a frame with an invite link.';

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
}

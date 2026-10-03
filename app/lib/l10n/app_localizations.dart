import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Ink Frame'**
  String get appTitle;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Your family\'s photos on e-ink frames.'**
  String get tagline;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'I\'ve been invited'**
  String get invited;

  /// No description provided for @setUpFrame.
  ///
  /// In en, this message translates to:
  /// **'Set up a frame'**
  String get setUpFrame;

  /// No description provided for @alreadyUse.
  ///
  /// In en, this message translates to:
  /// **'Already use Ink Frame? Sign in'**
  String get alreadyUse;

  /// No description provided for @joinWithInvite.
  ///
  /// In en, this message translates to:
  /// **'Join with an invite'**
  String get joinWithInvite;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @joinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a frame'**
  String get joinTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @pasteLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get pasteLinkLabel;

  /// No description provided for @pasteLinkHint.
  ///
  /// In en, this message translates to:
  /// **'https://…/join#…'**
  String get pasteLinkHint;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @joinLinkHelp.
  ///
  /// In en, this message translates to:
  /// **'Paste the link you were sent. A code on its own isn\'t enough, because the app also needs the frame\'s address.'**
  String get joinLinkHelp;

  /// No description provided for @signInLinkHelp.
  ///
  /// In en, this message translates to:
  /// **'Paste the link from \"Use on another device\" on your other phone or computer, or any invite link.'**
  String get signInLinkHelp;

  /// No description provided for @invalidLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like an Ink Frame link. Copy the whole link and try again.'**
  String get invalidLink;

  /// No description provided for @signInExplain.
  ///
  /// In en, this message translates to:
  /// **'Your account is only used to recognise you on this frame.'**
  String get signInExplain;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @appleHint.
  ///
  /// In en, this message translates to:
  /// **'Use Google if you also want to use Ink Frame on Android or a computer.'**
  String get appleHint;

  /// No description provided for @devSignIn.
  ///
  /// In en, this message translates to:
  /// **'Developer sign-in'**
  String get devSignIn;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @noSignInMethods.
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t set up in this build. Turn on developer mode in Account to sign in with email and password.'**
  String get noSignInMethods;

  /// No description provided for @nameHeading.
  ///
  /// In en, this message translates to:
  /// **'What should the others see?'**
  String get nameHeading;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get nameLabel;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @inviteInvalid.
  ///
  /// In en, this message translates to:
  /// **'This invite has expired or was already used. Ask for a new one.'**
  String get inviteInvalid;

  /// No description provided for @somethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWrong;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the frame. Check your internet connection.'**
  String get offline;

  /// No description provided for @firstTip.
  ///
  /// In en, this message translates to:
  /// **'Add photos with the + button. The frame checks for new photos once a day, or press its green button to check now.'**
  String get firstTip;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @noFramesOnLink.
  ///
  /// In en, this message translates to:
  /// **'You\'re not on any of the frames in that link any more.'**
  String get noFramesOnLink;

  /// No description provided for @skippedFrames.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You\'re no longer on one frame from that link, so it was skipped.} other{You\'re no longer on {count} frames from that link, so they were skipped.}}'**
  String skippedFrames(int count);

  /// No description provided for @noFramesYet.
  ///
  /// In en, this message translates to:
  /// **'No frames yet'**
  String get noFramesYet;

  /// No description provided for @noFramesBody.
  ///
  /// In en, this message translates to:
  /// **'Set up your own frame, or join one with the invite link you were sent.'**
  String get noFramesBody;

  /// No description provided for @setUpBy.
  ///
  /// In en, this message translates to:
  /// **'Set up by {name}'**
  String setUpBy(String name);

  /// No description provided for @frames.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get frames;

  /// No description provided for @setUpOrJoin.
  ///
  /// In en, this message translates to:
  /// **'Set up or join'**
  String get setUpOrJoin;

  /// No description provided for @chooseFrame.
  ///
  /// In en, this message translates to:
  /// **'Choose a frame'**
  String get chooseFrame;

  /// No description provided for @statusUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date · last checked {ago}'**
  String statusUpToDate(String ago);

  /// No description provided for @statusChangesWaiting.
  ///
  /// In en, this message translates to:
  /// **'Changes waiting · next check around {time}'**
  String statusChangesWaiting(String time);

  /// No description provided for @statusChangesWaitingSoon.
  ///
  /// In en, this message translates to:
  /// **'Changes waiting · next check soon'**
  String get statusChangesWaitingSoon;

  /// No description provided for @statusFirstCheck.
  ///
  /// In en, this message translates to:
  /// **'Connected · waiting for its first check'**
  String get statusFirstCheck;

  /// No description provided for @statusNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected yet'**
  String get statusNotConnected;

  /// No description provided for @statusNotCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Hasn\'t checked in since {when}. Check the frame\'s Wi-Fi and battery.'**
  String statusNotCheckedIn(String when);

  /// No description provided for @batteryLow.
  ///
  /// In en, this message translates to:
  /// **'Battery low ({pct} %)'**
  String batteryLow(int pct);

  /// No description provided for @checkHint.
  ///
  /// In en, this message translates to:
  /// **'To show changes now, press the green button on the frame.'**
  String get checkHint;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 day ago} other{{n} days ago}}'**
  String daysAgo(int n);

  /// No description provided for @asleepOwner.
  ///
  /// In en, this message translates to:
  /// **'{frame}\'s photo storage is asleep because it wasn\'t used for a while. The frame keeps showing its photos.'**
  String asleepOwner(String frame);

  /// No description provided for @asleepOther.
  ///
  /// In en, this message translates to:
  /// **'{frame} is asleep because it wasn\'t used for a while. Ask {owner} to open Ink Frame to wake it up. The frame keeps showing its photos.'**
  String asleepOther(String frame, String owner);

  /// No description provided for @asleepShort.
  ///
  /// In en, this message translates to:
  /// **'Asleep'**
  String get asleepShort;

  /// No description provided for @asleepJoin.
  ///
  /// In en, this message translates to:
  /// **'This frame is asleep because it wasn\'t used for a while. Ask the person who set it up to open Ink Frame to wake it up, then try again.'**
  String get asleepJoin;

  /// No description provided for @theOwner.
  ///
  /// In en, this message translates to:
  /// **'the person who set it up'**
  String get theOwner;

  /// No description provided for @removedFromFrame.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer on this frame.'**
  String get removedFromFrame;

  /// No description provided for @removeFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove from this device'**
  String get removeFromDevice;

  /// No description provided for @signedOutOfFrame.
  ///
  /// In en, this message translates to:
  /// **'You were signed out of this frame.'**
  String get signedOutOfFrame;

  /// No description provided for @signInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgain;

  /// No description provided for @unknownFrame.
  ///
  /// In en, this message translates to:
  /// **'A frame'**
  String get unknownFrame;

  /// No description provided for @noPhotosYet.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get noPhotosYet;

  /// No description provided for @setUpComing.
  ///
  /// In en, this message translates to:
  /// **'Setting up a frame arrives in a later build. For now, join a frame with an invite link.'**
  String get setUpComing;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @onThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Frames on this device'**
  String get onThisDevice;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out of every frame on this device? You can sign in again with a link from another device or an invite.'**
  String get signOutConfirm;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {v}'**
  String version(String v);

  /// No description provided for @developerMode.
  ///
  /// In en, this message translates to:
  /// **'Developer mode'**
  String get developerMode;

  /// No description provided for @developerModeOn.
  ///
  /// In en, this message translates to:
  /// **'Developer mode is on'**
  String get developerModeOn;

  /// No description provided for @developerModeBody.
  ///
  /// In en, this message translates to:
  /// **'Email and password sign-in on dev projects, and extra details.'**
  String get developerModeBody;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get addPhotos;

  /// No description provided for @noPhotosBody.
  ///
  /// In en, this message translates to:
  /// **'Add some and the frame will show them after it next checks.'**
  String get noPhotosBody;

  /// No description provided for @prepareTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare'**
  String get prepareTitle;

  /// No description provided for @uploadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Upload} other{Upload {count}}}'**
  String uploadCount(int count);

  /// No description provided for @original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get original;

  /// No description provided for @prepareHint.
  ///
  /// In en, this message translates to:
  /// **'How they\'ll look on the frame. Tap one to adjust.'**
  String get prepareHint;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @addMore.
  ///
  /// In en, this message translates to:
  /// **'Add more photos'**
  String get addMore;

  /// No description provided for @photoOfCount.
  ///
  /// In en, this message translates to:
  /// **'Photo {index} of {count}'**
  String photoOfCount(int index, int count);

  /// No description provided for @previousPhoto.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get previousPhoto;

  /// No description provided for @nextPhoto.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get nextPhoto;

  /// No description provided for @moveHintTouch.
  ///
  /// In en, this message translates to:
  /// **'Drag the photo to move it. Pinch to zoom.'**
  String get moveHintTouch;

  /// No description provided for @moveHintMouse.
  ///
  /// In en, this message translates to:
  /// **'Drag the photo to move it. Scroll to zoom.'**
  String get moveHintMouse;

  /// No description provided for @viewOriginal.
  ///
  /// In en, this message translates to:
  /// **'View original'**
  String get viewOriginal;

  /// No description provided for @viewOriginalHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to see the original photo'**
  String get viewOriginalHint;

  /// No description provided for @startOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get startOver;

  /// No description provided for @leaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave without uploading?'**
  String get leaveTitle;

  /// No description provided for @leaveBody.
  ///
  /// In en, this message translates to:
  /// **'The photos you picked and your changes won\'t be kept.'**
  String get leaveBody;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @rotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get rotate;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove this photo'**
  String get removePhoto;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @automaticHint.
  ///
  /// In en, this message translates to:
  /// **'Makes the photo look as close to the original as the frame\'s colours allow.'**
  String get automaticHint;

  /// No description provided for @brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// No description provided for @contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// No description provided for @colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colour;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @dotPattern.
  ///
  /// In en, this message translates to:
  /// **'Dot pattern'**
  String get dotPattern;

  /// No description provided for @patternFine.
  ///
  /// In en, this message translates to:
  /// **'Fine'**
  String get patternFine;

  /// No description provided for @patternSmooth.
  ///
  /// In en, this message translates to:
  /// **'Smooth'**
  String get patternSmooth;

  /// No description provided for @patternCrisp.
  ///
  /// In en, this message translates to:
  /// **'Crisp'**
  String get patternCrisp;

  /// No description provided for @patternGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get patternGrid;

  /// No description provided for @patternGrainy.
  ///
  /// In en, this message translates to:
  /// **'Grainy'**
  String get patternGrainy;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @useForAll.
  ///
  /// In en, this message translates to:
  /// **'Use for all'**
  String get useForAll;

  /// No description provided for @appliedToAll.
  ///
  /// In en, this message translates to:
  /// **'Applied to all photos'**
  String get appliedToAll;

  /// No description provided for @cantOpenPhoto.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this photo.'**
  String get cantOpenPhoto;

  /// No description provided for @cantOpenPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t open 1 photo.} other{Couldn\'t open {count} photos.}}'**
  String cantOpenPhotos(int count);

  /// No description provided for @openingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Opening photos…'**
  String get openingPhotos;

  /// No description provided for @dropHere.
  ///
  /// In en, this message translates to:
  /// **'Drop photos to add them to {frame}'**
  String dropHere(String frame);

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get updating;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get waiting;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload this photo.'**
  String get uploadFailed;

  /// No description provided for @retryAll.
  ///
  /// In en, this message translates to:
  /// **'Retry all'**
  String get retryAll;

  /// No description provided for @uploadsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo couldn\'t be added.} other{{count} photos couldn\'t be added.}}'**
  String uploadsFailed(int count);

  /// No description provided for @alreadyOnFrame.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo was already on the frame.} other{{count} photos were already on the frame.}}'**
  String alreadyOnFrame(int count);

  /// No description provided for @storageFull.
  ///
  /// In en, this message translates to:
  /// **'{frame}\'s storage is full. Delete some photos to add more.'**
  String storageFull(String frame);

  /// No description provided for @addedBy.
  ///
  /// In en, this message translates to:
  /// **'Added by {name} · {when}'**
  String addedBy(String name, String when);

  /// No description provided for @someoneWhoLeft.
  ///
  /// In en, this message translates to:
  /// **'someone who left'**
  String get someoneWhoLeft;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get you;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selected(int count);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this photo from the frame?} other{Delete {count} photos from the frame?}}'**
  String deleteConfirm(int count);

  /// No description provided for @cantDeleteOthers.
  ///
  /// In en, this message translates to:
  /// **'You can only delete your own photos. The frame\'s owner can delete any.'**
  String get cantDeleteOthers;

  /// No description provided for @noReEdit.
  ///
  /// In en, this message translates to:
  /// **'To change the crop or look, delete the photo and add it again.'**
  String get noReEdit;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Change order'**
  String get reorder;

  /// No description provided for @reorderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag photos to change the order the frame shows them in.'**
  String get reorderHint;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @photoOf.
  ///
  /// In en, this message translates to:
  /// **'Photo {n} of {total}'**
  String photoOf(int n, int total);

  /// No description provided for @photoLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo added by {name} on {date}'**
  String photoLabel(String name, String date);

  /// No description provided for @couldntLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this photo.'**
  String get couldntLoad;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @frameName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get frameName;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename the frame'**
  String get renameTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @sectionPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get sectionPhotos;

  /// No description provided for @sectionChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for new photos'**
  String get sectionChecking;

  /// No description provided for @sectionBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get sectionBattery;

  /// No description provided for @sectionHardware.
  ///
  /// In en, this message translates to:
  /// **'The frame'**
  String get sectionHardware;

  /// No description provided for @changePhotoEvery.
  ///
  /// In en, this message translates to:
  /// **'Change photo every'**
  String get changePhotoEvery;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @orderShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get orderShuffle;

  /// No description provided for @orderInOrder.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get orderInOrder;

  /// No description provided for @quietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get quietHours;

  /// No description provided for @quietHoursHint.
  ///
  /// In en, this message translates to:
  /// **'The frame won\'t change photos during these hours.'**
  String get quietHoursHint;

  /// No description provided for @quietFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get quietFrom;

  /// No description provided for @quietTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get quietTo;

  /// No description provided for @timeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get timeZone;

  /// No description provided for @searchTimeZones.
  ///
  /// In en, this message translates to:
  /// **'Search for a city'**
  String get searchTimeZones;

  /// No description provided for @checkForNewPhotos.
  ///
  /// In en, this message translates to:
  /// **'Check for new photos'**
  String get checkForNewPhotos;

  /// No description provided for @checkMoreOftenHint.
  ///
  /// In en, this message translates to:
  /// **'More often uses more battery.'**
  String get checkMoreOftenHint;

  /// No description provided for @lowBatteryWarning.
  ///
  /// In en, this message translates to:
  /// **'Low battery warning'**
  String get lowBatteryWarning;

  /// No description provided for @lowBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'Shows a warning when the battery drops below this.'**
  String get lowBatteryHint;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @percent.
  ///
  /// In en, this message translates to:
  /// **'{value} %'**
  String percent(int value);

  /// No description provided for @frameModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get frameModel;

  /// No description provided for @hardwareConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected · software {version}'**
  String hardwareConnected(String version);

  /// No description provided for @hardwareConnectedNoVersion.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get hardwareConnectedNoVersion;

  /// No description provided for @hardwareNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected yet'**
  String get hardwareNotConnected;

  /// No description provided for @batteryNow.
  ///
  /// In en, this message translates to:
  /// **'Battery now: {value} %'**
  String batteryNow(int value);

  /// No description provided for @onlyOwnerChanges.
  ///
  /// In en, this message translates to:
  /// **'Only {name} can change these settings.'**
  String onlyOwnerChanges(String name);

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @savedNextCheck.
  ///
  /// In en, this message translates to:
  /// **'Saved · the frame gets it at its next check'**
  String get savedNextCheck;

  /// No description provided for @couldntSave.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Try again.'**
  String get couldntSave;

  /// No description provided for @hoursCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String hoursCount(int count);

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String daysCount(int count);

  /// No description provided for @inviteSomeone.
  ///
  /// In en, this message translates to:
  /// **'Invite someone'**
  String get inviteSomeone;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite someone to add photos'**
  String get inviteTitle;

  /// No description provided for @inviteExplain.
  ///
  /// In en, this message translates to:
  /// **'They scan this with their phone\'s camera, or open the link.'**
  String get inviteExplain;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCode;

  /// No description provided for @inviteOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get inviteOptions;

  /// No description provided for @worksFor.
  ///
  /// In en, this message translates to:
  /// **'Works for'**
  String get worksFor;

  /// No description provided for @onePerson.
  ///
  /// In en, this message translates to:
  /// **'1 person'**
  String get onePerson;

  /// No description provided for @upToTen.
  ///
  /// In en, this message translates to:
  /// **'Up to 10 people'**
  String get upToTen;

  /// No description provided for @expiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in'**
  String get expiresIn;

  /// No description provided for @inviteShareText.
  ///
  /// In en, this message translates to:
  /// **'Join {frame} on Ink Frame to add photos: {link}'**
  String inviteShareText(String frame, String link);

  /// No description provided for @makingInvite.
  ///
  /// In en, this message translates to:
  /// **'Making an invite…'**
  String get makingInvite;

  /// No description provided for @activeInvites.
  ///
  /// In en, this message translates to:
  /// **'Invites'**
  String get activeInvites;

  /// No description provided for @inviteForOne.
  ///
  /// In en, this message translates to:
  /// **'For 1 person · expires {date}'**
  String inviteForOne(String date);

  /// No description provided for @inviteForMany.
  ///
  /// In en, this message translates to:
  /// **'{used} of {max} joined · expires {date}'**
  String inviteForMany(int used, int max, String date);

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @justYou.
  ///
  /// In en, this message translates to:
  /// **'Just you so far'**
  String get justYou;

  /// No description provided for @ownerBadge.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get ownerBadge;

  /// No description provided for @youBadge.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youBadge;

  /// No description provided for @removePerson.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removePerson;

  /// No description provided for @removePersonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from {frame}? Their photos stay; you can delete them.'**
  String removePersonConfirm(String name, String frame);

  /// No description provided for @leaveFrame.
  ///
  /// In en, this message translates to:
  /// **'Leave this frame'**
  String get leaveFrame;

  /// No description provided for @leaveFrameConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave {frame}? You\'ll stop seeing its photos. Photos you added stay.'**
  String leaveFrameConfirm(String frame);

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit}'**
  String storageUsed(String used, String limit);

  /// No description provided for @freePlan.
  ///
  /// In en, this message translates to:
  /// **'Free Supabase plan'**
  String get freePlan;

  /// No description provided for @photoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String photoCount(int count);

  /// No description provided for @storageNote.
  ///
  /// In en, this message translates to:
  /// **'The frame\'s own downloads aren\'t counted here.'**
  String get storageNote;

  /// No description provided for @storageByPerson.
  ///
  /// In en, this message translates to:
  /// **'By person'**
  String get storageByPerson;

  /// No description provided for @storageGettingFull.
  ///
  /// In en, this message translates to:
  /// **'{frame}\'s storage is getting full ({value} %).'**
  String storageGettingFull(String frame, int value);

  /// No description provided for @seeStorage.
  ///
  /// In en, this message translates to:
  /// **'See storage'**
  String get seeStorage;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHint.
  ///
  /// In en, this message translates to:
  /// **'What the others see, on every frame you\'re on.'**
  String get yourNameHint;

  /// No description provided for @nameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get nameUpdated;

  /// No description provided for @nameUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your name on {frames}.'**
  String nameUpdateFailed(String frames);

  /// No description provided for @anotherDevice.
  ///
  /// In en, this message translates to:
  /// **'Use on another device'**
  String get anotherDevice;

  /// No description provided for @anotherDeviceExplain.
  ///
  /// In en, this message translates to:
  /// **'On your other phone or computer, open Ink Frame, choose “Already use Ink Frame? Sign in”, then scan this or paste the link.'**
  String get anotherDeviceExplain;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll leave these frames and your account on them is deleted:'**
  String get deleteAccountBody;

  /// No description provided for @deletePhotosToo.
  ///
  /// In en, this message translates to:
  /// **'Also delete my photos'**
  String get deletePhotosToo;

  /// No description provided for @deleteOwnedBlock.
  ///
  /// In en, this message translates to:
  /// **'You set up {frames}. To delete your account, those frames have to be deleted first, which isn\'t possible in the app yet.'**
  String deleteOwnedBlock(String frames);

  /// No description provided for @typeDelete.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get typeDelete;

  /// No description provided for @deleteWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get deleteWord;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountButton;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account on {frames}. Try again.'**
  String deleteFailed(String frames);

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQr;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the invite\'s QR code.'**
  String get scanHint;

  /// No description provided for @notAnInvite.
  ///
  /// In en, this message translates to:
  /// **'That QR code isn\'t an Ink Frame link.'**
  String get notAnInvite;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

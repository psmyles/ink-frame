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

  /// No description provided for @photosComing.
  ///
  /// In en, this message translates to:
  /// **'Adding photos arrives in the next build.'**
  String get photosComing;

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

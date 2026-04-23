import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
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
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Tichu Online'**
  String get appTitle;

  /// No description provided for @languageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (System)'**
  String get languageAuto;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKorean;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsAppInfo.
  ///
  /// In en, this message translates to:
  /// **'App Info'**
  String get settingsAppInfo;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get settingsAppVersion;

  /// No description provided for @settingsNotLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Not the latest version'**
  String get settingsNotLatestVersion;

  /// No description provided for @settingsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get settingsUpdate;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get settingsLogout;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account?\nAll data will be permanently deleted.'**
  String get settingsDeleteAccountConfirm;

  /// No description provided for @settingsNickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get settingsNickname;

  /// No description provided for @settingsSocialLink.
  ///
  /// In en, this message translates to:
  /// **'Social Link'**
  String get settingsSocialLink;

  /// No description provided for @settingsTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTermsOfService;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsNotices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get settingsNotices;

  /// No description provided for @settingsMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get settingsMyProfile;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsAdminCenter.
  ///
  /// In en, this message translates to:
  /// **'Admin Center'**
  String get settingsAdminCenter;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get commonLink;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @settingsHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsHeaderTitle;

  /// No description provided for @settingsNotificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsSection;

  /// No description provided for @settingsPushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get settingsPushNotifications;

  /// No description provided for @settingsPushNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Turn all notifications on or off'**
  String get settingsPushNotificationsDesc;

  /// No description provided for @settingsInquiryNotifications.
  ///
  /// In en, this message translates to:
  /// **'Inquiry Notifications'**
  String get settingsInquiryNotifications;

  /// No description provided for @settingsInquiryNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Receive push when a new inquiry arrives'**
  String get settingsInquiryNotificationsDesc;

  /// No description provided for @settingsReportNotifications.
  ///
  /// In en, this message translates to:
  /// **'Report Notifications'**
  String get settingsReportNotifications;

  /// No description provided for @settingsReportNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Receive push when a new report arrives'**
  String get settingsReportNotificationsDesc;

  /// No description provided for @settingsAdminSection.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get settingsAdminSection;

  /// No description provided for @settingsAdminCenterDesc.
  ///
  /// In en, this message translates to:
  /// **'View inquiries, reports, users, and active users'**
  String get settingsAdminCenterDesc;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View level, record, and recent matches'**
  String get settingsProfileSubtitle;

  /// No description provided for @settingsSocialLinked.
  ///
  /// In en, this message translates to:
  /// **'{provider} linked'**
  String settingsSocialLinked(String provider);

  /// No description provided for @settingsNoLinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'No linked account (ranked play unavailable)'**
  String get settingsNoLinkedAccount;

  /// No description provided for @settingsInquirySection.
  ///
  /// In en, this message translates to:
  /// **'Inquiry'**
  String get settingsInquirySection;

  /// No description provided for @settingsSubmitInquiry.
  ///
  /// In en, this message translates to:
  /// **'Submit Inquiry'**
  String get settingsSubmitInquiry;

  /// No description provided for @settingsInquiryHistory.
  ///
  /// In en, this message translates to:
  /// **'Inquiry History'**
  String get settingsInquiryHistory;

  /// No description provided for @settingsAccountManagement.
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get settingsAccountManagement;

  /// No description provided for @settingsDeleteAccountWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get settingsDeleteAccountWithdraw;

  /// No description provided for @settingsLinkComplete.
  ///
  /// In en, this message translates to:
  /// **'Linking completed'**
  String get settingsLinkComplete;

  /// No description provided for @settingsLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Linking failed: {error}'**
  String settingsLinkFailed(String error);

  /// No description provided for @noticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get noticeTitle;

  /// No description provided for @noticeEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notices available'**
  String get noticeEmpty;

  /// No description provided for @noticeRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get noticeRetry;

  /// No description provided for @noticeCategoryRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get noticeCategoryRelease;

  /// No description provided for @noticeCategoryUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get noticeCategoryUpdate;

  /// No description provided for @noticeCategoryPreview.
  ///
  /// In en, this message translates to:
  /// **'Update Preview'**
  String get noticeCategoryPreview;

  /// No description provided for @noticeCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get noticeCategoryGeneral;

  /// No description provided for @inquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit Inquiry'**
  String get inquiryTitle;

  /// No description provided for @inquiryCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get inquiryCategory;

  /// No description provided for @inquiryCategoryBug.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get inquiryCategoryBug;

  /// No description provided for @inquiryCategorySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get inquiryCategorySuggestion;

  /// No description provided for @inquiryCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get inquiryCategoryOther;

  /// No description provided for @inquiryFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get inquiryFieldTitle;

  /// No description provided for @inquiryFieldTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a title'**
  String get inquiryFieldTitleHint;

  /// No description provided for @inquiryFieldContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get inquiryFieldContent;

  /// No description provided for @inquiryFieldContentHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the details'**
  String get inquiryFieldContentHint;

  /// No description provided for @inquirySubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get inquirySubmit;

  /// No description provided for @inquirySubmitted.
  ///
  /// In en, this message translates to:
  /// **'Your inquiry has been submitted'**
  String get inquirySubmitted;

  /// No description provided for @inquiryHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inquiry History'**
  String get inquiryHistoryTitle;

  /// No description provided for @inquiryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No inquiries found'**
  String get inquiryEmpty;

  /// No description provided for @inquiryStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get inquiryStatusResolved;

  /// No description provided for @inquiryStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get inquiryStatusPending;

  /// No description provided for @inquiryAnswerLabel.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get inquiryAnswerLabel;

  /// No description provided for @inquiryAnswerDate.
  ///
  /// In en, this message translates to:
  /// **'Answered on: {date}'**
  String inquiryAnswerDate(String date);

  /// No description provided for @inquiryNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer has been registered yet.'**
  String get inquiryNoAnswer;

  /// No description provided for @linkDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Link Social Account'**
  String get linkDialogTitle;

  /// No description provided for @linkDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Select a social account to link'**
  String get linkDialogContent;

  /// No description provided for @textViewLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load content.'**
  String get textViewLoadFailed;

  /// No description provided for @loginEnterUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter your username'**
  String get loginEnterUsername;

  /// No description provided for @loginEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get loginEnterPassword;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @loginSocialFailed.
  ///
  /// In en, this message translates to:
  /// **'Social login failed: {error}'**
  String loginSocialFailed(String error);

  /// No description provided for @loginSocialFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Social login failed'**
  String get loginSocialFailedGeneric;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Team card game'**
  String get loginSubtitle;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'Quickly reconnect and\njump right back into the game.'**
  String get loginTagline;

  /// No description provided for @loginUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get loginUsernameHint;

  /// No description provided for @loginPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordHint;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// No description provided for @loginRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get loginRegisterButton;

  /// No description provided for @loginQuickLogin.
  ///
  /// In en, this message translates to:
  /// **'Quick login'**
  String get loginQuickLogin;

  /// No description provided for @loginAutoLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto login failed'**
  String get loginAutoLoginFailed;

  /// No description provided for @loginCheckSavedInfo.
  ///
  /// In en, this message translates to:
  /// **'Please check your saved login info.'**
  String get loginCheckSavedInfo;

  /// No description provided for @loginRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get loginRetry;

  /// No description provided for @loginManual.
  ///
  /// In en, this message translates to:
  /// **'Login manually'**
  String get loginManual;

  /// No description provided for @loginAutoLoggingIn.
  ///
  /// In en, this message translates to:
  /// **'Auto logging in...'**
  String get loginAutoLoggingIn;

  /// No description provided for @loginLoggingIn.
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loginLoggingIn;

  /// No description provided for @loginVerifyingAccount.
  ///
  /// In en, this message translates to:
  /// **'Verifying account info.'**
  String get loginVerifyingAccount;

  /// No description provided for @loginRegistrationComplete.
  ///
  /// In en, this message translates to:
  /// **'Registration complete. Please log in.'**
  String get loginRegistrationComplete;

  /// No description provided for @loginNicknameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a nickname'**
  String get loginNicknameEmpty;

  /// No description provided for @loginNicknameLength.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be 2-10 characters'**
  String get loginNicknameLength;

  /// No description provided for @loginNicknameNoSpaces.
  ///
  /// In en, this message translates to:
  /// **'Nickname cannot contain spaces'**
  String get loginNicknameNoSpaces;

  /// No description provided for @loginServerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to the server.'**
  String get loginServerUnavailable;

  /// No description provided for @loginServerNoResponse.
  ///
  /// In en, this message translates to:
  /// **'No response from server. Please try again.'**
  String get loginServerNoResponse;

  /// No description provided for @loginUsernameMinLength.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 2 characters'**
  String get loginUsernameMinLength;

  /// No description provided for @loginUsernameNoSpaces.
  ///
  /// In en, this message translates to:
  /// **'Username cannot contain spaces'**
  String get loginUsernameNoSpaces;

  /// No description provided for @loginPasswordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 4 characters'**
  String get loginPasswordMinLength;

  /// No description provided for @loginPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get loginPasswordMismatch;

  /// No description provided for @loginNicknameCheckRequired.
  ///
  /// In en, this message translates to:
  /// **'Please check nickname availability'**
  String get loginNicknameCheckRequired;

  /// No description provided for @loginServerTimeout.
  ///
  /// In en, this message translates to:
  /// **'Server response timed out'**
  String get loginServerTimeout;

  /// No description provided for @loginRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get loginRegisterTitle;

  /// No description provided for @loginUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get loginUsernameLabel;

  /// No description provided for @loginUsernameHintRegister.
  ///
  /// In en, this message translates to:
  /// **'2+ characters, no spaces'**
  String get loginUsernameHintRegister;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginPasswordHintRegister.
  ///
  /// In en, this message translates to:
  /// **'4+ characters'**
  String get loginPasswordHintRegister;

  /// No description provided for @loginConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get loginConfirmPasswordLabel;

  /// No description provided for @loginConfirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get loginConfirmPasswordHint;

  /// No description provided for @loginSubmitRegister.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get loginSubmitRegister;

  /// No description provided for @loginNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get loginNicknameLabel;

  /// No description provided for @loginNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'2-10 characters, no spaces'**
  String get loginNicknameHint;

  /// No description provided for @loginCheckAvailability.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get loginCheckAvailability;

  /// No description provided for @loginSetNicknameTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Nickname'**
  String get loginSetNicknameTitle;

  /// No description provided for @loginSetNicknameDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose a nickname to use in the game'**
  String get loginSetNicknameDesc;

  /// No description provided for @loginGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get loginGetStarted;

  /// No description provided for @lobbyRoomInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Room Invite'**
  String get lobbyRoomInviteTitle;

  /// No description provided for @lobbyRoomInviteMessage.
  ///
  /// In en, this message translates to:
  /// **'{nickname} invited you to a room!'**
  String lobbyRoomInviteMessage(String nickname);

  /// No description provided for @lobbyDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get lobbyDecline;

  /// No description provided for @lobbyJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get lobbyJoin;

  /// No description provided for @lobbyInviteFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get lobbyInviteFriendsTitle;

  /// No description provided for @lobbyNoOnlineFriends.
  ///
  /// In en, this message translates to:
  /// **'No online friends available to invite'**
  String get lobbyNoOnlineFriends;

  /// No description provided for @lobbyInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent to {nickname}'**
  String lobbyInviteSent(String nickname);

  /// No description provided for @lobbyInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get lobbyInvite;

  /// No description provided for @lobbySpectatorListTitle.
  ///
  /// In en, this message translates to:
  /// **'Spectator List'**
  String get lobbySpectatorListTitle;

  /// No description provided for @lobbyNoSpectators.
  ///
  /// In en, this message translates to:
  /// **'No one is spectating'**
  String get lobbyNoSpectators;

  /// No description provided for @lobbyRoomSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Room Settings'**
  String get lobbyRoomSettingsTitle;

  /// No description provided for @lobbyEnterRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a room title'**
  String get lobbyEnterRoomTitle;

  /// No description provided for @lobbyChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get lobbyChange;

  /// No description provided for @lobbyCreateRoom.
  ///
  /// In en, this message translates to:
  /// **'Create Room'**
  String get lobbyCreateRoom;

  /// No description provided for @lobbyCreateRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set a room title and rules, and the waiting room opens right away.'**
  String get lobbyCreateRoomSubtitle;

  /// No description provided for @lobbySelectGame.
  ///
  /// In en, this message translates to:
  /// **'Select Game'**
  String get lobbySelectGame;

  /// No description provided for @lobbySelectGameDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose the game to play.'**
  String get lobbySelectGameDesc;

  /// No description provided for @lobbyTichu.
  ///
  /// In en, this message translates to:
  /// **'Tichu'**
  String get lobbyTichu;

  /// No description provided for @lobbySkullKing.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get lobbySkullKing;

  /// No description provided for @lobbyMaxPlayers.
  ///
  /// In en, this message translates to:
  /// **'Max Players'**
  String get lobbyMaxPlayers;

  /// No description provided for @lobbyPlayerCount.
  ///
  /// In en, this message translates to:
  /// **'{count}P'**
  String lobbyPlayerCount(int count);

  /// No description provided for @lobbyExpansionOptional.
  ///
  /// In en, this message translates to:
  /// **'Expansions (Optional)'**
  String get lobbyExpansionOptional;

  /// No description provided for @lobbyExpansionDesc.
  ///
  /// In en, this message translates to:
  /// **'Add special cards to the base rules. Multiple selections allowed.'**
  String get lobbyExpansionDesc;

  /// No description provided for @lobbyExpKraken.
  ///
  /// In en, this message translates to:
  /// **'Kraken'**
  String get lobbyExpKraken;

  /// No description provided for @lobbyExpKrakenDesc.
  ///
  /// In en, this message translates to:
  /// **'Void a trick'**
  String get lobbyExpKrakenDesc;

  /// No description provided for @lobbyExpWhiteWhale.
  ///
  /// In en, this message translates to:
  /// **'White Whale'**
  String get lobbyExpWhiteWhale;

  /// No description provided for @lobbyExpWhiteWhaleDesc.
  ///
  /// In en, this message translates to:
  /// **'Neutralize special cards'**
  String get lobbyExpWhiteWhaleDesc;

  /// No description provided for @lobbyExpLoot.
  ///
  /// In en, this message translates to:
  /// **'Loot'**
  String get lobbyExpLoot;

  /// No description provided for @lobbyExpLootDesc.
  ///
  /// In en, this message translates to:
  /// **'Bonus points'**
  String get lobbyExpLootDesc;

  /// No description provided for @lobbyBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get lobbyBasicInfo;

  /// No description provided for @lobbyBasicInfoDesc.
  ///
  /// In en, this message translates to:
  /// **'Set the room name and visibility.'**
  String get lobbyBasicInfoDesc;

  /// No description provided for @lobbyRoomName.
  ///
  /// In en, this message translates to:
  /// **'Room Name'**
  String get lobbyRoomName;

  /// No description provided for @lobbyRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get lobbyRandom;

  /// No description provided for @lobbyPrivateRoom.
  ///
  /// In en, this message translates to:
  /// **'Private Room'**
  String get lobbyPrivateRoom;

  /// No description provided for @lobbyPrivateRoomDescRanked.
  ///
  /// In en, this message translates to:
  /// **'Cannot create a private room in ranked play.'**
  String get lobbyPrivateRoomDescRanked;

  /// No description provided for @lobbyPrivateRoomDesc.
  ///
  /// In en, this message translates to:
  /// **'Only invited players or those with the password can join.'**
  String get lobbyPrivateRoomDesc;

  /// No description provided for @lobbyPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password (4+ characters)'**
  String get lobbyPasswordHint;

  /// No description provided for @lobbyRanked.
  ///
  /// In en, this message translates to:
  /// **'Ranked'**
  String get lobbyRanked;

  /// No description provided for @lobbyRankedDesc.
  ///
  /// In en, this message translates to:
  /// **'Score is fixed at 1000 and private settings are automatically disabled.'**
  String get lobbyRankedDesc;

  /// No description provided for @lobbyRankedDescSk.
  ///
  /// In en, this message translates to:
  /// **'Private settings are automatically disabled.'**
  String get lobbyRankedDescSk;

  /// No description provided for @lobbyRankedDescMighty.
  ///
  /// In en, this message translates to:
  /// **'Score is fixed at 50 and private settings are automatically disabled.'**
  String get lobbyRankedDescMighty;

  /// No description provided for @lobbyGameSettings.
  ///
  /// In en, this message translates to:
  /// **'Game Settings'**
  String get lobbyGameSettings;

  /// No description provided for @lobbyGameSettingsDescSk.
  ///
  /// In en, this message translates to:
  /// **'Set the turn time.'**
  String get lobbyGameSettingsDescSk;

  /// No description provided for @lobbyGameSettingsDescTichu.
  ///
  /// In en, this message translates to:
  /// **'Set the turn time and target score.'**
  String get lobbyGameSettingsDescTichu;

  /// No description provided for @lobbyTimeLimit.
  ///
  /// In en, this message translates to:
  /// **'Time Limit'**
  String get lobbyTimeLimit;

  /// No description provided for @lobbySuffixSeconds.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get lobbySuffixSeconds;

  /// No description provided for @lobbyTargetScore.
  ///
  /// In en, this message translates to:
  /// **'Target Score'**
  String get lobbyTargetScore;

  /// No description provided for @lobbySuffixPoints.
  ///
  /// In en, this message translates to:
  /// **'pts'**
  String get lobbySuffixPoints;

  /// No description provided for @lobbyTimeLimitRange.
  ///
  /// In en, this message translates to:
  /// **'10–999'**
  String get lobbyTimeLimitRange;

  /// No description provided for @lobbyTargetScoreRange.
  ///
  /// In en, this message translates to:
  /// **'100–20000'**
  String get lobbyTargetScoreRange;

  /// No description provided for @lobbyTargetScoreRangeMighty.
  ///
  /// In en, this message translates to:
  /// **'10–500'**
  String get lobbyTargetScoreRangeMighty;

  /// No description provided for @lobbyTargetScoreFixed.
  ///
  /// In en, this message translates to:
  /// **'1000 (fixed)'**
  String get lobbyTargetScoreFixed;

  /// No description provided for @lobbyTargetScoreFixedMighty.
  ///
  /// In en, this message translates to:
  /// **'50 (fixed)'**
  String get lobbyTargetScoreFixedMighty;

  /// No description provided for @lobbyRankedFixedScoreInfo.
  ///
  /// In en, this message translates to:
  /// **'Ranked play uses a fixed target score of 1000.'**
  String get lobbyRankedFixedScoreInfo;

  /// No description provided for @lobbyRankedInfoSk.
  ///
  /// In en, this message translates to:
  /// **'Private rooms are not available in ranked play.'**
  String get lobbyRankedInfoSk;

  /// No description provided for @lobbyRankedInfoMighty.
  ///
  /// In en, this message translates to:
  /// **'Ranked play uses a fixed target score of 50. Private rooms are not available.'**
  String get lobbyRankedInfoMighty;

  /// No description provided for @lobbyNormalSettingsInfo.
  ///
  /// In en, this message translates to:
  /// **'Time limit: 10–999 sec, target score: 100–20000 pts.'**
  String get lobbyNormalSettingsInfo;

  /// No description provided for @lobbyNormalSettingsInfoMighty.
  ///
  /// In en, this message translates to:
  /// **'Time limit: 10–999 sec, target score: 10–500 pts.'**
  String get lobbyNormalSettingsInfoMighty;

  /// No description provided for @lobbyEnterRoomName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a room name.'**
  String get lobbyEnterRoomName;

  /// No description provided for @lobbyPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 4 characters.'**
  String get lobbyPasswordTooShort;

  /// No description provided for @lobbyDuplicateLoginKicked.
  ///
  /// In en, this message translates to:
  /// **'You were logged out because another device logged in'**
  String get lobbyDuplicateLoginKicked;

  /// No description provided for @lobbyRoomListTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Room List'**
  String get lobbyRoomListTitle;

  /// No description provided for @lobbyEmptyRoomList.
  ///
  /// In en, this message translates to:
  /// **'No rooms yet!\nWhy not create one?'**
  String get lobbyEmptyRoomList;

  /// No description provided for @lobbySkullKingBadge.
  ///
  /// In en, this message translates to:
  /// **'☠️ Skull King'**
  String get lobbySkullKingBadge;

  /// No description provided for @lobbyTichuBadge.
  ///
  /// In en, this message translates to:
  /// **'Tichu'**
  String get lobbyTichuBadge;

  /// No description provided for @lobbyRoomTimeSec.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String lobbyRoomTimeSec(int seconds);

  /// No description provided for @lobbyRoomTimeAndScore.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s · {score}pts'**
  String lobbyRoomTimeAndScore(int seconds, int score);

  /// No description provided for @lobbyExpKrakenShort.
  ///
  /// In en, this message translates to:
  /// **'Kraken'**
  String get lobbyExpKrakenShort;

  /// No description provided for @lobbyExpWhaleShort.
  ///
  /// In en, this message translates to:
  /// **'Whale'**
  String get lobbyExpWhaleShort;

  /// No description provided for @lobbyExpLootShort.
  ///
  /// In en, this message translates to:
  /// **'Loot'**
  String get lobbyExpLootShort;

  /// No description provided for @lobbyInProgress.
  ///
  /// In en, this message translates to:
  /// **'Spectating {count}'**
  String lobbyInProgress(int count);

  /// No description provided for @lobbySocialLinkRequired.
  ///
  /// In en, this message translates to:
  /// **'Social Link Required'**
  String get lobbySocialLinkRequired;

  /// No description provided for @lobbySocialLinkRequiredDesc.
  ///
  /// In en, this message translates to:
  /// **'Ranked play requires a linked social account.\nGo to Settings > Social Link to link your Google or Kakao account.'**
  String get lobbySocialLinkRequiredDesc;

  /// No description provided for @lobbyJoinPrivateRoom.
  ///
  /// In en, this message translates to:
  /// **'Join Private Room'**
  String get lobbyJoinPrivateRoom;

  /// No description provided for @lobbyEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get lobbyEnter;

  /// No description provided for @lobbySpectatePrivateRoom.
  ///
  /// In en, this message translates to:
  /// **'Spectate Private Room'**
  String get lobbySpectatePrivateRoom;

  /// No description provided for @lobbySpectate.
  ///
  /// In en, this message translates to:
  /// **'Spectate'**
  String get lobbySpectate;

  /// No description provided for @lobbyPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get lobbyPassword;

  /// No description provided for @lobbyMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get lobbyMessageHint;

  /// No description provided for @lobbyChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get lobbyChat;

  /// No description provided for @lobbyViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get lobbyViewProfile;

  /// No description provided for @lobbyAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get lobbyAddFriend;

  /// No description provided for @lobbyUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get lobbyUnblock;

  /// No description provided for @lobbyBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get lobbyBlock;

  /// No description provided for @lobbyUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User has been unblocked'**
  String get lobbyUnblocked;

  /// No description provided for @lobbyBlocked.
  ///
  /// In en, this message translates to:
  /// **'User has been blocked'**
  String get lobbyBlocked;

  /// No description provided for @lobbyFriendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent'**
  String get lobbyFriendRequestSent;

  /// No description provided for @lobbyReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get lobbyReport;

  /// No description provided for @lobbyWaitingRoomTools.
  ///
  /// In en, this message translates to:
  /// **'Waiting Room Tools'**
  String get lobbyWaitingRoomTools;

  /// No description provided for @lobbyWaitingRoomToolsDesc.
  ///
  /// In en, this message translates to:
  /// **'Features not directly related to game preparation can be found here.'**
  String get lobbyWaitingRoomToolsDesc;

  /// No description provided for @lobbyFriendsDm.
  ///
  /// In en, this message translates to:
  /// **'Friends / DM'**
  String get lobbyFriendsDm;

  /// No description provided for @lobbyUnreadDmCount.
  ///
  /// In en, this message translates to:
  /// **'You have {count} unread requests and DMs.'**
  String lobbyUnreadDmCount(int count);

  /// No description provided for @lobbyFriendsDmDesc.
  ///
  /// In en, this message translates to:
  /// **'View your friends list and DM conversations.'**
  String get lobbyFriendsDmDesc;

  /// No description provided for @lobbyCurrentSpectators.
  ///
  /// In en, this message translates to:
  /// **'View {count} current spectators.'**
  String lobbyCurrentSpectators(int count);

  /// No description provided for @lobbyMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get lobbyMore;

  /// No description provided for @lobbyRoomSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get lobbyRoomSettings;

  /// No description provided for @lobbySkullKingRanked.
  ///
  /// In en, this message translates to:
  /// **'Skull King - Ranked'**
  String get lobbySkullKingRanked;

  /// No description provided for @lobbyTichuRanked.
  ///
  /// In en, this message translates to:
  /// **'Tichu - Ranked'**
  String get lobbyTichuRanked;

  /// No description provided for @lobbyMightyRanked.
  ///
  /// In en, this message translates to:
  /// **'Mighty - Ranked'**
  String get lobbyMightyRanked;

  /// No description provided for @lobbySkullKingPlayers.
  ///
  /// In en, this message translates to:
  /// **'Skull King · {count}P'**
  String lobbySkullKingPlayers(int count);

  /// No description provided for @lobbyStartGame.
  ///
  /// In en, this message translates to:
  /// **'Start Game'**
  String get lobbyStartGame;

  /// No description provided for @lobbyReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get lobbyReady;

  /// No description provided for @lobbyReadyDone.
  ///
  /// In en, this message translates to:
  /// **'Ready!'**
  String get lobbyReadyDone;

  /// No description provided for @lobbyReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report {nickname}'**
  String lobbyReportTitle(String nickname);

  /// No description provided for @lobbyReportWarning.
  ///
  /// In en, this message translates to:
  /// **'Reports are reviewed by the moderation team.\nFalse reports may result in penalties.'**
  String get lobbyReportWarning;

  /// No description provided for @lobbySelectReason.
  ///
  /// In en, this message translates to:
  /// **'Select Reason'**
  String get lobbySelectReason;

  /// No description provided for @lobbyReportDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter details (optional)'**
  String get lobbyReportDetailHint;

  /// No description provided for @lobbyReportReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse/Insults'**
  String get lobbyReportReasonAbuse;

  /// No description provided for @lobbyReportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam/Flooding'**
  String get lobbyReportReasonSpam;

  /// No description provided for @lobbyReportReasonNickname.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate Nickname'**
  String get lobbyReportReasonNickname;

  /// No description provided for @lobbyReportReasonGameplay.
  ///
  /// In en, this message translates to:
  /// **'Gameplay Disruption'**
  String get lobbyReportReasonGameplay;

  /// No description provided for @lobbyReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get lobbyReportReasonOther;

  /// No description provided for @lobbyProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Profile not found'**
  String get lobbyProfileNotFound;

  /// No description provided for @lobbyMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get lobbyMyProfile;

  /// No description provided for @lobbyPlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'Player Profile'**
  String get lobbyPlayerProfile;

  /// No description provided for @lobbyAlreadyFriend.
  ///
  /// In en, this message translates to:
  /// **'Already friends'**
  String get lobbyAlreadyFriend;

  /// No description provided for @lobbyRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get lobbyRequestPending;

  /// No description provided for @lobbyTichuSeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Tichu Season Ranked'**
  String get lobbyTichuSeasonRanked;

  /// No description provided for @lobbySkullKingSeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Skull King Season Ranked'**
  String get lobbySkullKingSeasonRanked;

  /// No description provided for @lobbyTichuRecord.
  ///
  /// In en, this message translates to:
  /// **'Tichu Record'**
  String get lobbyTichuRecord;

  /// No description provided for @lobbySkullKingRecord.
  ///
  /// In en, this message translates to:
  /// **'Skull King Record'**
  String get lobbySkullKingRecord;

  /// No description provided for @lobbyLoveLetterRecord.
  ///
  /// In en, this message translates to:
  /// **'Love Letter Record'**
  String get lobbyLoveLetterRecord;

  /// No description provided for @lobbyStatRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get lobbyStatRecord;

  /// No description provided for @lobbyStatWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win Rate'**
  String get lobbyStatWinRate;

  /// No description provided for @lobbyRecordFormat.
  ///
  /// In en, this message translates to:
  /// **'{games}G {wins}W {losses}L'**
  String lobbyRecordFormat(int games, int wins, int losses);

  /// No description provided for @lobbyRecentMatches.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches ({count})'**
  String lobbyRecentMatches(int count);

  /// No description provided for @lobbyRecentMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches'**
  String get lobbyRecentMatchesTitle;

  /// No description provided for @lobbyRecentMatchesDesc.
  ///
  /// In en, this message translates to:
  /// **'View results of the last {count} matches.'**
  String lobbyRecentMatchesDesc(int count);

  /// No description provided for @lobbySeeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get lobbySeeMore;

  /// No description provided for @lobbyNoRecentMatches.
  ///
  /// In en, this message translates to:
  /// **'No recent matches'**
  String get lobbyNoRecentMatches;

  /// No description provided for @lobbyMatchDesertion.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get lobbyMatchDesertion;

  /// No description provided for @lobbyMatchDraw.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get lobbyMatchDraw;

  /// No description provided for @lobbyMatchWin.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get lobbyMatchWin;

  /// No description provided for @lobbyMatchLoss.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get lobbyMatchLoss;

  /// No description provided for @lobbyMatchTypeSkullKing.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get lobbyMatchTypeSkullKing;

  /// No description provided for @lobbyMatchTypeLoveLetter.
  ///
  /// In en, this message translates to:
  /// **'Love Letter'**
  String get lobbyMatchTypeLoveLetter;

  /// No description provided for @lobbyMatchTypeRanked.
  ///
  /// In en, this message translates to:
  /// **'Ranked'**
  String get lobbyMatchTypeRanked;

  /// No description provided for @lobbyMatchTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get lobbyMatchTypeNormal;

  /// No description provided for @lobbyRankAndScore.
  ///
  /// In en, this message translates to:
  /// **'#{rank} ({score}pts)'**
  String lobbyRankAndScore(String rank, int score);

  /// No description provided for @lobbyMannerGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get lobbyMannerGood;

  /// No description provided for @lobbyMannerNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get lobbyMannerNormal;

  /// No description provided for @lobbyMannerBad.
  ///
  /// In en, this message translates to:
  /// **'Bad'**
  String get lobbyMannerBad;

  /// No description provided for @lobbyMannerVeryBad.
  ///
  /// In en, this message translates to:
  /// **'Very Bad'**
  String get lobbyMannerVeryBad;

  /// No description provided for @lobbyMannerWorst.
  ///
  /// In en, this message translates to:
  /// **'Terrible'**
  String get lobbyMannerWorst;

  /// No description provided for @lobbyManner.
  ///
  /// In en, this message translates to:
  /// **'Manner {label}'**
  String lobbyManner(String label);

  /// No description provided for @lobbyDesertions.
  ///
  /// In en, this message translates to:
  /// **'Desertions {count}'**
  String lobbyDesertions(int count);

  /// No description provided for @lobbyKick.
  ///
  /// In en, this message translates to:
  /// **'Kick'**
  String get lobbyKick;

  /// No description provided for @lobbyKickConfirm.
  ///
  /// In en, this message translates to:
  /// **'Kick {playerName}?'**
  String lobbyKickConfirm(String playerName);

  /// No description provided for @lobbyHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get lobbyHost;

  /// No description provided for @lobbyBot.
  ///
  /// In en, this message translates to:
  /// **'Bot'**
  String get lobbyBot;

  /// No description provided for @lobbyBotSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Bot Speed'**
  String get lobbyBotSpeedTitle;

  /// No description provided for @lobbyBotSpeedFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get lobbyBotSpeedFast;

  /// No description provided for @lobbyBotSpeedNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get lobbyBotSpeedNormal;

  /// No description provided for @lobbyBotSpeedSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get lobbyBotSpeedSlow;

  /// No description provided for @lobbyEmptySlot.
  ///
  /// In en, this message translates to:
  /// **'[Empty]'**
  String get lobbyEmptySlot;

  /// No description provided for @lobbySlotBlocked.
  ///
  /// In en, this message translates to:
  /// **'[Blocked]'**
  String get lobbySlotBlocked;

  /// No description provided for @lobbyMaintenanceDefault.
  ///
  /// In en, this message translates to:
  /// **'Server maintenance scheduled'**
  String get lobbyMaintenanceDefault;

  /// No description provided for @lobbyRoomInfoSk.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s · {players}/{maxPlayers}P'**
  String lobbyRoomInfoSk(int seconds, int players, int maxPlayers);

  /// No description provided for @lobbyRoomInfoTichu.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s · {score}pts'**
  String lobbyRoomInfoTichu(int seconds, int score);

  /// No description provided for @lobbyRandomAdjTichu1.
  ///
  /// In en, this message translates to:
  /// **'Joyful'**
  String get lobbyRandomAdjTichu1;

  /// No description provided for @lobbyRandomAdjTichu2.
  ///
  /// In en, this message translates to:
  /// **'Exciting'**
  String get lobbyRandomAdjTichu2;

  /// No description provided for @lobbyRandomAdjTichu3.
  ///
  /// In en, this message translates to:
  /// **'Passionate'**
  String get lobbyRandomAdjTichu3;

  /// No description provided for @lobbyRandomAdjTichu4.
  ///
  /// In en, this message translates to:
  /// **'Fiery'**
  String get lobbyRandomAdjTichu4;

  /// No description provided for @lobbyRandomAdjTichu5.
  ///
  /// In en, this message translates to:
  /// **'Lucky'**
  String get lobbyRandomAdjTichu5;

  /// No description provided for @lobbyRandomAdjTichu6.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get lobbyRandomAdjTichu6;

  /// No description provided for @lobbyRandomAdjTichu7.
  ///
  /// In en, this message translates to:
  /// **'Supreme'**
  String get lobbyRandomAdjTichu7;

  /// No description provided for @lobbyRandomAdjTichu8.
  ///
  /// In en, this message translates to:
  /// **'Invincible'**
  String get lobbyRandomAdjTichu8;

  /// No description provided for @lobbyRandomNounTichu1.
  ///
  /// In en, this message translates to:
  /// **'Tichu Room'**
  String get lobbyRandomNounTichu1;

  /// No description provided for @lobbyRandomNounTichu2.
  ///
  /// In en, this message translates to:
  /// **'Card Game'**
  String get lobbyRandomNounTichu2;

  /// No description provided for @lobbyRandomNounTichu3.
  ///
  /// In en, this message translates to:
  /// **'Showdown'**
  String get lobbyRandomNounTichu3;

  /// No description provided for @lobbyRandomNounTichu4.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get lobbyRandomNounTichu4;

  /// No description provided for @lobbyRandomNounTichu5.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get lobbyRandomNounTichu5;

  /// No description provided for @lobbyRandomNounTichu6.
  ///
  /// In en, this message translates to:
  /// **'Battle'**
  String get lobbyRandomNounTichu6;

  /// No description provided for @lobbyRandomNounTichu7.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get lobbyRandomNounTichu7;

  /// No description provided for @lobbyRandomNounTichu8.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get lobbyRandomNounTichu8;

  /// No description provided for @lobbyRandomAdjSk1.
  ///
  /// In en, this message translates to:
  /// **'Fearsome'**
  String get lobbyRandomAdjSk1;

  /// No description provided for @lobbyRandomAdjSk2.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get lobbyRandomAdjSk2;

  /// No description provided for @lobbyRandomAdjSk3.
  ///
  /// In en, this message translates to:
  /// **'Invincible'**
  String get lobbyRandomAdjSk3;

  /// No description provided for @lobbyRandomAdjSk4.
  ///
  /// In en, this message translates to:
  /// **'Ruthless'**
  String get lobbyRandomAdjSk4;

  /// No description provided for @lobbyRandomAdjSk5.
  ///
  /// In en, this message translates to:
  /// **'Greedy'**
  String get lobbyRandomAdjSk5;

  /// No description provided for @lobbyRandomAdjSk6.
  ///
  /// In en, this message translates to:
  /// **'Supreme'**
  String get lobbyRandomAdjSk6;

  /// No description provided for @lobbyRandomAdjSk7.
  ///
  /// In en, this message translates to:
  /// **'Stormy'**
  String get lobbyRandomAdjSk7;

  /// No description provided for @lobbyRandomAdjSk8.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get lobbyRandomAdjSk8;

  /// No description provided for @lobbyRandomNounSk1.
  ///
  /// In en, this message translates to:
  /// **'Pirate Ship'**
  String get lobbyRandomNounSk1;

  /// No description provided for @lobbyRandomNounSk2.
  ///
  /// In en, this message translates to:
  /// **'Treasure Island'**
  String get lobbyRandomNounSk2;

  /// No description provided for @lobbyRandomNounSk3.
  ///
  /// In en, this message translates to:
  /// **'Voyage'**
  String get lobbyRandomNounSk3;

  /// No description provided for @lobbyRandomNounSk4.
  ///
  /// In en, this message translates to:
  /// **'Plunder'**
  String get lobbyRandomNounSk4;

  /// No description provided for @lobbyRandomNounSk5.
  ///
  /// In en, this message translates to:
  /// **'Captain'**
  String get lobbyRandomNounSk5;

  /// No description provided for @lobbyRandomNounSk6.
  ///
  /// In en, this message translates to:
  /// **'Sea Battle'**
  String get lobbyRandomNounSk6;

  /// No description provided for @lobbyRandomNounSk7.
  ///
  /// In en, this message translates to:
  /// **'Adventure'**
  String get lobbyRandomNounSk7;

  /// No description provided for @lobbyRandomNounSk8.
  ///
  /// In en, this message translates to:
  /// **'Kraken'**
  String get lobbyRandomNounSk8;

  /// No description provided for @skGameRecoveringGame.
  ///
  /// In en, this message translates to:
  /// **'Recovering game...'**
  String get skGameRecoveringGame;

  /// No description provided for @skGameCheckingState.
  ///
  /// In en, this message translates to:
  /// **'Checking game state...'**
  String get skGameCheckingState;

  /// No description provided for @skGameReloadingRoom.
  ///
  /// In en, this message translates to:
  /// **'Reloading room info...'**
  String get skGameReloadingRoom;

  /// No description provided for @skGameLoadingState.
  ///
  /// In en, this message translates to:
  /// **'Loading game state...'**
  String get skGameLoadingState;

  /// No description provided for @skGameSpectatorWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Spectating Skull King Waiting Room'**
  String get skGameSpectatorWaitingTitle;

  /// No description provided for @skGameSpectatorWaitingDesc.
  ///
  /// In en, this message translates to:
  /// **'Viewing the room before the game starts. The spectator screen will load automatically once the game begins.'**
  String get skGameSpectatorWaitingDesc;

  /// No description provided for @skGameHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get skGameHost;

  /// No description provided for @skGameReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get skGameReady;

  /// No description provided for @skGameWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get skGameWaiting;

  /// No description provided for @skGameSpectatorStandby.
  ///
  /// In en, this message translates to:
  /// **'Spectator Standby'**
  String get skGameSpectatorStandby;

  /// No description provided for @skGameSpectatorListTitle.
  ///
  /// In en, this message translates to:
  /// **'Spectator List'**
  String get skGameSpectatorListTitle;

  /// No description provided for @skGameNoSpectators.
  ///
  /// In en, this message translates to:
  /// **'No one is spectating'**
  String get skGameNoSpectators;

  /// No description provided for @skGameAlwaysAccept.
  ///
  /// In en, this message translates to:
  /// **'Always Accept'**
  String get skGameAlwaysAccept;

  /// No description provided for @skGameAlwaysReject.
  ///
  /// In en, this message translates to:
  /// **'Always Reject'**
  String get skGameAlwaysReject;

  /// No description provided for @skGameRoundTrick.
  ///
  /// In en, this message translates to:
  /// **'Round {round} Trick {trick}'**
  String skGameRoundTrick(int round, int trick);

  /// No description provided for @skGameSpectating.
  ///
  /// In en, this message translates to:
  /// **'Spectating'**
  String get skGameSpectating;

  /// No description provided for @skGameBiddingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Bidding in progress · Leader: {name}'**
  String skGameBiddingInProgress(String name);

  /// No description provided for @skGamePlayerTurn.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s turn'**
  String skGamePlayerTurn(String name);

  /// No description provided for @skGameLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave Game'**
  String get skGameLeaveTitle;

  /// No description provided for @skGameLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave the game?'**
  String get skGameLeaveConfirm;

  /// No description provided for @skGameLeaveButton.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get skGameLeaveButton;

  /// No description provided for @skGameLeaderLabel.
  ///
  /// In en, this message translates to:
  /// **'Leader: {name}'**
  String skGameLeaderLabel(String name);

  /// No description provided for @skGameMyTurn.
  ///
  /// In en, this message translates to:
  /// **'My Turn'**
  String get skGameMyTurn;

  /// No description provided for @skGameWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}'**
  String skGameWaitingFor(String name);

  /// No description provided for @skGameSecondsShort.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String skGameSecondsShort(int seconds);

  /// No description provided for @skGameTapToRequestCards.
  ///
  /// In en, this message translates to:
  /// **'Tap a profile above to request to view their hand'**
  String get skGameTapToRequestCards;

  /// No description provided for @skGameRequestingCardView.
  ///
  /// In en, this message translates to:
  /// **'Requesting to view {name}\'s hand...'**
  String skGameRequestingCardView(String name);

  /// No description provided for @skGamePlayerHand.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s hand'**
  String skGamePlayerHand(String name);

  /// No description provided for @skGameNoCards.
  ///
  /// In en, this message translates to:
  /// **'No cards'**
  String get skGameNoCards;

  /// No description provided for @skGameCardViewRejected.
  ///
  /// In en, this message translates to:
  /// **'{name} declined the request. Tap another player.'**
  String skGameCardViewRejected(String name);

  /// No description provided for @skGameTimeout.
  ///
  /// In en, this message translates to:
  /// **'{name} timed out!'**
  String skGameTimeout(String name);

  /// No description provided for @skGameDesertionTimeout.
  ///
  /// In en, this message translates to:
  /// **'{name} deserted! (3 timeouts)'**
  String skGameDesertionTimeout(String name);

  /// No description provided for @skGameDesertionLeave.
  ///
  /// In en, this message translates to:
  /// **'{name} left the game'**
  String skGameDesertionLeave(String name);

  /// No description provided for @skGameCardViewRequest.
  ///
  /// In en, this message translates to:
  /// **'{name} is requesting to view your hand'**
  String skGameCardViewRequest(String name);

  /// No description provided for @skGameReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get skGameReject;

  /// No description provided for @skGameAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get skGameAllow;

  /// No description provided for @skGameChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get skGameChat;

  /// No description provided for @skGameMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get skGameMessageHint;

  /// No description provided for @skGameViewingMyHand.
  ///
  /// In en, this message translates to:
  /// **'Viewing my hand'**
  String get skGameViewingMyHand;

  /// No description provided for @skGameNoViewers.
  ///
  /// In en, this message translates to:
  /// **'No one is watching'**
  String get skGameNoViewers;

  /// No description provided for @skGameViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get skGameViewProfile;

  /// No description provided for @skGameBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get skGameBlock;

  /// No description provided for @skGameUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get skGameUnblock;

  /// No description provided for @skGameScoreHistory.
  ///
  /// In en, this message translates to:
  /// **'Score History'**
  String get skGameScoreHistory;

  /// No description provided for @skGameBiddingPhase.
  ///
  /// In en, this message translates to:
  /// **'Bidding...'**
  String get skGameBiddingPhase;

  /// No description provided for @skGamePlayCard.
  ///
  /// In en, this message translates to:
  /// **'Play a card'**
  String get skGamePlayCard;

  /// No description provided for @skGameKrakenActivated.
  ///
  /// In en, this message translates to:
  /// **'🐙 Kraken activated'**
  String get skGameKrakenActivated;

  /// No description provided for @skGameWhiteWhaleActivated.
  ///
  /// In en, this message translates to:
  /// **'🐋 White Whale activated'**
  String get skGameWhiteWhaleActivated;

  /// No description provided for @skGameWhiteWhaleNullify.
  ///
  /// In en, this message translates to:
  /// **'🐋 White Whale · Special cards nullified'**
  String get skGameWhiteWhaleNullify;

  /// No description provided for @skGameTrickVoided.
  ///
  /// In en, this message translates to:
  /// **'Trick Voided'**
  String get skGameTrickVoided;

  /// No description provided for @skGameLeadPlayer.
  ///
  /// In en, this message translates to:
  /// **'{name} leads next'**
  String skGameLeadPlayer(String name);

  /// No description provided for @skGameTrickWinner.
  ///
  /// In en, this message translates to:
  /// **'{name} wins'**
  String skGameTrickWinner(String name);

  /// No description provided for @skGameCheckingCards.
  ///
  /// In en, this message translates to:
  /// **'Checking cards...'**
  String get skGameCheckingCards;

  /// No description provided for @skGameBonusWithLoot.
  ///
  /// In en, this message translates to:
  /// **'Bonus +{bonus} (💰 +{loot})'**
  String skGameBonusWithLoot(int bonus, int loot);

  /// No description provided for @skGameBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus +{bonus}'**
  String skGameBonus(int bonus);

  /// No description provided for @skGameBidDone.
  ///
  /// In en, this message translates to:
  /// **'Bid: {bid} wins'**
  String skGameBidDone(int bid);

  /// No description provided for @skGameWaitingOthers.
  ///
  /// In en, this message translates to:
  /// **'Waiting for other players...'**
  String get skGameWaitingOthers;

  /// No description provided for @skGameBidPrompt.
  ///
  /// In en, this message translates to:
  /// **'Predict how many tricks you will win this round'**
  String get skGameBidPrompt;

  /// No description provided for @skGameBidSubmit.
  ///
  /// In en, this message translates to:
  /// **'Bid {bid} wins'**
  String skGameBidSubmit(int bid);

  /// No description provided for @skGameSelectNumber.
  ///
  /// In en, this message translates to:
  /// **'Select a number'**
  String get skGameSelectNumber;

  /// No description provided for @skGamePlayCardButton.
  ///
  /// In en, this message translates to:
  /// **'Play Card'**
  String get skGamePlayCardButton;

  /// No description provided for @skGameSelectCard.
  ///
  /// In en, this message translates to:
  /// **'Select a card'**
  String get skGameSelectCard;

  /// No description provided for @skGameReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get skGameReset;

  /// No description provided for @skGameTigressEscape.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get skGameTigressEscape;

  /// No description provided for @skGameTigressPirate.
  ///
  /// In en, this message translates to:
  /// **'Pirate'**
  String get skGameTigressPirate;

  /// No description provided for @skGameRoundResult.
  ///
  /// In en, this message translates to:
  /// **'Round {round} Results'**
  String skGameRoundResult(int round);

  /// No description provided for @skGameBidTricks.
  ///
  /// In en, this message translates to:
  /// **'Bid/Won'**
  String get skGameBidTricks;

  /// No description provided for @skGameBonusHeader.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get skGameBonusHeader;

  /// No description provided for @skGameScoreHeader.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get skGameScoreHeader;

  /// No description provided for @skGameNextRoundPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing next round...'**
  String get skGameNextRoundPreparing;

  /// No description provided for @skGameGameOver.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get skGameGameOver;

  /// No description provided for @skGameAutoReturnCountdown.
  ///
  /// In en, this message translates to:
  /// **'Returning to waiting room in {seconds}s'**
  String skGameAutoReturnCountdown(int seconds);

  /// No description provided for @skGameReturningToRoom.
  ///
  /// In en, this message translates to:
  /// **'Returning to waiting room...'**
  String get skGameReturningToRoom;

  /// No description provided for @skGamePlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'Player Profile'**
  String get skGamePlayerProfile;

  /// No description provided for @skGameAlreadyFriend.
  ///
  /// In en, this message translates to:
  /// **'Already friends'**
  String get skGameAlreadyFriend;

  /// No description provided for @skGameRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get skGameRequestPending;

  /// No description provided for @skGameAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get skGameAddFriend;

  /// No description provided for @skGameFriendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent'**
  String get skGameFriendRequestSent;

  /// No description provided for @skGameBlockUser.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get skGameBlockUser;

  /// No description provided for @skGameUnblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get skGameUnblockUser;

  /// No description provided for @skGameUserBlocked.
  ///
  /// In en, this message translates to:
  /// **'User has been blocked'**
  String get skGameUserBlocked;

  /// No description provided for @skGameUserUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User has been unblocked'**
  String get skGameUserUnblocked;

  /// No description provided for @skGameProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Profile not found'**
  String get skGameProfileNotFound;

  /// No description provided for @skGameTichuRecord.
  ///
  /// In en, this message translates to:
  /// **'Tichu Record'**
  String get skGameTichuRecord;

  /// No description provided for @skGameSkullKingRecord.
  ///
  /// In en, this message translates to:
  /// **'Skull King Record'**
  String get skGameSkullKingRecord;

  /// No description provided for @skGameLoveLetterRecord.
  ///
  /// In en, this message translates to:
  /// **'Love Letter Record'**
  String get skGameLoveLetterRecord;

  /// No description provided for @skGameStatRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get skGameStatRecord;

  /// No description provided for @skGameStatWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win Rate'**
  String get skGameStatWinRate;

  /// No description provided for @skGameRecordFormat.
  ///
  /// In en, this message translates to:
  /// **'{games}G {wins}W {losses}L'**
  String skGameRecordFormat(int games, int wins, int losses);

  /// No description provided for @gameSparrowCall.
  ///
  /// In en, this message translates to:
  /// **'Mahjong Call'**
  String get gameSparrowCall;

  /// No description provided for @gameSelectNumberToCall.
  ///
  /// In en, this message translates to:
  /// **'Select a number to call'**
  String get gameSelectNumberToCall;

  /// No description provided for @gameNoCall.
  ///
  /// In en, this message translates to:
  /// **'No Call'**
  String get gameNoCall;

  /// No description provided for @gameCancelPickAnother.
  ///
  /// In en, this message translates to:
  /// **'Cancel and pick another card'**
  String get gameCancelPickAnother;

  /// No description provided for @gameRestoringGame.
  ///
  /// In en, this message translates to:
  /// **'Restoring game...'**
  String get gameRestoringGame;

  /// No description provided for @gameCheckingState.
  ///
  /// In en, this message translates to:
  /// **'Checking game state...'**
  String get gameCheckingState;

  /// No description provided for @gameRecheckingRoomState.
  ///
  /// In en, this message translates to:
  /// **'Re-checking current room state.'**
  String get gameRecheckingRoomState;

  /// No description provided for @gameReloadingRoom.
  ///
  /// In en, this message translates to:
  /// **'Reloading room info...'**
  String get gameReloadingRoom;

  /// No description provided for @gameWaitForRestore.
  ///
  /// In en, this message translates to:
  /// **'Please wait while restoring to the current game state.'**
  String get gameWaitForRestore;

  /// No description provided for @gamePreparingScreen.
  ///
  /// In en, this message translates to:
  /// **'Preparing game screen...'**
  String get gamePreparingScreen;

  /// No description provided for @gameAdjustingScreen.
  ///
  /// In en, this message translates to:
  /// **'Adjusting screen transition state.'**
  String get gameAdjustingScreen;

  /// No description provided for @gameTransitioningScreen.
  ///
  /// In en, this message translates to:
  /// **'Transitioning game screen...'**
  String get gameTransitioningScreen;

  /// No description provided for @gameRecheckingDestination.
  ///
  /// In en, this message translates to:
  /// **'Re-checking current destination state.'**
  String get gameRecheckingDestination;

  /// No description provided for @gameSoundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound Effects'**
  String get gameSoundEffects;

  /// No description provided for @gameChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get gameChat;

  /// No description provided for @gameMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get gameMessageHint;

  /// No description provided for @gameMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get gameMyProfile;

  /// No description provided for @gamePlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'Player Profile'**
  String get gamePlayerProfile;

  /// No description provided for @gameAlreadyFriend.
  ///
  /// In en, this message translates to:
  /// **'Already friends'**
  String get gameAlreadyFriend;

  /// No description provided for @gameRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get gameRequestPending;

  /// No description provided for @gameAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get gameAddFriend;

  /// No description provided for @gameFriendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent'**
  String get gameFriendRequestSent;

  /// No description provided for @gameUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get gameUnblock;

  /// No description provided for @gameBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get gameBlock;

  /// No description provided for @gameUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User has been unblocked'**
  String get gameUnblocked;

  /// No description provided for @gameBlocked.
  ///
  /// In en, this message translates to:
  /// **'User has been blocked'**
  String get gameBlocked;

  /// No description provided for @gameReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get gameReport;

  /// No description provided for @gameClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get gameClose;

  /// No description provided for @gameProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Profile not found'**
  String get gameProfileNotFound;

  /// No description provided for @gameTichuSeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Tichu Season Ranked'**
  String get gameTichuSeasonRanked;

  /// No description provided for @gameStatRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get gameStatRecord;

  /// No description provided for @gameStatWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win Rate'**
  String get gameStatWinRate;

  /// No description provided for @gameOverallRecord.
  ///
  /// In en, this message translates to:
  /// **'Overall Record'**
  String get gameOverallRecord;

  /// No description provided for @gameRecordFormat.
  ///
  /// In en, this message translates to:
  /// **'{games}G {wins}W {losses}L'**
  String gameRecordFormat(int games, int wins, int losses);

  /// No description provided for @gameMannerGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get gameMannerGood;

  /// No description provided for @gameMannerNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get gameMannerNormal;

  /// No description provided for @gameMannerBad.
  ///
  /// In en, this message translates to:
  /// **'Bad'**
  String get gameMannerBad;

  /// No description provided for @gameMannerVeryBad.
  ///
  /// In en, this message translates to:
  /// **'Very Bad'**
  String get gameMannerVeryBad;

  /// No description provided for @gameMannerWorst.
  ///
  /// In en, this message translates to:
  /// **'Terrible'**
  String get gameMannerWorst;

  /// No description provided for @gameManner.
  ///
  /// In en, this message translates to:
  /// **'Manner {label}'**
  String gameManner(String label);

  /// No description provided for @gameDesertionLabel.
  ///
  /// In en, this message translates to:
  /// **'Desertions'**
  String get gameDesertionLabel;

  /// No description provided for @gameDesertions.
  ///
  /// In en, this message translates to:
  /// **'Desertions {count}'**
  String gameDesertions(int count);

  /// No description provided for @gameRecentMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches'**
  String get gameRecentMatchesTitle;

  /// No description provided for @gameRecentMatchesDesc.
  ///
  /// In en, this message translates to:
  /// **'View results of the last {count} matches.'**
  String gameRecentMatchesDesc(int count);

  /// No description provided for @gameRecentMatchesThree.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches (3)'**
  String get gameRecentMatchesThree;

  /// No description provided for @gameSeeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get gameSeeMore;

  /// No description provided for @gameNoRecentMatches.
  ///
  /// In en, this message translates to:
  /// **'No recent matches'**
  String get gameNoRecentMatches;

  /// No description provided for @gameMatchDesertion.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get gameMatchDesertion;

  /// No description provided for @gameMatchDraw.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get gameMatchDraw;

  /// No description provided for @gameMatchWin.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get gameMatchWin;

  /// No description provided for @gameMatchLoss.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get gameMatchLoss;

  /// No description provided for @gameMatchTypeRanked.
  ///
  /// In en, this message translates to:
  /// **'Ranked'**
  String get gameMatchTypeRanked;

  /// No description provided for @gameMatchTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get gameMatchTypeNormal;

  /// No description provided for @gameViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get gameViewProfile;

  /// No description provided for @gameCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gameCancel;

  /// No description provided for @gameReportReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse/Insults'**
  String get gameReportReasonAbuse;

  /// No description provided for @gameReportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam/Flooding'**
  String get gameReportReasonSpam;

  /// No description provided for @gameReportReasonNickname.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate Nickname'**
  String get gameReportReasonNickname;

  /// No description provided for @gameReportReasonGameplay.
  ///
  /// In en, this message translates to:
  /// **'Gameplay Disruption'**
  String get gameReportReasonGameplay;

  /// No description provided for @gameReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get gameReportReasonOther;

  /// No description provided for @gameReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report {nickname}'**
  String gameReportTitle(String nickname);

  /// No description provided for @gameReportWarning.
  ///
  /// In en, this message translates to:
  /// **'Reports are reviewed by the moderation team.\nFalse reports may result in penalties.'**
  String get gameReportWarning;

  /// No description provided for @gameSelectReason.
  ///
  /// In en, this message translates to:
  /// **'Select Reason'**
  String get gameSelectReason;

  /// No description provided for @gameReportDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter details (optional)'**
  String get gameReportDetailHint;

  /// No description provided for @gameReportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get gameReportSubmit;

  /// No description provided for @gameLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave Game'**
  String get gameLeaveTitle;

  /// No description provided for @gameLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave?\nLeaving mid-game harms your team.'**
  String get gameLeaveConfirm;

  /// No description provided for @gameLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get gameLeave;

  /// No description provided for @gameCallError.
  ///
  /// In en, this message translates to:
  /// **'You must play the called number first!'**
  String get gameCallError;

  /// No description provided for @gameTimeout.
  ///
  /// In en, this message translates to:
  /// **'{playerName} timed out!'**
  String gameTimeout(String playerName);

  /// No description provided for @gameDesertionTimeout.
  ///
  /// In en, this message translates to:
  /// **'{playerName} deserted! (3 timeouts)'**
  String gameDesertionTimeout(String playerName);

  /// No description provided for @gameDesertionLeave.
  ///
  /// In en, this message translates to:
  /// **'{playerName} has left the game'**
  String gameDesertionLeave(String playerName);

  /// No description provided for @gameSpectator.
  ///
  /// In en, this message translates to:
  /// **'Spectator'**
  String get gameSpectator;

  /// No description provided for @gameCardViewRequest.
  ///
  /// In en, this message translates to:
  /// **'{nickname} is requesting to view your cards'**
  String gameCardViewRequest(String nickname);

  /// No description provided for @gameReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get gameReject;

  /// No description provided for @gameAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get gameAllow;

  /// No description provided for @gameAlwaysReject.
  ///
  /// In en, this message translates to:
  /// **'Always Reject'**
  String get gameAlwaysReject;

  /// No description provided for @gameAlwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Always Allow'**
  String get gameAlwaysAllow;

  /// No description provided for @gameSpectatorList.
  ///
  /// In en, this message translates to:
  /// **'Spectator List'**
  String get gameSpectatorList;

  /// No description provided for @gameNoSpectators.
  ///
  /// In en, this message translates to:
  /// **'No one is spectating'**
  String get gameNoSpectators;

  /// No description provided for @gameViewingMyCards.
  ///
  /// In en, this message translates to:
  /// **'Viewing my cards'**
  String get gameViewingMyCards;

  /// No description provided for @gameNoViewers.
  ///
  /// In en, this message translates to:
  /// **'No one is viewing'**
  String get gameNoViewers;

  /// No description provided for @gamePartner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get gamePartner;

  /// No description provided for @gameLeftPlayer.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get gameLeftPlayer;

  /// No description provided for @gameRightPlayer.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get gameRightPlayer;

  /// No description provided for @gameMyTurn.
  ///
  /// In en, this message translates to:
  /// **'My Turn!'**
  String get gameMyTurn;

  /// No description provided for @gamePlayerTurn.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s turn'**
  String gamePlayerTurn(String name);

  /// No description provided for @gameCall.
  ///
  /// In en, this message translates to:
  /// **'Call {rank}'**
  String gameCall(String rank);

  /// No description provided for @gameMyTurnShort.
  ///
  /// In en, this message translates to:
  /// **'My Turn'**
  String get gameMyTurnShort;

  /// No description provided for @gamePlayerTurnShort.
  ///
  /// In en, this message translates to:
  /// **'{name} Turn'**
  String gamePlayerTurnShort(String name);

  /// No description provided for @gamePlayerWaiting.
  ///
  /// In en, this message translates to:
  /// **'{name} Waiting'**
  String gamePlayerWaiting(String name);

  /// No description provided for @gameTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'{turnLabel} {seconds}s'**
  String gameTimerLabel(String turnLabel, int seconds);

  /// No description provided for @gameScoreHistory.
  ///
  /// In en, this message translates to:
  /// **'Score History'**
  String get gameScoreHistory;

  /// No description provided for @gameScoreHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Round-by-round scores and current totals'**
  String get gameScoreHistorySubtitle;

  /// No description provided for @gameNoCompletedRounds.
  ///
  /// In en, this message translates to:
  /// **'No completed rounds yet'**
  String get gameNoCompletedRounds;

  /// No description provided for @gameTeamLabel.
  ///
  /// In en, this message translates to:
  /// **'Team {label}'**
  String gameTeamLabel(String label);

  /// No description provided for @gameDogPlayedBy.
  ///
  /// In en, this message translates to:
  /// **'{name} played the Dog'**
  String gameDogPlayedBy(String name);

  /// No description provided for @gameDogPlayed.
  ///
  /// In en, this message translates to:
  /// **'The Dog was played'**
  String get gameDogPlayed;

  /// No description provided for @gamePlayedCards.
  ///
  /// In en, this message translates to:
  /// **'\'s play'**
  String get gamePlayedCards;

  /// No description provided for @gamePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get gamePlay;

  /// No description provided for @gamePass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get gamePass;

  /// No description provided for @gameLargeTichuQuestion.
  ///
  /// In en, this message translates to:
  /// **'Large Tichu?'**
  String get gameLargeTichuQuestion;

  /// No description provided for @gameDeclare.
  ///
  /// In en, this message translates to:
  /// **'Declare!'**
  String get gameDeclare;

  /// No description provided for @gameSmallTichuDeclare.
  ///
  /// In en, this message translates to:
  /// **'Declare Small Tichu'**
  String get gameSmallTichuDeclare;

  /// No description provided for @gameSmallTichuConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Declare Small Tichu'**
  String get gameSmallTichuConfirmTitle;

  /// No description provided for @gameSmallTichuConfirmContent.
  ///
  /// In en, this message translates to:
  /// **'Declare Small Tichu?\n+100 points on success, -100 on failure'**
  String get gameSmallTichuConfirmContent;

  /// No description provided for @gameDeclareButton.
  ///
  /// In en, this message translates to:
  /// **'Declare'**
  String get gameDeclareButton;

  /// No description provided for @gameSelectRecipient.
  ///
  /// In en, this message translates to:
  /// **'Select who to give card to'**
  String get gameSelectRecipient;

  /// No description provided for @gameSelectExchangeCard.
  ///
  /// In en, this message translates to:
  /// **'Select card to exchange ({count}/3)'**
  String gameSelectExchangeCard(int count);

  /// No description provided for @gameReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get gameReset;

  /// No description provided for @gameExchangeComplete.
  ///
  /// In en, this message translates to:
  /// **'Exchange Done'**
  String get gameExchangeComplete;

  /// No description provided for @gameDragonQuestion.
  ///
  /// In en, this message translates to:
  /// **'Who would you like to give the Dragon trick to?'**
  String get gameDragonQuestion;

  /// No description provided for @gameSelectCallRank.
  ///
  /// In en, this message translates to:
  /// **'Select a number to call'**
  String get gameSelectCallRank;

  /// No description provided for @gameGameEnd.
  ///
  /// In en, this message translates to:
  /// **'Game Over!'**
  String get gameGameEnd;

  /// No description provided for @gameRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round Over!'**
  String get gameRoundEnd;

  /// No description provided for @gameMyTeamWin.
  ///
  /// In en, this message translates to:
  /// **'Our Team Wins!'**
  String get gameMyTeamWin;

  /// No description provided for @gameEnemyTeamWin.
  ///
  /// In en, this message translates to:
  /// **'Opponent Wins!'**
  String get gameEnemyTeamWin;

  /// No description provided for @gameDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw!'**
  String get gameDraw;

  /// No description provided for @gameThisRound.
  ///
  /// In en, this message translates to:
  /// **'This round: '**
  String get gameThisRound;

  /// No description provided for @gameTotalScore.
  ///
  /// In en, this message translates to:
  /// **'Total: '**
  String get gameTotalScore;

  /// No description provided for @gameAutoReturnLobby.
  ///
  /// In en, this message translates to:
  /// **'Returning to lobby in 3 seconds...'**
  String get gameAutoReturnLobby;

  /// No description provided for @gameAutoNextRound.
  ///
  /// In en, this message translates to:
  /// **'Auto-continuing in 3 seconds...'**
  String get gameAutoNextRound;

  /// No description provided for @gameRankedScore.
  ///
  /// In en, this message translates to:
  /// **'Ranked Score {score}'**
  String gameRankedScore(int score);

  /// No description provided for @gameRankDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get gameRankDiamond;

  /// No description provided for @gameRankGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get gameRankGold;

  /// No description provided for @gameRankSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get gameRankSilver;

  /// No description provided for @gameRankBronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get gameRankBronze;

  /// No description provided for @gameFinishPosition.
  ///
  /// In en, this message translates to:
  /// **'Place {position}!'**
  String gameFinishPosition(int position);

  /// No description provided for @gameCardCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cards'**
  String gameCardCount(int count);

  /// No description provided for @gamePhaseLargeTichu.
  ///
  /// In en, this message translates to:
  /// **'Large Tichu Declaration'**
  String get gamePhaseLargeTichu;

  /// No description provided for @gamePhaseDealing.
  ///
  /// In en, this message translates to:
  /// **'Dealing Cards'**
  String get gamePhaseDealing;

  /// No description provided for @gamePhaseExchange.
  ///
  /// In en, this message translates to:
  /// **'Card Exchange'**
  String get gamePhaseExchange;

  /// No description provided for @gamePhasePlaying.
  ///
  /// In en, this message translates to:
  /// **'Game in Progress'**
  String get gamePhasePlaying;

  /// No description provided for @gamePhaseRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round Over'**
  String get gamePhaseRoundEnd;

  /// No description provided for @gamePhaseGameEnd.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get gamePhaseGameEnd;

  /// No description provided for @gameReceivedCards.
  ///
  /// In en, this message translates to:
  /// **'Received Cards'**
  String get gameReceivedCards;

  /// No description provided for @gameBadgeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get gameBadgeLarge;

  /// No description provided for @gameBadgeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get gameBadgeSmall;

  /// No description provided for @gameNotAfk.
  ///
  /// In en, this message translates to:
  /// **'Not AFK'**
  String get gameNotAfk;

  /// No description provided for @spectatorRecovering.
  ///
  /// In en, this message translates to:
  /// **'Recovering spectator view...'**
  String get spectatorRecovering;

  /// No description provided for @spectatorTransitioning.
  ///
  /// In en, this message translates to:
  /// **'Transitioning spectator view...'**
  String get spectatorTransitioning;

  /// No description provided for @spectatorRecheckingState.
  ///
  /// In en, this message translates to:
  /// **'Rechecking current spectator state.'**
  String get spectatorRecheckingState;

  /// No description provided for @spectatorWatching.
  ///
  /// In en, this message translates to:
  /// **'Spectating'**
  String get spectatorWatching;

  /// No description provided for @spectatorWaitingForGame.
  ///
  /// In en, this message translates to:
  /// **'Waiting for game to start...'**
  String get spectatorWaitingForGame;

  /// No description provided for @spectatorSit.
  ///
  /// In en, this message translates to:
  /// **'Sit'**
  String get spectatorSit;

  /// No description provided for @spectatorHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get spectatorHost;

  /// No description provided for @spectatorReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get spectatorReady;

  /// No description provided for @spectatorWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get spectatorWaiting;

  /// No description provided for @spectatorTeamWin.
  ///
  /// In en, this message translates to:
  /// **'Team {team} wins!'**
  String spectatorTeamWin(String team);

  /// No description provided for @spectatorDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw!'**
  String get spectatorDraw;

  /// No description provided for @spectatorTeamScores.
  ///
  /// In en, this message translates to:
  /// **'Team A: {scoreA} | Team B: {scoreB}'**
  String spectatorTeamScores(int scoreA, int scoreB);

  /// No description provided for @spectatorAutoReturn.
  ///
  /// In en, this message translates to:
  /// **'Moving to waiting room in 3s...'**
  String get spectatorAutoReturn;

  /// No description provided for @spectatorPhaseLargeTichu.
  ///
  /// In en, this message translates to:
  /// **'Large Tichu'**
  String get spectatorPhaseLargeTichu;

  /// No description provided for @spectatorPhaseCardExchange.
  ///
  /// In en, this message translates to:
  /// **'Card Exchange'**
  String get spectatorPhaseCardExchange;

  /// No description provided for @spectatorPhasePlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get spectatorPhasePlaying;

  /// No description provided for @spectatorPhaseRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round Over'**
  String get spectatorPhaseRoundEnd;

  /// No description provided for @spectatorPhaseGameEnd.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get spectatorPhaseGameEnd;

  /// No description provided for @spectatorFinished.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get spectatorFinished;

  /// No description provided for @spectatorRequesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting... ({count} cards)'**
  String spectatorRequesting(int count);

  /// No description provided for @spectatorRequestCardView.
  ///
  /// In en, this message translates to:
  /// **'View hand ({count} cards)'**
  String spectatorRequestCardView(int count);

  /// No description provided for @spectatorSoundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound Effects'**
  String get spectatorSoundEffects;

  /// No description provided for @spectatorListTitle.
  ///
  /// In en, this message translates to:
  /// **'Spectator List'**
  String get spectatorListTitle;

  /// No description provided for @spectatorNoSpectators.
  ///
  /// In en, this message translates to:
  /// **'No spectators'**
  String get spectatorNoSpectators;

  /// No description provided for @spectatorClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get spectatorClose;

  /// No description provided for @spectatorChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get spectatorChat;

  /// No description provided for @spectatorMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get spectatorMessageHint;

  /// No description provided for @spectatorNewTrick.
  ///
  /// In en, this message translates to:
  /// **'New trick'**
  String get spectatorNewTrick;

  /// No description provided for @spectatorPlayedCards.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s play'**
  String spectatorPlayedCards(String name);

  /// No description provided for @rulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Rules'**
  String get rulesTitle;

  /// No description provided for @rulesTabTichu.
  ///
  /// In en, this message translates to:
  /// **'Tichu'**
  String get rulesTabTichu;

  /// No description provided for @rulesTabSkullKing.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get rulesTabSkullKing;

  /// No description provided for @rulesTabLoveLetter.
  ///
  /// In en, this message translates to:
  /// **'Love Letter'**
  String get rulesTabLoveLetter;

  /// No description provided for @rulesTichuGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Objective'**
  String get rulesTichuGoalTitle;

  /// No description provided for @rulesTichuGoalBody.
  ///
  /// In en, this message translates to:
  /// **'A trick-taking game for 4 players in 2 teams (partners sit across from each other). The first team to reach the target score wins.'**
  String get rulesTichuGoalBody;

  /// No description provided for @rulesTichuCardCompositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Composition (56 cards total)'**
  String get rulesTichuCardCompositionTitle;

  /// No description provided for @rulesTichuNumberCards.
  ///
  /// In en, this message translates to:
  /// **'Number Cards (2 – A)'**
  String get rulesTichuNumberCards;

  /// No description provided for @rulesTichuNumberCardsSub.
  ///
  /// In en, this message translates to:
  /// **'4 suits × 13 cards'**
  String get rulesTichuNumberCardsSub;

  /// No description provided for @rulesTichuMahjong.
  ///
  /// In en, this message translates to:
  /// **'Mahjong'**
  String get rulesTichuMahjong;

  /// No description provided for @rulesTichuMahjongSub.
  ///
  /// In en, this message translates to:
  /// **'Card that starts the game'**
  String get rulesTichuMahjongSub;

  /// No description provided for @rulesTichuDog.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get rulesTichuDog;

  /// No description provided for @rulesTichuDogSub.
  ///
  /// In en, this message translates to:
  /// **'Passes the lead to your partner'**
  String get rulesTichuDogSub;

  /// No description provided for @rulesTichuPhoenix.
  ///
  /// In en, this message translates to:
  /// **'Phoenix'**
  String get rulesTichuPhoenix;

  /// No description provided for @rulesTichuPhoenixSub.
  ///
  /// In en, this message translates to:
  /// **'Wild card (-25 points)'**
  String get rulesTichuPhoenixSub;

  /// No description provided for @rulesTichuDragon.
  ///
  /// In en, this message translates to:
  /// **'Dragon'**
  String get rulesTichuDragon;

  /// No description provided for @rulesTichuDragonSub.
  ///
  /// In en, this message translates to:
  /// **'Strongest card (+25 points)'**
  String get rulesTichuDragonSub;

  /// No description provided for @rulesTichuSpecialTitle.
  ///
  /// In en, this message translates to:
  /// **'Special Card Rules'**
  String get rulesTichuSpecialTitle;

  /// No description provided for @rulesTichuSpecialMahjongTitle.
  ///
  /// In en, this message translates to:
  /// **'Mahjong'**
  String get rulesTichuSpecialMahjongTitle;

  /// No description provided for @rulesTichuSpecialMahjongLine1.
  ///
  /// In en, this message translates to:
  /// **'The player holding this card leads the very first trick.'**
  String get rulesTichuSpecialMahjongLine1;

  /// No description provided for @rulesTichuSpecialMahjongLine2.
  ///
  /// In en, this message translates to:
  /// **'When playing the Mahjong, you may declare a number (2–14). The next player must include that number in their combination if they have it (ignored if they don\'t).'**
  String get rulesTichuSpecialMahjongLine2;

  /// No description provided for @rulesTichuSpecialDogTitle.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get rulesTichuSpecialDogTitle;

  /// No description provided for @rulesTichuSpecialDogLine1.
  ///
  /// In en, this message translates to:
  /// **'Can only be played when leading. Immediately passes the lead to your partner.'**
  String get rulesTichuSpecialDogLine1;

  /// No description provided for @rulesTichuSpecialDogLine2.
  ///
  /// In en, this message translates to:
  /// **'Worth 0 points in scoring.'**
  String get rulesTichuSpecialDogLine2;

  /// No description provided for @rulesTichuSpecialPhoenixTitle.
  ///
  /// In en, this message translates to:
  /// **'Phoenix'**
  String get rulesTichuSpecialPhoenixTitle;

  /// No description provided for @rulesTichuSpecialPhoenixLine1.
  ///
  /// In en, this message translates to:
  /// **'When played as a single, it counts as the previous card\'s value + 0.5. However, it cannot beat the Dragon.'**
  String get rulesTichuSpecialPhoenixLine1;

  /// No description provided for @rulesTichuSpecialPhoenixLine2.
  ///
  /// In en, this message translates to:
  /// **'In combinations (Pair/Triple/Full House/Straight, etc.) it can substitute for any number.'**
  String get rulesTichuSpecialPhoenixLine2;

  /// No description provided for @rulesTichuSpecialPhoenixLine3.
  ///
  /// In en, this message translates to:
  /// **'Worth -25 points, so taking it is a disadvantage.'**
  String get rulesTichuSpecialPhoenixLine3;

  /// No description provided for @rulesTichuSpecialDragonTitle.
  ///
  /// In en, this message translates to:
  /// **'Dragon'**
  String get rulesTichuSpecialDragonTitle;

  /// No description provided for @rulesTichuSpecialDragonLine1.
  ///
  /// In en, this message translates to:
  /// **'The strongest card; can only be played as a single.'**
  String get rulesTichuSpecialDragonLine1;

  /// No description provided for @rulesTichuSpecialDragonLine2.
  ///
  /// In en, this message translates to:
  /// **'Worth +25 points, but the trick won with the Dragon must be given to one opponent.'**
  String get rulesTichuSpecialDragonLine2;

  /// No description provided for @rulesTichuDeclarationTitle.
  ///
  /// In en, this message translates to:
  /// **'Tichu Declaration'**
  String get rulesTichuDeclarationTitle;

  /// No description provided for @rulesTichuDeclarationBody.
  ///
  /// In en, this message translates to:
  /// **'A Tichu declaration is a bet that you will be the first to empty your hand this round. Success earns bonus points for your team; failure deducts points.'**
  String get rulesTichuDeclarationBody;

  /// No description provided for @rulesTichuLargeTichu.
  ///
  /// In en, this message translates to:
  /// **'Large Tichu'**
  String get rulesTichuLargeTichu;

  /// No description provided for @rulesTichuLargeTichuWhen.
  ///
  /// In en, this message translates to:
  /// **'Declared after receiving only the first 8 cards (before seeing the remaining 6)'**
  String get rulesTichuLargeTichuWhen;

  /// No description provided for @rulesTichuSmallTichu.
  ///
  /// In en, this message translates to:
  /// **'Small Tichu'**
  String get rulesTichuSmallTichu;

  /// No description provided for @rulesTichuSmallTichuWhen.
  ///
  /// In en, this message translates to:
  /// **'Declared after receiving all 14 cards, but before playing any card'**
  String get rulesTichuSmallTichuWhen;

  /// No description provided for @rulesTichuDeclSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success {points}'**
  String rulesTichuDeclSuccess(String points);

  /// No description provided for @rulesTichuDeclFail.
  ///
  /// In en, this message translates to:
  /// **'Fail {points}'**
  String rulesTichuDeclFail(String points);

  /// No description provided for @rulesTichuFlowTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn Sequence'**
  String get rulesTichuFlowTitle;

  /// No description provided for @rulesTichuFlowBody.
  ///
  /// In en, this message translates to:
  /// **'1. All players receive 8 cards each.\n2. After viewing 8 cards, you may declare Large Tichu.\n3. The remaining 6 cards are dealt, totaling 14.\n4. Each player passes 1 card to each of the other 3 players.\n5. After the exchange, before playing any card, you may declare Small Tichu.\n6. The player holding the Mahjong leads the first trick.'**
  String get rulesTichuFlowBody;

  /// No description provided for @rulesTichuPlayTitle.
  ///
  /// In en, this message translates to:
  /// **'Play Rules'**
  String get rulesTichuPlayTitle;

  /// No description provided for @rulesTichuPlayBody.
  ///
  /// In en, this message translates to:
  /// **'• You can only play the same type of combination as the leading play, but higher. (e.g., a higher single over a single, a higher pair over a pair)\n• Available combinations:\n   - Single (1 card)\n   - Pair (2 cards of the same number)\n   - Triple (3 cards of the same number)\n   - Full House (Triple + Pair)\n   - Straight (5+ consecutive numbers)\n   - Consecutive Pairs (2+ consecutive pairs = 4+ cards)\n• You may pass on your turn if you cannot or do not want to play.'**
  String get rulesTichuPlayBody;

  /// No description provided for @rulesTichuBombTitle.
  ///
  /// In en, this message translates to:
  /// **'Bomb'**
  String get rulesTichuBombTitle;

  /// No description provided for @rulesTichuBombBody.
  ///
  /// In en, this message translates to:
  /// **'A Bomb can be played at any time, even out of turn, and beats any combination.\n\n• Four-of-a-Kind Bomb: 4 cards of the same number (e.g., 7♠ 7♥ 7♦ 7♣)\n• Straight Flush Bomb: 5+ consecutive cards of the same suit\n\nBomb hierarchy:\n  Straight Flush > Four-of-a-Kind\n  Same type: higher number / longer straight wins'**
  String get rulesTichuBombBody;

  /// No description provided for @rulesTichuScoringTitle.
  ///
  /// In en, this message translates to:
  /// **'Scoring'**
  String get rulesTichuScoringTitle;

  /// No description provided for @rulesTichuScoringBody.
  ///
  /// In en, this message translates to:
  /// **'Card points:\n• 5: 5 points\n• 10, K: 10 points\n• Dragon: +25 points / Phoenix: -25 points\n• All other cards: 0 points\n\nRound settlement:\n• The player who finishes 1st takes all trick points collected by the last-place (4th) player.\n• Cards remaining in the last player\'s hand go to the opposing team.\n• If both partners on one team finish 1st and 2nd (\"Double Victory\"), that round ends immediately — the winning team gets +200 points (no trick point calculation).\n• Tichu declaration success/failure bonuses are added on top.'**
  String get rulesTichuScoringBody;

  /// No description provided for @rulesTichuWinTitle.
  ///
  /// In en, this message translates to:
  /// **'Victory Condition'**
  String get rulesTichuWinTitle;

  /// No description provided for @rulesTichuWinBody.
  ///
  /// In en, this message translates to:
  /// **'The first team to reach the target score (default 1000 points) set when creating the room wins. Ranked games use a fixed target of 1000 points.'**
  String get rulesTichuWinBody;

  /// No description provided for @rulesSkGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Objective'**
  String get rulesSkGoalTitle;

  /// No description provided for @rulesSkGoalBody.
  ///
  /// In en, this message translates to:
  /// **'A trick-taking game for 2–6 players (free-for-all). Over 10 rounds, you must accurately predict the number of tricks you will win each round to score points.'**
  String get rulesSkGoalBody;

  /// No description provided for @rulesSkCardCompositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Composition (67 base cards)'**
  String get rulesSkCardCompositionTitle;

  /// No description provided for @rulesSkNumberCards.
  ///
  /// In en, this message translates to:
  /// **'Number Cards (1 – 13)'**
  String get rulesSkNumberCards;

  /// No description provided for @rulesSkNumberCardsSub.
  ///
  /// In en, this message translates to:
  /// **'4 suits × 13 cards (Yellow / Green / Purple / Black)'**
  String get rulesSkNumberCardsSub;

  /// No description provided for @rulesSkEscape.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get rulesSkEscape;

  /// No description provided for @rulesSkEscapeSub.
  ///
  /// In en, this message translates to:
  /// **'Never wins a trick'**
  String get rulesSkEscapeSub;

  /// No description provided for @rulesSkPirate.
  ///
  /// In en, this message translates to:
  /// **'Pirate'**
  String get rulesSkPirate;

  /// No description provided for @rulesSkPirateSub.
  ///
  /// In en, this message translates to:
  /// **'Beats all number cards'**
  String get rulesSkPirateSub;

  /// No description provided for @rulesSkMermaid.
  ///
  /// In en, this message translates to:
  /// **'Mermaid'**
  String get rulesSkMermaid;

  /// No description provided for @rulesSkMermaidSub.
  ///
  /// In en, this message translates to:
  /// **'Captures Skull King (+50 bonus)'**
  String get rulesSkMermaidSub;

  /// No description provided for @rulesSkSkullKing.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get rulesSkSkullKing;

  /// No description provided for @rulesSkSkullKingSub.
  ///
  /// In en, this message translates to:
  /// **'Beats Pirates (+30 bonus per Pirate)'**
  String get rulesSkSkullKingSub;

  /// No description provided for @rulesSkTigress.
  ///
  /// In en, this message translates to:
  /// **'Tigress'**
  String get rulesSkTigress;

  /// No description provided for @rulesSkTigressSub.
  ///
  /// In en, this message translates to:
  /// **'Choose to play as Pirate or Escape'**
  String get rulesSkTigressSub;

  /// No description provided for @rulesSkIncludedByDefault.
  ///
  /// In en, this message translates to:
  /// **'Included by default'**
  String get rulesSkIncludedByDefault;

  /// No description provided for @rulesSkCardCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cards'**
  String rulesSkCardCount(int count);

  /// No description provided for @rulesSkTrumpTitle.
  ///
  /// In en, this message translates to:
  /// **'Black suit = Trump'**
  String get rulesSkTrumpTitle;

  /// No description provided for @rulesSkTrumpBody.
  ///
  /// In en, this message translates to:
  /// **'Black number cards beat all other suit number cards regardless of number. However, you must follow the lead suit (the suit of the first number card) if you can, and may only play black when you have no cards of the led suit.'**
  String get rulesSkTrumpBody;

  /// No description provided for @rulesSkSpecialTitle.
  ///
  /// In en, this message translates to:
  /// **'Special Card Rules'**
  String get rulesSkSpecialTitle;

  /// No description provided for @rulesSkSpecialEscapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get rulesSkSpecialEscapeTitle;

  /// No description provided for @rulesSkSpecialEscapeLine1.
  ///
  /// In en, this message translates to:
  /// **'Never wins a trick. Can be played at any time regardless of suit following.'**
  String get rulesSkSpecialEscapeLine1;

  /// No description provided for @rulesSkSpecialEscapeLine2.
  ///
  /// In en, this message translates to:
  /// **'If all players play only Escapes, the lead player takes the trick.'**
  String get rulesSkSpecialEscapeLine2;

  /// No description provided for @rulesSkSpecialPirateTitle.
  ///
  /// In en, this message translates to:
  /// **'Pirate'**
  String get rulesSkSpecialPirateTitle;

  /// No description provided for @rulesSkSpecialPirateLine1.
  ///
  /// In en, this message translates to:
  /// **'Beats all number cards (including black trumps). If multiple Pirates appear in one trick, the first one played wins.'**
  String get rulesSkSpecialPirateLine1;

  /// No description provided for @rulesSkSpecialPirateLine2.
  ///
  /// In en, this message translates to:
  /// **'Beats Mermaids but loses to Skull King.'**
  String get rulesSkSpecialPirateLine2;

  /// No description provided for @rulesSkSpecialMermaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mermaid'**
  String get rulesSkSpecialMermaidTitle;

  /// No description provided for @rulesSkSpecialMermaidLine1.
  ///
  /// In en, this message translates to:
  /// **'Loses to Pirates but captures and beats Skull King.'**
  String get rulesSkSpecialMermaidLine1;

  /// No description provided for @rulesSkSpecialMermaidLine2.
  ///
  /// In en, this message translates to:
  /// **'When a Mermaid captures Skull King, the trick winner gets +50 bonus.'**
  String get rulesSkSpecialMermaidLine2;

  /// No description provided for @rulesSkSpecialMermaidLine3.
  ///
  /// In en, this message translates to:
  /// **'If only Mermaids are present (no Pirates/Skull King), they beat number cards.'**
  String get rulesSkSpecialMermaidLine3;

  /// No description provided for @rulesSkSpecialSkullKingTitle.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get rulesSkSpecialSkullKingTitle;

  /// No description provided for @rulesSkSpecialSkullKingLine1.
  ///
  /// In en, this message translates to:
  /// **'Beats Pirates — +30 bonus per Pirate defeated.'**
  String get rulesSkSpecialSkullKingLine1;

  /// No description provided for @rulesSkSpecialSkullKingLine2.
  ///
  /// In en, this message translates to:
  /// **'However, loses to Mermaids (gets captured).'**
  String get rulesSkSpecialSkullKingLine2;

  /// No description provided for @rulesSkSpecialTigressTitle.
  ///
  /// In en, this message translates to:
  /// **'Tigress — 3 cards by default'**
  String get rulesSkSpecialTigressTitle;

  /// No description provided for @rulesSkSpecialTigressLine1.
  ///
  /// In en, this message translates to:
  /// **'When playing, choose either Pirate or Escape.'**
  String get rulesSkSpecialTigressLine1;

  /// No description provided for @rulesSkSpecialTigressLine2.
  ///
  /// In en, this message translates to:
  /// **'Tigress played as Pirate works identically to a Pirate, including the Skull King\'s +30 bonus.'**
  String get rulesSkSpecialTigressLine2;

  /// No description provided for @rulesSkSpecialTigressLine3.
  ///
  /// In en, this message translates to:
  /// **'Tigress played as Escape works identically to an Escape and never wins a trick.'**
  String get rulesSkSpecialTigressLine3;

  /// No description provided for @rulesSkSpecialTigressLine4.
  ///
  /// In en, this message translates to:
  /// **'A Tigress played as Pirate/Escape shows a purple check mark in the top-left corner to distinguish it from regular Pirate/Escape cards.'**
  String get rulesSkSpecialTigressLine4;

  /// No description provided for @rulesSkTigressPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'In-game display example'**
  String get rulesSkTigressPreviewTitle;

  /// No description provided for @rulesSkTigressChoiceEscape.
  ///
  /// In en, this message translates to:
  /// **'Played as Escape'**
  String get rulesSkTigressChoiceEscape;

  /// No description provided for @rulesSkTigressChoicePirate.
  ///
  /// In en, this message translates to:
  /// **'Played as Pirate'**
  String get rulesSkTigressChoicePirate;

  /// No description provided for @rulesSkFlowTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn Sequence'**
  String get rulesSkFlowTitle;

  /// No description provided for @rulesSkFlowBody.
  ///
  /// In en, this message translates to:
  /// **'1. In Round N, each player receives N cards. (Rounds 1–10)\n2. All players simultaneously predict (bid) the number of tricks they will win.\n3. Starting from the lead player, cards are played following suit-following rules.\n4. After each round, scores are calculated based on bid success/failure.'**
  String get rulesSkFlowBody;

  /// No description provided for @rulesSkScoringTitle.
  ///
  /// In en, this message translates to:
  /// **'Scoring'**
  String get rulesSkScoringTitle;

  /// No description provided for @rulesSkScoringBody.
  ///
  /// In en, this message translates to:
  /// **'• Bid 0 success (0 tricks won): +10 × round number\n• Bid 0 failure: -10 × round number\n• Bid N success (exactly N tricks won): +20 × N + bonus\n• Bid N failure: -10 × |difference| (no bonus)\n• Bonuses are only awarded when the bid is exact.'**
  String get rulesSkScoringBody;

  /// No description provided for @rulesSkExample1Title.
  ///
  /// In en, this message translates to:
  /// **'Example 1. Simple bid success'**
  String get rulesSkExample1Title;

  /// No description provided for @rulesSkExample1Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 3 · Bid 2 · 2 tricks won · No bonus'**
  String get rulesSkExample1Setup;

  /// No description provided for @rulesSkExample1Calc.
  ///
  /// In en, this message translates to:
  /// **'20 × 2 = 40'**
  String get rulesSkExample1Calc;

  /// No description provided for @rulesSkExample1Result.
  ///
  /// In en, this message translates to:
  /// **'+40 pts'**
  String get rulesSkExample1Result;

  /// No description provided for @rulesSkExample2Title.
  ///
  /// In en, this message translates to:
  /// **'Example 2. Bid 0 success'**
  String get rulesSkExample2Title;

  /// No description provided for @rulesSkExample2Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 5 · Bid 0 · 0 tricks won'**
  String get rulesSkExample2Setup;

  /// No description provided for @rulesSkExample2Calc.
  ///
  /// In en, this message translates to:
  /// **'10 × 5 = 50'**
  String get rulesSkExample2Calc;

  /// No description provided for @rulesSkExample2Result.
  ///
  /// In en, this message translates to:
  /// **'+50 pts'**
  String get rulesSkExample2Result;

  /// No description provided for @rulesSkExample3Title.
  ///
  /// In en, this message translates to:
  /// **'Example 3. Bid failure'**
  String get rulesSkExample3Title;

  /// No description provided for @rulesSkExample3Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 5 · Bid 3 · 1 trick won (difference 2)'**
  String get rulesSkExample3Setup;

  /// No description provided for @rulesSkExample3Calc.
  ///
  /// In en, this message translates to:
  /// **'-10 × 2 = -20'**
  String get rulesSkExample3Calc;

  /// No description provided for @rulesSkExample3Result.
  ///
  /// In en, this message translates to:
  /// **'-20 pts'**
  String get rulesSkExample3Result;

  /// No description provided for @rulesSkExample4Title.
  ///
  /// In en, this message translates to:
  /// **'Example 4. Skull King captures 2 Pirates'**
  String get rulesSkExample4Title;

  /// No description provided for @rulesSkExample4Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 3 · Bid 2 · 2 tricks won · Bonus +60 (2 Pirates × 30)'**
  String get rulesSkExample4Setup;

  /// No description provided for @rulesSkExample4Calc.
  ///
  /// In en, this message translates to:
  /// **'(20 × 2) + 60 = 100'**
  String get rulesSkExample4Calc;

  /// No description provided for @rulesSkExample4Result.
  ///
  /// In en, this message translates to:
  /// **'+100 pts'**
  String get rulesSkExample4Result;

  /// No description provided for @rulesSkExample5Title.
  ///
  /// In en, this message translates to:
  /// **'Example 5. Mermaid captures Skull King'**
  String get rulesSkExample5Title;

  /// No description provided for @rulesSkExample5Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 4 · Bid 1 · 1 trick won · Bonus +50 (Mermaid × SK)'**
  String get rulesSkExample5Setup;

  /// No description provided for @rulesSkExample5Calc.
  ///
  /// In en, this message translates to:
  /// **'(20 × 1) + 50 = 70'**
  String get rulesSkExample5Calc;

  /// No description provided for @rulesSkExample5Result.
  ///
  /// In en, this message translates to:
  /// **'+70 pts'**
  String get rulesSkExample5Result;

  /// No description provided for @rulesSkExample6Title.
  ///
  /// In en, this message translates to:
  /// **'Example 6. Bid 0 failure (took a trick)'**
  String get rulesSkExample6Title;

  /// No description provided for @rulesSkExample6Setup.
  ///
  /// In en, this message translates to:
  /// **'Round 7 · Bid 0 · 1 trick won'**
  String get rulesSkExample6Setup;

  /// No description provided for @rulesSkExample6Calc.
  ///
  /// In en, this message translates to:
  /// **'-10 × 7 = -70'**
  String get rulesSkExample6Calc;

  /// No description provided for @rulesSkExample6Result.
  ///
  /// In en, this message translates to:
  /// **'-70 pts'**
  String get rulesSkExample6Result;

  /// No description provided for @rulesSkWinTitle.
  ///
  /// In en, this message translates to:
  /// **'Victory Condition'**
  String get rulesSkWinTitle;

  /// No description provided for @rulesSkWinBody.
  ///
  /// In en, this message translates to:
  /// **'After all 10 rounds, the player with the highest cumulative score wins.'**
  String get rulesSkWinBody;

  /// No description provided for @rulesSkExpansionTitle.
  ///
  /// In en, this message translates to:
  /// **'Expansions (Optional)'**
  String get rulesSkExpansionTitle;

  /// No description provided for @rulesSkExpansionBody.
  ///
  /// In en, this message translates to:
  /// **'Each expansion can be individually selected when creating a room. Expansion cards are shuffled into the base deck.'**
  String get rulesSkExpansionBody;

  /// No description provided for @rulesSkExpKraken.
  ///
  /// In en, this message translates to:
  /// **'🐙 Kraken'**
  String get rulesSkExpKraken;

  /// No description provided for @rulesSkExpKrakenDesc.
  ///
  /// In en, this message translates to:
  /// **'A trick containing the Kraken is voided. No one wins the trick and no bonuses are awarded. The player who would have won without the Kraken leads the next trick.'**
  String get rulesSkExpKrakenDesc;

  /// No description provided for @rulesSkExpWhiteWhale.
  ///
  /// In en, this message translates to:
  /// **'🐋 White Whale'**
  String get rulesSkExpWhiteWhale;

  /// No description provided for @rulesSkExpWhiteWhaleDesc.
  ///
  /// In en, this message translates to:
  /// **'Neutralizes all special card effects. Only number cards are compared in the trick, and the highest number wins regardless of suit. If no number cards are present, the trick is voided.'**
  String get rulesSkExpWhiteWhaleDesc;

  /// No description provided for @rulesSkExpLoot.
  ///
  /// In en, this message translates to:
  /// **'💰 Loot'**
  String get rulesSkExpLoot;

  /// No description provided for @rulesSkExpLootDesc.
  ///
  /// In en, this message translates to:
  /// **'The trick winner earns +20 bonus per Loot card in the trick, and each player who played a Loot card also earns +20 as their own bonus. (Only awarded on bid success)'**
  String get rulesSkExpLootDesc;

  /// No description provided for @rulesLlGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Objective'**
  String get rulesLlGoalTitle;

  /// No description provided for @rulesLlGoalBody.
  ///
  /// In en, this message translates to:
  /// **'A card game for 2–4 players. Each round, the last player standing or the player with the highest card when the deck runs out wins a token. The first player to collect enough tokens wins the game.'**
  String get rulesLlGoalBody;

  /// No description provided for @rulesLlCardCompositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Composition (16 cards total)'**
  String get rulesLlCardCompositionTitle;

  /// No description provided for @rulesLlGuard.
  ///
  /// In en, this message translates to:
  /// **'Guard'**
  String get rulesLlGuard;

  /// No description provided for @rulesLlGuardSub.
  ///
  /// In en, this message translates to:
  /// **'Guess an opponent\'s card to eliminate them'**
  String get rulesLlGuardSub;

  /// No description provided for @rulesLlSpy.
  ///
  /// In en, this message translates to:
  /// **'Spy'**
  String get rulesLlSpy;

  /// No description provided for @rulesLlSpySub.
  ///
  /// In en, this message translates to:
  /// **'Secretly view an opponent\'s card'**
  String get rulesLlSpySub;

  /// No description provided for @rulesLlBaron.
  ///
  /// In en, this message translates to:
  /// **'Baron'**
  String get rulesLlBaron;

  /// No description provided for @rulesLlBaronSub.
  ///
  /// In en, this message translates to:
  /// **'Compare cards; lower card is eliminated'**
  String get rulesLlBaronSub;

  /// No description provided for @rulesLlHandmaid.
  ///
  /// In en, this message translates to:
  /// **'Handmaid'**
  String get rulesLlHandmaid;

  /// No description provided for @rulesLlHandmaidSub.
  ///
  /// In en, this message translates to:
  /// **'Protected from effects until next turn'**
  String get rulesLlHandmaidSub;

  /// No description provided for @rulesLlPrince.
  ///
  /// In en, this message translates to:
  /// **'Prince'**
  String get rulesLlPrince;

  /// No description provided for @rulesLlPrinceSub.
  ///
  /// In en, this message translates to:
  /// **'Force a player to discard their card'**
  String get rulesLlPrinceSub;

  /// No description provided for @rulesLlKing.
  ///
  /// In en, this message translates to:
  /// **'King'**
  String get rulesLlKing;

  /// No description provided for @rulesLlKingSub.
  ///
  /// In en, this message translates to:
  /// **'Swap cards with another player'**
  String get rulesLlKingSub;

  /// No description provided for @rulesLlCountess.
  ///
  /// In en, this message translates to:
  /// **'Countess'**
  String get rulesLlCountess;

  /// No description provided for @rulesLlCountessSub.
  ///
  /// In en, this message translates to:
  /// **'Must be played if holding King or Prince'**
  String get rulesLlCountessSub;

  /// No description provided for @rulesLlPrincess.
  ///
  /// In en, this message translates to:
  /// **'Princess'**
  String get rulesLlPrincess;

  /// No description provided for @rulesLlPrincessSub.
  ///
  /// In en, this message translates to:
  /// **'Eliminated if played or discarded'**
  String get rulesLlPrincessSub;

  /// No description provided for @rulesLlCardEffectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed Card Effects'**
  String get rulesLlCardEffectsTitle;

  /// No description provided for @rulesLlEffectGuardTitle.
  ///
  /// In en, this message translates to:
  /// **'Guard (1)'**
  String get rulesLlEffectGuardTitle;

  /// No description provided for @rulesLlEffectGuardLine1.
  ///
  /// In en, this message translates to:
  /// **'Name a player and guess a non-Guard card they might hold.'**
  String get rulesLlEffectGuardLine1;

  /// No description provided for @rulesLlEffectGuardLine2.
  ///
  /// In en, this message translates to:
  /// **'If correct, that player is eliminated from the round.'**
  String get rulesLlEffectGuardLine2;

  /// No description provided for @rulesLlEffectSpyTitle.
  ///
  /// In en, this message translates to:
  /// **'Spy (2)'**
  String get rulesLlEffectSpyTitle;

  /// No description provided for @rulesLlEffectSpyLine1.
  ///
  /// In en, this message translates to:
  /// **'Choose a player and secretly look at their hand card.'**
  String get rulesLlEffectSpyLine1;

  /// No description provided for @rulesLlEffectBaronTitle.
  ///
  /// In en, this message translates to:
  /// **'Baron (3)'**
  String get rulesLlEffectBaronTitle;

  /// No description provided for @rulesLlEffectBaronLine1.
  ///
  /// In en, this message translates to:
  /// **'Choose a player and privately compare hand cards.'**
  String get rulesLlEffectBaronLine1;

  /// No description provided for @rulesLlEffectBaronLine2.
  ///
  /// In en, this message translates to:
  /// **'The player with the lower card is eliminated. Ties have no effect.'**
  String get rulesLlEffectBaronLine2;

  /// No description provided for @rulesLlEffectHandmaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Handmaid (4)'**
  String get rulesLlEffectHandmaidTitle;

  /// No description provided for @rulesLlEffectHandmaidLine1.
  ///
  /// In en, this message translates to:
  /// **'Until your next turn, you cannot be chosen as the target of any card effect.'**
  String get rulesLlEffectHandmaidLine1;

  /// No description provided for @rulesLlEffectPrinceTitle.
  ///
  /// In en, this message translates to:
  /// **'Prince (5)'**
  String get rulesLlEffectPrinceTitle;

  /// No description provided for @rulesLlEffectPrinceLine1.
  ///
  /// In en, this message translates to:
  /// **'Choose any player (including yourself) to discard their hand and draw a new card.'**
  String get rulesLlEffectPrinceLine1;

  /// No description provided for @rulesLlEffectPrinceLine2.
  ///
  /// In en, this message translates to:
  /// **'If they discard the Princess, they are eliminated.'**
  String get rulesLlEffectPrinceLine2;

  /// No description provided for @rulesLlEffectKingTitle.
  ///
  /// In en, this message translates to:
  /// **'King (6)'**
  String get rulesLlEffectKingTitle;

  /// No description provided for @rulesLlEffectKingLine1.
  ///
  /// In en, this message translates to:
  /// **'Choose a player and swap hand cards with them.'**
  String get rulesLlEffectKingLine1;

  /// No description provided for @rulesLlEffectCountessTitle.
  ///
  /// In en, this message translates to:
  /// **'Countess (7)'**
  String get rulesLlEffectCountessTitle;

  /// No description provided for @rulesLlEffectCountessLine1.
  ///
  /// In en, this message translates to:
  /// **'If you hold the King (6) or Prince (5) with the Countess, you must play the Countess.'**
  String get rulesLlEffectCountessLine1;

  /// No description provided for @rulesLlEffectCountessLine2.
  ///
  /// In en, this message translates to:
  /// **'Otherwise, it can be freely played and has no effect.'**
  String get rulesLlEffectCountessLine2;

  /// No description provided for @rulesLlEffectPrincessTitle.
  ///
  /// In en, this message translates to:
  /// **'Princess (8)'**
  String get rulesLlEffectPrincessTitle;

  /// No description provided for @rulesLlEffectPrincessLine1.
  ///
  /// In en, this message translates to:
  /// **'If this card is played or discarded for any reason, you are immediately eliminated.'**
  String get rulesLlEffectPrincessLine1;

  /// No description provided for @rulesLlFlowTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn Sequence'**
  String get rulesLlFlowTitle;

  /// No description provided for @rulesLlFlowBody.
  ///
  /// In en, this message translates to:
  /// **'1. Remove 1 card face-down from the deck. (In a 2-player game, 3 additional cards are removed face-up.)\n2. Deal 1 card to each player.\n3. On your turn, draw 1 card from the deck, then play 1 of your 2 cards and resolve its effect.\n4. After resolving the effect, play passes to the next player.\n5. The round ends when only 1 player remains or the deck is empty.'**
  String get rulesLlFlowBody;

  /// No description provided for @rulesLlWinTitle.
  ///
  /// In en, this message translates to:
  /// **'Victory Condition'**
  String get rulesLlWinTitle;

  /// No description provided for @rulesLlWinBody.
  ///
  /// In en, this message translates to:
  /// **'When the round ends, the surviving player with the highest card (ties broken by total card value) wins a token.\n\nTokens needed to win:\n• 2 players: 4 tokens\n• 3 players: 3 tokens\n• 4 players: 2 tokens'**
  String get rulesLlWinBody;

  /// No description provided for @rulesTabMighty.
  ///
  /// In en, this message translates to:
  /// **'Mighty'**
  String get rulesTabMighty;

  /// No description provided for @rulesMtGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Objective'**
  String get rulesMtGoalTitle;

  /// No description provided for @rulesMtGoalBody.
  ///
  /// In en, this message translates to:
  /// **'A trick-taking card game for 5 or 6 players. One player becomes the declarer and chooses a friend; together they try to win enough point cards to meet the bid. The remaining players form the defence and try to stop them.\n\nWith 6 players the kill-mighty variant applies automatically. If the host locks one seat, the room plays classic 5-player mighty.'**
  String get rulesMtGoalBody;

  /// No description provided for @rulesMtCardCompositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Composition (53 cards)'**
  String get rulesMtCardCompositionTitle;

  /// No description provided for @rulesMtCardCompositionBody.
  ///
  /// In en, this message translates to:
  /// **'Standard 52-card deck (4 suits × 13 ranks: 2–A) plus 1 Joker.\nCard strength order: A > K > Q > J > 10 > 9 > … > 2\nPoint cards: A = 1 pt, K = 1 pt, Q = 1 pt, J = 1 pt, 10 = 1 pt (total 20 pts)\n\n[Deal]\n• 5 players: 10 cards each + 3-card kitty\n• 6 players: 8 cards each + 5-card kitty'**
  String get rulesMtCardCompositionBody;

  /// No description provided for @rulesMtSpecialTitle.
  ///
  /// In en, this message translates to:
  /// **'Special Cards'**
  String get rulesMtSpecialTitle;

  /// No description provided for @rulesMtSpecialMightyTitle.
  ///
  /// In en, this message translates to:
  /// **'Mighty'**
  String get rulesMtSpecialMightyTitle;

  /// No description provided for @rulesMtSpecialMightyLine1.
  ///
  /// In en, this message translates to:
  /// **'The strongest card in the game. Beats everything except the Joker Call.'**
  String get rulesMtSpecialMightyLine1;

  /// No description provided for @rulesMtSpecialMightyLine2.
  ///
  /// In en, this message translates to:
  /// **'By default it is the Spade Ace. If the trump suit is Spades, the Mighty becomes the Diamond Ace instead.'**
  String get rulesMtSpecialMightyLine2;

  /// No description provided for @rulesMtSpecialJokerTitle.
  ///
  /// In en, this message translates to:
  /// **'Joker'**
  String get rulesMtSpecialJokerTitle;

  /// No description provided for @rulesMtSpecialJokerLine1.
  ///
  /// In en, this message translates to:
  /// **'The second-strongest card. Wins any trick unless the Joker Call is played.'**
  String get rulesMtSpecialJokerLine1;

  /// No description provided for @rulesMtSpecialJokerLine2.
  ///
  /// In en, this message translates to:
  /// **'When leading a trick, the Joker player declares which suit others must follow.\nThe Joker loses its power on the first and last tricks.'**
  String get rulesMtSpecialJokerLine2;

  /// No description provided for @rulesMtSpecialJokerCallTitle.
  ///
  /// In en, this message translates to:
  /// **'Joker Call'**
  String get rulesMtSpecialJokerCallTitle;

  /// No description provided for @rulesMtSpecialJokerCallLine1.
  ///
  /// In en, this message translates to:
  /// **'When the designated Joker-Call card (♣3 by default) leads the trick, the Joker loses its power and is treated as the weakest card.'**
  String get rulesMtSpecialJokerCallLine1;

  /// No description provided for @rulesMtSpecialJokerCallLine2.
  ///
  /// In en, this message translates to:
  /// **'If the trump suit is Clubs, the Joker Call becomes ♠3 instead.'**
  String get rulesMtSpecialJokerCallLine2;

  /// No description provided for @rulesMtBiddingTitle.
  ///
  /// In en, this message translates to:
  /// **'Bidding'**
  String get rulesMtBiddingTitle;

  /// No description provided for @rulesMtBiddingBody.
  ///
  /// In en, this message translates to:
  /// **'Players bid in turn, stating how many points (out of 20) they will capture.\n\n• Minimum bid: 13 in 5-player mighty, 14 in 6-player kill mighty\n• Maximum bid: 20\n\nThe highest bidder becomes the declarer and chooses the trump suit. If all players pass, the round is redealt (no-game).\n\nA player with a very weak hand may also declare a deal miss for a redeal instead of bidding or passing.'**
  String get rulesMtBiddingBody;

  /// No description provided for @rulesMtDealMissTitle.
  ///
  /// In en, this message translates to:
  /// **'Deal Miss'**
  String get rulesMtDealMissTitle;

  /// No description provided for @rulesMtDealMissBody.
  ///
  /// In en, this message translates to:
  /// **'During bidding, a player whose hand is very weak may declare a deal miss.\n\n[Hand scoring]\n• Spade A = 0 pts\n• Joker = cancels the single highest point card in hand\n• A / K / Q / J = 1 pt each\n• 10 = 0.5 pt\n\n[Declaration rules]\n• It must be your turn, and you haven\'t bid or passed yet\n• 5-player: hand score ≤ 0.5\n• 6-player kill mighty: hand score exactly 0\n\n[Effect]\n• Declarer loses 5 points immediately\n• These 5 points accumulate in the \"deal-miss pool\"\n• The deck is reshuffled and the same dealer redeals\n• The pool is awarded as a bonus to the next successful declarer (it carries over on failure)'**
  String get rulesMtDealMissBody;

  /// No description provided for @rulesMtKillTitle.
  ///
  /// In en, this message translates to:
  /// **'Kill Declaration (6-player only)'**
  String get rulesMtKillTitle;

  /// No description provided for @rulesMtKillBody.
  ///
  /// In en, this message translates to:
  /// **'After bidding ends in 6-player mode, the declarer names one kill target card that is NOT in their own hand.\n\n[① Kill — target is in another player\'s hand]\n• The victim\'s 8 cards + the 5-card kitty = 13 cards are shuffled\n• Declarer receives 5, each of the other 4 survivors receives 2\n• Victim is excluded from the round (scores 0)\n• Play proceeds like 5-player mighty (discard 3, choose friend)\n\n[② Self-KO — target is in the kitty]\n• The declarer\'s 8 cards + the 5-card kitty = 13 cards are shuffled\n• The other 5 players each receive 2; the remaining 3 form a new kitty\n• The declarer is excluded from the round (scores 0)\n• Bidding restarts under 5-player rules (min 13, deal-miss 0.5)'**
  String get rulesMtKillBody;

  /// No description provided for @rulesMtFriendTitle.
  ///
  /// In en, this message translates to:
  /// **'Friend Declaration'**
  String get rulesMtFriendTitle;

  /// No description provided for @rulesMtFriendBody.
  ///
  /// In en, this message translates to:
  /// **'After winning the bid, the declarer declares a friend by naming a specific card (e.g. \'Spade King\'). The player who holds that card becomes the declarer\'s secret ally — their identity is revealed when the card is played.\n\nThe declarer may also choose to go alone (no friend), or designate the first trick winner as their friend.'**
  String get rulesMtFriendBody;

  /// No description provided for @rulesMtKittyTitle.
  ///
  /// In en, this message translates to:
  /// **'Kitty Exchange'**
  String get rulesMtKittyTitle;

  /// No description provided for @rulesMtKittyBody.
  ///
  /// In en, this message translates to:
  /// **'The declarer receives 3 kitty cards and must discard 3 cards from their hand.\n\nDuring this phase, the declarer may raise the bid by +2 (capped at 20), with or without changing the trump suit.'**
  String get rulesMtKittyBody;

  /// No description provided for @rulesMtTrickTitle.
  ///
  /// In en, this message translates to:
  /// **'Trick Rules'**
  String get rulesMtTrickTitle;

  /// No description provided for @rulesMtTrickBody.
  ///
  /// In en, this message translates to:
  /// **'1. The lead player plays any card, setting the lead suit.\n2. Other players must follow suit if possible.\n3. If you cannot follow suit, you may play any card (including trump).\n4. The highest card of the lead suit wins, unless a trump card is played — in that case the highest trump wins.\n5. Mighty and Joker override normal strength rules.\n6. The trick winner leads the next trick.\n7. On the first trick, you cannot lead with a trump suit card.'**
  String get rulesMtTrickBody;

  /// No description provided for @rulesMtScoringTitle.
  ///
  /// In en, this message translates to:
  /// **'Scoring'**
  String get rulesMtScoringTitle;

  /// No description provided for @rulesMtScoringBody.
  ///
  /// In en, this message translates to:
  /// **'20 point cards in the deck (A, K, Q, J, 10 × 4 suits = 20).\n\n[Base Score]\nBase = (Bid − 13 + 1) × 2\nOn success: + (points collected − bid)\n\n[Score Distribution]\n• Declarer: Base × 2\n• Friend: Base × 1\n• Each Defender: −Base\nOn failure, signs are reversed.\n\n[Multipliers (multiply base, stackable)]\n• Solo (no friend): ×2\n• Run (all 20 pts): ×2\n• No Trump: ×2\n• Bid 20: ×2\nMax multiplier: ×16 (solo + run + NT + bid 20)\n\n[Example]\nBid 13, collected 15 pts with a friend:\nBase = (1×2) + 2 = 4\nDeclarer +8, Friend +4, Defenders −4 each'**
  String get rulesMtScoringBody;

  /// No description provided for @rulesMtWinTitle.
  ///
  /// In en, this message translates to:
  /// **'Victory Condition'**
  String get rulesMtWinTitle;

  /// No description provided for @rulesMtWinBody.
  ///
  /// In en, this message translates to:
  /// **'After all 10 tricks are played, count the point cards collected by the declarer\'s team.\n\n• If they meet or exceed the bid → Declarer team wins.\n• If they fall short → Defence team wins.\n\nScores are accumulated over multiple rounds. The player with the highest score at the end of the session wins.'**
  String get rulesMtWinBody;

  /// No description provided for @mtPhaseBidding.
  ///
  /// In en, this message translates to:
  /// **'Bidding'**
  String get mtPhaseBidding;

  /// No description provided for @mtPhaseKitty.
  ///
  /// In en, this message translates to:
  /// **'Kitty'**
  String get mtPhaseKitty;

  /// No description provided for @mtPhasePlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get mtPhasePlaying;

  /// No description provided for @mtPhaseRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round End'**
  String get mtPhaseRoundEnd;

  /// No description provided for @mtPhaseGameEnd.
  ///
  /// In en, this message translates to:
  /// **'Game End'**
  String get mtPhaseGameEnd;

  /// No description provided for @mtRoundPhase.
  ///
  /// In en, this message translates to:
  /// **'R{round} {phase}'**
  String mtRoundPhase(Object round, Object phase);

  /// No description provided for @mtSolo.
  ///
  /// In en, this message translates to:
  /// **'Solo'**
  String get mtSolo;

  /// No description provided for @mtFriendLabel.
  ///
  /// In en, this message translates to:
  /// **'Friend: {label}'**
  String mtFriendLabel(Object label);

  /// No description provided for @mtChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get mtChat;

  /// No description provided for @mtTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get mtTypeMessage;

  /// No description provided for @mtLeaveGame.
  ///
  /// In en, this message translates to:
  /// **'Leave Game?'**
  String get mtLeaveGame;

  /// No description provided for @mtLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave?'**
  String get mtLeaveConfirm;

  /// No description provided for @mtCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get mtCancel;

  /// No description provided for @mtLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get mtLeave;

  /// No description provided for @mtDeclarer.
  ///
  /// In en, this message translates to:
  /// **'Declarer'**
  String get mtDeclarer;

  /// No description provided for @mtFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get mtFriend;

  /// No description provided for @mtPointCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} - Point Cards ({count}P)'**
  String mtPointCardsTitle(Object name, Object count);

  /// No description provided for @mtNoPointCards.
  ///
  /// In en, this message translates to:
  /// **'No point cards yet'**
  String get mtNoPointCards;

  /// No description provided for @mtClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get mtClose;

  /// No description provided for @mtYourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get mtYourTurn;

  /// No description provided for @mtWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting...'**
  String get mtWaiting;

  /// No description provided for @mtPlayed.
  ///
  /// In en, this message translates to:
  /// **'{current}/{total} played'**
  String mtPlayed(Object current, Object total);

  /// No description provided for @mtFriendRevealed.
  ///
  /// In en, this message translates to:
  /// **'Friend: {card} → {name}'**
  String mtFriendRevealed(Object card, Object name);

  /// No description provided for @mtFriendHidden.
  ///
  /// In en, this message translates to:
  /// **'Friend: {card}'**
  String mtFriendHidden(Object card);

  /// No description provided for @mtWins.
  ///
  /// In en, this message translates to:
  /// **'{name} wins!'**
  String mtWins(Object name);

  /// No description provided for @mtCurrentBid.
  ///
  /// In en, this message translates to:
  /// **'Current bid: {points} {suit}'**
  String mtCurrentBid(Object points, Object suit);

  /// No description provided for @mtPass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get mtPass;

  /// No description provided for @mtDealMiss.
  ///
  /// In en, this message translates to:
  /// **'Deal miss'**
  String get mtDealMiss;

  /// No description provided for @mtDealMissPool.
  ///
  /// In en, this message translates to:
  /// **'Deal miss {points}'**
  String mtDealMissPool(Object points);

  /// No description provided for @mtDealMissReveal.
  ///
  /// In en, this message translates to:
  /// **'{name} declared deal miss with a {score}-point hand'**
  String mtDealMissReveal(Object name, Object score);

  /// No description provided for @mtDealMissTapToClose.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere to dismiss'**
  String get mtDealMissTapToClose;

  /// No description provided for @mtKillPhase.
  ///
  /// In en, this message translates to:
  /// **'Kill Declaration'**
  String get mtKillPhase;

  /// No description provided for @mtKillPhasePrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a card to kill'**
  String get mtKillPhasePrompt;

  /// No description provided for @mtKillPhaseWait.
  ///
  /// In en, this message translates to:
  /// **'{name} is choosing a card to kill'**
  String mtKillPhaseWait(Object name);

  /// No description provided for @mtKillResultKilled.
  ///
  /// In en, this message translates to:
  /// **'{declarer} named {target} → {victim} eliminated'**
  String mtKillResultKilled(Object declarer, Object target, Object victim);

  /// No description provided for @mtKillResultSuicide.
  ///
  /// In en, this message translates to:
  /// **'{declarer} named {target} but it was in the kitty. Self-KO!'**
  String mtKillResultSuicide(Object declarer, Object target);

  /// No description provided for @mtKillExcluded.
  ///
  /// In en, this message translates to:
  /// **'OUT'**
  String get mtKillExcluded;

  /// No description provided for @mtKillConfirm.
  ///
  /// In en, this message translates to:
  /// **'Kill'**
  String get mtKillConfirm;

  /// No description provided for @mtPoints.
  ///
  /// In en, this message translates to:
  /// **'Points:'**
  String get mtPoints;

  /// No description provided for @mtBid.
  ///
  /// In en, this message translates to:
  /// **'Bid {points} {suit}'**
  String mtBid(Object points, Object suit);

  /// No description provided for @mtWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}'**
  String mtWaitingFor(Object name);

  /// No description provided for @mtExchangingKitty.
  ///
  /// In en, this message translates to:
  /// **'Declarer is exchanging kitty...'**
  String get mtExchangingKitty;

  /// No description provided for @mtDiscard3.
  ///
  /// In en, this message translates to:
  /// **'Discard 3 cards'**
  String get mtDiscard3;

  /// No description provided for @mtFriendColon.
  ///
  /// In en, this message translates to:
  /// **'Friend:'**
  String get mtFriendColon;

  /// No description provided for @mtNoFriend.
  ///
  /// In en, this message translates to:
  /// **'No Friend'**
  String get mtNoFriend;

  /// No description provided for @mt1stTrick.
  ///
  /// In en, this message translates to:
  /// **'1st Trick'**
  String get mt1stTrick;

  /// No description provided for @mtJoker.
  ///
  /// In en, this message translates to:
  /// **'Joker'**
  String get mtJoker;

  /// No description provided for @mtCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get mtCard;

  /// No description provided for @mtConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get mtConfirm;

  /// No description provided for @mtChangeTrump.
  ///
  /// In en, this message translates to:
  /// **'Change Trump'**
  String get mtChangeTrump;

  /// No description provided for @mtTrumpPenalty.
  ///
  /// In en, this message translates to:
  /// **'Bid +{penalty}'**
  String mtTrumpPenalty(int penalty);

  /// No description provided for @mtPlayTimer.
  ///
  /// In en, this message translates to:
  /// **'Play ({seconds}s)'**
  String mtPlayTimer(Object seconds);

  /// No description provided for @mtPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get mtPlay;

  /// No description provided for @mtSelectCard.
  ///
  /// In en, this message translates to:
  /// **'Select a card'**
  String get mtSelectCard;

  /// No description provided for @mtJokerLoses1st.
  ///
  /// In en, this message translates to:
  /// **'Joker loses on 1st trick!'**
  String get mtJokerLoses1st;

  /// No description provided for @mtJokerLosesLast.
  ///
  /// In en, this message translates to:
  /// **'Joker loses on last trick!'**
  String get mtJokerLosesLast;

  /// No description provided for @mtJokerSuit.
  ///
  /// In en, this message translates to:
  /// **'Joker suit: '**
  String get mtJokerSuit;

  /// No description provided for @mtJokerCall.
  ///
  /// In en, this message translates to:
  /// **'Joker Call: '**
  String get mtJokerCall;

  /// No description provided for @mtYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get mtYes;

  /// No description provided for @mtNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get mtNo;

  /// No description provided for @mtRoundResult.
  ///
  /// In en, this message translates to:
  /// **'Round {round} Result'**
  String mtRoundResult(Object round);

  /// No description provided for @mtDeclarerWins.
  ///
  /// In en, this message translates to:
  /// **'Declarer wins! ({points}P)'**
  String mtDeclarerWins(Object points);

  /// No description provided for @mtDeclarerFails.
  ///
  /// In en, this message translates to:
  /// **'Declarer fails ({points}P)'**
  String mtDeclarerFails(Object points);

  /// No description provided for @mtNextRound.
  ///
  /// In en, this message translates to:
  /// **'Next round preparing...'**
  String get mtNextRound;

  /// No description provided for @mtGameOver.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get mtGameOver;

  /// No description provided for @mtReturningIn.
  ///
  /// In en, this message translates to:
  /// **'Returning in {seconds}...'**
  String mtReturningIn(Object seconds);

  /// No description provided for @mtReturningToRoom.
  ///
  /// In en, this message translates to:
  /// **'Returning to room...'**
  String get mtReturningToRoom;

  /// No description provided for @mtScoreHistory.
  ///
  /// In en, this message translates to:
  /// **'Score History'**
  String get mtScoreHistory;

  /// No description provided for @mtRoundAbbr.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get mtRoundAbbr;

  /// No description provided for @mtOpposition.
  ///
  /// In en, this message translates to:
  /// **'Defense'**
  String get mtOpposition;

  /// No description provided for @mtContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get mtContract;

  /// No description provided for @mtResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get mtResult;

  /// No description provided for @mtTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get mtTotal;

  /// No description provided for @mtSoloSuffix.
  ///
  /// In en, this message translates to:
  /// **'(solo)'**
  String get mtSoloSuffix;

  /// No description provided for @mtFriendCardJoker.
  ///
  /// In en, this message translates to:
  /// **'Joker'**
  String get mtFriendCardJoker;

  /// No description provided for @mtFriendCardSolo.
  ///
  /// In en, this message translates to:
  /// **'Solo'**
  String get mtFriendCardSolo;

  /// No description provided for @mtFriendCard1st.
  ///
  /// In en, this message translates to:
  /// **'1st Trick'**
  String get mtFriendCard1st;

  /// No description provided for @mtJokerAbbr.
  ///
  /// In en, this message translates to:
  /// **'JK'**
  String get mtJokerAbbr;

  /// No description provided for @friendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friendsTitle;

  /// No description provided for @friendsTabFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friendsTabFriends;

  /// No description provided for @friendsTabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get friendsTabSearch;

  /// No description provided for @friendsTabRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get friendsTabRequests;

  /// No description provided for @friendsEmptyList.
  ///
  /// In en, this message translates to:
  /// **'No friends yet!\nSearch and add friends from the Search tab.'**
  String get friendsEmptyList;

  /// No description provided for @friendsStatusPlayingInRoom.
  ///
  /// In en, this message translates to:
  /// **'Playing in {roomName}'**
  String friendsStatusPlayingInRoom(String roomName);

  /// No description provided for @friendsStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get friendsStatusOnline;

  /// No description provided for @friendsStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get friendsStatusOffline;

  /// No description provided for @friendsRestrictedDuringGame.
  ///
  /// In en, this message translates to:
  /// **'Restricted during game'**
  String get friendsRestrictedDuringGame;

  /// No description provided for @friendsDmBlockedDuringGame.
  ///
  /// In en, this message translates to:
  /// **'Cannot enter DM chat during a game'**
  String get friendsDmBlockedDuringGame;

  /// No description provided for @friendsInvited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get friendsInvited;

  /// No description provided for @friendsInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get friendsInvite;

  /// No description provided for @friendsInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Sent an invite to {nickname}'**
  String friendsInviteSent(String nickname);

  /// No description provided for @friendsJoinRoom.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get friendsJoinRoom;

  /// No description provided for @friendsSpectateRoom.
  ///
  /// In en, this message translates to:
  /// **'Spectate'**
  String get friendsSpectateRoom;

  /// No description provided for @friendsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by nickname'**
  String get friendsSearchHint;

  /// No description provided for @friendsSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter a nickname to search'**
  String get friendsSearchPrompt;

  /// No description provided for @friendsSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get friendsSearchNoResults;

  /// No description provided for @friendsStatusFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get friendsStatusFriend;

  /// No description provided for @friendsRequestReceived.
  ///
  /// In en, this message translates to:
  /// **'Request received'**
  String get friendsRequestReceived;

  /// No description provided for @friendsRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get friendsRequestSent;

  /// No description provided for @friendsRequestSentSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Sent a friend request to {nickname}'**
  String friendsRequestSentSnackbar(String nickname);

  /// No description provided for @friendsAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get friendsAddFriend;

  /// No description provided for @friendsNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get friendsNoRequests;

  /// No description provided for @friendsAccepted.
  ///
  /// In en, this message translates to:
  /// **'You are now friends with {nickname}'**
  String friendsAccepted(String nickname);

  /// No description provided for @friendsAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get friendsAccept;

  /// No description provided for @friendsReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get friendsReject;

  /// No description provided for @friendsDmEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages.\nSend the first message!'**
  String get friendsDmEmpty;

  /// No description provided for @friendsDmInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a message'**
  String get friendsDmInputHint;

  /// No description provided for @friendsRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get friendsRemoveTitle;

  /// No description provided for @friendsRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {nickname} from your friends list?'**
  String friendsRemoveConfirm(String nickname);

  /// No description provided for @friendsRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed {nickname} from your friends list'**
  String friendsRemoved(String nickname);

  /// No description provided for @rankingTitle.
  ///
  /// In en, this message translates to:
  /// **'Rankings'**
  String get rankingTitle;

  /// No description provided for @rankingTichu.
  ///
  /// In en, this message translates to:
  /// **'Tichu'**
  String get rankingTichu;

  /// No description provided for @rankingSkullKing.
  ///
  /// In en, this message translates to:
  /// **'Skull King'**
  String get rankingSkullKing;

  /// No description provided for @rankingNoData.
  ///
  /// In en, this message translates to:
  /// **'No ranking data available'**
  String get rankingNoData;

  /// No description provided for @rankingRecordWithWinRate.
  ///
  /// In en, this message translates to:
  /// **'Record {total}G {wins}W {losses}L · Win rate {winRate}%'**
  String rankingRecordWithWinRate(int total, int wins, int losses, int winRate);

  /// No description provided for @rankingSeasonScore.
  ///
  /// In en, this message translates to:
  /// **'Season Score'**
  String get rankingSeasonScore;

  /// No description provided for @rankingProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Profile not found'**
  String get rankingProfileNotFound;

  /// No description provided for @rankingTichuSeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Tichu Season Ranked'**
  String get rankingTichuSeasonRanked;

  /// No description provided for @rankingTichuRecord.
  ///
  /// In en, this message translates to:
  /// **'Tichu Record'**
  String get rankingTichuRecord;

  /// No description provided for @rankingSkullKingSeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Skull King Season Ranked'**
  String get rankingSkullKingSeasonRanked;

  /// No description provided for @rankingSkullKingRecord.
  ///
  /// In en, this message translates to:
  /// **'Skull King Record'**
  String get rankingSkullKingRecord;

  /// No description provided for @rankingMighty.
  ///
  /// In en, this message translates to:
  /// **'Mighty'**
  String get rankingMighty;

  /// No description provided for @rankingMightySeasonRanked.
  ///
  /// In en, this message translates to:
  /// **'Mighty Season Ranked'**
  String get rankingMightySeasonRanked;

  /// No description provided for @rankingMightyRecord.
  ///
  /// In en, this message translates to:
  /// **'Mighty Record'**
  String get rankingMightyRecord;

  /// No description provided for @rankingMightyMatchDetail.
  ///
  /// In en, this message translates to:
  /// **'{declarer} bid {bid} {trump}'**
  String rankingMightyMatchDetail(String declarer, int bid, String trump);

  /// No description provided for @rankingLoveLetterRecord.
  ///
  /// In en, this message translates to:
  /// **'Love Letter Record'**
  String get rankingLoveLetterRecord;

  /// No description provided for @rankingStatRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get rankingStatRecord;

  /// No description provided for @rankingStatWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win Rate'**
  String get rankingStatWinRate;

  /// No description provided for @rankingRecordFormat.
  ///
  /// In en, this message translates to:
  /// **'{games}G {wins}W {losses}L'**
  String rankingRecordFormat(int games, int wins, int losses);

  /// No description provided for @rankingGold.
  ///
  /// In en, this message translates to:
  /// **'{gold} Gold'**
  String rankingGold(int gold);

  /// No description provided for @rankingDesertions.
  ///
  /// In en, this message translates to:
  /// **'Desertions {count}'**
  String rankingDesertions(int count);

  /// No description provided for @rankingRecentMatchesHeader.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches (3)'**
  String get rankingRecentMatchesHeader;

  /// No description provided for @rankingSeeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get rankingSeeMore;

  /// No description provided for @rankingNoRecentMatches.
  ///
  /// In en, this message translates to:
  /// **'No recent matches'**
  String get rankingNoRecentMatches;

  /// No description provided for @rankingBadgeDesertion.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get rankingBadgeDesertion;

  /// No description provided for @rankingBadgeDraw.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get rankingBadgeDraw;

  /// No description provided for @rankingSkRankScore.
  ///
  /// In en, this message translates to:
  /// **'#{rank} {score}pts'**
  String rankingSkRankScore(String rank, int score);

  /// No description provided for @rankingRecentMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Matches'**
  String get rankingRecentMatchesTitle;

  /// No description provided for @rankingMannerScore.
  ///
  /// In en, this message translates to:
  /// **'Manner'**
  String get rankingMannerScore;

  /// No description provided for @shopTitle.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopTitle;

  /// No description provided for @shopGoldAmount.
  ///
  /// In en, this message translates to:
  /// **'{gold} Gold'**
  String shopGoldAmount(int gold);

  /// No description provided for @shopHowToEarn.
  ///
  /// In en, this message translates to:
  /// **'How to Earn'**
  String get shopHowToEarn;

  /// No description provided for @shopDesertionCount.
  ///
  /// In en, this message translates to:
  /// **'Left {count}'**
  String shopDesertionCount(int count);

  /// No description provided for @shopGoldHistory.
  ///
  /// In en, this message translates to:
  /// **'Gold History'**
  String get shopGoldHistory;

  /// No description provided for @shopGoldCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current gold: {gold}'**
  String shopGoldCurrent(int gold);

  /// No description provided for @shopGoldHistoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Shows game results, ad rewards, shop purchases, and season rewards in recent order.'**
  String get shopGoldHistoryDesc;

  /// No description provided for @shopGoldHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No gold history to display yet.'**
  String get shopGoldHistoryEmpty;

  /// No description provided for @shopGoldChangeFallback.
  ///
  /// In en, this message translates to:
  /// **'Gold change'**
  String get shopGoldChangeFallback;

  /// No description provided for @shopGoldGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to Earn Gold'**
  String get shopGoldGuideTitle;

  /// No description provided for @shopGoldGuideDesc.
  ///
  /// In en, this message translates to:
  /// **'Gold can be earned through gameplay and rewards, and is used to purchase items in the shop.'**
  String get shopGoldGuideDesc;

  /// No description provided for @shopGuideNormalWin.
  ///
  /// In en, this message translates to:
  /// **'Normal Win'**
  String get shopGuideNormalWin;

  /// No description provided for @shopGuideNormalWinValue.
  ///
  /// In en, this message translates to:
  /// **'+10 Gold'**
  String get shopGuideNormalWinValue;

  /// No description provided for @shopGuideNormalWinDesc.
  ///
  /// In en, this message translates to:
  /// **'Earn a base reward for winning a normal Tichu or Skull King game.'**
  String get shopGuideNormalWinDesc;

  /// No description provided for @shopGuideNormalLoss.
  ///
  /// In en, this message translates to:
  /// **'Normal Loss'**
  String get shopGuideNormalLoss;

  /// No description provided for @shopGuideNormalLossValue.
  ///
  /// In en, this message translates to:
  /// **'+3 Gold'**
  String get shopGuideNormalLossValue;

  /// No description provided for @shopGuideNormalLossDesc.
  ///
  /// In en, this message translates to:
  /// **'You still earn a participation reward even if you lose.'**
  String get shopGuideNormalLossDesc;

  /// No description provided for @shopGuideRankedWin.
  ///
  /// In en, this message translates to:
  /// **'Ranked Win'**
  String get shopGuideRankedWin;

  /// No description provided for @shopGuideRankedWinValue.
  ///
  /// In en, this message translates to:
  /// **'+20 Gold'**
  String get shopGuideRankedWinValue;

  /// No description provided for @shopGuideRankedWinDesc.
  ///
  /// In en, this message translates to:
  /// **'Ranked games award 2x gold compared to normal games.'**
  String get shopGuideRankedWinDesc;

  /// No description provided for @shopGuideRankedLoss.
  ///
  /// In en, this message translates to:
  /// **'Ranked Loss'**
  String get shopGuideRankedLoss;

  /// No description provided for @shopGuideRankedLossValue.
  ///
  /// In en, this message translates to:
  /// **'+6 Gold'**
  String get shopGuideRankedLossValue;

  /// No description provided for @shopGuideRankedLossDesc.
  ///
  /// In en, this message translates to:
  /// **'Ranked loss rewards are also 2x compared to normal games.'**
  String get shopGuideRankedLossDesc;

  /// No description provided for @shopGuideAdReward.
  ///
  /// In en, this message translates to:
  /// **'Ad Reward'**
  String get shopGuideAdReward;

  /// No description provided for @shopGuideAdRewardValue.
  ///
  /// In en, this message translates to:
  /// **'+50 Gold'**
  String get shopGuideAdRewardValue;

  /// No description provided for @shopGuideAdRewardDesc.
  ///
  /// In en, this message translates to:
  /// **'Watch ads to earn bonus gold up to 5 times per day.'**
  String get shopGuideAdRewardDesc;

  /// No description provided for @shopGuideSeasonReward.
  ///
  /// In en, this message translates to:
  /// **'Season Reward'**
  String get shopGuideSeasonReward;

  /// No description provided for @shopGuideSeasonRewardValue.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get shopGuideSeasonRewardValue;

  /// No description provided for @shopGuideSeasonRewardDesc.
  ///
  /// In en, this message translates to:
  /// **'Bonus gold is awarded at the end of the season based on your ranking.'**
  String get shopGuideSeasonRewardDesc;

  /// No description provided for @shopTabShop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopTabShop;

  /// No description provided for @shopTabInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get shopTabInventory;

  /// No description provided for @shopNoItems.
  ///
  /// In en, this message translates to:
  /// **'No shop items available'**
  String get shopNoItems;

  /// No description provided for @shopCategoryBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get shopCategoryBanner;

  /// No description provided for @shopCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get shopCategoryTitle;

  /// No description provided for @shopCategoryTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get shopCategoryTheme;

  /// No description provided for @shopCategoryUtil.
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get shopCategoryUtil;

  /// No description provided for @shopCategorySeason.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get shopCategorySeason;

  /// No description provided for @shopItemEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items'**
  String get shopItemEmpty;

  /// No description provided for @shopItemOwned.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get shopItemOwned;

  /// No description provided for @shopButtonExtend.
  ///
  /// In en, this message translates to:
  /// **'Extend'**
  String get shopButtonExtend;

  /// No description provided for @shopButtonPurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get shopButtonPurchase;

  /// No description provided for @shopExtendTitle.
  ///
  /// In en, this message translates to:
  /// **'Extend Duration'**
  String get shopExtendTitle;

  /// No description provided for @shopExtendConfirm.
  ///
  /// In en, this message translates to:
  /// **'You already own this item.\nExtend {name} by {days} days?\n\nCost: {price} Gold'**
  String shopExtendConfirm(String name, int days, int price);

  /// No description provided for @shopExtendAction.
  ///
  /// In en, this message translates to:
  /// **'Extend'**
  String get shopExtendAction;

  /// No description provided for @shopNoInventoryItems.
  ///
  /// In en, this message translates to:
  /// **'No items in inventory'**
  String get shopNoInventoryItems;

  /// No description provided for @shopStatusActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get shopStatusActivated;

  /// No description provided for @shopStatusInUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get shopStatusInUse;

  /// No description provided for @shopPermanentOwned.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get shopPermanentOwned;

  /// No description provided for @shopButtonUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get shopButtonUse;

  /// No description provided for @shopButtonEquip.
  ///
  /// In en, this message translates to:
  /// **'Equip'**
  String get shopButtonEquip;

  /// No description provided for @shopTagSeason.
  ///
  /// In en, this message translates to:
  /// **'Season Item'**
  String get shopTagSeason;

  /// No description provided for @shopTagPermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get shopTagPermanent;

  /// No description provided for @shopTagDuration.
  ///
  /// In en, this message translates to:
  /// **'{days}d duration'**
  String shopTagDuration(int days);

  /// No description provided for @shopTagDurationOnly.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get shopTagDurationOnly;

  /// No description provided for @shopExpireDate.
  ///
  /// In en, this message translates to:
  /// **'Expires: {date}'**
  String shopExpireDate(String date);

  /// No description provided for @shopExpireSoon.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get shopExpireSoon;

  /// No description provided for @shopPurchaseComplete.
  ///
  /// In en, this message translates to:
  /// **'Purchase Complete'**
  String get shopPurchaseComplete;

  /// No description provided for @shopExtendComplete.
  ///
  /// In en, this message translates to:
  /// **'Extension Complete'**
  String get shopExtendComplete;

  /// No description provided for @shopExtendDone.
  ///
  /// In en, this message translates to:
  /// **'{name} duration has been extended.'**
  String shopExtendDone(String name);

  /// No description provided for @shopPurchaseDoneConsumable.
  ///
  /// In en, this message translates to:
  /// **'Purchase complete.\nPlease use it from your inventory.'**
  String get shopPurchaseDoneConsumable;

  /// No description provided for @shopPurchaseDonePassive.
  ///
  /// In en, this message translates to:
  /// **'Purchase complete.\nAutomatically activated upon purchase.'**
  String get shopPurchaseDonePassive;

  /// No description provided for @shopPurchaseDoneEquip.
  ///
  /// In en, this message translates to:
  /// **'Purchase complete.\nWould you like to equip it now?'**
  String get shopPurchaseDoneEquip;

  /// No description provided for @shopEquipNow.
  ///
  /// In en, this message translates to:
  /// **'Equip'**
  String get shopEquipNow;

  /// No description provided for @shopDetailCategoryBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get shopDetailCategoryBanner;

  /// No description provided for @shopDetailCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get shopDetailCategoryTitle;

  /// No description provided for @shopDetailCategoryThemeSkin.
  ///
  /// In en, this message translates to:
  /// **'Theme / Card Skin'**
  String get shopDetailCategoryThemeSkin;

  /// No description provided for @shopDetailCategoryUtility.
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get shopDetailCategoryUtility;

  /// No description provided for @shopDetailCategoryItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get shopDetailCategoryItem;

  /// No description provided for @shopDetailNormalItem.
  ///
  /// In en, this message translates to:
  /// **'Normal Item'**
  String get shopDetailNormalItem;

  /// No description provided for @shopDetailPermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get shopDetailPermanent;

  /// No description provided for @shopDetailDuration.
  ///
  /// In en, this message translates to:
  /// **'{days}d duration'**
  String shopDetailDuration(int days);

  /// No description provided for @shopEffectNicknameChange.
  ///
  /// In en, this message translates to:
  /// **'Effect: 1 nickname change'**
  String get shopEffectNicknameChange;

  /// No description provided for @shopEffectLeaveReduce.
  ///
  /// In en, this message translates to:
  /// **'Effect: Desertions -{value}'**
  String shopEffectLeaveReduce(String value);

  /// No description provided for @shopEffectStatsReset.
  ///
  /// In en, this message translates to:
  /// **'Effect: Reset all stats (wins/losses/games)'**
  String get shopEffectStatsReset;

  /// No description provided for @shopEffectLeaveReset.
  ///
  /// In en, this message translates to:
  /// **'Effect: Reset leave count to 0'**
  String get shopEffectLeaveReset;

  /// No description provided for @shopEffectSeasonStatsReset.
  ///
  /// In en, this message translates to:
  /// **'Effect: Reset ranked stats (wins/losses/games)'**
  String get shopEffectSeasonStatsReset;

  /// No description provided for @shopPriceGold.
  ///
  /// In en, this message translates to:
  /// **'{price} Gold'**
  String shopPriceGold(int price);

  /// No description provided for @shopNicknameChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Nickname'**
  String get shopNicknameChangeTitle;

  /// No description provided for @shopNicknameChangeDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter your new nickname.\n(2-10 characters, no spaces)'**
  String get shopNicknameChangeDesc;

  /// No description provided for @shopNicknameChangeHint.
  ///
  /// In en, this message translates to:
  /// **'New nickname'**
  String get shopNicknameChangeHint;

  /// No description provided for @shopNicknameChangeValidation.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be 2-10 characters'**
  String get shopNicknameChangeValidation;

  /// No description provided for @shopNicknameChangeButton.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get shopNicknameChangeButton;

  /// No description provided for @shopAdCannotShow.
  ///
  /// In en, this message translates to:
  /// **'Unable to show the ad'**
  String get shopAdCannotShow;

  /// No description provided for @shopAdWatchForGold.
  ///
  /// In en, this message translates to:
  /// **'Watch ad for 50 Gold ({current}/{max})'**
  String shopAdWatchForGold(int current, int max);

  /// No description provided for @shopAdRewardDone.
  ///
  /// In en, this message translates to:
  /// **'Daily ad rewards complete'**
  String get shopAdRewardDone;

  /// No description provided for @appForceUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get appForceUpdateTitle;

  /// No description provided for @appForceUpdateBody.
  ///
  /// In en, this message translates to:
  /// **'A new version has been released.\nPlease update to continue using the app.'**
  String get appForceUpdateBody;

  /// No description provided for @appForceUpdateButton.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get appForceUpdateButton;

  /// No description provided for @appEulaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get appEulaSubtitle;

  /// No description provided for @appEulaLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load Terms of Service. Please check your network connection.'**
  String get appEulaLoadFailed;

  /// No description provided for @appEulaAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service'**
  String get appEulaAgree;

  /// No description provided for @appEulaStart.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get appEulaStart;

  /// No description provided for @serviceRestoreRefreshingSocial.
  ///
  /// In en, this message translates to:
  /// **'Verifying social login info...'**
  String get serviceRestoreRefreshingSocial;

  /// No description provided for @serviceRestoreSocialLogin.
  ///
  /// In en, this message translates to:
  /// **'Logging in with social account...'**
  String get serviceRestoreSocialLogin;

  /// No description provided for @serviceRestoreLocalLogin.
  ///
  /// In en, this message translates to:
  /// **'Logging in with saved account...'**
  String get serviceRestoreLocalLogin;

  /// No description provided for @serviceRestoreRoomState.
  ///
  /// In en, this message translates to:
  /// **'Restoring room info...'**
  String get serviceRestoreRoomState;

  /// No description provided for @serviceRestoreLoadingLobby.
  ///
  /// In en, this message translates to:
  /// **'Loading lobby data...'**
  String get serviceRestoreLoadingLobby;

  /// No description provided for @serviceRestoreAutoLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto login failed.'**
  String get serviceRestoreAutoLoginFailed;

  /// No description provided for @serviceRestoreConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get serviceRestoreConnecting;

  /// No description provided for @serviceRestoreNeedsNickname.
  ///
  /// In en, this message translates to:
  /// **'A nickname needs to be set.'**
  String get serviceRestoreNeedsNickname;

  /// No description provided for @serviceRestoreSocialFailed.
  ///
  /// In en, this message translates to:
  /// **'Social login restoration failed.'**
  String get serviceRestoreSocialFailed;

  /// No description provided for @serviceRestoreSocialTokenExpired.
  ///
  /// In en, this message translates to:
  /// **'Social login info needs to be re-verified.'**
  String get serviceRestoreSocialTokenExpired;

  /// No description provided for @serviceRestoreLocalFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved account login failed.'**
  String get serviceRestoreLocalFailed;

  /// No description provided for @serviceRestoreAutoError.
  ///
  /// In en, this message translates to:
  /// **'An error occurred during auto login.'**
  String get serviceRestoreAutoError;

  /// No description provided for @serviceServerTimeout.
  ///
  /// In en, this message translates to:
  /// **'Server response timed out'**
  String get serviceServerTimeout;

  /// No description provided for @serviceKicked.
  ///
  /// In en, this message translates to:
  /// **'You have been kicked'**
  String get serviceKicked;

  /// No description provided for @serviceRankingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load rankings'**
  String get serviceRankingsLoadFailed;

  /// No description provided for @serviceGoldHistoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load gold history'**
  String get serviceGoldHistoryLoadFailed;

  /// No description provided for @serviceAdminUsersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load user list'**
  String get serviceAdminUsersLoadFailed;

  /// No description provided for @serviceAdminUserDetailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load user details'**
  String get serviceAdminUserDetailLoadFailed;

  /// No description provided for @serviceAdminInquiriesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inquiry list'**
  String get serviceAdminInquiriesLoadFailed;

  /// No description provided for @serviceAdminReportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load report list'**
  String get serviceAdminReportsLoadFailed;

  /// No description provided for @serviceAdminReportGroupLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load report details'**
  String get serviceAdminReportGroupLoadFailed;

  /// No description provided for @serviceAdminActionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Action completed'**
  String get serviceAdminActionSuccess;

  /// No description provided for @serviceAdminActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get serviceAdminActionFailed;

  /// No description provided for @serviceShopLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load shop data'**
  String get serviceShopLoadFailed;

  /// No description provided for @serviceInventoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inventory'**
  String get serviceInventoryLoadFailed;

  /// No description provided for @serviceInquiriesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inquiry history'**
  String get serviceInquiriesLoadFailed;

  /// No description provided for @serviceNoticesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notices'**
  String get serviceNoticesLoadFailed;

  /// No description provided for @serviceNicknameChanged.
  ///
  /// In en, this message translates to:
  /// **'Nickname has been changed'**
  String get serviceNicknameChanged;

  /// No description provided for @serviceNicknameChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Nickname change failed'**
  String get serviceNicknameChangeFailed;

  /// No description provided for @serviceRewardFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to grant reward'**
  String get serviceRewardFailed;

  /// No description provided for @serviceRoomRestoreFallback.
  ///
  /// In en, this message translates to:
  /// **'Could not restore room info. Returning to lobby.'**
  String get serviceRoomRestoreFallback;

  /// No description provided for @serviceInviteInGame.
  ///
  /// In en, this message translates to:
  /// **'Cannot send room invites during a game'**
  String get serviceInviteInGame;

  /// No description provided for @serviceInviteCooldown.
  ///
  /// In en, this message translates to:
  /// **'Invite already sent. Please try again shortly'**
  String get serviceInviteCooldown;

  /// No description provided for @serviceAdShowFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to show the ad'**
  String get serviceAdShowFailed;

  /// No description provided for @serviceAdLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the ad'**
  String get serviceAdLoadFailed;

  /// No description provided for @serviceInquiryReply.
  ///
  /// In en, this message translates to:
  /// **'Inquiry reply received: {title}'**
  String serviceInquiryReply(String title);

  /// No description provided for @serviceInquiryDefault.
  ///
  /// In en, this message translates to:
  /// **'Inquiry'**
  String get serviceInquiryDefault;

  /// No description provided for @serviceChatBanned.
  ///
  /// In en, this message translates to:
  /// **'Chat restricted ({remaining} remaining)'**
  String serviceChatBanned(String remaining);

  /// No description provided for @serviceChatBanHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String serviceChatBanHoursMinutes(int hours, int minutes);

  /// No description provided for @serviceChatBanMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String serviceChatBanMinutes(int minutes);

  /// No description provided for @serviceAdRewardSuccess.
  ///
  /// In en, this message translates to:
  /// **'Received 50 Gold! (Remaining: {remaining})'**
  String serviceAdRewardSuccess(int remaining);

  /// No description provided for @lobbyLoveLetter.
  ///
  /// In en, this message translates to:
  /// **'Love Letter'**
  String get lobbyLoveLetter;

  /// No description provided for @lobbyLoveLetterBadge.
  ///
  /// In en, this message translates to:
  /// **'Love Letter'**
  String get lobbyLoveLetterBadge;

  /// No description provided for @lobbyLoveLetterPlayers.
  ///
  /// In en, this message translates to:
  /// **'Love Letter · {count}P'**
  String lobbyLoveLetterPlayers(int count);

  /// No description provided for @llRound.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get llRound;

  /// No description provided for @llPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get llPlay;

  /// No description provided for @llConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get llConfirm;

  /// No description provided for @llOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get llOk;

  /// No description provided for @llRoundEnd.
  ///
  /// In en, this message translates to:
  /// **'Round Over'**
  String get llRoundEnd;

  /// No description provided for @llRoundWinner.
  ///
  /// In en, this message translates to:
  /// **'Round Winner'**
  String get llRoundWinner;

  /// No description provided for @llNextRoundAuto.
  ///
  /// In en, this message translates to:
  /// **'Next round starting soon...'**
  String get llNextRoundAuto;

  /// No description provided for @llGameEnd.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get llGameEnd;

  /// No description provided for @llWins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get llWins;

  /// No description provided for @llReturnIn.
  ///
  /// In en, this message translates to:
  /// **'Returning in'**
  String get llReturnIn;

  /// No description provided for @llGuardSelectTarget.
  ///
  /// In en, this message translates to:
  /// **'Guard: Select a target and guess a card'**
  String get llGuardSelectTarget;

  /// No description provided for @llGuardGuessCard.
  ///
  /// In en, this message translates to:
  /// **'Guess which card they hold:'**
  String get llGuardGuessCard;

  /// No description provided for @llSelectTargetFor.
  ///
  /// In en, this message translates to:
  /// **'Select target for:'**
  String get llSelectTargetFor;

  /// No description provided for @llGuardEffect.
  ///
  /// In en, this message translates to:
  /// **'{name} is using Guard...'**
  String llGuardEffect(String name);

  /// No description provided for @llSpyEffect.
  ///
  /// In en, this message translates to:
  /// **'{name} is using Spy...'**
  String llSpyEffect(String name);

  /// No description provided for @llBaronEffect.
  ///
  /// In en, this message translates to:
  /// **'{name} is using Baron...'**
  String llBaronEffect(String name);

  /// No description provided for @llPrinceEffect.
  ///
  /// In en, this message translates to:
  /// **'{name} is using Prince...'**
  String llPrinceEffect(String name);

  /// No description provided for @llKingEffect.
  ///
  /// In en, this message translates to:
  /// **'{name} is using King...'**
  String llKingEffect(String name);

  /// No description provided for @llGuardCorrect.
  ///
  /// In en, this message translates to:
  /// **'{actor} guessed {target}\'s card correctly! Eliminated!'**
  String llGuardCorrect(String actor, String target);

  /// No description provided for @llGuardWrong.
  ///
  /// In en, this message translates to:
  /// **'{actor} guessed wrong about {target}'**
  String llGuardWrong(String actor, String target);

  /// No description provided for @llSpyReveal.
  ///
  /// In en, this message translates to:
  /// **'{target}\'s card:'**
  String llSpyReveal(String target);

  /// No description provided for @llSpySawYour.
  ///
  /// In en, this message translates to:
  /// **'{actor} saw your card'**
  String llSpySawYour(String actor);

  /// No description provided for @llSpyPeeked.
  ///
  /// In en, this message translates to:
  /// **'{actor} peeked at {target}\'s card'**
  String llSpyPeeked(String actor, String target);

  /// No description provided for @llBaronTie.
  ///
  /// In en, this message translates to:
  /// **'{actor} and {target} tied'**
  String llBaronTie(String actor, String target);

  /// No description provided for @llBaronLose.
  ///
  /// In en, this message translates to:
  /// **'{loser} was eliminated by Baron comparison'**
  String llBaronLose(String loser);

  /// No description provided for @llPrinceEliminated.
  ///
  /// In en, this message translates to:
  /// **'{target} was forced to discard Princess! Eliminated!'**
  String llPrinceEliminated(String target);

  /// No description provided for @llPrinceDiscard.
  ///
  /// In en, this message translates to:
  /// **'{target} discarded and drew a new card'**
  String llPrinceDiscard(String target);

  /// No description provided for @llKingSwap.
  ///
  /// In en, this message translates to:
  /// **'{actor} and {target} swapped hands'**
  String llKingSwap(String actor, String target);

  /// No description provided for @llEliminated.
  ///
  /// In en, this message translates to:
  /// **'OUT'**
  String get llEliminated;

  /// No description provided for @llSetAsideFaceUp.
  ///
  /// In en, this message translates to:
  /// **'Set aside (face-up)'**
  String get llSetAsideFaceUp;

  /// No description provided for @llPlayed.
  ///
  /// In en, this message translates to:
  /// **'Played:'**
  String get llPlayed;

  /// No description provided for @llCardGuard.
  ///
  /// In en, this message translates to:
  /// **'Guard'**
  String get llCardGuard;

  /// No description provided for @llCardSpy.
  ///
  /// In en, this message translates to:
  /// **'Spy'**
  String get llCardSpy;

  /// No description provided for @llCardBaron.
  ///
  /// In en, this message translates to:
  /// **'Baron'**
  String get llCardBaron;

  /// No description provided for @llCardHandmaid.
  ///
  /// In en, this message translates to:
  /// **'Handmaid'**
  String get llCardHandmaid;

  /// No description provided for @llCardPrince.
  ///
  /// In en, this message translates to:
  /// **'Prince'**
  String get llCardPrince;

  /// No description provided for @llCardKing.
  ///
  /// In en, this message translates to:
  /// **'King'**
  String get llCardKing;

  /// No description provided for @llCardCountess.
  ///
  /// In en, this message translates to:
  /// **'Countess'**
  String get llCardCountess;

  /// No description provided for @llCardPrincess.
  ///
  /// In en, this message translates to:
  /// **'Princess'**
  String get llCardPrincess;

  /// No description provided for @llCardGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Guide'**
  String get llCardGuideTitle;

  /// No description provided for @llDescGuard.
  ///
  /// In en, this message translates to:
  /// **'1 · Guard: Name a player and guess their card. If correct, they\'re eliminated!'**
  String get llDescGuard;

  /// No description provided for @llDescSpy.
  ///
  /// In en, this message translates to:
  /// **'2 · Spy: Secretly look at another player\'s card.'**
  String get llDescSpy;

  /// No description provided for @llDescBaron.
  ///
  /// In en, this message translates to:
  /// **'3 · Baron: Compare cards with a player. Lower card is eliminated!'**
  String get llDescBaron;

  /// No description provided for @llDescHandmaid.
  ///
  /// In en, this message translates to:
  /// **'4 · Handmaid: Protected from all effects until your next turn.'**
  String get llDescHandmaid;

  /// No description provided for @llDescPrince.
  ///
  /// In en, this message translates to:
  /// **'5 · Prince: Force a player to discard. If they discard Princess, eliminated!'**
  String get llDescPrince;

  /// No description provided for @llDescKing.
  ///
  /// In en, this message translates to:
  /// **'6 · King: Trade cards with another player.'**
  String get llDescKing;

  /// No description provided for @llDescCountess.
  ///
  /// In en, this message translates to:
  /// **'7 · Countess: Must be played if you hold King or Prince.'**
  String get llDescCountess;

  /// No description provided for @llDescPrincess.
  ///
  /// In en, this message translates to:
  /// **'8 · Princess: If you play this card, you are eliminated!'**
  String get llDescPrincess;

  /// No description provided for @maintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Server Under Maintenance'**
  String get maintenanceTitle;

  /// No description provided for @maintenanceCountdown.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {time}'**
  String maintenanceCountdown(String time);

  /// No description provided for @maintenanceRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get maintenanceRetry;

  /// No description provided for @maintenanceEnded.
  ///
  /// In en, this message translates to:
  /// **'Maintenance over, reconnecting...'**
  String get maintenanceEnded;

  /// No description provided for @goldHistoryShopPurchase.
  ///
  /// In en, this message translates to:
  /// **'Shop purchase'**
  String get goldHistoryShopPurchase;

  /// No description provided for @goldHistoryLeaveDefeat.
  ///
  /// In en, this message translates to:
  /// **'Forfeit loss'**
  String get goldHistoryLeaveDefeat;

  /// No description provided for @goldHistoryRankedWin.
  ///
  /// In en, this message translates to:
  /// **'Ranked win'**
  String get goldHistoryRankedWin;

  /// No description provided for @goldHistoryCasualWin.
  ///
  /// In en, this message translates to:
  /// **'Casual win'**
  String get goldHistoryCasualWin;

  /// No description provided for @goldHistoryDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get goldHistoryDraw;

  /// No description provided for @goldHistoryRankedLoss.
  ///
  /// In en, this message translates to:
  /// **'Ranked loss'**
  String get goldHistoryRankedLoss;

  /// No description provided for @goldHistoryCasualLoss.
  ///
  /// In en, this message translates to:
  /// **'Casual loss'**
  String get goldHistoryCasualLoss;

  /// No description provided for @goldHistoryAdReward.
  ///
  /// In en, this message translates to:
  /// **'Ad reward'**
  String get goldHistoryAdReward;

  /// No description provided for @goldHistorySeasonReward.
  ///
  /// In en, this message translates to:
  /// **'Season reward'**
  String get goldHistorySeasonReward;

  /// No description provided for @goldHistorySkLeaveDefeat.
  ///
  /// In en, this message translates to:
  /// **'Skull King forfeit loss'**
  String get goldHistorySkLeaveDefeat;

  /// No description provided for @goldHistorySkRankedWin.
  ///
  /// In en, this message translates to:
  /// **'Skull King ranked win'**
  String get goldHistorySkRankedWin;

  /// No description provided for @goldHistorySkCasualWin.
  ///
  /// In en, this message translates to:
  /// **'Skull King casual win'**
  String get goldHistorySkCasualWin;

  /// No description provided for @goldHistorySkRankedLoss.
  ///
  /// In en, this message translates to:
  /// **'Skull King ranked loss'**
  String get goldHistorySkRankedLoss;

  /// No description provided for @goldHistorySkCasualLoss.
  ///
  /// In en, this message translates to:
  /// **'Skull King casual loss'**
  String get goldHistorySkCasualLoss;

  /// No description provided for @goldHistoryAdminGrant.
  ///
  /// In en, this message translates to:
  /// **'Admin grant'**
  String get goldHistoryAdminGrant;

  /// No description provided for @goldHistoryAdminDeduct.
  ///
  /// In en, this message translates to:
  /// **'Admin deduction'**
  String get goldHistoryAdminDeduct;

  /// No description provided for @goldHistoryFinalScore.
  ///
  /// In en, this message translates to:
  /// **'Final score {scoreA}:{scoreB}'**
  String goldHistoryFinalScore(String scoreA, String scoreB);

  /// No description provided for @goldHistorySeasonRank.
  ///
  /// In en, this message translates to:
  /// **'Season rank: {rank}'**
  String goldHistorySeasonRank(String rank);

  /// No description provided for @goldHistorySkRankScore.
  ///
  /// In en, this message translates to:
  /// **'Rank {rank} ({score} pts)'**
  String goldHistorySkRankScore(String rank, String score);

  /// No description provided for @goldHistoryAdminBy.
  ///
  /// In en, this message translates to:
  /// **'By admin: {admin}'**
  String goldHistoryAdminBy(String admin);

  /// No description provided for @adminCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Center'**
  String get adminCenterTitle;

  /// No description provided for @adminTabInquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get adminTabInquiries;

  /// No description provided for @adminTabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get adminTabReports;

  /// No description provided for @adminTabUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminTabUsers;

  /// No description provided for @adminActiveUsers.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminActiveUsers;

  /// No description provided for @adminPendingInquiries.
  ///
  /// In en, this message translates to:
  /// **'Pending inquiries'**
  String get adminPendingInquiries;

  /// No description provided for @adminPendingReports.
  ///
  /// In en, this message translates to:
  /// **'Pending reports'**
  String get adminPendingReports;

  /// No description provided for @adminTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total users'**
  String get adminTotalUsers;

  /// No description provided for @adminSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by nickname'**
  String get adminSearchHint;

  /// No description provided for @adminSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get adminSearch;

  /// No description provided for @adminOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get adminOnline;

  /// No description provided for @adminOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get adminOffline;

  /// No description provided for @adminUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get adminUser;

  /// No description provided for @adminSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get adminSubject;

  /// No description provided for @adminNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get adminNote;

  /// No description provided for @adminResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get adminResolved;

  /// No description provided for @adminReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get adminReviewed;

  /// No description provided for @adminBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic info'**
  String get adminBasicInfo;

  /// No description provided for @adminUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get adminUsername;

  /// No description provided for @adminRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get adminRating;

  /// No description provided for @adminGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get adminGold;

  /// No description provided for @adminRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get adminRecord;

  /// No description provided for @adminStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminStatus;

  /// No description provided for @adminCurrentRoom.
  ///
  /// In en, this message translates to:
  /// **'Current room'**
  String get adminCurrentRoom;

  /// No description provided for @adminGoldAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust gold'**
  String get adminGoldAdjust;

  /// No description provided for @adminGoldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get adminGoldAmount;

  /// No description provided for @adminGoldHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive number'**
  String get adminGoldHint;

  /// No description provided for @adminGoldValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid positive amount'**
  String get adminGoldValidation;

  /// No description provided for @adminGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get adminGrant;

  /// No description provided for @adminDeduct.
  ///
  /// In en, this message translates to:
  /// **'Deduct'**
  String get adminDeduct;

  /// No description provided for @adminReportCount.
  ///
  /// In en, this message translates to:
  /// **'{count} reports'**
  String adminReportCount(int count);

  /// No description provided for @adminReportRoom.
  ///
  /// In en, this message translates to:
  /// **'Room: {roomId}'**
  String adminReportRoom(String roomId);

  /// No description provided for @adminInquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inquiry #{id}'**
  String adminInquiryTitle(int id);

  /// No description provided for @adminReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report: {nickname}'**
  String adminReportTitle(String nickname);

  /// No description provided for @adminWinLoss.
  ///
  /// In en, this message translates to:
  /// **'{wins}W/{losses}L'**
  String adminWinLoss(int wins, int losses);
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return L10nDe();
    case 'en':
      return L10nEn();
    case 'ko':
      return L10nKo();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

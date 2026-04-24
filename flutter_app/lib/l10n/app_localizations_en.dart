// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tichu Online';

  @override
  String get languageAuto => 'Auto (System)';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageKorean => 'Korean';

  @override
  String get languageGerman => 'German';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAppInfo => 'App Info';

  @override
  String get settingsAppVersion => 'App Version';

  @override
  String get settingsNotLatestVersion => 'Not the latest version';

  @override
  String get settingsUpdate => 'Update';

  @override
  String get settingsLogout => 'Logout';

  @override
  String get settingsDeleteAccount => 'Delete Account';

  @override
  String get settingsDeleteAccountConfirm =>
      'Are you sure you want to delete your account?\nAll data will be permanently deleted.';

  @override
  String get settingsNickname => 'Nickname';

  @override
  String get settingsSocialLink => 'Social Link';

  @override
  String get settingsTermsOfService => 'Terms of Service';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsNotices => 'Notices';

  @override
  String get settingsMyProfile => 'My Profile';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsAdminCenter => 'Admin Center';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonLink => 'Link';

  @override
  String get commonError => 'Error';

  @override
  String get settingsHeaderTitle => 'Settings';

  @override
  String get settingsNotificationsSection => 'Notifications';

  @override
  String get settingsPushNotifications => 'Push Notifications';

  @override
  String get settingsPushNotificationsDesc =>
      'Turn all notifications on or off';

  @override
  String get settingsInquiryNotifications => 'Inquiry Notifications';

  @override
  String get settingsInquiryNotificationsDesc =>
      'Receive push when a new inquiry arrives';

  @override
  String get settingsReportNotifications => 'Report Notifications';

  @override
  String get settingsReportNotificationsDesc =>
      'Receive push when a new report arrives';

  @override
  String get settingsAdminSection => 'Admin';

  @override
  String get settingsAdminCenterDesc =>
      'View inquiries, reports, users, and active users';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsProfileSubtitle =>
      'View level, record, and recent matches';

  @override
  String settingsSocialLinked(String provider) {
    return '$provider linked';
  }

  @override
  String get settingsNoLinkedAccount =>
      'No linked account (ranked play unavailable)';

  @override
  String get settingsInquirySection => 'Inquiry';

  @override
  String get settingsSubmitInquiry => 'Submit Inquiry';

  @override
  String get settingsInquiryHistory => 'Inquiry History';

  @override
  String get settingsAccountManagement => 'Account Management';

  @override
  String get settingsDeleteAccountWithdraw => 'Withdraw';

  @override
  String get settingsLinkComplete => 'Linking completed';

  @override
  String settingsLinkFailed(String error) {
    return 'Linking failed: $error';
  }

  @override
  String get noticeTitle => 'Notices';

  @override
  String get noticeEmpty => 'No notices available';

  @override
  String get noticeRetry => 'Retry';

  @override
  String get noticeCategoryRelease => 'Release';

  @override
  String get noticeCategoryUpdate => 'Update';

  @override
  String get noticeCategoryPreview => 'Update Preview';

  @override
  String get noticeCategoryGeneral => 'Notice';

  @override
  String get inquiryTitle => 'Submit Inquiry';

  @override
  String get inquiryCategory => 'Category';

  @override
  String get inquiryCategoryBug => 'Bug Report';

  @override
  String get inquiryCategorySuggestion => 'Suggestion';

  @override
  String get inquiryCategoryOther => 'Other';

  @override
  String get inquiryFieldTitle => 'Title';

  @override
  String get inquiryFieldTitleHint => 'Enter a title';

  @override
  String get inquiryFieldContent => 'Content';

  @override
  String get inquiryFieldContentHint => 'Enter the details';

  @override
  String get inquirySubmit => 'Submit';

  @override
  String get inquirySubmitted => 'Your inquiry has been submitted';

  @override
  String get inquiryHistoryTitle => 'Inquiry History';

  @override
  String get inquiryEmpty => 'No inquiries found';

  @override
  String get inquiryStatusResolved => 'Resolved';

  @override
  String get inquiryStatusPending => 'Pending';

  @override
  String get inquiryAnswerLabel => 'Answer';

  @override
  String inquiryAnswerDate(String date) {
    return 'Answered on: $date';
  }

  @override
  String get inquiryNoAnswer => 'No answer has been registered yet.';

  @override
  String get linkDialogTitle => 'Link Social Account';

  @override
  String get linkDialogContent => 'Select a social account to link';

  @override
  String get textViewLoadFailed => 'Failed to load content.';

  @override
  String get loginEnterUsername => 'Please enter your username';

  @override
  String get loginEnterPassword => 'Please enter your password';

  @override
  String get loginFailed => 'Login failed';

  @override
  String loginSocialFailed(String error) {
    return 'Social login failed: $error';
  }

  @override
  String get loginSocialFailedGeneric => 'Social login failed';

  @override
  String get loginSubtitle => 'Team card game';

  @override
  String get loginTagline =>
      'Quickly reconnect and\njump right back into the game.';

  @override
  String get loginUsernameHint => 'Username';

  @override
  String get loginPasswordHint => 'Password';

  @override
  String get loginButton => 'Login';

  @override
  String get loginRegisterButton => 'Register';

  @override
  String get loginQuickLogin => 'Quick login';

  @override
  String get loginAutoLoginFailed => 'Auto login failed';

  @override
  String get loginCheckSavedInfo => 'Please check your saved login info.';

  @override
  String get loginRetry => 'Retry';

  @override
  String get loginManual => 'Login manually';

  @override
  String get loginAutoLoggingIn => 'Auto logging in...';

  @override
  String get loginLoggingIn => 'Logging in...';

  @override
  String get loginVerifyingAccount => 'Verifying account info.';

  @override
  String get loginRegistrationComplete =>
      'Registration complete. Please log in.';

  @override
  String get loginNicknameEmpty => 'Please enter a nickname';

  @override
  String get loginNicknameLength => 'Nickname must be 2-10 characters';

  @override
  String get loginNicknameNoSpaces => 'Nickname cannot contain spaces';

  @override
  String get loginServerUnavailable => 'Cannot connect to the server.';

  @override
  String get loginServerNoResponse =>
      'No response from server. Please try again.';

  @override
  String get loginUsernameMinLength => 'Username must be at least 2 characters';

  @override
  String get loginUsernameNoSpaces => 'Username cannot contain spaces';

  @override
  String get loginPasswordMinLength => 'Password must be at least 4 characters';

  @override
  String get loginPasswordMismatch => 'Passwords do not match';

  @override
  String get loginNicknameCheckRequired => 'Please check nickname availability';

  @override
  String get loginServerTimeout => 'Server response timed out';

  @override
  String get loginRegisterTitle => 'Register';

  @override
  String get loginUsernameLabel => 'Username';

  @override
  String get loginUsernameHintRegister => '2+ characters, no spaces';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHintRegister => '4+ characters';

  @override
  String get loginConfirmPasswordLabel => 'Confirm Password';

  @override
  String get loginConfirmPasswordHint => 'Re-enter your password';

  @override
  String get loginSubmitRegister => 'Sign Up';

  @override
  String get loginNicknameLabel => 'Nickname';

  @override
  String get loginNicknameHint => '2-10 characters, no spaces';

  @override
  String get loginCheckAvailability => 'Check';

  @override
  String get loginSetNicknameTitle => 'Set Nickname';

  @override
  String get loginSetNicknameDesc => 'Choose a nickname to use in the game';

  @override
  String get loginGetStarted => 'Get Started';

  @override
  String get lobbyRoomInviteTitle => 'Room Invite';

  @override
  String lobbyRoomInviteMessage(String nickname) {
    return '$nickname invited you to a room!';
  }

  @override
  String get lobbyDecline => 'Decline';

  @override
  String get lobbyJoin => 'Join';

  @override
  String get lobbyInviteFriendsTitle => 'Invite Friends';

  @override
  String get lobbyNoOnlineFriends => 'No online friends available to invite';

  @override
  String lobbyInviteSent(String nickname) {
    return 'Invitation sent to $nickname';
  }

  @override
  String get lobbyInvite => 'Invite';

  @override
  String get lobbySpectatorListTitle => 'Spectator List';

  @override
  String get lobbyNoSpectators => 'No one is spectating';

  @override
  String get lobbyRoomSettingsTitle => 'Room Settings';

  @override
  String get lobbyEnterRoomTitle => 'Enter a room title';

  @override
  String get lobbyChange => 'Change';

  @override
  String get lobbyCreateRoom => 'Create Room';

  @override
  String get lobbyCreateRoomSubtitle =>
      'Set a room title and rules, and the waiting room opens right away.';

  @override
  String get lobbySelectGame => 'Select Game';

  @override
  String get lobbySelectGameDesc => 'Choose the game to play.';

  @override
  String get lobbyTichu => 'Tichu';

  @override
  String get lobbySkullKing => 'Skull King';

  @override
  String get lobbyMaxPlayers => 'Max Players';

  @override
  String lobbyPlayerCount(int count) {
    return '${count}P';
  }

  @override
  String get lobbyExpansionOptional => 'Expansions (Optional)';

  @override
  String get lobbyExpansionDesc =>
      'Add special cards to the base rules. Multiple selections allowed.';

  @override
  String get lobbyExpKraken => 'Kraken';

  @override
  String get lobbyExpKrakenDesc => 'Void a trick';

  @override
  String get lobbyExpWhiteWhale => 'White Whale';

  @override
  String get lobbyExpWhiteWhaleDesc => 'Neutralize special cards';

  @override
  String get lobbyExpLoot => 'Loot';

  @override
  String get lobbyExpLootDesc => 'Bonus points';

  @override
  String get lobbyBasicInfo => 'Basic Info';

  @override
  String get lobbyBasicInfoDesc => 'Set the room name and visibility.';

  @override
  String get lobbyRoomName => 'Room Name';

  @override
  String get lobbyRandom => 'Random';

  @override
  String get lobbyPrivateRoom => 'Private Room';

  @override
  String get lobbyPrivateRoomDescRanked =>
      'Cannot create a private room in ranked play.';

  @override
  String get lobbyPrivateRoomDesc =>
      'Only invited players or those with the password can join.';

  @override
  String get lobbyPasswordHint => 'Password (4+ characters)';

  @override
  String get lobbyRanked => 'Ranked';

  @override
  String get lobbyRankedDesc =>
      'Score is fixed at 1000 and private settings are automatically disabled.';

  @override
  String get lobbyRankedDescSk =>
      'Private settings are automatically disabled.';

  @override
  String get lobbyRankedDescMighty =>
      'Score is fixed at 50 and private settings are automatically disabled.';

  @override
  String get lobbyGameSettings => 'Game Settings';

  @override
  String get lobbyGameSettingsDescSk => 'Set the turn time.';

  @override
  String get lobbyGameSettingsDescTichu =>
      'Set the turn time and target score.';

  @override
  String get lobbyTimeLimit => 'Time Limit';

  @override
  String get lobbySuffixSeconds => 'sec';

  @override
  String get lobbyTargetScore => 'Target Score';

  @override
  String get lobbySuffixPoints => 'pts';

  @override
  String get lobbyTimeLimitRange => '10–999';

  @override
  String get lobbyTargetScoreRange => '100–20000';

  @override
  String get lobbyTargetScoreRangeMighty => '10–500';

  @override
  String get lobbyTargetScoreFixed => '1000 (fixed)';

  @override
  String get lobbyTargetScoreFixedMighty => '50 (fixed)';

  @override
  String get lobbyRankedFixedScoreInfo =>
      'Ranked play uses a fixed target score of 1000.';

  @override
  String get lobbyRankedInfoSk =>
      'Private rooms are not available in ranked play.';

  @override
  String get lobbyRankedInfoMighty =>
      'Ranked play uses a fixed target score of 50. Private rooms are not available.';

  @override
  String get lobbyNormalSettingsInfo =>
      'Time limit: 10–999 sec, target score: 100–20000 pts.';

  @override
  String get lobbyNormalSettingsInfoMighty =>
      'Time limit: 10–999 sec, target score: 10–500 pts.';

  @override
  String get lobbyNormalSettingsInfoTimeOnly => 'Time limit: 10–999 sec.';

  @override
  String get lobbyEnterRoomName => 'Please enter a room name.';

  @override
  String get lobbyPasswordTooShort => 'Password must be at least 4 characters.';

  @override
  String get lobbyDuplicateLoginKicked =>
      'You were logged out because another device logged in';

  @override
  String get lobbyRoomListTitle => 'Game Room List';

  @override
  String get lobbyEmptyRoomList => 'No rooms yet!\nWhy not create one?';

  @override
  String get lobbySkullKingBadge => '☠️ Skull King';

  @override
  String get lobbyTichuBadge => 'Tichu';

  @override
  String lobbyRoomTimeSec(int seconds) {
    return '${seconds}s';
  }

  @override
  String lobbyRoomTimeAndScore(int seconds, int score) {
    return '${seconds}s · ${score}pts';
  }

  @override
  String get lobbyExpKrakenShort => 'Kraken';

  @override
  String get lobbyExpWhaleShort => 'Whale';

  @override
  String get lobbyExpLootShort => 'Loot';

  @override
  String lobbyInProgress(int count) {
    return 'Spectating $count';
  }

  @override
  String get lobbySocialLinkRequired => 'Social Link Required';

  @override
  String get lobbySocialLinkRequiredDesc =>
      'Ranked play requires a linked social account.\nGo to Settings > Social Link to link your Google or Kakao account.';

  @override
  String get lobbyJoinPrivateRoom => 'Join Private Room';

  @override
  String get lobbyEnter => 'Enter';

  @override
  String get lobbySpectatePrivateRoom => 'Spectate Private Room';

  @override
  String get lobbySpectate => 'Spectate';

  @override
  String get lobbyPassword => 'Password';

  @override
  String get lobbyMessageHint => 'Type a message...';

  @override
  String get lobbyChat => 'Chat';

  @override
  String get lobbyViewProfile => 'View Profile';

  @override
  String get lobbyAddFriend => 'Add Friend';

  @override
  String get lobbyUnblock => 'Unblock';

  @override
  String get lobbyBlock => 'Block';

  @override
  String get lobbyUnblocked => 'User has been unblocked';

  @override
  String get lobbyBlocked => 'User has been blocked';

  @override
  String get lobbyFriendRequestSent => 'Friend request sent';

  @override
  String get lobbyReport => 'Report';

  @override
  String get lobbyWaitingRoomTools => 'Waiting Room Tools';

  @override
  String get lobbyWaitingRoomToolsDesc =>
      'Features not directly related to game preparation can be found here.';

  @override
  String get lobbyFriendsDm => 'Friends / DM';

  @override
  String lobbyUnreadDmCount(int count) {
    return 'You have $count unread requests and DMs.';
  }

  @override
  String get lobbyFriendsDmDesc =>
      'View your friends list and DM conversations.';

  @override
  String lobbyCurrentSpectators(int count) {
    return 'View $count current spectators.';
  }

  @override
  String get lobbyMore => 'More';

  @override
  String get lobbyRoomSettings => 'Settings';

  @override
  String get lobbySkullKingRanked => 'Skull King - Ranked';

  @override
  String get lobbyTichuRanked => 'Tichu - Ranked';

  @override
  String get lobbyMightyRanked => 'Mighty - Ranked';

  @override
  String get lobbyTichuRandomSeating => 'Tichu - Random Teams';

  @override
  String get lobbyRandomSeatingOn => 'Random teams';

  @override
  String get lobbyRandomSeatingOff => 'Fixed teams';

  @override
  String lobbySkullKingPlayers(int count) {
    return 'Skull King · ${count}P';
  }

  @override
  String get lobbyStartGame => 'Start Game';

  @override
  String get lobbyReady => 'Ready';

  @override
  String get lobbyReadyDone => 'Ready!';

  @override
  String lobbyReportTitle(String nickname) {
    return 'Report $nickname';
  }

  @override
  String get lobbyReportWarning =>
      'Reports are reviewed by the moderation team.\nFalse reports may result in penalties.';

  @override
  String get lobbySelectReason => 'Select Reason';

  @override
  String get lobbyReportDetailHint => 'Enter details (optional)';

  @override
  String get lobbyReportReasonAbuse => 'Abuse/Insults';

  @override
  String get lobbyReportReasonSpam => 'Spam/Flooding';

  @override
  String get lobbyReportReasonNickname => 'Inappropriate Nickname';

  @override
  String get lobbyReportReasonGameplay => 'Gameplay Disruption';

  @override
  String get lobbyReportReasonOther => 'Other';

  @override
  String get lobbyProfileNotFound => 'Profile not found';

  @override
  String get lobbyMyProfile => 'My Profile';

  @override
  String get lobbyPlayerProfile => 'Player Profile';

  @override
  String get lobbyAlreadyFriend => 'Already friends';

  @override
  String get lobbyRequestPending => 'Request pending';

  @override
  String get lobbyTichuSeasonRanked => 'Tichu Season Ranked';

  @override
  String get lobbySkullKingSeasonRanked => 'Skull King Season Ranked';

  @override
  String get lobbyTichuRecord => 'Tichu Record';

  @override
  String get lobbySkullKingRecord => 'Skull King Record';

  @override
  String get lobbyLoveLetterRecord => 'Love Letter Record';

  @override
  String get lobbyStatRecord => 'Record';

  @override
  String get lobbyStatWinRate => 'Win Rate';

  @override
  String lobbyRecordFormat(int games, int wins, int losses) {
    return '${games}G ${wins}W ${losses}L';
  }

  @override
  String lobbyRecentMatches(int count) {
    return 'Recent Matches ($count)';
  }

  @override
  String get lobbyRecentMatchesTitle => 'Recent Matches';

  @override
  String lobbyRecentMatchesDesc(int count) {
    return 'View results of the last $count matches.';
  }

  @override
  String get lobbySeeMore => 'See More';

  @override
  String get lobbyNoRecentMatches => 'No recent matches';

  @override
  String get lobbyMatchDesertion => 'D';

  @override
  String get lobbyMatchDraw => 'D';

  @override
  String get lobbyMatchWin => 'W';

  @override
  String get lobbyMatchLoss => 'L';

  @override
  String get lobbyMatchTypeSkullKing => 'Skull King';

  @override
  String get lobbyMatchTypeLoveLetter => 'Love Letter';

  @override
  String get lobbyMatchTypeRanked => 'Ranked';

  @override
  String get lobbyMatchTypeNormal => 'Normal';

  @override
  String lobbyRankAndScore(String rank, int score) {
    return '#$rank (${score}pts)';
  }

  @override
  String get lobbyMannerGood => 'Good';

  @override
  String get lobbyMannerNormal => 'Normal';

  @override
  String get lobbyMannerBad => 'Bad';

  @override
  String get lobbyMannerVeryBad => 'Very Bad';

  @override
  String get lobbyMannerWorst => 'Terrible';

  @override
  String lobbyManner(String label) {
    return 'Manner $label';
  }

  @override
  String lobbyDesertions(int count) {
    return 'Desertions $count';
  }

  @override
  String get lobbyKick => 'Kick';

  @override
  String lobbyKickConfirm(String playerName) {
    return 'Kick $playerName?';
  }

  @override
  String get lobbyHost => 'Host';

  @override
  String get lobbyBot => 'Bot';

  @override
  String get lobbyBotSpeedTitle => 'Bot Speed';

  @override
  String get lobbyBotSpeedFast => 'Fast';

  @override
  String get lobbyBotSpeedNormal => 'Normal';

  @override
  String get lobbyBotSpeedSlow => 'Slow';

  @override
  String get lobbyEmptySlot => '[Empty]';

  @override
  String get lobbySlotBlocked => '[Blocked]';

  @override
  String get lobbyMaintenanceDefault => 'Server maintenance scheduled';

  @override
  String lobbyRoomInfoSk(int seconds, int players, int maxPlayers) {
    return '${seconds}s · $players/${maxPlayers}P';
  }

  @override
  String lobbyRoomInfoTichu(int seconds, int score) {
    return '${seconds}s · ${score}pts';
  }

  @override
  String get lobbyRandomAdjTichu1 => 'Joyful';

  @override
  String get lobbyRandomAdjTichu2 => 'Exciting';

  @override
  String get lobbyRandomAdjTichu3 => 'Passionate';

  @override
  String get lobbyRandomAdjTichu4 => 'Fiery';

  @override
  String get lobbyRandomAdjTichu5 => 'Lucky';

  @override
  String get lobbyRandomAdjTichu6 => 'Legendary';

  @override
  String get lobbyRandomAdjTichu7 => 'Supreme';

  @override
  String get lobbyRandomAdjTichu8 => 'Invincible';

  @override
  String get lobbyRandomNounTichu1 => 'Tichu Room';

  @override
  String get lobbyRandomNounTichu2 => 'Card Game';

  @override
  String get lobbyRandomNounTichu3 => 'Showdown';

  @override
  String get lobbyRandomNounTichu4 => 'Round';

  @override
  String get lobbyRandomNounTichu5 => 'Game';

  @override
  String get lobbyRandomNounTichu6 => 'Battle';

  @override
  String get lobbyRandomNounTichu7 => 'Challenge';

  @override
  String get lobbyRandomNounTichu8 => 'Party';

  @override
  String get lobbyRandomAdjSk1 => 'Fearsome';

  @override
  String get lobbyRandomAdjSk2 => 'Legendary';

  @override
  String get lobbyRandomAdjSk3 => 'Invincible';

  @override
  String get lobbyRandomAdjSk4 => 'Ruthless';

  @override
  String get lobbyRandomAdjSk5 => 'Greedy';

  @override
  String get lobbyRandomAdjSk6 => 'Supreme';

  @override
  String get lobbyRandomAdjSk7 => 'Stormy';

  @override
  String get lobbyRandomAdjSk8 => 'Bold';

  @override
  String get lobbyRandomNounSk1 => 'Pirate Ship';

  @override
  String get lobbyRandomNounSk2 => 'Treasure Island';

  @override
  String get lobbyRandomNounSk3 => 'Voyage';

  @override
  String get lobbyRandomNounSk4 => 'Plunder';

  @override
  String get lobbyRandomNounSk5 => 'Captain';

  @override
  String get lobbyRandomNounSk6 => 'Sea Battle';

  @override
  String get lobbyRandomNounSk7 => 'Adventure';

  @override
  String get lobbyRandomNounSk8 => 'Kraken';

  @override
  String get skGameRecoveringGame => 'Recovering game...';

  @override
  String get skGameCheckingState => 'Checking game state...';

  @override
  String get skGameReloadingRoom => 'Reloading room info...';

  @override
  String get skGameLoadingState => 'Loading game state...';

  @override
  String get skGameSpectatorWaitingTitle =>
      'Spectating Skull King Waiting Room';

  @override
  String get skGameSpectatorWaitingDesc =>
      'Viewing the room before the game starts. The spectator screen will load automatically once the game begins.';

  @override
  String get skGameHost => 'Host';

  @override
  String get skGameReady => 'Ready';

  @override
  String get skGameWaiting => 'Waiting';

  @override
  String get skGameSpectatorStandby => 'Spectator Standby';

  @override
  String get skGameSpectatorListTitle => 'Spectator List';

  @override
  String get skGameNoSpectators => 'No one is spectating';

  @override
  String get skGameAlwaysAccept => 'Always Accept';

  @override
  String get skGameAlwaysReject => 'Always Reject';

  @override
  String skGameRoundTrick(int round, int trick) {
    return 'Round $round Trick $trick';
  }

  @override
  String get skGameSpectating => 'Spectating';

  @override
  String skGameBiddingInProgress(String name) {
    return 'Bidding in progress · Leader: $name';
  }

  @override
  String skGamePlayerTurn(String name) {
    return '$name\'s turn';
  }

  @override
  String get skGameLeaveTitle => 'Leave Game';

  @override
  String get skGameLeaveConfirm => 'Are you sure you want to leave the game?';

  @override
  String get skGameLeaveButton => 'Leave';

  @override
  String skGameLeaderLabel(String name) {
    return 'Leader: $name';
  }

  @override
  String get skGameMyTurn => 'My Turn';

  @override
  String skGameWaitingFor(String name) {
    return 'Waiting for $name';
  }

  @override
  String skGameSecondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String get skGameTapToRequestCards =>
      'Tap a profile above to request to view their hand';

  @override
  String skGameRequestingCardView(String name) {
    return 'Requesting to view $name\'s hand...';
  }

  @override
  String skGamePlayerHand(String name) {
    return '$name\'s hand';
  }

  @override
  String get skGameNoCards => 'No cards';

  @override
  String skGameCardViewRejected(String name) {
    return '$name declined the request. Tap another player.';
  }

  @override
  String skGameTimeout(String name) {
    return '$name timed out!';
  }

  @override
  String skGameDesertionTimeout(String name) {
    return '$name deserted! (3 timeouts)';
  }

  @override
  String skGameDesertionLeave(String name) {
    return '$name left the game';
  }

  @override
  String skGameCardViewRequest(String name) {
    return '$name is requesting to view your hand';
  }

  @override
  String get skGameReject => 'Reject';

  @override
  String get skGameAllow => 'Allow';

  @override
  String get skGameChat => 'Chat';

  @override
  String get skGameMessageHint => 'Type a message...';

  @override
  String get skGameViewingMyHand => 'Viewing my hand';

  @override
  String get skGameNoViewers => 'No one is watching';

  @override
  String get skGameViewProfile => 'View Profile';

  @override
  String get skGameBlock => 'Block';

  @override
  String get skGameUnblock => 'Unblock';

  @override
  String get skGameScoreHistory => 'Score History';

  @override
  String get skGameBiddingPhase => 'Bidding...';

  @override
  String get skGamePlayCard => 'Play a card';

  @override
  String get skGameKrakenActivated => '🐙 Kraken activated';

  @override
  String get skGameWhiteWhaleActivated => '🐋 White Whale activated';

  @override
  String get skGameWhiteWhaleNullify =>
      '🐋 White Whale · Special cards nullified';

  @override
  String get skGameTrickVoided => 'Trick Voided';

  @override
  String skGameLeadPlayer(String name) {
    return '$name leads next';
  }

  @override
  String skGameTrickWinner(String name) {
    return '$name wins';
  }

  @override
  String get skGameCheckingCards => 'Checking cards...';

  @override
  String skGameBonusWithLoot(int bonus, int loot) {
    return 'Bonus +$bonus (💰 +$loot)';
  }

  @override
  String skGameBonus(int bonus) {
    return 'Bonus +$bonus';
  }

  @override
  String skGameBidDone(int bid) {
    return 'Bid: $bid wins';
  }

  @override
  String get skGameWaitingOthers => 'Waiting for other players...';

  @override
  String get skGameBidPrompt =>
      'Predict how many tricks you will win this round';

  @override
  String skGameBidSubmit(int bid) {
    return 'Bid $bid wins';
  }

  @override
  String get skGameSelectNumber => 'Select a number';

  @override
  String get skGamePlayCardButton => 'Play Card';

  @override
  String get skGameSelectCard => 'Select a card';

  @override
  String get skGameReset => 'Reset';

  @override
  String get skGameTigressEscape => 'Escape';

  @override
  String get skGameTigressPirate => 'Pirate';

  @override
  String skGameRoundResult(int round) {
    return 'Round $round Results';
  }

  @override
  String get skGameBidTricks => 'Bid/Won';

  @override
  String get skGameBonusHeader => 'Bonus';

  @override
  String get skGameScoreHeader => 'Score';

  @override
  String get skGameNextRoundPreparing => 'Preparing next round...';

  @override
  String get skGameGameOver => 'Game Over';

  @override
  String skGameAutoReturnCountdown(int seconds) {
    return 'Returning to waiting room in ${seconds}s';
  }

  @override
  String get skGameReturningToRoom => 'Returning to waiting room...';

  @override
  String get skGamePlayerProfile => 'Player Profile';

  @override
  String get skGameAlreadyFriend => 'Already friends';

  @override
  String get skGameRequestPending => 'Request pending';

  @override
  String get skGameAddFriend => 'Add Friend';

  @override
  String get skGameFriendRequestSent => 'Friend request sent';

  @override
  String get skGameBlockUser => 'Block';

  @override
  String get skGameUnblockUser => 'Unblock';

  @override
  String get skGameUserBlocked => 'User has been blocked';

  @override
  String get skGameUserUnblocked => 'User has been unblocked';

  @override
  String get skGameProfileNotFound => 'Profile not found';

  @override
  String get skGameTichuRecord => 'Tichu Record';

  @override
  String get skGameSkullKingRecord => 'Skull King Record';

  @override
  String get skGameLoveLetterRecord => 'Love Letter Record';

  @override
  String get skGameStatRecord => 'Record';

  @override
  String get skGameStatWinRate => 'Win Rate';

  @override
  String skGameRecordFormat(int games, int wins, int losses) {
    return '${games}G ${wins}W ${losses}L';
  }

  @override
  String get gameSparrowCall => 'Mahjong Call';

  @override
  String get gameSelectNumberToCall => 'Select a number to call';

  @override
  String get gameNoCall => 'No Call';

  @override
  String get gameCancelPickAnother => 'Cancel and pick another card';

  @override
  String get gameRestoringGame => 'Restoring game...';

  @override
  String get gameCheckingState => 'Checking game state...';

  @override
  String get gameRecheckingRoomState => 'Re-checking current room state.';

  @override
  String get gameReloadingRoom => 'Reloading room info...';

  @override
  String get gameWaitForRestore =>
      'Please wait while restoring to the current game state.';

  @override
  String get gamePreparingScreen => 'Preparing game screen...';

  @override
  String get gameAdjustingScreen => 'Adjusting screen transition state.';

  @override
  String get gameTransitioningScreen => 'Transitioning game screen...';

  @override
  String get gameRecheckingDestination =>
      'Re-checking current destination state.';

  @override
  String get gameSoundEffects => 'Sound Effects';

  @override
  String get gameChat => 'Chat';

  @override
  String get gameMessageHint => 'Type a message...';

  @override
  String get gameMyProfile => 'My Profile';

  @override
  String get gamePlayerProfile => 'Player Profile';

  @override
  String get gameAlreadyFriend => 'Already friends';

  @override
  String get gameRequestPending => 'Request pending';

  @override
  String get gameAddFriend => 'Add Friend';

  @override
  String get gameFriendRequestSent => 'Friend request sent';

  @override
  String get gameUnblock => 'Unblock';

  @override
  String get gameBlock => 'Block';

  @override
  String get gameUnblocked => 'User has been unblocked';

  @override
  String get gameBlocked => 'User has been blocked';

  @override
  String get gameReport => 'Report';

  @override
  String get gameClose => 'Close';

  @override
  String get gameProfileNotFound => 'Profile not found';

  @override
  String get gameTichuSeasonRanked => 'Tichu Season Ranked';

  @override
  String get gameStatRecord => 'Record';

  @override
  String get gameStatWinRate => 'Win Rate';

  @override
  String get gameOverallRecord => 'Overall Record';

  @override
  String gameRecordFormat(int games, int wins, int losses) {
    return '${games}G ${wins}W ${losses}L';
  }

  @override
  String get gameMannerGood => 'Good';

  @override
  String get gameMannerNormal => 'Normal';

  @override
  String get gameMannerBad => 'Bad';

  @override
  String get gameMannerVeryBad => 'Very Bad';

  @override
  String get gameMannerWorst => 'Terrible';

  @override
  String gameManner(String label) {
    return 'Manner $label';
  }

  @override
  String get gameDesertionLabel => 'Desertions';

  @override
  String gameDesertions(int count) {
    return 'Desertions $count';
  }

  @override
  String get gameRecentMatchesTitle => 'Recent Matches';

  @override
  String gameRecentMatchesDesc(int count) {
    return 'View results of the last $count matches.';
  }

  @override
  String get gameRecentMatchesThree => 'Recent Matches (3)';

  @override
  String get gameSeeMore => 'See More';

  @override
  String get gameNoRecentMatches => 'No recent matches';

  @override
  String get gameMatchDesertion => 'D';

  @override
  String get gameMatchDraw => 'D';

  @override
  String get gameMatchWin => 'W';

  @override
  String get gameMatchLoss => 'L';

  @override
  String get gameMatchTypeRanked => 'Ranked';

  @override
  String get gameMatchTypeNormal => 'Normal';

  @override
  String get gameViewProfile => 'View Profile';

  @override
  String get gameCancel => 'Cancel';

  @override
  String get gameReportReasonAbuse => 'Abuse/Insults';

  @override
  String get gameReportReasonSpam => 'Spam/Flooding';

  @override
  String get gameReportReasonNickname => 'Inappropriate Nickname';

  @override
  String get gameReportReasonGameplay => 'Gameplay Disruption';

  @override
  String get gameReportReasonOther => 'Other';

  @override
  String gameReportTitle(String nickname) {
    return 'Report $nickname';
  }

  @override
  String get gameReportWarning =>
      'Reports are reviewed by the moderation team.\nFalse reports may result in penalties.';

  @override
  String get gameSelectReason => 'Select Reason';

  @override
  String get gameReportDetailHint => 'Enter details (optional)';

  @override
  String get gameReportSubmit => 'Report';

  @override
  String get gameLeaveTitle => 'Leave Game';

  @override
  String get gameLeaveConfirm =>
      'Are you sure you want to leave?\nLeaving mid-game harms your team.';

  @override
  String get gameLeave => 'Leave';

  @override
  String get gameCallError => 'You must play the called number first!';

  @override
  String gameTimeout(String playerName) {
    return '$playerName timed out!';
  }

  @override
  String gameDesertionTimeout(String playerName) {
    return '$playerName deserted! (3 timeouts)';
  }

  @override
  String gameDesertionLeave(String playerName) {
    return '$playerName has left the game';
  }

  @override
  String get gameSpectator => 'Spectator';

  @override
  String gameCardViewRequest(String nickname) {
    return '$nickname is requesting to view your cards';
  }

  @override
  String get gameReject => 'Reject';

  @override
  String get gameAllow => 'Allow';

  @override
  String get gameAlwaysReject => 'Always Reject';

  @override
  String get gameAlwaysAllow => 'Always Allow';

  @override
  String get gameSpectatorList => 'Spectator List';

  @override
  String get gameNoSpectators => 'No one is spectating';

  @override
  String get gameViewingMyCards => 'Viewing my cards';

  @override
  String get gameNoViewers => 'No one is viewing';

  @override
  String get gamePartner => 'Partner';

  @override
  String get gameLeftPlayer => 'Left';

  @override
  String get gameRightPlayer => 'Right';

  @override
  String get gameMyTurn => 'My Turn!';

  @override
  String gamePlayerTurn(String name) {
    return '$name\'s turn';
  }

  @override
  String gameCall(String rank) {
    return 'Call $rank';
  }

  @override
  String get gameMyTurnShort => 'My Turn';

  @override
  String gamePlayerTurnShort(String name) {
    return '$name Turn';
  }

  @override
  String gamePlayerWaiting(String name) {
    return '$name Waiting';
  }

  @override
  String gameTimerLabel(String turnLabel, int seconds) {
    return '$turnLabel ${seconds}s';
  }

  @override
  String get gameScoreHistory => 'Score History';

  @override
  String get gameScoreHistorySubtitle =>
      'Round-by-round scores and current totals';

  @override
  String get gameNoCompletedRounds => 'No completed rounds yet';

  @override
  String gameTeamLabel(String label) {
    return 'Team $label';
  }

  @override
  String gameDogPlayedBy(String name) {
    return '$name played the Dog';
  }

  @override
  String get gameDogPlayed => 'The Dog was played';

  @override
  String get gamePlayedCards => '\'s play';

  @override
  String get gamePlay => 'Play';

  @override
  String get gamePass => 'Pass';

  @override
  String get gameLargeTichuQuestion => 'Large Tichu?';

  @override
  String get gameDeclare => 'Declare!';

  @override
  String get gameSmallTichuDeclare => 'Declare Small Tichu';

  @override
  String get gameSmallTichuConfirmTitle => 'Declare Small Tichu';

  @override
  String get gameSmallTichuConfirmContent =>
      'Declare Small Tichu?\n+100 points on success, -100 on failure';

  @override
  String get gameDeclareButton => 'Declare';

  @override
  String get gameSelectRecipient => 'Select who to give card to';

  @override
  String gameSelectExchangeCard(int count) {
    return 'Select card to exchange ($count/3)';
  }

  @override
  String get gameReset => 'Reset';

  @override
  String get gameExchangeComplete => 'Exchange Done';

  @override
  String get gameDragonQuestion =>
      'Who would you like to give the Dragon trick to?';

  @override
  String get gameSelectCallRank => 'Select a number to call';

  @override
  String get gameGameEnd => 'Game Over!';

  @override
  String get gameRoundEnd => 'Round Over!';

  @override
  String get gameMyTeamWin => 'Our Team Wins!';

  @override
  String get gameEnemyTeamWin => 'Opponent Wins!';

  @override
  String get gameDraw => 'Draw!';

  @override
  String get gameThisRound => 'This round: ';

  @override
  String get gameTotalScore => 'Total: ';

  @override
  String get gameAutoReturnLobby => 'Returning to lobby in 3 seconds...';

  @override
  String get gameAutoNextRound => 'Auto-continuing in 3 seconds...';

  @override
  String gameRankedScore(int score) {
    return 'Ranked Score $score';
  }

  @override
  String get gameRankDiamond => 'Diamond';

  @override
  String get gameRankGold => 'Gold';

  @override
  String get gameRankSilver => 'Silver';

  @override
  String get gameRankBronze => 'Bronze';

  @override
  String gameFinishPosition(int position) {
    return 'Place $position!';
  }

  @override
  String gameCardCount(int count) {
    return '$count cards';
  }

  @override
  String get gamePhaseLargeTichu => 'Large Tichu Declaration';

  @override
  String get gamePhaseDealing => 'Dealing Cards';

  @override
  String get gamePhaseExchange => 'Card Exchange';

  @override
  String get gamePhasePlaying => 'Game in Progress';

  @override
  String get gamePhaseRoundEnd => 'Round Over';

  @override
  String get gamePhaseGameEnd => 'Game Over';

  @override
  String get gameReceivedCards => 'Received Cards';

  @override
  String get gameBadgeLarge => 'Large';

  @override
  String get gameBadgeSmall => 'Small';

  @override
  String get gameNotAfk => 'Not AFK';

  @override
  String get spectatorRecovering => 'Recovering spectator view...';

  @override
  String get spectatorTransitioning => 'Transitioning spectator view...';

  @override
  String get spectatorRecheckingState => 'Rechecking current spectator state.';

  @override
  String get spectatorWatching => 'Spectating';

  @override
  String get spectatorWaitingForGame => 'Waiting for game to start...';

  @override
  String get spectatorSit => 'Sit';

  @override
  String get spectatorHost => 'Host';

  @override
  String get spectatorReady => 'Ready';

  @override
  String get spectatorWaiting => 'Waiting';

  @override
  String spectatorTeamWin(String team) {
    return 'Team $team wins!';
  }

  @override
  String get spectatorDraw => 'Draw!';

  @override
  String spectatorTeamScores(int scoreA, int scoreB) {
    return 'Team A: $scoreA | Team B: $scoreB';
  }

  @override
  String get spectatorAutoReturn => 'Moving to waiting room in 3s...';

  @override
  String get spectatorPhaseLargeTichu => 'Large Tichu';

  @override
  String get spectatorPhaseCardExchange => 'Card Exchange';

  @override
  String get spectatorPhasePlaying => 'Playing';

  @override
  String get spectatorPhaseRoundEnd => 'Round Over';

  @override
  String get spectatorPhaseGameEnd => 'Game Over';

  @override
  String get spectatorFinished => 'Done';

  @override
  String spectatorRequesting(int count) {
    return 'Requesting... ($count cards)';
  }

  @override
  String spectatorRequestCardView(int count) {
    return 'View hand ($count cards)';
  }

  @override
  String get spectatorSoundEffects => 'Sound Effects';

  @override
  String get spectatorListTitle => 'Spectator List';

  @override
  String get spectatorNoSpectators => 'No spectators';

  @override
  String get spectatorClose => 'Close';

  @override
  String get spectatorChat => 'Chat';

  @override
  String get spectatorMessageHint => 'Type a message...';

  @override
  String get spectatorNewTrick => 'New trick';

  @override
  String spectatorPlayedCards(String name) {
    return '$name\'s play';
  }

  @override
  String get rulesTitle => 'Game Rules';

  @override
  String get rulesTabTichu => 'Tichu';

  @override
  String get rulesTabSkullKing => 'Skull King';

  @override
  String get rulesTabLoveLetter => 'Love Letter';

  @override
  String get rulesTichuGoalTitle => 'Game Objective';

  @override
  String get rulesTichuGoalBody =>
      'A trick-taking game for 4 players in 2 teams (partners sit across from each other). The first team to reach the target score wins.';

  @override
  String get rulesTichuCardCompositionTitle =>
      'Card Composition (56 cards total)';

  @override
  String get rulesTichuNumberCards => 'Number Cards (2 – A)';

  @override
  String get rulesTichuNumberCardsSub => '4 suits × 13 cards';

  @override
  String get rulesTichuMahjong => 'Mahjong';

  @override
  String get rulesTichuMahjongSub => 'Card that starts the game';

  @override
  String get rulesTichuDog => 'Dog';

  @override
  String get rulesTichuDogSub => 'Passes the lead to your partner';

  @override
  String get rulesTichuPhoenix => 'Phoenix';

  @override
  String get rulesTichuPhoenixSub => 'Wild card (-25 points)';

  @override
  String get rulesTichuDragon => 'Dragon';

  @override
  String get rulesTichuDragonSub => 'Strongest card (+25 points)';

  @override
  String get rulesTichuSpecialTitle => 'Special Card Rules';

  @override
  String get rulesTichuSpecialMahjongTitle => 'Mahjong';

  @override
  String get rulesTichuSpecialMahjongLine1 =>
      'The player holding this card leads the very first trick.';

  @override
  String get rulesTichuSpecialMahjongLine2 =>
      'When playing the Mahjong, you may declare a number (2–14). The next player must include that number in their combination if they have it (ignored if they don\'t).';

  @override
  String get rulesTichuSpecialDogTitle => 'Dog';

  @override
  String get rulesTichuSpecialDogLine1 =>
      'Can only be played when leading. Immediately passes the lead to your partner.';

  @override
  String get rulesTichuSpecialDogLine2 => 'Worth 0 points in scoring.';

  @override
  String get rulesTichuSpecialPhoenixTitle => 'Phoenix';

  @override
  String get rulesTichuSpecialPhoenixLine1 =>
      'When played as a single, it counts as the previous card\'s value + 0.5. However, it cannot beat the Dragon.';

  @override
  String get rulesTichuSpecialPhoenixLine2 =>
      'In combinations (Pair/Triple/Full House/Straight, etc.) it can substitute for any number.';

  @override
  String get rulesTichuSpecialPhoenixLine3 =>
      'Worth -25 points, so taking it is a disadvantage.';

  @override
  String get rulesTichuSpecialDragonTitle => 'Dragon';

  @override
  String get rulesTichuSpecialDragonLine1 =>
      'The strongest card; can only be played as a single.';

  @override
  String get rulesTichuSpecialDragonLine2 =>
      'Worth +25 points, but the trick won with the Dragon must be given to one opponent.';

  @override
  String get rulesTichuDeclarationTitle => 'Tichu Declaration';

  @override
  String get rulesTichuDeclarationBody =>
      'A Tichu declaration is a bet that you will be the first to empty your hand this round. Success earns bonus points for your team; failure deducts points.';

  @override
  String get rulesTichuLargeTichu => 'Large Tichu';

  @override
  String get rulesTichuLargeTichuWhen =>
      'Declared after receiving only the first 8 cards (before seeing the remaining 6)';

  @override
  String get rulesTichuSmallTichu => 'Small Tichu';

  @override
  String get rulesTichuSmallTichuWhen =>
      'Declared after receiving all 14 cards, but before playing any card';

  @override
  String rulesTichuDeclSuccess(String points) {
    return 'Success $points';
  }

  @override
  String rulesTichuDeclFail(String points) {
    return 'Fail $points';
  }

  @override
  String get rulesTichuFlowTitle => 'Turn Sequence';

  @override
  String get rulesTichuFlowBody =>
      '1. All players receive 8 cards each.\n2. After viewing 8 cards, you may declare Large Tichu.\n3. The remaining 6 cards are dealt, totaling 14.\n4. Each player passes 1 card to each of the other 3 players.\n5. After the exchange, before playing any card, you may declare Small Tichu.\n6. The player holding the Mahjong leads the first trick.';

  @override
  String get rulesTichuPlayTitle => 'Play Rules';

  @override
  String get rulesTichuPlayBody =>
      '• You can only play the same type of combination as the leading play, but higher. (e.g., a higher single over a single, a higher pair over a pair)\n• Available combinations:\n   - Single (1 card)\n   - Pair (2 cards of the same number)\n   - Triple (3 cards of the same number)\n   - Full House (Triple + Pair)\n   - Straight (5+ consecutive numbers)\n   - Consecutive Pairs (2+ consecutive pairs = 4+ cards)\n• You may pass on your turn if you cannot or do not want to play.';

  @override
  String get rulesTichuBombTitle => 'Bomb';

  @override
  String get rulesTichuBombBody =>
      'A Bomb can be played at any time, even out of turn, and beats any combination.\n\n• Four-of-a-Kind Bomb: 4 cards of the same number (e.g., 7♠ 7♥ 7♦ 7♣)\n• Straight Flush Bomb: 5+ consecutive cards of the same suit\n\nBomb hierarchy:\n  Straight Flush > Four-of-a-Kind\n  Same type: higher number / longer straight wins';

  @override
  String get rulesTichuScoringTitle => 'Scoring';

  @override
  String get rulesTichuScoringBody =>
      'Card points:\n• 5: 5 points\n• 10, K: 10 points\n• Dragon: +25 points / Phoenix: -25 points\n• All other cards: 0 points\n\nRound settlement:\n• The player who finishes 1st takes all trick points collected by the last-place (4th) player.\n• Cards remaining in the last player\'s hand go to the opposing team.\n• If both partners on one team finish 1st and 2nd (\"Double Victory\"), that round ends immediately — the winning team gets +200 points (no trick point calculation).\n• Tichu declaration success/failure bonuses are added on top.';

  @override
  String get rulesTichuWinTitle => 'Victory Condition';

  @override
  String get rulesTichuWinBody =>
      'The first team to reach the target score (default 1000 points) set when creating the room wins. Ranked games use a fixed target of 1000 points.';

  @override
  String get rulesSkGoalTitle => 'Game Objective';

  @override
  String get rulesSkGoalBody =>
      'A trick-taking game for 2–6 players (free-for-all). Over 10 rounds, you must accurately predict the number of tricks you will win each round to score points.';

  @override
  String get rulesSkCardCompositionTitle => 'Card Composition (65 base cards)';

  @override
  String get rulesSkNumberCards => 'Number Cards (1 – 13)';

  @override
  String get rulesSkNumberCardsSub =>
      '4 suits × 13 cards (Yellow / Green / Purple / Black)';

  @override
  String get rulesSkEscape => 'Escape';

  @override
  String get rulesSkEscapeSub => 'Never wins a trick';

  @override
  String get rulesSkPirate => 'Pirate';

  @override
  String get rulesSkPirateSub => 'Beats all number cards';

  @override
  String get rulesSkMermaid => 'Mermaid';

  @override
  String get rulesSkMermaidSub => 'Captures Skull King (+50 bonus)';

  @override
  String get rulesSkSkullKing => 'Skull King';

  @override
  String get rulesSkSkullKingSub => 'Beats Pirates (+30 bonus per Pirate)';

  @override
  String get rulesSkTigress => 'Tigress';

  @override
  String get rulesSkTigressSub => 'Choose to play as Pirate or Escape';

  @override
  String get rulesSkIncludedByDefault => 'Included by default';

  @override
  String rulesSkCardCount(int count) {
    return '$count cards';
  }

  @override
  String get rulesSkTrumpTitle => 'Black suit = Trump';

  @override
  String get rulesSkTrumpBody =>
      'Black number cards beat all other suit number cards regardless of number. However, you must follow the lead suit (the suit of the first number card) if you can, and may only play black when you have no cards of the led suit.';

  @override
  String get rulesSkSpecialTitle => 'Special Card Rules';

  @override
  String get rulesSkSpecialEscapeTitle => 'Escape';

  @override
  String get rulesSkSpecialEscapeLine1 =>
      'Never wins a trick. Can be played at any time regardless of suit following.';

  @override
  String get rulesSkSpecialEscapeLine2 =>
      'If all players play only Escapes, the lead player takes the trick.';

  @override
  String get rulesSkSpecialPirateTitle => 'Pirate';

  @override
  String get rulesSkSpecialPirateLine1 =>
      'Beats all number cards (including black trumps). If multiple Pirates appear in one trick, the first one played wins.';

  @override
  String get rulesSkSpecialPirateLine2 =>
      'Beats Mermaids but loses to Skull King.';

  @override
  String get rulesSkSpecialMermaidTitle => 'Mermaid';

  @override
  String get rulesSkSpecialMermaidLine1 =>
      'Loses to Pirates but captures and beats Skull King.';

  @override
  String get rulesSkSpecialMermaidLine2 =>
      'When a Mermaid captures Skull King, the trick winner gets +50 bonus.';

  @override
  String get rulesSkSpecialMermaidLine3 =>
      'If only Mermaids are present (no Pirates/Skull King), they beat number cards.';

  @override
  String get rulesSkSpecialSkullKingTitle => 'Skull King';

  @override
  String get rulesSkSpecialSkullKingLine1 =>
      'Beats Pirates — +30 bonus per Pirate defeated.';

  @override
  String get rulesSkSpecialSkullKingLine2 =>
      'However, loses to Mermaids (gets captured).';

  @override
  String get rulesSkSpecialTigressTitle => 'Tigress — 1 card by default';

  @override
  String get rulesSkSpecialTigressLine1 =>
      'When playing, choose either Pirate or Escape.';

  @override
  String get rulesSkSpecialTigressLine2 =>
      'Tigress played as Pirate works identically to a Pirate, including the Skull King\'s +30 bonus.';

  @override
  String get rulesSkSpecialTigressLine3 =>
      'Tigress played as Escape works identically to an Escape and never wins a trick.';

  @override
  String get rulesSkSpecialTigressLine4 =>
      'A Tigress played as Pirate/Escape shows a purple check mark in the top-left corner to distinguish it from regular Pirate/Escape cards.';

  @override
  String get rulesSkTigressPreviewTitle => 'In-game display example';

  @override
  String get rulesSkTigressChoiceEscape => 'Played as Escape';

  @override
  String get rulesSkTigressChoicePirate => 'Played as Pirate';

  @override
  String get rulesSkFlowTitle => 'Turn Sequence';

  @override
  String get rulesSkFlowBody =>
      '1. In Round N, each player receives N cards. (Rounds 1–10)\n2. All players simultaneously predict (bid) the number of tricks they will win.\n3. Starting from the lead player, cards are played following suit-following rules.\n4. After each round, scores are calculated based on bid success/failure.';

  @override
  String get rulesSkScoringTitle => 'Scoring';

  @override
  String get rulesSkScoringBody =>
      '• Bid 0 success (0 tricks won): +10 × round number\n• Bid 0 failure: -10 × round number\n• Bid N success (exactly N tricks won): +20 × N + bonus\n• Bid N failure: -10 × |difference| (no bonus)\n• Bonuses are only awarded when the bid is exact.';

  @override
  String get rulesSkExample1Title => 'Example 1. Simple bid success';

  @override
  String get rulesSkExample1Setup =>
      'Round 3 · Bid 2 · 2 tricks won · No bonus';

  @override
  String get rulesSkExample1Calc => '20 × 2 = 40';

  @override
  String get rulesSkExample1Result => '+40 pts';

  @override
  String get rulesSkExample2Title => 'Example 2. Bid 0 success';

  @override
  String get rulesSkExample2Setup => 'Round 5 · Bid 0 · 0 tricks won';

  @override
  String get rulesSkExample2Calc => '10 × 5 = 50';

  @override
  String get rulesSkExample2Result => '+50 pts';

  @override
  String get rulesSkExample3Title => 'Example 3. Bid failure';

  @override
  String get rulesSkExample3Setup =>
      'Round 5 · Bid 3 · 1 trick won (difference 2)';

  @override
  String get rulesSkExample3Calc => '-10 × 2 = -20';

  @override
  String get rulesSkExample3Result => '-20 pts';

  @override
  String get rulesSkExample4Title => 'Example 4. Skull King captures 2 Pirates';

  @override
  String get rulesSkExample4Setup =>
      'Round 3 · Bid 2 · 2 tricks won · Bonus +60 (2 Pirates × 30)';

  @override
  String get rulesSkExample4Calc => '(20 × 2) + 60 = 100';

  @override
  String get rulesSkExample4Result => '+100 pts';

  @override
  String get rulesSkExample5Title => 'Example 5. Mermaid captures Skull King';

  @override
  String get rulesSkExample5Setup =>
      'Round 4 · Bid 1 · 1 trick won · Bonus +50 (Mermaid × SK)';

  @override
  String get rulesSkExample5Calc => '(20 × 1) + 50 = 70';

  @override
  String get rulesSkExample5Result => '+70 pts';

  @override
  String get rulesSkExample6Title => 'Example 6. Bid 0 failure (took a trick)';

  @override
  String get rulesSkExample6Setup => 'Round 7 · Bid 0 · 1 trick won';

  @override
  String get rulesSkExample6Calc => '-10 × 7 = -70';

  @override
  String get rulesSkExample6Result => '-70 pts';

  @override
  String get rulesSkWinTitle => 'Victory Condition';

  @override
  String get rulesSkWinBody =>
      'After all 10 rounds, the player with the highest cumulative score wins.';

  @override
  String get rulesSkExpansionTitle => 'Expansions (Optional)';

  @override
  String get rulesSkExpansionBody =>
      'Each expansion can be individually selected when creating a room. Expansion cards are shuffled into the base deck.';

  @override
  String get rulesSkExpKraken => '🐙 Kraken';

  @override
  String get rulesSkExpKrakenDesc =>
      'A trick containing the Kraken is voided. No one wins the trick and no bonuses are awarded. The player who would have won without the Kraken leads the next trick.';

  @override
  String get rulesSkExpWhiteWhale => '🐋 White Whale';

  @override
  String get rulesSkExpWhiteWhaleDesc =>
      'Neutralizes all special card effects. Only number cards are compared in the trick, and the highest number wins regardless of suit. If no number cards are present, the trick is voided.';

  @override
  String get rulesSkExpLoot => '💰 Loot';

  @override
  String get rulesSkExpLootDesc =>
      'The trick winner earns +20 bonus per Loot card in the trick, and each player who played a Loot card also earns +20 as their own bonus. (Only awarded on bid success)';

  @override
  String get rulesLlGoalTitle => 'Game Objective';

  @override
  String get rulesLlGoalBody =>
      'A card game for 2–4 players. Each round, the last player standing or the player with the highest card when the deck runs out wins a token. The first player to collect enough tokens wins the game.';

  @override
  String get rulesLlCardCompositionTitle => 'Card Composition (16 cards total)';

  @override
  String get rulesLlGuard => 'Guard';

  @override
  String get rulesLlGuardSub => 'Guess an opponent\'s card to eliminate them';

  @override
  String get rulesLlSpy => 'Spy';

  @override
  String get rulesLlSpySub => 'Secretly view an opponent\'s card';

  @override
  String get rulesLlBaron => 'Baron';

  @override
  String get rulesLlBaronSub => 'Compare cards; lower card is eliminated';

  @override
  String get rulesLlHandmaid => 'Handmaid';

  @override
  String get rulesLlHandmaidSub => 'Protected from effects until next turn';

  @override
  String get rulesLlPrince => 'Prince';

  @override
  String get rulesLlPrinceSub => 'Force a player to discard their card';

  @override
  String get rulesLlKing => 'King';

  @override
  String get rulesLlKingSub => 'Swap cards with another player';

  @override
  String get rulesLlCountess => 'Countess';

  @override
  String get rulesLlCountessSub => 'Must be played if holding King or Prince';

  @override
  String get rulesLlPrincess => 'Princess';

  @override
  String get rulesLlPrincessSub => 'Eliminated if played or discarded';

  @override
  String get rulesLlCardEffectsTitle => 'Detailed Card Effects';

  @override
  String get rulesLlEffectGuardTitle => 'Guard (1)';

  @override
  String get rulesLlEffectGuardLine1 =>
      'Name a player and guess a non-Guard card they might hold.';

  @override
  String get rulesLlEffectGuardLine2 =>
      'If correct, that player is eliminated from the round.';

  @override
  String get rulesLlEffectSpyTitle => 'Spy (2)';

  @override
  String get rulesLlEffectSpyLine1 =>
      'Choose a player and secretly look at their hand card.';

  @override
  String get rulesLlEffectBaronTitle => 'Baron (3)';

  @override
  String get rulesLlEffectBaronLine1 =>
      'Choose a player and privately compare hand cards.';

  @override
  String get rulesLlEffectBaronLine2 =>
      'The player with the lower card is eliminated. Ties have no effect.';

  @override
  String get rulesLlEffectHandmaidTitle => 'Handmaid (4)';

  @override
  String get rulesLlEffectHandmaidLine1 =>
      'Until your next turn, you cannot be chosen as the target of any card effect.';

  @override
  String get rulesLlEffectPrinceTitle => 'Prince (5)';

  @override
  String get rulesLlEffectPrinceLine1 =>
      'Choose any player (including yourself) to discard their hand and draw a new card.';

  @override
  String get rulesLlEffectPrinceLine2 =>
      'If they discard the Princess, they are eliminated.';

  @override
  String get rulesLlEffectKingTitle => 'King (6)';

  @override
  String get rulesLlEffectKingLine1 =>
      'Choose a player and swap hand cards with them.';

  @override
  String get rulesLlEffectCountessTitle => 'Countess (7)';

  @override
  String get rulesLlEffectCountessLine1 =>
      'If you hold the King (6) or Prince (5) with the Countess, you must play the Countess.';

  @override
  String get rulesLlEffectCountessLine2 =>
      'Otherwise, it can be freely played and has no effect.';

  @override
  String get rulesLlEffectPrincessTitle => 'Princess (8)';

  @override
  String get rulesLlEffectPrincessLine1 =>
      'If this card is played or discarded for any reason, you are immediately eliminated.';

  @override
  String get rulesLlFlowTitle => 'Turn Sequence';

  @override
  String get rulesLlFlowBody =>
      '1. Remove 1 card face-down from the deck. (In a 2-player game, 3 additional cards are removed face-up.)\n2. Deal 1 card to each player.\n3. On your turn, draw 1 card from the deck, then play 1 of your 2 cards and resolve its effect.\n4. After resolving the effect, play passes to the next player.\n5. The round ends when only 1 player remains or the deck is empty.';

  @override
  String get rulesLlWinTitle => 'Victory Condition';

  @override
  String get rulesLlWinBody =>
      'When the round ends, the surviving player with the highest card (ties broken by total card value) wins a token.\n\nTokens needed to win:\n• 2 players: 4 tokens\n• 3 players: 3 tokens\n• 4 players: 2 tokens';

  @override
  String get rulesTabMighty => 'Mighty';

  @override
  String get rulesMtGoalTitle => 'Game Objective';

  @override
  String get rulesMtGoalBody =>
      'A trick-taking card game for 5 or 6 players. One player becomes the declarer and chooses a friend; together they try to win enough point cards to meet the bid. The remaining players form the defence and try to stop them.\n\nWith 6 players the kill-mighty variant applies automatically. If the host locks one seat, the room plays classic 5-player mighty.';

  @override
  String get rulesMtCardCompositionTitle => 'Card Composition (53 cards)';

  @override
  String get rulesMtCardCompositionBody =>
      'Standard 52-card deck (4 suits × 13 ranks: 2–A) plus 1 Joker.\nCard strength order: A > K > Q > J > 10 > 9 > … > 2\nPoint cards: A = 1 pt, K = 1 pt, Q = 1 pt, J = 1 pt, 10 = 1 pt (total 20 pts)\n\n[Deal]\n• 5 players: 10 cards each + 3-card kitty\n• 6 players: 8 cards each + 5-card kitty';

  @override
  String get rulesMtSpecialTitle => 'Special Cards';

  @override
  String get rulesMtSpecialMightyTitle => 'Mighty';

  @override
  String get rulesMtSpecialMightyLine1 =>
      'The strongest card in the game. Beats everything except the Joker Call.';

  @override
  String get rulesMtSpecialMightyLine2 =>
      'By default it is the Spade Ace. If the trump suit is Spades, the Mighty becomes the Diamond Ace instead.';

  @override
  String get rulesMtSpecialMightyAltLabel => 'when trump = ♠';

  @override
  String get rulesMtSpecialJokerTitle => 'Joker';

  @override
  String get rulesMtSpecialJokerLine1 =>
      'The second-strongest card. Wins any trick unless the Joker Call is played.';

  @override
  String get rulesMtSpecialJokerLine2 =>
      'When leading a trick, the Joker player declares which suit others must follow.\nThe Joker loses its power on the first and last tricks.';

  @override
  String get rulesMtSpecialJokerCallTitle => 'Joker Call';

  @override
  String get rulesMtSpecialJokerCallLine1 =>
      'When the designated Joker-Call card (♣3 by default) leads the trick, the Joker loses its power and is treated as the weakest card.';

  @override
  String get rulesMtSpecialJokerCallLine2 =>
      'If the trump suit is Clubs, the Joker Call becomes ♠3 instead.';

  @override
  String get rulesMtBiddingTitle => 'Bidding';

  @override
  String get rulesMtBiddingBody =>
      'Players bid in turn, stating how many points (out of 20) they will capture.\n\n• Minimum bid: 13 in 5-player mighty, 14 in 6-player kill mighty\n• Maximum bid: 20\n\nThe highest bidder becomes the declarer and chooses the trump suit. If all players pass, the round is redealt (no-game).\n\nA player with a very weak hand may also declare a deal miss for a redeal instead of bidding or passing.';

  @override
  String get rulesMtDealMissTitle => 'Deal Miss';

  @override
  String get rulesMtDealMissBody =>
      'During bidding, a player whose hand is very weak may declare a deal miss.\n\n[Hand scoring]\n• Spade A = 0 pts\n• Joker = cancels the single highest point card in hand\n• A / K / Q / J = 1 pt each\n• 10 = 0.5 pt\n\n[Declaration rules]\n• It must be your turn, and you haven\'t bid or passed yet\n• 5-player: hand score ≤ 0.5\n• 6-player kill mighty: hand score exactly 0\n\n[Effect]\n• Declarer loses 5 points immediately\n• These 5 points accumulate in the \"deal-miss pool\"\n• The deck is reshuffled and the same dealer redeals\n• The pool is awarded as a bonus to the next successful declarer (it carries over on failure)';

  @override
  String get rulesMtKillTitle => 'Kill Declaration (6-player only)';

  @override
  String get rulesMtKillBody =>
      'After bidding ends in 6-player mode, the declarer names one kill target card that is NOT in their own hand.\n\n[① Kill — target is in another player\'s hand]\n• The victim\'s 8 cards + the 5-card kitty = 13 cards are shuffled\n• Declarer receives 5, each of the other 4 survivors receives 2\n• Victim is excluded from the round (scores 0)\n• Play proceeds like 5-player mighty (discard 3, choose friend)\n\n[② Self-KO — target is in the kitty]\n• The declarer\'s 8 cards + the 5-card kitty = 13 cards are shuffled\n• The other 5 players each receive 2; the remaining 3 form a new kitty\n• The declarer is excluded from the round (scores 0)\n• Bidding restarts under 5-player rules (min 13, deal-miss 0.5)';

  @override
  String get rulesMtFriendTitle => 'Friend Declaration';

  @override
  String get rulesMtFriendBody =>
      'After winning the bid, the declarer declares a friend by naming a specific card (e.g. \'Spade King\'). The player who holds that card becomes the declarer\'s secret ally — their identity is revealed when the card is played.\n\nThe declarer may also choose to go alone (no friend), or designate the first trick winner as their friend.';

  @override
  String get rulesMtKittyTitle => 'Kitty Exchange';

  @override
  String get rulesMtKittyBody =>
      'The declarer receives 3 kitty cards and must discard 3 cards from their hand.\n\nDuring this phase, the declarer may raise the bid by +2 (capped at 20), with or without changing the trump suit.';

  @override
  String get rulesMtTrickTitle => 'Trick Rules';

  @override
  String get rulesMtTrickBody =>
      '1. The lead player plays any card, setting the lead suit.\n2. Other players must follow suit if possible.\n3. If you cannot follow suit, you may play any card (including trump).\n4. The highest card of the lead suit wins, unless a trump card is played — in that case the highest trump wins.\n5. Mighty and Joker override normal strength rules.\n6. The trick winner leads the next trick.\n7. On the first trick, you cannot lead with a trump suit card.';

  @override
  String get rulesMtScoringTitle => 'Scoring';

  @override
  String get rulesMtScoringBody =>
      '20 point cards in the deck (A, K, Q, J, 10 × 4 suits = 20).\n\n[Base Score]\n• On success: Base = (Bid − minBid + 1) × 2 + (points collected − bid)\n• On failure: Base = (Bid − minBid + 1) × 1 + (bid − points collected)   ← bigger misses cost more\n(Only the ×2 on the base part is dropped on failure; the multipliers below still apply.)\n\n[Score Distribution]\n• Declarer: Base × 2\n• Friend: Base × 1\n• Each Defender: −Base\nOn failure, signs are reversed.\n\n[Multipliers (multiply base, apply on success and failure, stackable)]\n• Solo (no friend): ×2\n• Run (all 20 pts): ×2\n• No Trump: ×2\n• Bid 20: ×2\nMax multiplier: ×16 (solo + run + NT + bid 20)\n\n[Success example]\nBid 13, collected 15 pts with a friend:\nBase = (1×2) + 2 = 4\nDeclarer +8, Friend +4, Defenders −4 each\n\n[Failure example]\nBid 14, collected 5 pts (short by 9):\nBase = (2×1) + 9 = 11\nDeclarer −22, Friend −11, Defenders +11 each';

  @override
  String get rulesMtWinTitle => 'Victory Condition';

  @override
  String get rulesMtWinBody =>
      'After all 10 tricks are played, count the point cards collected by the declarer\'s team.\n\n• If they meet or exceed the bid → Declarer team wins.\n• If they fall short → Defence team wins.\n\nScores are accumulated over multiple rounds. The player with the highest score at the end of the session wins.';

  @override
  String get mtPhaseBidding => 'Bidding';

  @override
  String get mtPhaseKitty => 'Kitty';

  @override
  String get mtPhasePlaying => 'Playing';

  @override
  String get mtPhaseRoundEnd => 'Round End';

  @override
  String get mtPhaseGameEnd => 'Game End';

  @override
  String mtRoundPhase(Object round, Object phase) {
    return 'R$round $phase';
  }

  @override
  String get mtSolo => 'Solo';

  @override
  String mtFriendLabel(Object label) {
    return 'Friend: $label';
  }

  @override
  String get mtChat => 'Chat';

  @override
  String get mtTypeMessage => 'Type a message...';

  @override
  String get mtLeaveGame => 'Leave Game?';

  @override
  String get mtLeaveConfirm => 'Are you sure you want to leave?';

  @override
  String get mtCancel => 'Cancel';

  @override
  String get mtLeave => 'Leave';

  @override
  String get mtDeclarer => 'Declarer';

  @override
  String get mtFriend => 'Friend';

  @override
  String mtPointCardsTitle(Object name, Object count) {
    return '$name - Point Cards (${count}P)';
  }

  @override
  String get mtNoPointCards => 'No point cards yet';

  @override
  String get mtClose => 'Close';

  @override
  String get mtYourTurn => 'Your turn';

  @override
  String get mtWaiting => 'Waiting...';

  @override
  String mtPlayed(Object current, Object total) {
    return '$current/$total played';
  }

  @override
  String mtFriendRevealed(Object card, Object name) {
    return 'Friend: $card → $name';
  }

  @override
  String mtFriendHidden(Object card) {
    return 'Friend: $card';
  }

  @override
  String mtWins(Object name) {
    return '$name wins!';
  }

  @override
  String mtCurrentBid(Object points, Object suit) {
    return 'Current bid: $points $suit';
  }

  @override
  String get mtPass => 'Pass';

  @override
  String get mtDealMiss => 'Deal miss';

  @override
  String mtDealMissPool(Object points) {
    return 'Deal miss $points';
  }

  @override
  String mtDealMissReveal(Object name, Object score) {
    return '$name declared deal miss with a $score-point hand';
  }

  @override
  String get mtDealMissTapToClose => 'Tap anywhere to dismiss';

  @override
  String get mtKillPhase => 'Kill Declaration';

  @override
  String get mtKillPhasePrompt => 'Choose a card to kill';

  @override
  String mtKillPhaseWait(Object name) {
    return '$name is choosing a card to kill';
  }

  @override
  String mtKillResultKilled(Object declarer, Object target, Object victim) {
    return '$declarer named $target → $victim eliminated';
  }

  @override
  String mtKillResultSuicide(Object declarer, Object target) {
    return '$declarer named $target but it was in the kitty. Self-KO!';
  }

  @override
  String get mtKillExcluded => 'OUT';

  @override
  String get mtKillConfirm => 'Kill';

  @override
  String get mtPoints => 'Points:';

  @override
  String mtBid(Object points, Object suit) {
    return 'Bid $points $suit';
  }

  @override
  String mtWaitingFor(Object name) {
    return 'Waiting for $name';
  }

  @override
  String get mtExchangingKitty => 'Declarer is exchanging kitty...';

  @override
  String get mtDiscard3 => 'Discard 3 cards';

  @override
  String get mtFriendColon => 'Friend:';

  @override
  String get mtNoFriend => 'No Friend';

  @override
  String get mt1stTrick => '1st Trick';

  @override
  String get mtJoker => 'Joker';

  @override
  String get mtCard => 'Card';

  @override
  String get mtConfirm => 'Confirm';

  @override
  String get mtChangeTrump => 'Change Trump';

  @override
  String mtTrumpPenalty(int penalty) {
    return 'Bid +$penalty';
  }

  @override
  String mtPlayTimer(Object seconds) {
    return 'Play (${seconds}s)';
  }

  @override
  String get mtPlay => 'Play';

  @override
  String get mtSelectCard => 'Select a card';

  @override
  String get mtJokerLoses1st => 'Joker loses on 1st trick!';

  @override
  String get mtJokerLosesLast => 'Joker loses on last trick!';

  @override
  String get mtJokerSuit => 'Joker suit: ';

  @override
  String get mtJokerCall => 'Joker Call: ';

  @override
  String get mtYes => 'Yes';

  @override
  String get mtNo => 'No';

  @override
  String mtRoundResult(Object round) {
    return 'Round $round Result';
  }

  @override
  String mtDeclarerWins(Object points) {
    return 'Declarer wins! (${points}P)';
  }

  @override
  String mtDeclarerFails(Object points) {
    return 'Declarer fails (${points}P)';
  }

  @override
  String get mtNextRound => 'Next round preparing...';

  @override
  String get mtGameOver => 'Game Over';

  @override
  String mtReturningIn(Object seconds) {
    return 'Returning in $seconds...';
  }

  @override
  String get mtReturningToRoom => 'Returning to room...';

  @override
  String get mtScoreHistory => 'Score History';

  @override
  String get mtRoundAbbr => 'R';

  @override
  String get mtOpposition => 'Defense';

  @override
  String get mtContract => 'Contract';

  @override
  String get mtResult => 'Result';

  @override
  String get mtTotal => 'Total';

  @override
  String get mtSoloSuffix => '(solo)';

  @override
  String get mtFriendCardJoker => 'Joker';

  @override
  String get mtFriendCardSolo => 'Solo';

  @override
  String get mtFriendCard1st => '1st Trick';

  @override
  String get mtJokerAbbr => 'JK';

  @override
  String get friendsTitle => 'Friends';

  @override
  String get friendsTabFriends => 'Friends';

  @override
  String get friendsTabSearch => 'Search';

  @override
  String get friendsTabRequests => 'Requests';

  @override
  String get friendsEmptyList =>
      'No friends yet!\nSearch and add friends from the Search tab.';

  @override
  String friendsStatusPlayingInRoom(String roomName) {
    return 'Playing in $roomName';
  }

  @override
  String get friendsStatusOnline => 'Online';

  @override
  String get friendsStatusOffline => 'Offline';

  @override
  String get friendsRestrictedDuringGame => 'Restricted during game';

  @override
  String get friendsDmBlockedDuringGame => 'Cannot enter DM chat during a game';

  @override
  String get friendsInvited => 'Invited';

  @override
  String get friendsInvite => 'Invite';

  @override
  String friendsInviteSent(String nickname) {
    return 'Sent an invite to $nickname';
  }

  @override
  String get friendsJoinRoom => 'Join';

  @override
  String get friendsSpectateRoom => 'Spectate';

  @override
  String get friendsSearchHint => 'Search by nickname';

  @override
  String get friendsSearchPrompt => 'Enter a nickname to search';

  @override
  String get friendsSearchNoResults => 'No results found';

  @override
  String get friendsStatusFriend => 'Friend';

  @override
  String get friendsRequestReceived => 'Request received';

  @override
  String get friendsRequestSent => 'Request sent';

  @override
  String friendsRequestSentSnackbar(String nickname) {
    return 'Sent a friend request to $nickname';
  }

  @override
  String get friendsAddFriend => 'Add Friend';

  @override
  String get friendsNoRequests => 'No pending requests';

  @override
  String friendsAccepted(String nickname) {
    return 'You are now friends with $nickname';
  }

  @override
  String get friendsAccept => 'Accept';

  @override
  String get friendsReject => 'Reject';

  @override
  String get friendsDmEmpty => 'No messages.\nSend the first message!';

  @override
  String get friendsDmInputHint => 'Enter a message';

  @override
  String get friendsRemoveTitle => 'Remove Friend';

  @override
  String friendsRemoveConfirm(String nickname) {
    return 'Remove $nickname from your friends list?';
  }

  @override
  String friendsRemoved(String nickname) {
    return 'Removed $nickname from your friends list';
  }

  @override
  String get rankingTitle => 'Rankings';

  @override
  String get rankingTichu => 'Tichu';

  @override
  String get rankingSkullKing => 'Skull King';

  @override
  String get rankingNoData => 'No ranking data available';

  @override
  String rankingRecordWithWinRate(
    int total,
    int wins,
    int losses,
    int winRate,
  ) {
    return 'Record ${total}G ${wins}W ${losses}L · Win rate $winRate%';
  }

  @override
  String get rankingSeasonScore => 'Season Score';

  @override
  String get rankingProfileNotFound => 'Profile not found';

  @override
  String get rankingTichuSeasonRanked => 'Tichu Season Ranked';

  @override
  String get rankingTichuRecord => 'Tichu Record';

  @override
  String get rankingSkullKingSeasonRanked => 'Skull King Season Ranked';

  @override
  String get rankingSkullKingRecord => 'Skull King Record';

  @override
  String get rankingMighty => 'Mighty';

  @override
  String get rankingMightySeasonRanked => 'Mighty Season Ranked';

  @override
  String get rankingMightyRecord => 'Mighty Record';

  @override
  String rankingMightyMatchDetail(String declarer, int bid, String trump) {
    return '$declarer bid $bid $trump';
  }

  @override
  String get rankingLoveLetterRecord => 'Love Letter Record';

  @override
  String get rankingStatRecord => 'Record';

  @override
  String get rankingStatWinRate => 'Win Rate';

  @override
  String rankingRecordFormat(int games, int wins, int losses) {
    return '${games}G ${wins}W ${losses}L';
  }

  @override
  String rankingGold(int gold) {
    return '$gold Gold';
  }

  @override
  String rankingDesertions(int count) {
    return 'Desertions $count';
  }

  @override
  String get rankingRecentMatchesHeader => 'Recent Matches (3)';

  @override
  String get rankingSeeMore => 'See More';

  @override
  String get rankingNoRecentMatches => 'No recent matches';

  @override
  String get rankingBadgeDesertion => 'D';

  @override
  String get rankingBadgeDraw => 'D';

  @override
  String rankingSkRankScore(String rank, int score) {
    return '#$rank ${score}pts';
  }

  @override
  String get rankingRecentMatchesTitle => 'Recent Matches';

  @override
  String get rankingMannerScore => 'Manner';

  @override
  String get shopTitle => 'Shop';

  @override
  String shopGoldAmount(int gold) {
    return '$gold Gold';
  }

  @override
  String get shopHowToEarn => 'How to Earn';

  @override
  String shopDesertionCount(int count) {
    return 'Left $count';
  }

  @override
  String get shopGoldHistory => 'Gold History';

  @override
  String shopGoldCurrent(int gold) {
    return 'Current gold: $gold';
  }

  @override
  String get shopGoldHistoryDesc =>
      'Shows game results, ad rewards, shop purchases, and season rewards in recent order.';

  @override
  String get shopGoldHistoryEmpty => 'No gold history to display yet.';

  @override
  String get shopGoldChangeFallback => 'Gold change';

  @override
  String get shopGoldGuideTitle => 'How to Earn Gold';

  @override
  String get shopGoldGuideDesc =>
      'Gold can be earned through gameplay and rewards, and is used to purchase items in the shop.';

  @override
  String get shopGuideNormalWin => 'Normal Win';

  @override
  String get shopGuideNormalWinValue => '+10 Gold';

  @override
  String get shopGuideNormalWinDesc =>
      'Earn a base reward for winning a normal Tichu or Skull King game.';

  @override
  String get shopGuideNormalLoss => 'Normal Loss';

  @override
  String get shopGuideNormalLossValue => '+3 Gold';

  @override
  String get shopGuideNormalLossDesc =>
      'You still earn a participation reward even if you lose.';

  @override
  String get shopGuideRankedWin => 'Ranked Win';

  @override
  String get shopGuideRankedWinValue => '+20 Gold';

  @override
  String get shopGuideRankedWinDesc =>
      'Ranked games award 2x gold compared to normal games.';

  @override
  String get shopGuideRankedLoss => 'Ranked Loss';

  @override
  String get shopGuideRankedLossValue => '+6 Gold';

  @override
  String get shopGuideRankedLossDesc =>
      'Ranked loss rewards are also 2x compared to normal games.';

  @override
  String get shopGuideAdReward => 'Ad Reward';

  @override
  String get shopGuideAdRewardValue => '+50 Gold';

  @override
  String get shopGuideAdRewardDesc =>
      'Watch ads to earn bonus gold up to 5 times per day.';

  @override
  String get shopGuideSeasonReward => 'Season Reward';

  @override
  String get shopGuideSeasonRewardValue => 'Extra';

  @override
  String get shopGuideSeasonRewardDesc =>
      'Bonus gold is awarded at the end of the season based on your ranking.';

  @override
  String get shopTabShop => 'Shop';

  @override
  String get shopTabInventory => 'Inventory';

  @override
  String get shopNoItems => 'No shop items available';

  @override
  String get shopCategoryBanner => 'Banner';

  @override
  String get shopCategoryTitle => 'Title';

  @override
  String get shopCategoryTheme => 'Theme';

  @override
  String get shopCategoryUtil => 'Utility';

  @override
  String get shopCategorySeason => 'Season';

  @override
  String get shopItemEmpty => 'No items';

  @override
  String get shopItemOwned => 'Owned';

  @override
  String get shopButtonExtend => 'Extend';

  @override
  String get shopButtonPurchase => 'Purchase';

  @override
  String get shopExtendTitle => 'Extend Duration';

  @override
  String shopExtendConfirm(String name, int days, int price) {
    return 'You already own this item.\nExtend $name by $days days?\n\nCost: $price Gold';
  }

  @override
  String get shopExtendAction => 'Extend';

  @override
  String get shopNoInventoryItems => 'No items in inventory';

  @override
  String get shopStatusActivated => 'Activated';

  @override
  String get shopStatusInUse => 'In Use';

  @override
  String get shopPermanentOwned => 'Permanent';

  @override
  String get shopButtonUse => 'Use';

  @override
  String get shopButtonEquip => 'Equip';

  @override
  String get shopTagSeason => 'Season Item';

  @override
  String get shopTagPermanent => 'Permanent';

  @override
  String shopTagDuration(int days) {
    return '${days}d duration';
  }

  @override
  String get shopTagDurationOnly => 'Limited';

  @override
  String shopExpireDate(String date) {
    return 'Expires: $date';
  }

  @override
  String get shopExpireSoon => 'Expiring soon';

  @override
  String get shopPurchaseComplete => 'Purchase Complete';

  @override
  String get shopExtendComplete => 'Extension Complete';

  @override
  String shopExtendDone(String name) {
    return '$name duration has been extended.';
  }

  @override
  String get shopPurchaseDoneConsumable =>
      'Purchase complete.\nPlease use it from your inventory.';

  @override
  String get shopPurchaseDonePassive =>
      'Purchase complete.\nAutomatically activated upon purchase.';

  @override
  String get shopPurchaseDoneEquip =>
      'Purchase complete.\nWould you like to equip it now?';

  @override
  String get shopEquipNow => 'Equip';

  @override
  String get shopDetailCategoryBanner => 'Banner';

  @override
  String get shopDetailCategoryTitle => 'Title';

  @override
  String get shopDetailCategoryThemeSkin => 'Theme / Card Skin';

  @override
  String get shopDetailCategoryUtility => 'Utility';

  @override
  String get shopDetailCategoryItem => 'Item';

  @override
  String get shopDetailNormalItem => 'Normal Item';

  @override
  String get shopDetailPermanent => 'Permanent';

  @override
  String shopDetailDuration(int days) {
    return '${days}d duration';
  }

  @override
  String get shopEffectNicknameChange => 'Effect: 1 nickname change';

  @override
  String shopEffectLeaveReduce(String value) {
    return 'Effect: Desertions -$value';
  }

  @override
  String get shopEffectStatsReset =>
      'Effect: Reset all stats (wins/losses/games)';

  @override
  String get shopEffectLeaveReset => 'Effect: Reset leave count to 0';

  @override
  String get shopEffectSeasonStatsReset =>
      'Effect: Reset ALL ranked stats across Tichu, Skull King, and Mighty (wins/losses/games)';

  @override
  String get shopEffectTichuSeasonStatsReset =>
      'Effect: Reset Tichu ranked stats (wins/losses/games)';

  @override
  String get shopEffectSKSeasonStatsReset =>
      'Effect: Reset Skull King ranked stats (wins/losses/games)';

  @override
  String get shopEffectMightySeasonStatsReset =>
      'Effect: Reset Mighty ranked stats (wins/losses/games)';

  @override
  String shopPriceGold(int price) {
    return '$price Gold';
  }

  @override
  String get shopNicknameChangeTitle => 'Change Nickname';

  @override
  String get shopNicknameChangeDesc =>
      'Enter your new nickname.\n(2-10 characters, no spaces)';

  @override
  String get shopNicknameChangeHint => 'New nickname';

  @override
  String get shopNicknameChangeValidation => 'Nickname must be 2-10 characters';

  @override
  String get shopNicknameChangeButton => 'Change';

  @override
  String get shopAdCannotShow => 'Unable to show the ad';

  @override
  String shopAdWatchForGold(int current, int max) {
    return 'Watch ad for 50 Gold ($current/$max)';
  }

  @override
  String get shopAdRewardDone => 'Daily ad rewards complete';

  @override
  String get appForceUpdateTitle => 'Update Required';

  @override
  String get appForceUpdateBody =>
      'A new version has been released.\nPlease update to continue using the app.';

  @override
  String get appForceUpdateButton => 'Update';

  @override
  String get appEulaSubtitle => 'Terms of Service';

  @override
  String get appEulaLoadFailed =>
      'Unable to load Terms of Service. Please check your network connection.';

  @override
  String get appEulaAgree => 'I agree to the Terms of Service';

  @override
  String get appEulaStart => 'Get Started';

  @override
  String get serviceRestoreRefreshingSocial => 'Verifying social login info...';

  @override
  String get serviceRestoreSocialLogin => 'Logging in with social account...';

  @override
  String get serviceRestoreLocalLogin => 'Logging in with saved account...';

  @override
  String get serviceRestoreRoomState => 'Restoring room info...';

  @override
  String get serviceRestoreLoadingLobby => 'Loading lobby data...';

  @override
  String get serviceRestoreAutoLoginFailed => 'Auto login failed.';

  @override
  String get serviceRestoreConnecting => 'Connecting...';

  @override
  String get serviceRestoreNeedsNickname => 'A nickname needs to be set.';

  @override
  String get serviceRestoreSocialFailed => 'Social login restoration failed.';

  @override
  String get serviceRestoreSocialTokenExpired =>
      'Social login info needs to be re-verified.';

  @override
  String get serviceRestoreLocalFailed => 'Saved account login failed.';

  @override
  String get serviceRestoreAutoError => 'An error occurred during auto login.';

  @override
  String get serviceServerTimeout => 'Server response timed out';

  @override
  String get serviceKicked => 'You have been kicked';

  @override
  String get serviceRankingsLoadFailed => 'Failed to load rankings';

  @override
  String get serviceGoldHistoryLoadFailed => 'Failed to load gold history';

  @override
  String get serviceAdminUsersLoadFailed => 'Failed to load user list';

  @override
  String get serviceAdminUserDetailLoadFailed => 'Failed to load user details';

  @override
  String get serviceAdminInquiriesLoadFailed => 'Failed to load inquiry list';

  @override
  String get serviceAdminReportsLoadFailed => 'Failed to load report list';

  @override
  String get serviceAdminReportGroupLoadFailed =>
      'Failed to load report details';

  @override
  String get serviceAdminActionSuccess => 'Action completed';

  @override
  String get serviceAdminActionFailed => 'Action failed';

  @override
  String get serviceShopLoadFailed => 'Failed to load shop data';

  @override
  String get serviceInventoryLoadFailed => 'Failed to load inventory';

  @override
  String get serviceInquiriesLoadFailed => 'Failed to load inquiry history';

  @override
  String get serviceNoticesLoadFailed => 'Failed to load notices';

  @override
  String get serviceNicknameChanged => 'Nickname has been changed';

  @override
  String get serviceNicknameChangeFailed => 'Nickname change failed';

  @override
  String get serviceRewardFailed => 'Failed to grant reward';

  @override
  String get serviceRoomRestoreFallback =>
      'Could not restore room info. Returning to lobby.';

  @override
  String get serviceInviteInGame => 'Cannot send room invites during a game';

  @override
  String get serviceInviteCooldown =>
      'Invite already sent. Please try again shortly';

  @override
  String get serviceAdShowFailed => 'Unable to show the ad';

  @override
  String get serviceAdLoadFailed => 'Unable to load the ad';

  @override
  String serviceInquiryReply(String title) {
    return 'Inquiry reply received: $title';
  }

  @override
  String get serviceInquiryDefault => 'Inquiry';

  @override
  String serviceChatBanned(String remaining) {
    return 'Chat restricted ($remaining remaining)';
  }

  @override
  String serviceChatBanHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String serviceChatBanMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String serviceAdRewardSuccess(int remaining) {
    return 'Received 50 Gold! (Remaining: $remaining)';
  }

  @override
  String get lobbyLoveLetter => 'Love Letter';

  @override
  String get lobbyLoveLetterBadge => 'Love Letter';

  @override
  String lobbyLoveLetterPlayers(int count) {
    return 'Love Letter · ${count}P';
  }

  @override
  String get llRound => 'Round';

  @override
  String get llPlay => 'Play';

  @override
  String get llConfirm => 'Confirm';

  @override
  String get llOk => 'OK';

  @override
  String get llRoundEnd => 'Round Over';

  @override
  String get llRoundWinner => 'Round Winner';

  @override
  String get llNextRoundAuto => 'Next round starting soon...';

  @override
  String get llGameEnd => 'Game Over';

  @override
  String get llWins => 'Wins';

  @override
  String get llReturnIn => 'Returning in';

  @override
  String get llGuardSelectTarget => 'Guard: Select a target and guess a card';

  @override
  String get llGuardGuessCard => 'Guess which card they hold:';

  @override
  String get llSelectTargetFor => 'Select target for:';

  @override
  String llGuardEffect(String name) {
    return '$name is using Guard...';
  }

  @override
  String llSpyEffect(String name) {
    return '$name is using Spy...';
  }

  @override
  String llBaronEffect(String name) {
    return '$name is using Baron...';
  }

  @override
  String llPrinceEffect(String name) {
    return '$name is using Prince...';
  }

  @override
  String llKingEffect(String name) {
    return '$name is using King...';
  }

  @override
  String llGuardCorrect(String actor, String target) {
    return '$actor guessed $target\'s card correctly! Eliminated!';
  }

  @override
  String llGuardWrong(String actor, String target) {
    return '$actor guessed wrong about $target';
  }

  @override
  String llSpyReveal(String target) {
    return '$target\'s card:';
  }

  @override
  String llSpySawYour(String actor) {
    return '$actor saw your card';
  }

  @override
  String llSpyPeeked(String actor, String target) {
    return '$actor peeked at $target\'s card';
  }

  @override
  String llBaronTie(String actor, String target) {
    return '$actor and $target tied';
  }

  @override
  String llBaronLose(String loser) {
    return '$loser was eliminated by Baron comparison';
  }

  @override
  String llPrinceEliminated(String target) {
    return '$target was forced to discard Princess! Eliminated!';
  }

  @override
  String llPrinceDiscard(String target) {
    return '$target discarded and drew a new card';
  }

  @override
  String llKingSwap(String actor, String target) {
    return '$actor and $target swapped hands';
  }

  @override
  String get llEliminated => 'OUT';

  @override
  String get llSetAsideFaceUp => 'Set aside (face-up)';

  @override
  String get llPlayed => 'Played:';

  @override
  String get llCardGuard => 'Guard';

  @override
  String get llCardSpy => 'Spy';

  @override
  String get llCardBaron => 'Baron';

  @override
  String get llCardHandmaid => 'Handmaid';

  @override
  String get llCardPrince => 'Prince';

  @override
  String get llCardKing => 'King';

  @override
  String get llCardCountess => 'Countess';

  @override
  String get llCardPrincess => 'Princess';

  @override
  String get llCardGuideTitle => 'Card Guide';

  @override
  String get llDescGuard =>
      '1 · Guard: Name a player and guess their card. If correct, they\'re eliminated!';

  @override
  String get llDescSpy => '2 · Spy: Secretly look at another player\'s card.';

  @override
  String get llDescBaron =>
      '3 · Baron: Compare cards with a player. Lower card is eliminated!';

  @override
  String get llDescHandmaid =>
      '4 · Handmaid: Protected from all effects until your next turn.';

  @override
  String get llDescPrince =>
      '5 · Prince: Force a player to discard. If they discard Princess, eliminated!';

  @override
  String get llDescKing => '6 · King: Trade cards with another player.';

  @override
  String get llDescCountess =>
      '7 · Countess: Must be played if you hold King or Prince.';

  @override
  String get llDescPrincess =>
      '8 · Princess: If you play this card, you are eliminated!';

  @override
  String get maintenanceTitle => 'Server Under Maintenance';

  @override
  String maintenanceCountdown(String time) {
    return 'Remaining: $time';
  }

  @override
  String get maintenanceRetry => 'Retry';

  @override
  String get maintenanceEnded => 'Maintenance over, reconnecting...';

  @override
  String get goldHistoryShopPurchase => 'Shop purchase';

  @override
  String get goldHistoryLeaveDefeat => 'Forfeit loss';

  @override
  String get goldHistoryRankedWin => 'Ranked win';

  @override
  String get goldHistoryCasualWin => 'Casual win';

  @override
  String get goldHistoryDraw => 'Draw';

  @override
  String get goldHistoryRankedLoss => 'Ranked loss';

  @override
  String get goldHistoryCasualLoss => 'Casual loss';

  @override
  String get goldHistoryAdReward => 'Ad reward';

  @override
  String get goldHistorySeasonReward => 'Season reward';

  @override
  String get goldHistorySkLeaveDefeat => 'Skull King forfeit loss';

  @override
  String get goldHistorySkRankedWin => 'Skull King ranked win';

  @override
  String get goldHistorySkCasualWin => 'Skull King casual win';

  @override
  String get goldHistorySkRankedLoss => 'Skull King ranked loss';

  @override
  String get goldHistorySkCasualLoss => 'Skull King casual loss';

  @override
  String get goldHistoryAdminGrant => 'Admin grant';

  @override
  String get goldHistoryAdminDeduct => 'Admin deduction';

  @override
  String goldHistoryFinalScore(String scoreA, String scoreB) {
    return 'Final score $scoreA:$scoreB';
  }

  @override
  String goldHistorySeasonRank(String rank) {
    return 'Season rank: $rank';
  }

  @override
  String goldHistorySkRankScore(String rank, String score) {
    return 'Rank $rank ($score pts)';
  }

  @override
  String goldHistoryAdminBy(String admin) {
    return 'By admin: $admin';
  }

  @override
  String get adminCenterTitle => 'Admin Center';

  @override
  String get adminTabInquiries => 'Inquiries';

  @override
  String get adminTabReports => 'Reports';

  @override
  String get adminTabUsers => 'Users';

  @override
  String get adminActiveUsers => 'Active';

  @override
  String get adminPendingInquiries => 'Pending inquiries';

  @override
  String get adminPendingReports => 'Pending reports';

  @override
  String get adminTotalUsers => 'Total users';

  @override
  String get adminSearchHint => 'Search by nickname';

  @override
  String get adminSearch => 'Search';

  @override
  String get adminOnline => 'Online';

  @override
  String get adminOffline => 'Offline';

  @override
  String get adminUser => 'User';

  @override
  String get adminSubject => 'Subject';

  @override
  String get adminNote => 'Note';

  @override
  String get adminResolved => 'Resolved';

  @override
  String get adminReviewed => 'Reviewed';

  @override
  String get adminBasicInfo => 'Basic info';

  @override
  String get adminUsername => 'Username';

  @override
  String get adminRating => 'Rating';

  @override
  String get adminGold => 'Gold';

  @override
  String get adminRecord => 'Record';

  @override
  String get adminStatus => 'Status';

  @override
  String get adminCurrentRoom => 'Current room';

  @override
  String get adminGoldAdjust => 'Adjust gold';

  @override
  String get adminGoldAmount => 'Amount';

  @override
  String get adminGoldHint => 'Enter a positive number';

  @override
  String get adminGoldValidation => 'Please enter a valid positive amount';

  @override
  String get adminGrant => 'Grant';

  @override
  String get adminDeduct => 'Deduct';

  @override
  String adminReportCount(int count) {
    return '$count reports';
  }

  @override
  String adminReportRoom(String roomId) {
    return 'Room: $roomId';
  }

  @override
  String adminInquiryTitle(int id) {
    return 'Inquiry #$id';
  }

  @override
  String adminReportTitle(String nickname) {
    return 'Report: $nickname';
  }

  @override
  String adminWinLoss(int wins, int losses) {
    return '${wins}W/${losses}L';
  }
}

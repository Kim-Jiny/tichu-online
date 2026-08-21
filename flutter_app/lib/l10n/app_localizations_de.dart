// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class L10nDe extends L10n {
  L10nDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Tichu Online';

  @override
  String get languageAuto => 'Automatisch (Systemsprache)';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageKorean => 'Koreanisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsAppInfo => 'App-Info';

  @override
  String get settingsAppVersion => 'App-Version';

  @override
  String get settingsCurrentVersion => 'Aktuelle Version';

  @override
  String get settingsNotLatestVersion => 'Nicht die neueste Version';

  @override
  String get settingsUpdate => 'Aktualisieren';

  @override
  String get settingsLogout => 'Abmelden';

  @override
  String get settingsDeleteAccount => 'Konto löschen';

  @override
  String get settingsDeleteAccountConfirm =>
      'Möchten Sie Ihr Konto wirklich löschen?\nAlle Daten werden dauerhaft gelöscht.';

  @override
  String get settingsNickname => 'Spitzname';

  @override
  String get settingsSocialLink => 'Social-Verknüpfung';

  @override
  String get settingsTermsOfService => 'Nutzungsbedingungen';

  @override
  String get settingsPrivacyPolicy => 'Datenschutzrichtlinie';

  @override
  String get settingsNotices => 'Mitteilungen';

  @override
  String get settingsMyProfile => 'Mein Profil';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsSound => 'Ton';

  @override
  String get settingsAdminCenter => 'Admin-Center';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonTotal => 'Gesamt';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonConfirm => 'Bestätigen';

  @override
  String get commonLink => 'Verknüpfen';

  @override
  String get commonError => 'Fehler';

  @override
  String get settingsHeaderTitle => 'Einstellungen';

  @override
  String get settingsNotificationsSection => 'Benachrichtigungen';

  @override
  String get settingsPushNotifications => 'Push-Benachrichtigungen';

  @override
  String get settingsPushNotificationsDesc =>
      'Alle Benachrichtigungen ein- oder ausschalten';

  @override
  String get settingsInquiryNotifications => 'Anfrage-Benachrichtigungen';

  @override
  String get settingsInquiryNotificationsDesc =>
      'Push bei neuer Anfrage erhalten';

  @override
  String get settingsReportNotifications => 'Meldungs-Benachrichtigungen';

  @override
  String get settingsReportNotificationsDesc =>
      'Push bei neuer Meldung erhalten';

  @override
  String get settingsPaymentNotifications => 'Zahlungs-Benachrichtigungen';

  @override
  String get settingsPaymentNotificationsDesc =>
      'Push bei Kauf oder Erstattung eines Nutzers erhalten';

  @override
  String get settingsAdminSection => 'Admin';

  @override
  String get settingsAdminCenterDesc =>
      'Anfragen, Meldungen, Nutzer und aktive Nutzer einsehen';

  @override
  String get settingsAccountSection => 'Konto';

  @override
  String get settingsProfileSubtitle =>
      'Level, Statistiken und letzte Spiele ansehen';

  @override
  String settingsSocialLinked(String provider) {
    return '$provider verknüpft';
  }

  @override
  String get settingsNoLinkedAccount =>
      'Kein verknüpftes Konto (Ranglistenspiel nicht verfügbar)';

  @override
  String get settingsInquirySection => 'Anfragen';

  @override
  String get settingsSubmitInquiry => 'Anfrage senden';

  @override
  String get settingsInquiryHistory => 'Anfragenverlauf';

  @override
  String get settingsAccountManagement => 'Kontoverwaltung';

  @override
  String get settingsDeleteAccountWithdraw => 'Löschen';

  @override
  String get settingsLinkComplete => 'Verknüpfung abgeschlossen';

  @override
  String settingsLinkFailed(String error) {
    return 'Verknüpfung fehlgeschlagen: $error';
  }

  @override
  String get noticeTitle => 'Mitteilungen';

  @override
  String get noticeEmpty => 'Keine Mitteilungen vorhanden';

  @override
  String get noticeRetry => 'Erneut versuchen';

  @override
  String get noticeCategoryRelease => 'Release';

  @override
  String get noticeCategoryUpdate => 'Update';

  @override
  String get noticeCategoryPreview => 'Update-Vorschau';

  @override
  String get noticeCategoryGeneral => 'Mitteilung';

  @override
  String get inquiryTitle => 'Anfrage senden';

  @override
  String get inquiryCategory => 'Kategorie';

  @override
  String get inquiryCategoryBug => 'Fehlerbericht';

  @override
  String get inquiryCategorySuggestion => 'Vorschlag';

  @override
  String get inquiryCategoryPayment => 'Zahlung / Erstattung';

  @override
  String get inquiryCategoryOther => 'Sonstiges';

  @override
  String get inquiryFieldTitle => 'Titel';

  @override
  String get inquiryFieldTitleHint => 'Titel eingeben';

  @override
  String get inquiryFieldContent => 'Inhalt';

  @override
  String get inquiryFieldContentHint => 'Details eingeben';

  @override
  String get inquirySubmit => 'Absenden';

  @override
  String get inquirySubmitted => 'Ihre Anfrage wurde eingereicht';

  @override
  String get inquiryHistoryTitle => 'Anfragenverlauf';

  @override
  String get inquiryEmpty => 'Keine Anfragen vorhanden';

  @override
  String get inquiryStatusResolved => 'Beantwortet';

  @override
  String get inquiryStatusPending => 'Ausstehend';

  @override
  String get inquiryAnswerLabel => 'Antwort';

  @override
  String inquiryAnswerDate(String date) {
    return 'Beantwortet am: $date';
  }

  @override
  String get inquiryNoAnswer => 'Es wurde noch keine Antwort registriert.';

  @override
  String get linkDialogTitle => 'Social-Konto verknüpfen';

  @override
  String get linkDialogContent => 'Wähle ein Social-Konto zum Verknüpfen';

  @override
  String get textViewLoadFailed => 'Inhalt konnte nicht geladen werden.';

  @override
  String get loginEnterUsername => 'Bitte Benutzername eingeben';

  @override
  String get loginEnterPassword => 'Bitte Passwort eingeben';

  @override
  String get loginFailed => 'Anmeldung fehlgeschlagen';

  @override
  String loginSocialFailed(String error) {
    return 'Social-Login fehlgeschlagen: $error';
  }

  @override
  String get loginSocialFailedGeneric => 'Social-Login fehlgeschlagen';

  @override
  String get loginSubtitle => 'Team-Kartenspiel';

  @override
  String get loginTagline =>
      'Schnell wieder verbinden und\ndirekt ins Spiel einsteigen.';

  @override
  String get loginUsernameHint => 'Benutzername';

  @override
  String get loginPasswordHint => 'Passwort';

  @override
  String get loginButton => 'Anmelden';

  @override
  String get loginRegisterButton => 'Registrieren';

  @override
  String get loginQuickLogin => 'Schnellanmeldung';

  @override
  String get loginAutoLoginFailed => 'Automatische Anmeldung fehlgeschlagen';

  @override
  String get loginCheckSavedInfo => 'Bitte gespeicherte Anmeldedaten prüfen.';

  @override
  String get loginRetry => 'Erneut versuchen';

  @override
  String get loginManual => 'Manuell anmelden';

  @override
  String get loginAutoLoggingIn => 'Automatische Anmeldung...';

  @override
  String get loginLoggingIn => 'Anmeldung läuft...';

  @override
  String get loginVerifyingAccount => 'Kontodaten werden überprüft.';

  @override
  String get loginRegistrationComplete =>
      'Registrierung abgeschlossen. Bitte anmelden.';

  @override
  String get loginNicknameEmpty => 'Bitte Spitzname eingeben';

  @override
  String get loginNicknameLength => 'Spitzname muss 2-10 Zeichen lang sein';

  @override
  String get loginNicknameNoSpaces =>
      'Spitzname darf keine Leerzeichen enthalten';

  @override
  String get loginServerUnavailable => 'Server nicht erreichbar.';

  @override
  String get loginServerNoResponse =>
      'Keine Antwort vom Server. Bitte erneut versuchen.';

  @override
  String get loginUsernameMinLength =>
      'Benutzername muss mindestens 2 Zeichen lang sein';

  @override
  String get loginUsernameNoSpaces =>
      'Benutzername darf keine Leerzeichen enthalten';

  @override
  String get loginPasswordMinLength =>
      'Passwort muss mindestens 4 Zeichen lang sein';

  @override
  String get loginPasswordMismatch => 'Passwörter stimmen nicht überein';

  @override
  String get loginNicknameCheckRequired =>
      'Bitte Verfügbarkeit des Spitznamens prüfen';

  @override
  String get loginServerTimeout => 'Zeitüberschreitung der Serverantwort';

  @override
  String get loginRegisterTitle => 'Registrieren';

  @override
  String get loginUsernameLabel => 'Benutzername';

  @override
  String get loginUsernameHintRegister => '2+ Zeichen, keine Leerzeichen';

  @override
  String get loginPasswordLabel => 'Passwort';

  @override
  String get loginPasswordHintRegister => '4+ Zeichen';

  @override
  String get loginConfirmPasswordLabel => 'Passwort bestätigen';

  @override
  String get loginConfirmPasswordHint => 'Passwort erneut eingeben';

  @override
  String get loginSubmitRegister => 'Registrieren';

  @override
  String get loginNicknameLabel => 'Spitzname';

  @override
  String get loginNicknameHint => '2-10 Zeichen, keine Leerzeichen';

  @override
  String get loginCheckAvailability => 'Prüfen';

  @override
  String get loginSetNicknameTitle => 'Spitzname festlegen';

  @override
  String get loginSetNicknameDesc => 'Wähle einen Spitznamen für das Spiel';

  @override
  String get loginGetStarted => 'Los geht\'s';

  @override
  String get lobbyRoomInviteTitle => 'Raumeinladung';

  @override
  String lobbyRoomInviteMessage(String nickname) {
    return '$nickname hat dich in einen Raum eingeladen!';
  }

  @override
  String get lobbyDecline => 'Ablehnen';

  @override
  String get lobbyJoin => 'Beitreten';

  @override
  String get lobbyInviteFriendsTitle => 'Freunde einladen';

  @override
  String get lobbyNoOnlineFriends =>
      'Keine einladbaren Online-Freunde verfügbar';

  @override
  String lobbyInviteSent(String nickname) {
    return 'Einladung an $nickname gesendet';
  }

  @override
  String get lobbyInvite => 'Einladen';

  @override
  String get lobbySpectatorListTitle => 'Zuschauerliste';

  @override
  String get lobbyNoSpectators => 'Niemand schaut gerade zu';

  @override
  String get lobbyRoomSettingsTitle => 'Raumeinstellungen';

  @override
  String get lobbyEnterRoomTitle => 'Raumtitel eingeben';

  @override
  String get lobbyChange => 'Ändern';

  @override
  String get lobbyCreateRoom => 'Raum erstellen';

  @override
  String get lobbyCreateRoomSubtitle =>
      'Lege einen Raumtitel und Regeln fest, und der Warteraum öffnet sich sofort.';

  @override
  String get lobbySelectGame => 'Spiel wählen';

  @override
  String get lobbySelectGameDesc =>
      'Wähle das Spiel, das gespielt werden soll.';

  @override
  String get lobbyTichu => 'Tichu';

  @override
  String get lobbySkullKing => 'Skull King';

  @override
  String get lobbyMighty => 'Mighty';

  @override
  String get lobbyMaxPlayers => 'Max. Spieler';

  @override
  String lobbyPlayerCount(int count) {
    return '${count}P';
  }

  @override
  String get lobbyExpansionOptional => 'Erweiterungen (Optional)';

  @override
  String get lobbyExpansionDesc =>
      'Füge Spezialkarten zu den Grundregeln hinzu. Mehrfachauswahl möglich.';

  @override
  String get lobbyExpKraken => 'Kraken';

  @override
  String get lobbyExpKrakenDesc => 'Stich ungültig machen';

  @override
  String get lobbyExpWhiteWhale => 'White Whale';

  @override
  String get lobbyExpWhiteWhaleDesc => 'Spezialkarten neutralisieren';

  @override
  String get lobbyExpLoot => 'Loot';

  @override
  String get lobbyExpLootDesc => 'Bonuspunkte';

  @override
  String get lobbyBasicInfo => 'Grundeinstellungen';

  @override
  String get lobbyBasicInfoDesc =>
      'Lege den Raumnamen und die Sichtbarkeit fest.';

  @override
  String get lobbyRoomName => 'Raumname';

  @override
  String get lobbyRandom => 'Zufällig';

  @override
  String get lobbyPrivateRoom => 'Privater Raum';

  @override
  String get lobbyPrivateRoomDescRanked =>
      'Im Ranglistenspiel kann kein privater Raum erstellt werden.';

  @override
  String get lobbyPrivateRoomDesc =>
      'Nur eingeladene Spieler oder solche mit dem Passwort können beitreten.';

  @override
  String get lobbyPasswordHint => 'Passwort (4+ Zeichen)';

  @override
  String get lobbyRanked => 'Ranglistenspiel';

  @override
  String get lobbyRankedDesc =>
      'Die Punktzahl ist auf 1000 festgelegt und die Privat-Einstellung wird automatisch deaktiviert.';

  @override
  String get lobbyRankedDescSk =>
      'Die Privat-Einstellung wird automatisch deaktiviert.';

  @override
  String get lobbyRankedDescMighty =>
      'Die Punktzahl ist auf 50 festgelegt und die Privat-Einstellung wird automatisch deaktiviert.';

  @override
  String get lobbyGameSettings => 'Spieleinstellungen';

  @override
  String get lobbyGameSettingsDescSk => 'Lege die Zugzeit fest.';

  @override
  String get lobbyGameSettingsDescTichu =>
      'Lege die Zugzeit und die Zielpunktzahl fest.';

  @override
  String get lobbyTimeLimit => 'Zeitlimit';

  @override
  String get lobbySuffixSeconds => 'Sek.';

  @override
  String get lobbyTargetScore => 'Zielpunktzahl';

  @override
  String get lobbySuffixPoints => 'Pkt.';

  @override
  String get lobbyTimeLimitRange => '10–999';

  @override
  String get lobbyTargetScoreRange => '100–20000';

  @override
  String get lobbyTargetScoreRangeMighty => '10–500';

  @override
  String get lobbyTargetScoreFixed => '1000 (fest)';

  @override
  String get lobbyTargetScoreFixedMighty => '50 (fest)';

  @override
  String get lobbyRankedFixedScoreInfo =>
      'Im Ranglistenspiel ist die Zielpunktzahl auf 1000 festgelegt.';

  @override
  String get lobbyRankedInfoSk =>
      'Private Räume sind im Ranglistenspiel nicht verfügbar.';

  @override
  String get lobbyRankedInfoMighty =>
      'Im Ranglistenspiel ist die Zielpunktzahl auf 50 festgelegt. Private Räume sind nicht verfügbar.';

  @override
  String get lobbyNormalSettingsInfo =>
      'Zeitlimit: 10–999 Sek., Zielpunktzahl: 100–20000 Pkt.';

  @override
  String get lobbyNormalSettingsInfoMighty =>
      'Zeitlimit: 10–999 Sek., Zielpunktzahl: 10–500 Pkt.';

  @override
  String get lobbyNormalSettingsInfoTimeOnly => 'Zeitlimit: 10–999 Sek.';

  @override
  String get lobbyEnterRoomName => 'Bitte einen Raumnamen eingeben.';

  @override
  String get lobbyPasswordTooShort =>
      'Passwort muss mindestens 4 Zeichen haben.';

  @override
  String get lobbyDuplicateLoginKicked =>
      'Du wurdest abgemeldet, da sich ein anderes Gerät angemeldet hat';

  @override
  String get lobbyRoomListTitle => 'Raumliste';

  @override
  String get lobbyEmptyRoomList =>
      'Keine Räume vorhanden!\nErstelle doch einen!';

  @override
  String get lobbySkullKingBadge => 'Skull King';

  @override
  String get lobbyMightyBadge => 'Mighty';

  @override
  String get lobbyTichuBadge => 'Tichu';

  @override
  String lobbyRoomTimeSec(int seconds) {
    return '${seconds}s';
  }

  @override
  String lobbyRoomTimeAndScore(int seconds, int score) {
    return '${seconds}s · ${score}Pkt.';
  }

  @override
  String get lobbyExpKrakenShort => 'Kraken';

  @override
  String get lobbyExpWhaleShort => 'Whale';

  @override
  String get lobbyExpLootShort => 'Loot';

  @override
  String lobbyInProgress(int count) {
    return '$count Zuschauer';
  }

  @override
  String get lobbySocialLinkRequired => 'Social-Verknüpfung erforderlich';

  @override
  String get lobbySocialLinkRequiredDesc =>
      'Für das Ranglistenspiel wird ein verknüpftes Social-Konto benötigt.\nGehe zu Einstellungen > Social-Verknüpfung, um dein Google- oder Kakao-Konto zu verknüpfen.';

  @override
  String get lobbyJoinPrivateRoom => 'Privaten Raum betreten';

  @override
  String get lobbyEnter => 'Betreten';

  @override
  String get lobbySpectatePrivateRoom => 'Privaten Raum beobachten';

  @override
  String get lobbySpectate => 'Zuschauen';

  @override
  String get lobbyPassword => 'Passwort';

  @override
  String get lobbyMessageHint => 'Nachricht eingeben...';

  @override
  String get lobbyChat => 'Chat';

  @override
  String get lobbyViewProfile => 'Profil ansehen';

  @override
  String get lobbyAddFriend => 'Freund hinzufügen';

  @override
  String get lobbyUnblock => 'Entsperren';

  @override
  String get lobbyBlock => 'Sperren';

  @override
  String get lobbyUnblocked => 'Benutzer wurde entsperrt';

  @override
  String get lobbyBlocked => 'Benutzer wurde gesperrt';

  @override
  String get lobbyFriendRequestSent => 'Freundschaftsanfrage gesendet';

  @override
  String get lobbyReport => 'Melden';

  @override
  String get lobbyWaitingRoomTools => 'Warteraum-Tools';

  @override
  String get lobbyWaitingRoomToolsDesc =>
      'Funktionen, die nicht direkt mit der Spielvorbereitung zusammenhängen, findest du hier.';

  @override
  String get lobbyFriendsDm => 'Freunde / DM';

  @override
  String lobbyUnreadDmCount(int count) {
    return 'Du hast $count ungelesene Anfragen und DMs.';
  }

  @override
  String get lobbyFriendsDmDesc =>
      'Sieh deine Freundesliste und DM-Gespräche ein.';

  @override
  String lobbyCurrentSpectators(int count) {
    return '$count Zuschauer gerade anwesend.';
  }

  @override
  String get lobbyMore => 'Mehr';

  @override
  String get lobbyRoomSettings => 'Einstellungen';

  @override
  String get lobbySkullKingRanked => 'Skull King - Ranglistenspiel';

  @override
  String get lobbyTichuRanked => 'Tichu - Ranglistenspiel';

  @override
  String get lobbyMightyRanked => 'Mighty - Ranglistenspiel';

  @override
  String get lobbyTichuRandomSeating => 'Tichu - Zufallsteams';

  @override
  String get lobbyRandomSeatingOn => 'Zufallsteams';

  @override
  String get lobbyRandomSeatingOff => 'Feste Teams';

  @override
  String lobbySkullKingPlayers(int count) {
    return 'Skull King · ${count}P';
  }

  @override
  String get lobbyStartGame => 'Spiel starten';

  @override
  String get lobbyMatchIncoming =>
      'Server-Update läuft — du steigst in der nächsten Runde automatisch wieder ein';

  @override
  String get lobbyReady => 'Bereit';

  @override
  String get lobbyReadyDone => 'Bereit!';

  @override
  String lobbyReportTitle(String nickname) {
    return '$nickname melden';
  }

  @override
  String get lobbyReportWarning =>
      'Meldungen werden vom Moderationsteam geprüft.\nFalschmeldungen können bestraft werden.';

  @override
  String get lobbySelectReason => 'Grund wählen';

  @override
  String get lobbyReportDetailHint => 'Details eingeben (optional)';

  @override
  String get lobbyReportReasonAbuse => 'Beleidigung/Beschimpfung';

  @override
  String get lobbyReportReasonSpam => 'Spam/Flooding';

  @override
  String get lobbyReportReasonNickname => 'Unangemessener Spitzname';

  @override
  String get lobbyReportReasonPhoto => 'Unangemessenes Profilbild';

  @override
  String get lobbyReportReasonGameplay => 'Spielstörung';

  @override
  String get lobbyReportReasonOther => 'Sonstiges';

  @override
  String get lobbyProfileNotFound => 'Profil nicht gefunden';

  @override
  String get lobbyMyProfile => 'Mein Profil';

  @override
  String get lobbyPlayerProfile => 'Spielerprofil';

  @override
  String get lobbyAlreadyFriend => 'Bereits befreundet';

  @override
  String get lobbyRequestPending => 'Anfrage ausstehend';

  @override
  String get lobbyTichuSeasonRanked => 'Tichu Saison-Rangliste';

  @override
  String get lobbySkullKingSeasonRanked => 'Skull King Saison-Rangliste';

  @override
  String get lobbyTichuRecord => 'Tichu Statistik';

  @override
  String get lobbySkullKingRecord => 'Skull King Statistik';

  @override
  String get lobbyLoveLetterRecord => 'Love Letter Statistik';

  @override
  String get lobbyStatRecord => 'Bilanz';

  @override
  String get lobbyStatWinRate => 'Siegquote';

  @override
  String lobbyRecordFormat(int games, int wins, int losses) {
    return '${games}S ${wins}G ${losses}V';
  }

  @override
  String lobbyRecentMatches(int count) {
    return 'Letzte Spiele ($count)';
  }

  @override
  String get lobbyRecentMatchesTitle => 'Letzte Spiele';

  @override
  String get profileMatchHistoryTitle => 'Spielverlauf';

  @override
  String get profileOutcomeWin => 'Sieg';

  @override
  String get profileOutcomeLoss => 'Niederlage';

  @override
  String get profileOutcomeDraw => 'Unentschieden';

  @override
  String get profileOutcomeDesertion => 'Verlassen';

  @override
  String get profileOutcomeMidLeave => 'Vorzeitig verlassen';

  @override
  String lobbyRecentMatchesDesc(int count) {
    return 'Ergebnisse der letzten $count Spiele anzeigen.';
  }

  @override
  String get lobbySeeMore => 'Mehr anzeigen';

  @override
  String get lobbyNoRecentMatches => 'Keine aktuellen Spiele';

  @override
  String get lobbyMatchDesertion => 'A';

  @override
  String get lobbyMatchDraw => 'U';

  @override
  String get lobbyMatchWin => 'S';

  @override
  String get lobbyMatchLoss => 'N';

  @override
  String get lobbyMatchTypeSkullKing => 'Skull King';

  @override
  String get lobbyMatchTypeLoveLetter => 'Love Letter';

  @override
  String get lobbyMatchTypeRanked => 'Rangliste';

  @override
  String get lobbyMatchTypeNormal => 'Normal';

  @override
  String lobbyRankAndScore(String rank, int score) {
    return '#$rank (${score}Pkt.)';
  }

  @override
  String get lobbyMannerGood => 'Gut';

  @override
  String get lobbyMannerNormal => 'Normal';

  @override
  String get lobbyMannerBad => 'Schlecht';

  @override
  String get lobbyMannerVeryBad => 'Sehr schlecht';

  @override
  String get lobbyMannerWorst => 'Katastrophal';

  @override
  String lobbyManner(String label) {
    return 'Manieren $label';
  }

  @override
  String lobbyDesertions(int count) {
    return 'Verlassen $count';
  }

  @override
  String get lobbyKick => 'Rauswerfen';

  @override
  String lobbyKickConfirm(String playerName) {
    return '$playerName rauswerfen?';
  }

  @override
  String get lobbyHost => 'Host';

  @override
  String get lobbyBot => 'Bot';

  @override
  String get lobbyBotSpeedTitle => 'Bot-Geschwindigkeit';

  @override
  String get lobbyBotSpeedFast => 'Schnell';

  @override
  String get lobbyBotSpeedNormal => 'Normal';

  @override
  String get lobbyBotSpeedSlow => 'Langsam';

  @override
  String get lobbyBotStrategyTitle => 'Bot-Strategie';

  @override
  String get lobbyBotStrategyHeuristic => 'Heuristisch';

  @override
  String get lobbyBotStrategyPimcPlay => 'PIMC (Spiel)';

  @override
  String get lobbyBotStrategyPimcFull => 'PIMC (komplett)';

  @override
  String get lobbyBotStrategyExpectimax => 'Expectimax';

  @override
  String get lobbyBotStrategyExpectimaxSmart => 'Expectimax+ (smart rollout)';

  @override
  String get lobbyBotStrategyMixexpectimax => 'Mix Oracle (Regeln + Oracle)';

  @override
  String get lobbyAddBotDialogTitle => 'Bot hinzufügen';

  @override
  String get lobbyAddBotConfirm => 'Hinzufügen';

  @override
  String get lobbyAddBotCancel => 'Abbrechen';

  @override
  String get lobbyFillEmptyWithBots => 'Leere Plätze mit Bots füllen';

  @override
  String get lobbyEmptySlot => '[Leer]';

  @override
  String get lobbySlotBlocked => '[Gesperrt]';

  @override
  String get lobbyMaintenanceDefault => 'Serverwartung geplant';

  @override
  String lobbyRoomInfoSk(int seconds, int players, int maxPlayers) {
    return '${seconds}s · $players/${maxPlayers}P';
  }

  @override
  String lobbyRoomInfoTichu(int seconds, int score) {
    return '${seconds}s · ${score}Pkt.';
  }

  @override
  String get skGameRecoveringGame => 'Spiel wird wiederhergestellt...';

  @override
  String get skGameCheckingState => 'Spielstatus wird geprüft...';

  @override
  String get skGameReloadingRoom => 'Rauminformationen werden neu geladen...';

  @override
  String get skGameLoadingState => 'Spielstatus wird geladen...';

  @override
  String get skGameSpectatorWaitingTitle => 'Skull King Warteraum zuschauen';

  @override
  String get skGameSpectatorWaitingDesc =>
      'Du siehst den Raum vor Spielbeginn. Der Zuschauermodus startet automatisch, sobald das Spiel beginnt.';

  @override
  String get skGameHost => 'Host';

  @override
  String get skGameReady => 'Bereit';

  @override
  String get skGameWaiting => 'Wartend';

  @override
  String get skGameSpectatorStandby => 'Zuschauer-Standby';

  @override
  String get skGameSpectatorListTitle => 'Zuschauerliste';

  @override
  String get skGameNoSpectators => 'Niemand schaut gerade zu';

  @override
  String get skGameAlwaysAccept => 'Immer erlauben';

  @override
  String get skGameAlwaysReject => 'Immer ablehnen';

  @override
  String skGameRoundTrick(int round, int trick) {
    return 'Runde $round, Stich $trick';
  }

  @override
  String get skGameSpectating => 'Zuschauen';

  @override
  String skGameBiddingInProgress(String name) {
    return 'Ansage läuft · Startspieler: $name';
  }

  @override
  String skGamePlayerTurn(String name) {
    return '$name ist dran';
  }

  @override
  String get skGameLeaveTitle => 'Spiel verlassen';

  @override
  String get skGameLeaveConfirm => 'Möchtest du das Spiel wirklich verlassen?';

  @override
  String get skGameLeaveButton => 'Verlassen';

  @override
  String skGameLeaderLabel(String name) {
    return 'Startspieler: $name';
  }

  @override
  String get skGameLeaderLabelShort => 'Startspieler';

  @override
  String get skGameMyTurn => 'Mein Zug';

  @override
  String skGameWaitingFor(String name) {
    return 'Warte auf $name';
  }

  @override
  String skGameSecondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String get skGameTapToRequestCards =>
      'Tippe oben auf ein Profil, um die Hand einzusehen';

  @override
  String skGameRequestingCardView(String name) {
    return 'Anfrage an $name läuft...';
  }

  @override
  String skGamePlayerHand(String name) {
    return '${name}s Hand';
  }

  @override
  String get skGameNoCards => 'Keine Karten';

  @override
  String skGameCardViewRejected(String name) {
    return '$name hat die Anfrage abgelehnt. Tippe auf einen anderen Spieler.';
  }

  @override
  String skGameTimeout(String name) {
    return '$name – Zeit abgelaufen!';
  }

  @override
  String skGameDesertionTimeout(String name) {
    return '$name hat das Spiel verlassen! (3 Timeouts)';
  }

  @override
  String skGameDesertionLeave(String name) {
    return '$name hat das Spiel verlassen';
  }

  @override
  String skGameCardViewRequest(String name) {
    return '$name möchte deine Hand sehen';
  }

  @override
  String get skGameReject => 'Ablehnen';

  @override
  String get skGameAllow => 'Erlauben';

  @override
  String get skGameChat => 'Chat';

  @override
  String get skGameMessageHint => 'Nachricht eingeben...';

  @override
  String get skGameViewingMyHand => 'Meine Hand wird angesehen';

  @override
  String get skGameNoViewers => 'Niemand schaut zu';

  @override
  String get skGameViewProfile => 'Profil ansehen';

  @override
  String get skGameBlock => 'Sperren';

  @override
  String get skGameUnblock => 'Entsperren';

  @override
  String get skGameScoreHistory => 'Punktehistorie';

  @override
  String get skGameBiddingPhase => 'Ansage läuft...';

  @override
  String get skGamePlayCard => 'Spiele eine Karte';

  @override
  String get skGameKrakenActivated => '🐙 Kraken aktiviert';

  @override
  String get skGameWhiteWhaleActivated => '🐋 White Whale aktiviert';

  @override
  String get skGameWhiteWhaleNullify =>
      '🐋 White Whale · Spezialkarten neutralisiert';

  @override
  String get skGameTrickVoided => 'Trick ungültig';

  @override
  String skGameLeadPlayer(String name) {
    return '$name beginnt den nächsten Trick';
  }

  @override
  String skGameTrickWinner(String name) {
    return '$name gewinnt';
  }

  @override
  String get skGameCheckingCards => 'Karten werden geprüft...';

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
    return 'Ansage: $bid Siege';
  }

  @override
  String get skGameWaitingOthers => 'Warte auf andere Spieler...';

  @override
  String get skGameBidPrompt =>
      'Sage voraus, wie viele Tricks du diese Runde gewinnst';

  @override
  String skGameBidSubmit(int bid) {
    return '$bid Siege ansagen';
  }

  @override
  String get skGameSelectNumber => 'Wähle eine Zahl';

  @override
  String get skGamePlayCardButton => 'Karte spielen';

  @override
  String get skGameSelectCard => 'Wähle eine Karte';

  @override
  String get skGameReset => 'Zurücksetzen';

  @override
  String get skGameTigressEscape => 'Escape';

  @override
  String get skGameTigressPirate => 'Pirate';

  @override
  String skGameRoundResult(int round) {
    return 'Runde $round Ergebnis';
  }

  @override
  String get skGameBidTricks => 'Bid/Gewonnen';

  @override
  String get skGameStatBid => 'Wette';

  @override
  String get skGameStatTricks => 'Stiche';

  @override
  String get skGameStatScore => 'Punkte';

  @override
  String get skGameBonusHeader => 'Bonus';

  @override
  String get skGameScoreHeader => 'Punkte';

  @override
  String get skGameTotalScoreHeader => 'Gesamt';

  @override
  String get skGameNextRoundPreparing => 'Nächste Runde wird vorbereitet...';

  @override
  String get skGameGameOver => 'Spiel beendet';

  @override
  String skGameAutoReturnCountdown(int seconds) {
    return 'Zurück zum Warteraum in ${seconds}s';
  }

  @override
  String get skGameReturningToRoom => 'Zurück zum Warteraum...';

  @override
  String get skGamePlayerProfile => 'Spielerprofil';

  @override
  String get skGameAlreadyFriend => 'Bereits befreundet';

  @override
  String get skGameRequestPending => 'Anfrage ausstehend';

  @override
  String get skGameAddFriend => 'Freund hinzufügen';

  @override
  String get skGameFriendRequestSent => 'Freundschaftsanfrage gesendet';

  @override
  String get skGameBlockUser => 'Sperren';

  @override
  String get skGameUnblockUser => 'Entsperren';

  @override
  String get skGameUserBlocked => 'Benutzer wurde gesperrt';

  @override
  String get skGameUserUnblocked => 'Benutzer wurde entsperrt';

  @override
  String get skGameProfileNotFound => 'Profil nicht gefunden';

  @override
  String get skGameTichuRecord => 'Tichu Statistik';

  @override
  String get skGameSkullKingRecord => 'Skull King Statistik';

  @override
  String get skGameLoveLetterRecord => 'Love Letter Statistik';

  @override
  String get skGameStatRecord => 'Bilanz';

  @override
  String get skGameStatWinRate => 'Siegquote';

  @override
  String skGameRecordFormat(int games, int wins, int losses) {
    return '${games}S ${wins}G ${losses}V';
  }

  @override
  String get gameSparrowCall => 'Mahjong-Ruf';

  @override
  String get gameSelectNumberToCall => 'Wähle eine Zahl zum Rufen';

  @override
  String get gameNoCall => 'Nicht rufen';

  @override
  String get gameCancelPickAnother => 'Abbrechen und andere Karte wählen';

  @override
  String get gameRestoringGame => 'Spiel wird wiederhergestellt...';

  @override
  String get gameCheckingState => 'Spielstatus wird geprüft...';

  @override
  String get gameRecheckingRoomState =>
      'Aktueller Raumstatus wird erneut geprüft.';

  @override
  String get gameReloadingRoom => 'Rauminformationen werden neu geladen...';

  @override
  String get gameWaitForRestore =>
      'Bitte warten, der aktuelle Spielstatus wird wiederhergestellt.';

  @override
  String get gamePreparingScreen => 'Spielbildschirm wird vorbereitet...';

  @override
  String get gameAdjustingScreen => 'Bildschirmübergang wird angepasst.';

  @override
  String get gameTransitioningScreen => 'Spielbildschirm wird gewechselt...';

  @override
  String get gameRecheckingDestination =>
      'Aktueller Zielstatus wird erneut geprüft.';

  @override
  String get gameSoundEffects => 'Soundeffekte';

  @override
  String get gameChat => 'Chat';

  @override
  String get gameMessageHint => 'Nachricht eingeben...';

  @override
  String get gameMyProfile => 'Mein Profil';

  @override
  String get gamePlayerProfile => 'Spielerprofil';

  @override
  String get gameAlreadyFriend => 'Freund';

  @override
  String get gameAlreadyFriendToast => 'Ihr seid bereits befreundet';

  @override
  String get gameRequestPending => 'Anfrage ausstehend';

  @override
  String get gameAddFriend => 'Freund';

  @override
  String get gameFriendRequestSent => 'Freundschaftsanfrage gesendet';

  @override
  String get gameUnblock => 'Entsperren';

  @override
  String get gameBlock => 'Sperren';

  @override
  String get gameUnblocked => 'Benutzer wurde entsperrt';

  @override
  String get gameBlocked => 'Benutzer wurde gesperrt';

  @override
  String get gameReport => 'Melden';

  @override
  String get gameClose => 'Schließen';

  @override
  String get gameProfileNotFound => 'Profil nicht gefunden';

  @override
  String get gameTichuSeasonRanked => 'Tichu Saison-Rangliste';

  @override
  String get gameStatRecord => 'Bilanz';

  @override
  String get gameStatWinRate => 'Siegquote';

  @override
  String get gameOverallRecord => 'Gesamtbilanz';

  @override
  String gameRecordFormat(int games, int wins, int losses) {
    return '${games}S ${wins}G ${losses}V';
  }

  @override
  String get gameMannerGood => 'Gut';

  @override
  String get gameMannerNormal => 'Normal';

  @override
  String get gameMannerBad => 'Schlecht';

  @override
  String get gameMannerVeryBad => 'Sehr schlecht';

  @override
  String get gameMannerWorst => 'Katastrophal';

  @override
  String gameManner(String label) {
    return 'Manieren $label';
  }

  @override
  String get gameDesertionLabel => 'Verlassen';

  @override
  String gameDesertions(int count) {
    return 'Verlassen $count';
  }

  @override
  String get gameRecentMatchesTitle => 'Letzte Spiele';

  @override
  String gameRecentMatchesDesc(int count) {
    return 'Ergebnisse der letzten $count Spiele anzeigen.';
  }

  @override
  String get gameRecentMatchesThree => 'Letzte Spiele (3)';

  @override
  String get gameSeeMore => 'Mehr anzeigen';

  @override
  String get gameNoRecentMatches => 'Keine aktuellen Spiele';

  @override
  String get gameMatchDesertion => 'A';

  @override
  String get gameMatchDraw => 'U';

  @override
  String get gameMatchWin => 'S';

  @override
  String get gameMatchLoss => 'N';

  @override
  String get gameMatchTypeRanked => 'Rangliste';

  @override
  String get gameMatchTypeNormal => 'Normal';

  @override
  String get gameViewProfile => 'Profil ansehen';

  @override
  String get gameCancel => 'Abbrechen';

  @override
  String get gameReportReasonAbuse => 'Beleidigung/Beschimpfung';

  @override
  String get gameReportReasonSpam => 'Spam/Flooding';

  @override
  String get gameReportReasonNickname => 'Unangemessener Spitzname';

  @override
  String get gameReportReasonGameplay => 'Spielstörung';

  @override
  String get gameReportReasonOther => 'Sonstiges';

  @override
  String gameReportTitle(String nickname) {
    return '$nickname melden';
  }

  @override
  String get gameReportWarning =>
      'Meldungen werden vom Moderationsteam geprüft.\nFalschmeldungen können bestraft werden.';

  @override
  String get gameSelectReason => 'Grund wählen';

  @override
  String get gameReportDetailHint => 'Details eingeben (optional)';

  @override
  String get gameReportSubmit => 'Melden';

  @override
  String get gameLeaveTitle => 'Spiel verlassen';

  @override
  String get gameLeaveConfirm =>
      'Möchtest du wirklich gehen?\nDas Verlassen während des Spiels schadet deinem Team.';

  @override
  String get gameLeave => 'Verlassen';

  @override
  String get gameCallError => 'Du musst zuerst die gerufene Zahl spielen!';

  @override
  String gameTimeout(String playerName) {
    return '$playerName – Zeit abgelaufen!';
  }

  @override
  String gameDesertionTimeout(String playerName) {
    return '$playerName hat das Spiel verlassen! (3 Timeouts)';
  }

  @override
  String gameDesertionLeave(String playerName) {
    return '$playerName hat das Spiel verlassen';
  }

  @override
  String get gameSpectator => 'Zuschauer';

  @override
  String gameCardViewRequest(String nickname) {
    return '$nickname möchte deine Karten sehen';
  }

  @override
  String get gameReject => 'Ablehnen';

  @override
  String get gameAllow => 'Erlauben';

  @override
  String get gameAlwaysReject => 'Immer ablehnen';

  @override
  String get gameAlwaysAllow => 'Immer erlauben';

  @override
  String get gameCardViewPolicyTitle => 'Karteneinsicht-Richtlinie';

  @override
  String get gameCardViewPolicyAsk => 'Jedes Mal fragen';

  @override
  String get gameCardViewPolicyAllow => 'Immer erlauben';

  @override
  String get gameCardViewPolicyDeny => 'Immer ablehnen';

  @override
  String get settingsCardViewPolicy => 'Zuschauer-Karteneinsicht';

  @override
  String get settingsCardViewPolicyDescription =>
      'Lege fest, wie Anfragen zum Ansehen deiner Hand behandelt werden. Bleibt zwischen Partien erhalten.';

  @override
  String get gameSpectatorList => 'Zuschauerliste';

  @override
  String get gameNoSpectators => 'Niemand schaut gerade zu';

  @override
  String get gameViewingMyCards => 'Meine Karten werden angesehen';

  @override
  String get gameNoViewers => 'Niemand schaut zu';

  @override
  String get gamePartner => 'Partner';

  @override
  String get gameLeftPlayer => 'Links';

  @override
  String get gameRightPlayer => 'Rechts';

  @override
  String get gameMyTurn => 'Mein Zug!';

  @override
  String gamePlayerTurn(String name) {
    return '$name ist dran';
  }

  @override
  String gameCall(String rank) {
    return 'Call $rank';
  }

  @override
  String get gameMyTurnShort => 'Mein Zug';

  @override
  String gamePlayerTurnShort(String name) {
    return '$name Zug';
  }

  @override
  String gamePlayerWaiting(String name) {
    return '$name wartet';
  }

  @override
  String gameTimerLabel(String turnLabel, int seconds) {
    return '$turnLabel ${seconds}s';
  }

  @override
  String get gameScoreHistory => 'Punktehistorie';

  @override
  String get gameScoreHistorySubtitle =>
      'Rundenweise Punkte und aktuelle Summe';

  @override
  String get gameNoCompletedRounds => 'Noch keine abgeschlossenen Runden';

  @override
  String gameTeamLabel(String label) {
    return 'Team $label';
  }

  @override
  String gameDogPlayedBy(String name) {
    return '$name hat den Hund gespielt';
  }

  @override
  String get gameDogPlayed => 'Der Hund wurde gespielt';

  @override
  String get gamePlayedCards => ': Karten';

  @override
  String get gamePlay => 'Spielen';

  @override
  String get gamePass => 'Passen';

  @override
  String get gameLargeTichuQuestion => 'Large Tichu?';

  @override
  String get gameDeclare => 'Ansagen!';

  @override
  String get gameSmallTichuDeclare => 'Small Tichu ansagen';

  @override
  String get gameSmallTichuConfirmTitle => 'Small Tichu ansagen';

  @override
  String get gameSmallTichuConfirmContent =>
      'Small Tichu ansagen?\n+100 Punkte bei Erfolg, -100 bei Misserfolg';

  @override
  String get gameDeclareButton => 'Ansagen';

  @override
  String get gameSelectRecipient => 'Wähle einen Empfänger für die Karte';

  @override
  String gameSelectExchangeCard(int count) {
    return 'Karte zum Tauschen wählen ($count/3)';
  }

  @override
  String get gameReset => 'Zurücksetzen';

  @override
  String get gameExchangeComplete => 'Tausch abgeschlossen';

  @override
  String get gameDragonQuestion => 'Wem möchtest du den Drachen-Trick geben?';

  @override
  String get gameSelectCallRank => 'Wähle eine Zahl zum Rufen';

  @override
  String get gameGameEnd => 'Spiel beendet!';

  @override
  String get gameRoundEnd => 'Runde beendet!';

  @override
  String get gameMyTeamWin => 'Unser Team gewinnt!';

  @override
  String get gameEnemyTeamWin => 'Gegner gewinnt!';

  @override
  String get gameDraw => 'Unentschieden!';

  @override
  String get gameThisRound => 'Diese Runde: ';

  @override
  String get gameTotalScore => 'Gesamt: ';

  @override
  String get gameScoreUs => 'Wir';

  @override
  String get gameScoreThem => 'Sie';

  @override
  String get gameAutoReturnLobby => 'Rückkehr zur Lobby in 3 Sekunden...';

  @override
  String get gameAutoNextRound => 'Weiter in 3 Sekunden...';

  @override
  String gameRankedScore(int score) {
    return 'Ranglistenpunkte $score';
  }

  @override
  String get gameRankDiamond => 'Diamant';

  @override
  String get gameRankGold => 'Gold';

  @override
  String get gameRankSilver => 'Silber';

  @override
  String get gameRankBronze => 'Bronze';

  @override
  String gameFinishPosition(int position) {
    return '$position. Platz!';
  }

  @override
  String gameCardCount(int count) {
    return '$count Karten';
  }

  @override
  String get gamePhaseLargeTichu => 'Large Tichu Ansage';

  @override
  String get gamePhaseDealing => 'Karten werden verteilt';

  @override
  String get gamePhaseExchange => 'Kartentausch';

  @override
  String get gamePhasePlaying => 'Spiel läuft';

  @override
  String get gamePhaseRoundEnd => 'Runde beendet';

  @override
  String get gamePhaseGameEnd => 'Spiel beendet';

  @override
  String get gameReceivedCards => 'Erhaltene Karten';

  @override
  String get gameBadgeLarge => 'Large';

  @override
  String get gameBadgeSmall => 'Small';

  @override
  String get gameNotAfk => 'Nicht AFK';

  @override
  String get spectatorRecovering =>
      'Zuschaueransicht wird wiederhergestellt...';

  @override
  String get spectatorTransitioning => 'Zuschaueransicht wird gewechselt...';

  @override
  String get spectatorRecheckingState =>
      'Aktueller Zuschauerstatus wird erneut geprüft.';

  @override
  String get spectatorWatching => 'Zuschauer';

  @override
  String get spectatorWaitingForGame => 'Warten auf Spielstart...';

  @override
  String get spectatorSit => 'Hinsetzen';

  @override
  String get spectatorHost => 'Gastgeber';

  @override
  String get spectatorReady => 'Bereit';

  @override
  String get spectatorWaiting => 'Wartend';

  @override
  String get spectatorBlueTeamWin => 'Team A gewinnt!';

  @override
  String get spectatorRedTeamWin => 'Team B gewinnt!';

  @override
  String spectatorTeamWin(String team) {
    return 'Team $team gewinnt!';
  }

  @override
  String get spectatorDraw => 'Unentschieden!';

  @override
  String spectatorTeamScores(int scoreA, int scoreB) {
    return 'Team A: $scoreA | Team B: $scoreB';
  }

  @override
  String get spectatorAutoReturn => 'In 3 Sekunden zurück zum Warteraum...';

  @override
  String get spectatorPhaseLargeTichu => 'Large Tichu';

  @override
  String get spectatorPhaseCardExchange => 'Kartentausch';

  @override
  String get spectatorPhasePlaying => 'Spiel läuft';

  @override
  String get spectatorPhaseRoundEnd => 'Runde beendet';

  @override
  String get spectatorPhaseGameEnd => 'Spiel beendet';

  @override
  String get spectatorFinished => 'Fertig';

  @override
  String spectatorRequesting(int count) {
    return 'Anfrage... ($count Karten)';
  }

  @override
  String spectatorRequestCardView(int count) {
    return 'Hand ansehen ($count Karten)';
  }

  @override
  String get spectatorSoundEffects => 'Soundeffekte';

  @override
  String get spectatorListTitle => 'Zuschauerliste';

  @override
  String get spectatorNoSpectators => 'Keine Zuschauer';

  @override
  String get spectatorClose => 'Schließen';

  @override
  String get spectatorChat => 'Chat';

  @override
  String get spectatorMessageHint => 'Nachricht eingeben...';

  @override
  String get spectatorNewTrick => 'Neuer Stich';

  @override
  String spectatorPlayedCards(String name) {
    return '$name: Karten';
  }

  @override
  String get rulesTitle => 'Spielregeln';

  @override
  String get rulesTabTichu => 'Tichu';

  @override
  String get rulesTabSkullKing => 'Skull King';

  @override
  String get rulesTabLoveLetter => 'Love Letter';

  @override
  String get rulesTichuGoalTitle => 'Spielziel';

  @override
  String get rulesTichuGoalBody =>
      'Ein Stichspiel für 4 Spieler in 2 Teams (Partner sitzen sich gegenüber). Das erste Team, das die Zielpunktzahl erreicht, gewinnt.';

  @override
  String get rulesTichuCardCompositionTitle =>
      'Kartenzusammensetzung (56 Karten)';

  @override
  String get rulesTichuNumberCards => 'Zahlenkarten (2 – A)';

  @override
  String get rulesTichuNumberCardsSub => '4 Farben × 13 Karten';

  @override
  String get rulesTichuMahjong => 'Mahjong';

  @override
  String get rulesTichuMahjongSub => 'Startkarte des Spiels';

  @override
  String get rulesTichuDog => 'Dog';

  @override
  String get rulesTichuDogSub => 'Gibt die Führung an den Partner weiter';

  @override
  String get rulesTichuPhoenix => 'Phoenix';

  @override
  String get rulesTichuPhoenixSub => 'Jokerkarte (-25 Punkte)';

  @override
  String get rulesTichuDragon => 'Dragon';

  @override
  String get rulesTichuDragonSub => 'Stärkste Karte (+25 Punkte)';

  @override
  String get rulesTichuSpecialTitle => 'Spezialkarten-Regeln';

  @override
  String get rulesTichuSpecialMahjongTitle => 'Mahjong';

  @override
  String get rulesTichuSpecialMahjongLine1 =>
      'Der Spieler mit dieser Karte beginnt den allerersten Stich.';

  @override
  String get rulesTichuSpecialMahjongLine2 =>
      'Beim Ausspielen des Mahjong kannst du eine Zahl (2–14) ansagen. Der nächste Spieler muss diese Zahl in seiner Kombination verwenden, falls vorhanden (wird ignoriert, wenn nicht vorhanden).';

  @override
  String get rulesTichuSpecialDogTitle => 'Dog';

  @override
  String get rulesTichuSpecialDogLine1 =>
      'Kann nur beim Anführen gespielt werden. Gibt die Führung sofort an den Partner weiter.';

  @override
  String get rulesTichuSpecialDogLine2 => 'Zählt 0 Punkte bei der Wertung.';

  @override
  String get rulesTichuSpecialPhoenixTitle => 'Phoenix';

  @override
  String get rulesTichuSpecialPhoenixLine1 =>
      'Als Einzelkarte gespielt, zählt sie als vorherige Karte + 0,5. Kann jedoch den Dragon nicht schlagen.';

  @override
  String get rulesTichuSpecialPhoenixLine2 =>
      'In Kombinationen (Pair/Triple/Full House/Straight usw.) kann sie jede beliebige Zahl ersetzen.';

  @override
  String get rulesTichuSpecialPhoenixLine3 =>
      'Zählt -25 Punkte, daher ist es nachteilig, sie zu nehmen.';

  @override
  String get rulesTichuSpecialDragonTitle => 'Dragon';

  @override
  String get rulesTichuSpecialDragonLine1 =>
      'Die stärkste Karte; kann nur als Einzelkarte gespielt werden.';

  @override
  String get rulesTichuSpecialDragonLine2 =>
      'Zählt +25 Punkte, aber der mit dem Dragon gewonnene Stich muss an einen Gegner abgegeben werden.';

  @override
  String get rulesTichuDeclarationTitle => 'Tichu-Ansage';

  @override
  String get rulesTichuDeclarationBody =>
      'Eine Tichu-Ansage ist eine Wette, dass du als Erster deine Hand leer spielst. Bei Erfolg gibt es Bonuspunkte, bei Misserfolg Abzüge.';

  @override
  String get rulesTichuLargeTichu => 'Large Tichu';

  @override
  String get rulesTichuLargeTichuWhen =>
      'Angesagt nach Erhalt der ersten 8 Karten (vor den restlichen 6)';

  @override
  String get rulesTichuSmallTichu => 'Small Tichu';

  @override
  String get rulesTichuSmallTichuWhen =>
      'Angesagt nach Erhalt aller 14 Karten, aber bevor eine Karte gespielt wird';

  @override
  String rulesTichuDeclSuccess(String points) {
    return 'Erfolg $points';
  }

  @override
  String rulesTichuDeclFail(String points) {
    return 'Misserfolg $points';
  }

  @override
  String get rulesTichuFlowTitle => 'Spielablauf';

  @override
  String get rulesTichuFlowBody =>
      '1. Alle Spieler erhalten zunächst 8 Karten.\n2. Nach Ansicht der 8 Karten kann Large Tichu angesagt werden.\n3. Die restlichen 6 Karten werden verteilt, insgesamt 14.\n4. Jeder Spieler tauscht je 1 Karte mit jedem der 3 anderen Spieler.\n5. Nach dem Tausch, vor dem Ausspielen, kann Small Tichu angesagt werden.\n6. Der Spieler mit dem Mahjong beginnt den ersten Stich.';

  @override
  String get rulesTichuPlayTitle => 'Spielregeln';

  @override
  String get rulesTichuPlayBody =>
      '• Nur die gleiche Art von Kombination kann über die führende gespielt werden, aber höher. (z.B. eine höhere Einzelkarte über eine Einzelkarte, ein höheres Pair über ein Pair)\n• Verfügbare Kombinationen:\n   - Single (1 Karte)\n   - Pair (2 gleiche Zahlen)\n   - Triple (3 gleiche Zahlen)\n   - Full House (Triple + Pair)\n   - Straight (5+ aufeinanderfolgende Zahlen)\n   - Consecutive Pairs (2+ aufeinanderfolgende Pairs = 4+ Karten)\n• Du kannst passen, wenn du nicht spielen kannst oder willst.';

  @override
  String get rulesTichuBombTitle => 'Bombe';

  @override
  String get rulesTichuBombBody =>
      'Eine Bombe kann jederzeit gespielt werden, auch außer der Reihe, und schlägt jede Kombination.\n\n• Vierling-Bombe: 4 gleiche Zahlen (z.B. 7♠ 7♥ 7♦ 7♣)\n• Straight-Flush-Bombe: 5+ aufeinanderfolgende Karten derselben Farbe\n\nBomben-Hierarchie:\n  Straight Flush > Vierling\n  Gleicher Typ: höhere Zahl / längerer Straight gewinnt';

  @override
  String get rulesTichuScoringTitle => 'Punktwertung';

  @override
  String get rulesTichuScoringBody =>
      'Kartenpunkte:\n• 5: 5 Punkte\n• 10, K: 10 Punkte\n• Dragon: +25 Punkte / Phoenix: -25 Punkte\n• Alle anderen Karten: 0 Punkte\n\nRundenabrechnung:\n• Der Erstplatzierte erhält alle Stichpunkte des Letztplatzierten (4.).\n• Karten in der Hand des Letztplatzierten gehen an das gegnerische Team.\n• Wenn beide Partner eines Teams als 1. und 2. fertig werden (\"Double Victory\"), endet die Runde sofort — +200 Punkte für das Gewinnerteam (keine Stichpunktwertung).\n• Tichu-Ansage-Boni werden hinzuaddiert.';

  @override
  String get rulesTichuWinTitle => 'Siegbedingung';

  @override
  String get rulesTichuWinBody =>
      'Das erste Team, das die beim Erstellen festgelegte Zielpunktzahl (Standard 1000) erreicht, gewinnt. Ranglistenspiele verwenden feste 1000 Punkte.';

  @override
  String get rulesSkGoalTitle => 'Spielziel';

  @override
  String get rulesSkGoalBody =>
      'Ein Stichspiel für 2–6 Spieler (Jeder gegen Jeden). Über 10 Runden musst du die Anzahl deiner gewonnenen Stiche pro Runde genau vorhersagen, um Punkte zu erhalten.';

  @override
  String get rulesSkCardCompositionTitle =>
      'Kartenzusammensetzung (65 Basiskarten)';

  @override
  String get rulesSkNumberCards => 'Zahlenkarten (1 – 13)';

  @override
  String get rulesSkNumberCardsSub =>
      '4 Farben × 13 Karten (Gelb / Grün / Lila / Schwarz)';

  @override
  String get rulesSkEscape => 'Escape';

  @override
  String get rulesSkEscapeSub => 'Gewinnt nie einen Stich';

  @override
  String get rulesSkPirate => 'Pirate';

  @override
  String get rulesSkPirateSub => 'Schlägt alle Zahlenkarten';

  @override
  String get rulesSkMermaid => 'Mermaid';

  @override
  String get rulesSkMermaidSub => 'Fängt Skull King (+50 Bonus)';

  @override
  String get rulesSkSkullKing => 'Skull King';

  @override
  String get rulesSkSkullKingSub => 'Schlägt Pirates (+30 Bonus pro Pirate)';

  @override
  String get rulesSkTigress => 'Tigress';

  @override
  String get rulesSkTigressSub => 'Wähle zwischen Pirate oder Escape';

  @override
  String get rulesSkIncludedByDefault => 'Standardmäßig enthalten';

  @override
  String rulesSkCardCount(int count) {
    return '$count Karten';
  }

  @override
  String get rulesSkTrumpTitle => 'Schwarz = Trumpf';

  @override
  String get rulesSkTrumpBody =>
      'Schwarze Zahlenkarten schlagen alle anderen Farben unabhängig von der Zahl. Du musst jedoch der geführten Farbe folgen, wenn möglich, und darfst nur Schwarz spielen, wenn du keine Karte der geführten Farbe hast.';

  @override
  String get rulesSkSpecialTitle => 'Spezialkarten-Regeln';

  @override
  String get rulesSkSpecialEscapeTitle => 'Escape';

  @override
  String get rulesSkSpecialEscapeLine1 =>
      'Gewinnt niemals einen Stich. Kann jederzeit unabhängig von der Farbfolge gespielt werden.';

  @override
  String get rulesSkSpecialEscapeLine2 =>
      'Wenn alle Spieler nur Escapes spielen, nimmt der führende Spieler den Stich.';

  @override
  String get rulesSkSpecialPirateTitle => 'Pirate';

  @override
  String get rulesSkSpecialPirateLine1 =>
      'Schlägt alle Zahlenkarten (einschließlich schwarzer Trümpfe). Bei mehreren Pirates im selben Stich gewinnt der zuerst gespielte.';

  @override
  String get rulesSkSpecialPirateLine2 =>
      'Schlägt Mermaids, verliert aber gegen Skull King.';

  @override
  String get rulesSkSpecialMermaidTitle => 'Mermaid';

  @override
  String get rulesSkSpecialMermaidLine1 =>
      'Verliert gegen Pirates, fängt aber Skull King und gewinnt.';

  @override
  String get rulesSkSpecialMermaidLine2 =>
      'Wenn Mermaid den Skull King fängt, erhält der Stichgewinner +50 Bonus.';

  @override
  String get rulesSkSpecialMermaidLine3 =>
      'Wenn nur Mermaids vorhanden sind (keine Pirates/Skull King), schlagen sie Zahlenkarten.';

  @override
  String get rulesSkSpecialSkullKingTitle => 'Skull King';

  @override
  String get rulesSkSpecialSkullKingLine1 =>
      'Schlägt Pirates — +30 Bonus pro besiegtem Pirate.';

  @override
  String get rulesSkSpecialSkullKingLine2 =>
      'Verliert jedoch gegen Mermaids (wird gefangen).';

  @override
  String get rulesSkSpecialTigressTitle => 'Tigress — standardmäßig 1 Karte';

  @override
  String get rulesSkSpecialTigressLine1 =>
      'Beim Ausspielen wählst du entweder Pirate oder Escape.';

  @override
  String get rulesSkSpecialTigressLine2 =>
      'Als Pirate gespielte Tigress funktioniert identisch wie ein Pirate, einschließlich des +30 Skull King-Bonus.';

  @override
  String get rulesSkSpecialTigressLine3 =>
      'Als Escape gespielte Tigress funktioniert identisch wie ein Escape und gewinnt nie einen Stich.';

  @override
  String get rulesSkSpecialTigressLine4 =>
      'Eine als Pirate/Escape gespielte Tigress zeigt ein lila Häkchen oben links zur Unterscheidung von normalen Pirate/Escape-Karten.';

  @override
  String get rulesSkTigressPreviewTitle => 'Anzeige im Spiel';

  @override
  String get rulesSkTigressChoiceEscape => 'Als Escape gespielt';

  @override
  String get rulesSkTigressChoicePirate => 'Als Pirate gespielt';

  @override
  String get rulesSkFlowTitle => 'Spielablauf';

  @override
  String get rulesSkFlowBody =>
      '1. In Runde N erhält jeder Spieler N Karten. (Runden 1–10)\n2. Alle Spieler sagen gleichzeitig voraus (Bid), wie viele Stiche sie gewinnen werden.\n3. Ab dem führenden Spieler werden Karten nach Farbfolge-Regeln gespielt.\n4. Nach jeder Runde werden Punkte basierend auf Bid-Erfolg/-Misserfolg berechnet.';

  @override
  String get rulesSkScoringTitle => 'Punktwertung';

  @override
  String get rulesSkScoringBody =>
      '• Bid 0 Erfolg (0 Stiche gewonnen): +10 × Rundennummer\n• Bid 0 Misserfolg: -10 × Rundennummer\n• Bid N Erfolg (genau N Stiche): +20 × N + Bonus\n• Bid N Misserfolg: -10 × |Differenz| (kein Bonus)\n• Boni werden nur bei exaktem Bid vergeben.';

  @override
  String get rulesSkExample1Title => 'Beispiel 1. Einfacher Bid-Erfolg';

  @override
  String get rulesSkExample1Setup => 'Runde 3 · Bid 2 · 2 Stiche · Kein Bonus';

  @override
  String get rulesSkExample1Calc => '20 × 2 = 40';

  @override
  String get rulesSkExample1Result => '+40 Pkt.';

  @override
  String get rulesSkExample2Title => 'Beispiel 2. Bid 0 Erfolg';

  @override
  String get rulesSkExample2Setup => 'Runde 5 · Bid 0 · 0 Stiche';

  @override
  String get rulesSkExample2Calc => '10 × 5 = 50';

  @override
  String get rulesSkExample2Result => '+50 Pkt.';

  @override
  String get rulesSkExample3Title => 'Beispiel 3. Bid-Misserfolg';

  @override
  String get rulesSkExample3Setup => 'Runde 5 · Bid 3 · 1 Stich (Differenz 2)';

  @override
  String get rulesSkExample3Calc => '-10 × 2 = -20';

  @override
  String get rulesSkExample3Result => '-20 Pkt.';

  @override
  String get rulesSkExample4Title => 'Beispiel 4. Skull King fängt 2 Pirates';

  @override
  String get rulesSkExample4Setup =>
      'Runde 3 · Bid 2 · 2 Stiche · Bonus +60 (2 Pirates × 30)';

  @override
  String get rulesSkExample4Calc => '(20 × 2) + 60 = 100';

  @override
  String get rulesSkExample4Result => '+100 Pkt.';

  @override
  String get rulesSkExample5Title => 'Beispiel 5. Mermaid fängt Skull King';

  @override
  String get rulesSkExample5Setup =>
      'Runde 4 · Bid 1 · 1 Stich · Bonus +50 (Mermaid × SK)';

  @override
  String get rulesSkExample5Calc => '(20 × 1) + 50 = 70';

  @override
  String get rulesSkExample5Result => '+70 Pkt.';

  @override
  String get rulesSkExample6Title =>
      'Beispiel 6. Bid 0 Misserfolg (Stich genommen)';

  @override
  String get rulesSkExample6Setup => 'Runde 7 · Bid 0 · 1 Stich';

  @override
  String get rulesSkExample6Calc => '-10 × 7 = -70';

  @override
  String get rulesSkExample6Result => '-70 Pkt.';

  @override
  String get rulesSkWinTitle => 'Siegbedingung';

  @override
  String get rulesSkWinBody =>
      'Nach allen 10 Runden gewinnt der Spieler mit der höchsten Gesamtpunktzahl.';

  @override
  String get rulesSkExpansionTitle => 'Erweiterungen (Optional)';

  @override
  String get skGameIncludedExpansions => 'Enthaltene Erweiterungen';

  @override
  String get rulesSkExpansionBody =>
      'Jede Erweiterung kann beim Erstellen eines Raums einzeln ausgewählt werden. Erweiterungskarten werden in das Basisdeck gemischt.';

  @override
  String get rulesSkExpKraken => '🐙 Kraken';

  @override
  String get rulesSkExpKrakenDesc =>
      'Ein Stich mit dem Kraken wird ungültig. Niemand gewinnt den Stich und keine Boni werden vergeben. Der Spieler, der ohne Kraken gewonnen hätte, führt den nächsten Stich an.';

  @override
  String get rulesSkExpWhiteWhale => '🐋 White Whale';

  @override
  String get rulesSkExpWhiteWhaleDesc =>
      'Neutralisiert alle Spezialkarten-Effekte. Nur Zahlenkarten werden verglichen, und die höchste Zahl gewinnt unabhängig von der Farbe. Ohne Zahlenkarten wird der Stich ungültig.';

  @override
  String get rulesSkExpLoot => '💰 Loot';

  @override
  String get rulesSkExpLootDesc =>
      'Der Stichgewinner erhält +20 Bonus pro Loot-Karte im Stich, und jeder Spieler, der eine Loot-Karte gespielt hat, erhält ebenfalls +20 als eigenen Bonus. (Nur bei Bid-Erfolg)';

  @override
  String get rulesLlGoalTitle => 'Spielziel';

  @override
  String get rulesLlGoalBody =>
      'Ein Kartenspiel für 2–4 Spieler. Pro Runde gewinnt der letzte verbliebene Spieler oder der Spieler mit der höchsten Karte, wenn das Deck aufgebraucht ist, ein Token. Der erste Spieler, der genügend Token sammelt, gewinnt.';

  @override
  String get rulesLlCardCompositionTitle => 'Kartenzusammensetzung (16 Karten)';

  @override
  String get rulesLlGuard => 'Wache (Guard)';

  @override
  String get rulesLlGuardSub =>
      'Rate die Karte eines Gegners, um ihn zu eliminieren';

  @override
  String get rulesLlSpy => 'Spion (Spy)';

  @override
  String get rulesLlSpySub => 'Sieh dir heimlich die Karte eines Gegners an';

  @override
  String get rulesLlBaron => 'Baron';

  @override
  String get rulesLlBaronSub =>
      'Kartenvergleich; niedrigere Karte wird eliminiert';

  @override
  String get rulesLlHandmaid => 'Zofe (Handmaid)';

  @override
  String get rulesLlHandmaidSub =>
      'Bis zum nächsten Zug vor Effekten geschützt';

  @override
  String get rulesLlPrince => 'Prinz (Prince)';

  @override
  String get rulesLlPrinceSub => 'Zwinge einen Spieler, seine Karte abzuwerfen';

  @override
  String get rulesLlKing => 'König (King)';

  @override
  String get rulesLlKingSub => 'Tausche Karten mit einem Gegner';

  @override
  String get rulesLlCountess => 'Gräfin (Countess)';

  @override
  String get rulesLlCountessSub =>
      'Muss gespielt werden, wenn König oder Prinz gehalten wird';

  @override
  String get rulesLlPrincess => 'Prinzessin (Princess)';

  @override
  String get rulesLlPrincessSub => 'Eliminiert, wenn gespielt oder abgeworfen';

  @override
  String get rulesLlCardEffectsTitle => 'Detaillierte Karteneffekte';

  @override
  String get rulesLlEffectGuardTitle => 'Wache (1)';

  @override
  String get rulesLlEffectGuardLine1 =>
      'Nenne einen Spieler und rate eine Nicht-Wache-Karte, die er haben könnte.';

  @override
  String get rulesLlEffectGuardLine2 =>
      'Bei richtigem Tipp wird dieser Spieler eliminiert.';

  @override
  String get rulesLlEffectSpyTitle => 'Spion (2)';

  @override
  String get rulesLlEffectSpyLine1 =>
      'Wähle einen Spieler und sieh dir heimlich seine Handkarte an.';

  @override
  String get rulesLlEffectBaronTitle => 'Baron (3)';

  @override
  String get rulesLlEffectBaronLine1 =>
      'Wähle einen Spieler und vergleicht eure Handkarten privat.';

  @override
  String get rulesLlEffectBaronLine2 =>
      'Der Spieler mit der niedrigeren Karte wird eliminiert. Bei Gleichstand passiert nichts.';

  @override
  String get rulesLlEffectHandmaidTitle => 'Zofe (4)';

  @override
  String get rulesLlEffectHandmaidLine1 =>
      'Bis zu deinem nächsten Zug kannst du nicht als Ziel eines Karteneffekts gewählt werden.';

  @override
  String get rulesLlEffectPrinceTitle => 'Prinz (5)';

  @override
  String get rulesLlEffectPrinceLine1 =>
      'Wähle einen Spieler (auch dich selbst), der seine Handkarte abwerfen und eine neue ziehen muss.';

  @override
  String get rulesLlEffectPrinceLine2 =>
      'Wenn die Prinzessin abgeworfen wird, ist dieser Spieler eliminiert.';

  @override
  String get rulesLlEffectKingTitle => 'König (6)';

  @override
  String get rulesLlEffectKingLine1 =>
      'Wähle einen Spieler und tauscht eure Handkarten.';

  @override
  String get rulesLlEffectCountessTitle => 'Gräfin (7)';

  @override
  String get rulesLlEffectCountessLine1 =>
      'Wenn du den König (6) oder Prinzen (5) zusammen mit der Gräfin hältst, musst du die Gräfin spielen.';

  @override
  String get rulesLlEffectCountessLine2 =>
      'Ansonsten kann sie frei gespielt werden und hat keinen Effekt.';

  @override
  String get rulesLlEffectPrincessTitle => 'Prinzessin (8)';

  @override
  String get rulesLlEffectPrincessLine1 =>
      'Wenn diese Karte aus irgendeinem Grund gespielt oder abgeworfen wird, bist du sofort eliminiert.';

  @override
  String get rulesLlFlowTitle => 'Spielablauf';

  @override
  String get rulesLlFlowBody =>
      '1. Entferne 1 Karte verdeckt aus dem Deck. (Bei 2 Spielern werden 3 zusätzliche Karten offen entfernt.)\n2. Teile jedem Spieler 1 Karte aus.\n3. Ziehe in deinem Zug 1 Karte vom Deck und spiele dann 1 deiner 2 Karten aus, um ihren Effekt auszulösen.\n4. Nach dem Effekt geht der Zug an den nächsten Spieler.\n5. Die Runde endet, wenn nur 1 Spieler übrig ist oder das Deck leer ist.';

  @override
  String get rulesLlWinTitle => 'Siegbedingung';

  @override
  String get rulesLlWinBody =>
      'Am Ende der Runde gewinnt der überlebende Spieler mit der höchsten Karte ein Token. Bei Gleichstand (in dieser Reihenfolge):\n1. Höhere Gesamtsumme der in dieser Runde gespielten Karten gewinnt.\n2. Bleibt es gleich, gewinnen alle Gleichplatzierten ein Token.\n\nBenötigte Token zum Sieg:\n• 2 Spieler: 4 Token\n• 3 Spieler: 3 Token\n• 4 Spieler: 2 Token';

  @override
  String get rulesTabMighty => 'Mighty';

  @override
  String get rulesMtGoalTitle => 'Spielziel';

  @override
  String get rulesMtGoalBody =>
      'Ein Stichkartenspiel für 5 oder 6 Spieler. Ein Spieler wird zum Alleinspieler und wählt einen Freund; gemeinsam versuchen sie, genügend Punktkarten zu gewinnen, um das Gebot zu erfüllen. Die übrigen Spieler bilden die Verteidigung und versuchen, sie aufzuhalten.\n\nMit 6 Spielern gilt automatisch die Kill-Mighty-Variante. Sperrt der Gastgeber einen Platz, wird im klassischen 5-Spieler-Modus gespielt.';

  @override
  String get rulesMtCardCompositionTitle => 'Kartenzusammensetzung (53 Karten)';

  @override
  String get rulesMtCardCompositionBody =>
      'Standard-52-Karten-Deck (4 Farben × 13 Ränge: 2–A) plus 1 Joker.\nKartenstärke: A > K > Q > J > 10 > 9 > … > 2\nPunktkarten: A = 1 Pkt, K = 1 Pkt, Q = 1 Pkt, J = 1 Pkt, 10 = 1 Pkt (gesamt 20 Pkt)\n\n[Verteilung]\n• 5 Spieler: je 10 Karten + 3-Karten-Kitty\n• 6 Spieler: je 8 Karten + 5-Karten-Kitty';

  @override
  String get rulesMtSpecialTitle => 'Sonderkarten';

  @override
  String get rulesMtSpecialMightyTitle => 'Mighty';

  @override
  String get rulesMtSpecialMightyLine1 =>
      'Die stärkste Karte im Spiel. Schlägt alles außer dem Joker-Ruf.';

  @override
  String get rulesMtSpecialMightyLine2 =>
      'Standardmäßig das Pik-Ass. Wenn Pik die Trumpffarbe ist, wird stattdessen das Karo-Ass zum Mighty.';

  @override
  String get rulesMtSpecialMightyAltLabel => 'bei Trumpf = ♠';

  @override
  String get rulesMtSpecialJokerTitle => 'Joker';

  @override
  String get rulesMtSpecialJokerLine1 =>
      'Die zweitstärkste Karte. Gewinnt jeden Stich, es sei denn, der Joker-Ruf wird gespielt.';

  @override
  String get rulesMtSpecialJokerLine2 =>
      'Beim Ausspielen des Jokers erklärt der Spieler, welche Farbe die anderen bedienen müssen.\nDer Joker verliert seine Kraft im ersten und letzten Stich.';

  @override
  String get rulesMtSpecialJokerCallTitle => 'Joker-Ruf';

  @override
  String get rulesMtSpecialJokerCallLine1 =>
      'Wenn die festgelegte Joker-Ruf-Karte (Standard ♣3) den Stich anführt, verliert der Joker seine Kraft und wird als schwächste Karte behandelt.';

  @override
  String get rulesMtSpecialJokerCallLine2 =>
      'Wenn Kreuz die Trumpffarbe ist, wird der Joker-Ruf zu ♠3.';

  @override
  String get rulesMtBiddingTitle => 'Bieten';

  @override
  String get rulesMtBiddingBody =>
      'Spieler bieten reihum und geben an, wie viele Punkte (von 20) sie erzielen werden.\n\n• Mindestgebot: 13 im 5-Spieler-Modus, 14 in 6-Spieler-Kill-Mighty\n• Höchstgebot: 20\n\nDer Höchstbietende wird Alleinspieler und wählt die Trumpffarbe. Wenn alle Spieler passen, wird neu gegeben (kein Spiel).\n\nBei sehr schwacher Hand kann statt Bieten oder Passen ein Deal-Miss gerufen werden, um neu geben zu lassen.';

  @override
  String get rulesMtDealMissTitle => 'Deal-Miss';

  @override
  String get rulesMtDealMissBody =>
      'Ist deine Hand beim Bieten sehr schwach, kannst du einen Deal-Miss ansagen.\n\n[Hand-Bewertung]\n• Pik-Ass = 0 Pkt\n• Joker = streicht die einzelne höchste Punktkarte in der Hand\n• A / K / Q / J = je 1 Pkt\n• 10 = 0,5 Pkt\n\n[Ansage-Bedingungen]\n• Du bist dran und hast noch weder geboten noch gepasst\n• 5 Spieler: Handpunkte ≤ 0,5\n• 6-Spieler-Kill-Mighty: Handpunkte genau 0\n\n[Wirkung]\n• Der Ansager verliert sofort 5 Punkte\n• Diese 5 Punkte landen im \"Deal-Miss-Pool\"\n• Die Karten werden gemischt und derselbe Geber gibt neu\n• Der Pool geht als Bonus an den nächsten erfolgreichen Alleinspieler (bleibt bei Misserfolg bestehen)';

  @override
  String get rulesMtKillTitle => 'Kill-Ansage (nur 6 Spieler)';

  @override
  String get rulesMtKillBody =>
      'Nach Ende des Biedens im 6-Spieler-Modus benennt der Alleinspieler eine Kill-Zielkarte, die NICHT auf seiner Hand liegt.\n\n[① Kill – Ziel liegt in einer anderen Hand]\n• Die 8 Karten des Opfers + die 5 Kitty-Karten = 13 Karten werden gemischt\n• Der Alleinspieler erhält 5, jeder der anderen 4 erhält 2\n• Das Opfer ist diese Runde ausgeschlossen (0 Punkte)\n• Es geht wie im 5-Spieler-Mighty weiter (3 ablegen, Freund wählen)\n\n[② Selbst-KO – Ziel liegt im Kitty]\n• Die 8 Karten des Alleinspielers + 5 Kitty = 13 Karten werden gemischt\n• Die anderen 5 erhalten je 2, die restlichen 3 bilden das neue Kitty\n• Der Alleinspieler ist diese Runde ausgeschlossen (0 Punkte)\n• Das Bieten startet nach 5-Spieler-Regeln neu (min 13, Deal-Miss 0,5)';

  @override
  String get rulesMtFriendTitle => 'Freund-Erklärung';

  @override
  String get rulesMtFriendBody =>
      'Nach dem Gewinn des Gebots erklärt der Alleinspieler einen Freund, indem er eine bestimmte Karte nennt (z.B. \'Pik-König\'). Der Spieler, der diese Karte hält, wird zum geheimen Verbündeten — seine Identität wird enthüllt, wenn die Karte gespielt wird.\n\nDer Alleinspieler kann auch allein spielen (kein Freund) oder den Gewinner des ersten Stichs als Freund bestimmen.';

  @override
  String get rulesMtKittyTitle => 'Kitty-Tausch';

  @override
  String get rulesMtKittyBody =>
      'Der Alleinspieler erhält 3 Kitty-Karten und muss 3 Karten aus seiner Hand abwerfen.\n\nIn dieser Phase kann der Alleinspieler das Gebot um +2 erhöhen (maximal 20), mit oder ohne Änderung der Trumpffarbe.';

  @override
  String get rulesMtTrickTitle => 'Stichregeln';

  @override
  String get rulesMtTrickBody =>
      '1. Der Ausspieler spielt eine beliebige Karte und bestimmt die Ansagefarbe.\n2. Andere Spieler müssen die Farbe bedienen, wenn möglich.\n3. Wer nicht bedienen kann, darf eine beliebige Karte spielen (einschließlich Trumpf).\n4. Die höchste Karte der Ansagefarbe gewinnt, es sei denn, eine Trumpfkarte wird gespielt — dann gewinnt der höchste Trumpf.\n5. Mighty und Joker überschreiben die normalen Stärkeregeln.\n6. Der Stichgewinner spielt den nächsten Stich aus.\n7. Im ersten Stich darf nicht mit einer Trumpfkarte ausgespielt werden.';

  @override
  String get rulesMtScoringTitle => 'Punktwertung';

  @override
  String get rulesMtScoringBody =>
      '20 Punktkarten im Deck (A, K, Q, J, 10 × 4 Farben = 20).\n\n[Erfolgs-Wertung]\nBasis = (Gebot − minBid + 1) × 2 + (gesammelte Punkte − Gebot)\n\nVerteilung:\n• Alleinspieler: Basis × 2  (Solo: × 4 — kein Partner, ein Verteidiger mehr)\n• Freund: Basis × 1\n• Jeder Verteidiger: −Basis\n\nMultiplikatoren (stapelbar, für alle Seiten):\n• Run (alle 20 Pkt): ×2\n• Ohne Trumpf (NT): ×2\n• Gebot 20: ×2\nMax: ×8\n\n[Misserfolgs-Wertung]\nEinheit = (Gebot − gesammelte Punkte)\n\nVerteilung:\n• Alleinspieler: −Einheit × 2\n• Freund: −Einheit\n• Jeder Verteidiger: +Einheit\n\nMisserfolgs-Multiplikatoren:\n• Solo (kein Freund): Alleinspieler −Einheit × 2 × 2 = ×4 (kein Partner, ein Verteidiger mehr)\n• Backrun (Spielerteam ≤ 10 Pkt = Verteidiger ≥ 10 Pkt): ×2 auf allen Seiten, unabhängig vom Gebot\n\n[Erfolgs-Beispiel]\nGebot 13, 15 Pkt mit Freund:\nBasis = (1×2) + 2 = 4\nAlleinspieler +8, Freund +4, Verteidiger je −4\n\n[Solo-Erfolgs-Beispiel]\nGebot 14, kein Freund, 16 Pkt:\nBasis = (2×2) + 2 = 6\nAlleinspieler +24 (Basis × 4), Verteidiger je −6\n(mit NT: Basis 12 → Alleinspieler +48, Verteidiger je −12)\n\n[Misserfolgs-Beispiel]\nGebot 17, 15 Pkt mit Freund (2 Pkt unter Gebot):\nEinheit = 2  (kein Backrun)\nAlleinspieler −4, Freund −2, Verteidiger je +2\n\n[Misserfolg + Backrun]\nGebot 17, 10 Pkt (Backrun):\nEinheit = 7 × 2 = 14\nAlleinspieler −28, Freund −14, Verteidiger je +14\n\n[Misserfolg + Solo + Backrun]\nGebot 17, Solo, 5 Pkt (12 Pkt unter Gebot, Backrun):\nEinheit = 12 × 2 = 24\nAlleinspieler −24 × 4 = −96, Verteidiger je +24';

  @override
  String get rulesMtWinTitle => 'Siegbedingung';

  @override
  String get rulesMtWinBody =>
      'Nach allen 10 Stichen werden die Punktkarten des Alleinspieler-Teams gezählt.\n\n• Gebot erreicht oder übertroffen → Alleinspieler-Team gewinnt.\n• Gebot verfehlt → Verteidigung gewinnt.\n\nPunkte werden über mehrere Runden gesammelt. Der Spieler mit der höchsten Punktzahl am Ende der Sitzung gewinnt.';

  @override
  String get mtPhaseBidding => 'Bieten';

  @override
  String get mtPhaseKitty => 'Kitty';

  @override
  String get mtPhasePlaying => 'Spielen';

  @override
  String get mtPhaseRoundEnd => 'Rundenende';

  @override
  String get mtPhaseGameEnd => 'Spielende';

  @override
  String mtRoundPhase(Object round, Object phase) {
    return 'Runde $round · $phase';
  }

  @override
  String mtRoundOnly(Object round) {
    return 'Runde $round';
  }

  @override
  String get mtSolo => 'Solo';

  @override
  String mtFriendLabel(Object label) {
    return 'Freund: $label';
  }

  @override
  String get mtChat => 'Chat';

  @override
  String get mtTypeMessage => 'Nachricht eingeben...';

  @override
  String get mtLeaveGame => 'Spiel verlassen?';

  @override
  String get mtLeaveConfirm => 'Möchtest du das Spiel wirklich verlassen?';

  @override
  String get mtCancel => 'Abbrechen';

  @override
  String get mtLeave => 'Verlassen';

  @override
  String get mtDeclarer => 'Alleinspieler';

  @override
  String get mtFriend => 'Freund';

  @override
  String mtPointCardsTitle(Object name, Object count) {
    return '$name – Punktkarten (${count}P)';
  }

  @override
  String get mtNoPointCards => 'Noch keine Punktkarten';

  @override
  String get mtClose => 'Schließen';

  @override
  String get mtYourTurn => 'Du bist dran';

  @override
  String get mtWaiting => 'Warten...';

  @override
  String mtPlayed(Object current, Object total) {
    return '$current/$total gespielt';
  }

  @override
  String mtFriendRevealed(Object card, Object name) {
    return 'Freund: $card → $name';
  }

  @override
  String mtFriendHidden(Object card) {
    return 'Freund: $card';
  }

  @override
  String mtWins(Object name) {
    return '$name gewinnt!';
  }

  @override
  String mtCurrentBid(Object points, Object suit) {
    return 'Aktuelles Gebot: $points $suit';
  }

  @override
  String mtCurrentBidPoints(Object points) {
    return 'Aktuelles Gebot: $points';
  }

  @override
  String mtBidPoints(Object points) {
    return 'Bieten $points';
  }

  @override
  String get mtBidInProgress => 'Gebotsphase läuft';

  @override
  String get mtPass => 'Passen';

  @override
  String get mtDealMiss => 'Deal-Miss';

  @override
  String get mtDealMissConfirmBody =>
      'Deal-Miss erklären?\n\nDu verlierst sofort 5 Punkte, die in den Deal-Miss-Pool fließen — der nächste erfolgreiche Alleinspieler sammelt den gesamten Pool ein.';

  @override
  String get mtBidShort => 'Gebot';

  @override
  String get mtPrevTrick => 'Vorheriger Stich';

  @override
  String get profilePhotoChanged => 'Profilbild aktualisiert';

  @override
  String get profilePhotoNeedItem =>
      'Du benötigst einen aktiven Profilbild-Pass';

  @override
  String get profilePhotoUploadFailed =>
      'Foto-Upload fehlgeschlagen. Bitte erneut versuchen';

  @override
  String get profilePhotoSourceTitle => 'Profilbild ändern';

  @override
  String get profilePhotoFromCamera => 'Foto aufnehmen';

  @override
  String get profilePhotoFromGallery => 'Aus Galerie wählen';

  @override
  String get profilePhotoCameraDenied =>
      'Kamerazugriff wurde verweigert. Erlaube ihn in den Einstellungen';

  @override
  String get profilePhotoCameraDeniedTitle => 'Kamerazugriff erforderlich';

  @override
  String get profilePhotoCameraDeniedBody =>
      'Erlaube den Kamerazugriff in den Einstellungen, um ein Foto aufzunehmen.';

  @override
  String get profilePhotoOpenSettings => 'Einstellungen öffnen';

  @override
  String get profilePhotoPhotoDeniedTitle => 'Fotozugriff erforderlich';

  @override
  String get profilePhotoPhotoDeniedBody =>
      'Erlaube den Fotozugriff in den Einstellungen, um ein Bild auszuwählen.';

  @override
  String get profilePhotoCropTitle => 'Foto zuschneiden';

  @override
  String get profilePhotoCropHint =>
      'Ziehen und zoomen, um den gewünschten Ausschnitt zu wählen';

  @override
  String get profilePhotoUploading =>
      'Profilbild wird hochgeladen. Es erscheint, sobald der Vorgang abgeschlossen ist';

  @override
  String get profilePhotoUploadBusy => 'Eine Bildänderung läuft bereits';

  @override
  String get profilePhotoRejected =>
      'Dieses Bild wurde als unangemessen eingestuft und kann nicht verwendet werden';

  @override
  String get profilePhotoModerationDown =>
      'Das Bild konnte nicht geprüft werden. Bitte versuche es in Kürze erneut';

  @override
  String get mtSetting => 'Setting';

  @override
  String get mtSettingConfirmTitle => 'Setting erklären';

  @override
  String get mtSettingConfirmBody =>
      'Erkläre, dass du jeden verbleibenden Stich gewinnst. Deine Hand wird aufgedeckt und die Runde endet sofort.';

  @override
  String get mtSettingRevealTitle => 'Setting erklärt!';

  @override
  String mtSettingRevealBody(Object name) {
    return '$name hat Setting erklärt. Alle verbleibenden Stiche gehen an $name.';
  }

  @override
  String get mtSettingTapToClose => 'Zum Schließen tippen';

  @override
  String get mtRaiseBidConfirmTitle => 'Gebot erhöhen';

  @override
  String mtRaiseBidConfirmBody(Object points) {
    return 'Gebot auf $points erhöhen?';
  }

  @override
  String get mtChangeTrumpConfirmTitle => 'Trumpf wechseln';

  @override
  String mtChangeTrumpConfirmBody(Object points, Object suit) {
    return 'Trumpf auf $suit wechseln und Gebot auf $points erhöhen?';
  }

  @override
  String mtChangeTrumpNoPenaltyBody(Object suit) {
    return 'Trumpf auf $suit wechseln?';
  }

  @override
  String mtPrevTrickTitle(Object number) {
    return 'Stich $number';
  }

  @override
  String mtPrevTrickWinner(Object name) {
    return 'Gewinner: $name';
  }

  @override
  String mtDealMissPool(Object points) {
    return 'Deal-Miss $points';
  }

  @override
  String mtDealMissReveal(Object name, Object score) {
    return '$name hat Deal-Miss mit einer $score-Punkte-Hand angesagt';
  }

  @override
  String get mtDealMissTapToClose => 'Tippe zum Schließen';

  @override
  String get mtKillPhase => 'Kill-Ansage';

  @override
  String get mtKillPhasePrompt => 'Karte zum Killen wählen';

  @override
  String mtKillPhaseWait(Object name) {
    return '$name wählt eine Karte zum Killen';
  }

  @override
  String mtKillResultKilled(Object declarer, Object target, Object victim) {
    return '$declarer nannte $target → $victim ausgeschieden';
  }

  @override
  String mtKillResultSuicide(Object declarer, Object target) {
    return '$declarer nannte $target, aber sie lag im Kitty. Eigen-KO!';
  }

  @override
  String get mtKillExcluded => 'RAUS';

  @override
  String get mtKillConfirm => 'Killen';

  @override
  String get mtPoints => 'Punkte:';

  @override
  String mtBid(Object points, Object suit) {
    return 'Bieten $points $suit';
  }

  @override
  String mtWaitingFor(Object name) {
    return 'Warten auf $name';
  }

  @override
  String get mtExchangingKitty => 'Alleinspieler tauscht Kitty...';

  @override
  String get mtDiscard3 => '3 Karten abwerfen';

  @override
  String get mtFriendColon => 'Freund:';

  @override
  String get mtNoFriend => 'Kein Freund';

  @override
  String get mt1stTrick => '1. Stich';

  @override
  String get mtJoker => 'Joker';

  @override
  String get mtCard => 'Karte';

  @override
  String get mtConfirm => 'Bestätigen';

  @override
  String get mtChangeTrump => 'Trumpf ändern';

  @override
  String get mtChangeContract => 'Vertrag ändern';

  @override
  String mtTrumpPenalty(int penalty) {
    return 'Gebot +$penalty';
  }

  @override
  String mtPlayTimer(Object seconds) {
    return 'Spielen (${seconds}s)';
  }

  @override
  String get mtPlay => 'Spielen';

  @override
  String get mtSelectCard => 'Karte auswählen';

  @override
  String get mtJokerSelectSuit => 'Joker-Farbe wählen';

  @override
  String get mtJokerLoses1st => 'Joker verliert im 1. Stich!';

  @override
  String get mtJokerLosesLast => 'Joker verliert im letzten Stich!';

  @override
  String get mtJokerSuit => 'Joker-Farbe: ';

  @override
  String get mtJokerCall => 'Joker-Ruf: ';

  @override
  String get mtJokerCallLabel => 'Joker-Ruf';

  @override
  String get mtYes => 'Ja';

  @override
  String get mtNo => 'Nein';

  @override
  String mtRoundResult(Object round) {
    return 'Runde $round Ergebnis';
  }

  @override
  String mtDeclarerWins(Object points) {
    return 'Alleinspieler gewinnt! (${points}P)';
  }

  @override
  String mtDeclarerFails(Object points) {
    return 'Alleinspieler scheitert (${points}P)';
  }

  @override
  String get mtNextRound => 'Nächste Runde wird vorbereitet...';

  @override
  String get mtGameOver => 'Spiel vorbei';

  @override
  String mtReturningIn(Object seconds) {
    return 'Rückkehr in $seconds...';
  }

  @override
  String get mtReturningToRoom => 'Zurück zum Raum...';

  @override
  String get mtScoreHistory => 'Punkteverlauf';

  @override
  String get mtRoundAbbr => 'R';

  @override
  String get mtOpposition => 'Verteidigung';

  @override
  String get mtContract => 'Vertrag';

  @override
  String mtContractWithPoints(int points) {
    return 'Gebot $points';
  }

  @override
  String get mtLead => 'Führung';

  @override
  String get mtResult => 'Ergebnis';

  @override
  String get mtTotal => 'Gesamt';

  @override
  String get mtSoloSuffix => '(solo)';

  @override
  String get mtFriendCardJoker => 'Joker';

  @override
  String get mtFriendCardSolo => 'Solo';

  @override
  String get mtFriendCard1st => '1. Stich';

  @override
  String get mtJokerAbbr => 'JK';

  @override
  String get friendsTitle => 'Freunde';

  @override
  String get friendsTabFriends => 'Freunde';

  @override
  String get friendsTabSearch => 'Suche';

  @override
  String get friendsTabRequests => 'Anfragen';

  @override
  String get friendsEmptyList =>
      'Noch keine Freunde!\nSuche im Suche-Tab nach Freunden.';

  @override
  String friendsStatusPlayingInRoom(String roomName) {
    return 'Spielt in $roomName';
  }

  @override
  String get friendsStatusOnline => 'Online';

  @override
  String get friendsStatusOffline => 'Offline';

  @override
  String get friendsRestrictedDuringGame => 'Im Spiel eingeschränkt';

  @override
  String get friendsDmBlockedDuringGame =>
      'DM-Chat ist während des Spiels nicht verfügbar';

  @override
  String get friendsInvited => 'Eingeladen';

  @override
  String get friendsInvite => 'Einladen';

  @override
  String friendsInviteSent(String nickname) {
    return 'Einladung an $nickname gesendet';
  }

  @override
  String get friendsJoinRoom => 'Beitreten';

  @override
  String get friendsSpectateRoom => 'Zuschauen';

  @override
  String get friendsSearchHint => 'Nach Nickname suchen';

  @override
  String get friendsSearchPrompt => 'Nickname eingeben, um zu suchen';

  @override
  String get friendsSearchNoResults => 'Keine Ergebnisse gefunden';

  @override
  String get friendsStatusFriend => 'Freund';

  @override
  String get friendsRequestReceived => 'Anfrage erhalten';

  @override
  String get friendsStatusPendingShort => 'Ausstehend';

  @override
  String get friendsStatusReceivedShort => 'Erhalten';

  @override
  String get friendsRequestSent => 'Anfrage gesendet';

  @override
  String friendsRequestSentSnackbar(String nickname) {
    return 'Freundschaftsanfrage an $nickname gesendet';
  }

  @override
  String get friendsAddFriend => 'Freund hinzufügen';

  @override
  String get friendsNoRequests => 'Keine ausstehenden Anfragen';

  @override
  String friendsAccepted(String nickname) {
    return 'Du bist jetzt mit $nickname befreundet';
  }

  @override
  String get friendsAccept => 'Annehmen';

  @override
  String get friendsReject => 'Ablehnen';

  @override
  String get friendsRejected => 'Freundschaftsanfrage abgelehnt';

  @override
  String get friendsDmEmpty => 'Keine Nachrichten.\nSende die erste Nachricht!';

  @override
  String get friendsDmInputHint => 'Nachricht eingeben';

  @override
  String get friendsRemoveTitle => 'Freund entfernen';

  @override
  String friendsRemoveConfirm(String nickname) {
    return '$nickname aus der Freundesliste entfernen?';
  }

  @override
  String friendsRemoved(String nickname) {
    return '$nickname aus der Freundesliste entfernt';
  }

  @override
  String get rankingTitle => 'Rangliste';

  @override
  String get rankingTichu => 'Tichu';

  @override
  String get rankingSkullKing => 'Skull King';

  @override
  String get rankingNoData => 'Keine Ranglistendaten vorhanden';

  @override
  String rankingRecordWithWinRate(
    int total,
    int wins,
    int losses,
    int winRate,
  ) {
    return 'Bilanz ${total}S ${wins}G ${losses}V · Siegquote $winRate%';
  }

  @override
  String get rankingSeasonScore => 'Saisonpunkte';

  @override
  String get rankingProfileNotFound => 'Profil nicht gefunden';

  @override
  String get rankingTichuSeasonRanked => 'Tichu Saison-Rangliste';

  @override
  String get rankingTichuRecord => 'Tichu Statistik';

  @override
  String get rankingSkullKingSeasonRanked => 'Skull King Saison-Rangliste';

  @override
  String get rankingSkullKingRecord => 'Skull King Statistik';

  @override
  String get rankingMighty => 'Mighty';

  @override
  String get rankingMightySeasonRanked => 'Mighty Saison-Rang';

  @override
  String get rankingMightyRecord => 'Mighty Rekord';

  @override
  String rankingMightyMatchDetail(String declarer, int bid, String trump) {
    return '$declarer Gebot $bid $trump';
  }

  @override
  String get rankingLoveLetterRecord => 'Love Letter Statistik';

  @override
  String get rankingStatRecord => 'Bilanz';

  @override
  String get rankingStatWinRate => 'Siegquote';

  @override
  String rankingRecordFormat(int games, int wins, int losses) {
    return '${games}S ${wins}G ${losses}V';
  }

  @override
  String rankingGold(int gold) {
    return '$gold Gold';
  }

  @override
  String rankingDesertions(int count) {
    return 'Verlassen $count';
  }

  @override
  String get rankingRecentMatchesHeader => 'Letzte Spiele (3)';

  @override
  String get rankingSeeMore => 'Mehr anzeigen';

  @override
  String get rankingNoRecentMatches => 'Keine aktuellen Spiele';

  @override
  String get rankingBadgeDesertion => 'A';

  @override
  String get rankingBadgeDraw => 'U';

  @override
  String rankingSkRankScore(String rank, int score) {
    return '#$rank ${score}Pkt.';
  }

  @override
  String get rankingRecentMatchesTitle => 'Letzte Spiele';

  @override
  String get rankingMannerScore => 'Manieren';

  @override
  String get shopTitle => 'Shop';

  @override
  String shopGoldAmount(int gold) {
    final intl.NumberFormat goldNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String goldString = goldNumberFormat.format(gold);

    return '$goldString Gold';
  }

  @override
  String get shopHowToEarn => 'So verdienst du';

  @override
  String get shopGoldHistory => 'Gold-Verlauf';

  @override
  String shopGoldCurrent(int gold) {
    final intl.NumberFormat goldNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String goldString = goldNumberFormat.format(gold);

    return 'Aktuelles Gold: $goldString';
  }

  @override
  String get shopGoldHistoryDesc =>
      'Zeigt Spielergebnisse, Werbebelohnungen, Shop-Käufe und Saisonbelohnungen in chronologischer Reihenfolge.';

  @override
  String get shopGoldHistoryEmpty => 'Noch kein Gold-Verlauf vorhanden.';

  @override
  String get shopGoldChangeFallback => 'Goldänderung';

  @override
  String get shopGoldGuideTitle => 'So verdienst du Gold';

  @override
  String get shopGoldGuideDesc =>
      'Gold kann durch Spielen und Belohnungen verdient werden und wird zum Kauf von Gegenständen im Shop verwendet.';

  @override
  String get shopGuideNormalWin => 'Normaler Sieg';

  @override
  String get shopGuideNormalWinValue => '+10 Gold';

  @override
  String get shopGuideNormalWinDesc =>
      'Erhalte eine Grundbelohnung für den Sieg in einem normalen Tichu- oder Skull-King-Spiel.';

  @override
  String get shopGuideNormalLoss => 'Normale Niederlage';

  @override
  String get shopGuideNormalLossValue => '+3 Gold';

  @override
  String get shopGuideNormalLossDesc =>
      'Du erhältst auch bei einer Niederlage eine Teilnahmebelohnung.';

  @override
  String get shopGuideRankedWin => 'Ranglistensieg';

  @override
  String get shopGuideRankedWinValue => '+20 Gold';

  @override
  String get shopGuideRankedWinDesc =>
      'Ranglistenspiele belohnen doppelt so viel Gold wie normale Spiele.';

  @override
  String get shopGuideRankedLoss => 'Ranglistenniederlage';

  @override
  String get shopGuideRankedLossValue => '+6 Gold';

  @override
  String get shopGuideRankedLossDesc =>
      'Auch die Ranglistenniederlage-Belohnung ist doppelt so hoch wie bei normalen Spielen.';

  @override
  String get shopGuideAdReward => 'Werbebelohnung';

  @override
  String get shopGuideAdRewardValue => '+50 Gold';

  @override
  String get shopGuideAdRewardDesc =>
      'Sieh dir Werbung an, um bis zu 5-mal pro Tag Bonusgold zu erhalten.';

  @override
  String get shopGuideSeasonReward => 'Saisonbelohnung';

  @override
  String get shopGuideSeasonRewardValue => 'Extra';

  @override
  String get shopGuideSeasonRewardDesc =>
      'Am Ende der Saison wird basierend auf deinem Rang Bonusgold vergeben.';

  @override
  String get shopTabShop => 'Shop';

  @override
  String get shopTabInventory => 'Inventar';

  @override
  String get shopNoItems => 'Keine Shop-Artikel verfügbar';

  @override
  String get shopCategoryBanner => 'Banner';

  @override
  String get shopCategoryTitle => 'Titel';

  @override
  String get shopCategoryTheme => 'Design';

  @override
  String get shopCategoryUtil => 'Nützliches';

  @override
  String get shopCategoryFeature => 'Funktionen';

  @override
  String get shopCategorySeason => 'Saison';

  @override
  String get shopItemEmpty => 'Keine Artikel';

  @override
  String get shopItemOwned => 'Im Besitz';

  @override
  String get shopButtonExtend => 'Verlängern';

  @override
  String get shopButtonPurchase => 'Kaufen';

  @override
  String get shopExtendTitle => 'Laufzeit verlängern';

  @override
  String shopExtendConfirm(String name, int days, int price) {
    return 'Du besitzt diesen Gegenstand bereits.\n$name um $days Tage verlängern?\n\nKosten: $price Gold';
  }

  @override
  String get shopExtendAction => 'Verlängern';

  @override
  String get shopNoInventoryItems => 'Keine Gegenstände im Inventar';

  @override
  String get shopStatusActivated => 'Aktiviert';

  @override
  String get shopStatusInUse => 'In Benutzung';

  @override
  String get shopPermanentOwned => 'Dauerhaft';

  @override
  String get shopButtonUse => 'Benutzen';

  @override
  String get shopButtonEquip => 'Ausrüsten';

  @override
  String get shopTagSeason => 'Saisonartikel';

  @override
  String get shopTagPermanent => 'Dauerhaft';

  @override
  String shopTagDuration(int days) {
    return '$days Tage Laufzeit';
  }

  @override
  String get shopTagDurationOnly => 'Befristet';

  @override
  String shopExpireDate(String date) {
    return 'Läuft ab: $date';
  }

  @override
  String get shopExpireSoon => 'Läuft bald ab';

  @override
  String get shopPurchaseComplete => 'Kauf abgeschlossen';

  @override
  String get shopExtendComplete => 'Verlängerung abgeschlossen';

  @override
  String shopExtendDone(String name) {
    return 'Laufzeit von $name wurde verlängert.';
  }

  @override
  String get shopPurchaseDoneConsumable =>
      'Kauf abgeschlossen.\nBitte im Inventar verwenden.';

  @override
  String get shopPurchaseDonePassive =>
      'Kauf abgeschlossen.\nWird sofort nach dem Kauf automatisch aktiviert.';

  @override
  String get shopPurchaseDoneEquip =>
      'Kauf abgeschlossen.\nMöchtest du es jetzt ausrüsten?';

  @override
  String get shopEquipNow => 'Ausrüsten';

  @override
  String get shopDetailCategoryBanner => 'Banner';

  @override
  String get shopDetailCategoryTitle => 'Titel';

  @override
  String get shopDetailCategoryThemeSkin => 'Design / Kartenskin';

  @override
  String get shopDetailCategoryUtility => 'Nützliches';

  @override
  String get shopDetailCategoryItem => 'Gegenstand';

  @override
  String get shopDetailNormalItem => 'Normaler Gegenstand';

  @override
  String get shopDetailPermanent => 'Dauerhaft';

  @override
  String shopDetailDuration(int days) {
    return '$days Tage Laufzeit';
  }

  @override
  String get shopEffectNicknameChange => 'Effekt: 1 Namensänderung';

  @override
  String shopEffectLeaveReduce(String value) {
    return 'Effekt: Verlassen -$value';
  }

  @override
  String get shopEffectStatsReset =>
      'Effekt: Alle Statistiken zurücksetzen (Siege/Niederlagen/Spiele)';

  @override
  String get shopEffectLeaveReset =>
      'Effekt: Verlassen-Zähler auf 0 zurücksetzen';

  @override
  String get shopEffectSeasonStatsReset =>
      'Effekt: ALLE Ranglistenstatistiken zurücksetzen (Tichu, Skull King, Mighty — Siege/Niederlagen/Spiele)';

  @override
  String get shopEffectTichuSeasonStatsReset =>
      'Effekt: Tichu-Ranglistenstatistiken zurücksetzen (Siege/Niederlagen/Spiele)';

  @override
  String get shopEffectSKSeasonStatsReset =>
      'Effekt: Skull-King-Ranglistenstatistiken zurücksetzen (Siege/Niederlagen/Spiele)';

  @override
  String get shopEffectMightySeasonStatsReset =>
      'Effekt: Mighty-Ranglistenstatistiken zurücksetzen (Siege/Niederlagen/Spiele)';

  @override
  String shopPriceGold(int price) {
    return '$price Gold';
  }

  @override
  String get shopNicknameChangeTitle => 'Nickname ändern';

  @override
  String get shopNicknameChangeDesc =>
      'Gib deinen neuen Nickname ein.\n(2–10 Zeichen, keine Leerzeichen)';

  @override
  String get shopNicknameChangeHint => 'Neuer Nickname';

  @override
  String get shopNicknameChangeValidation =>
      'Nickname muss 2–10 Zeichen lang sein';

  @override
  String get shopNicknameChangeButton => 'Ändern';

  @override
  String get shopAdCannotShow => 'Werbung kann nicht angezeigt werden';

  @override
  String shopAdWatchForGold(int current, int max) {
    return 'Werbung sehen und 50 Gold erhalten ($current/$max)';
  }

  @override
  String get shopAdRewardDone => 'Tägliche Werbebelohnungen abgeschlossen';

  @override
  String get appForceUpdateTitle => 'Update erforderlich';

  @override
  String get appForceUpdateBody =>
      'Eine neue Version wurde veröffentlicht.\nBitte aktualisiere, um die App weiter zu nutzen.';

  @override
  String get appForceUpdateButton => 'Aktualisieren';

  @override
  String get appEulaSubtitle => 'Nutzungsbedingungen';

  @override
  String get appEulaLoadFailed =>
      'Nutzungsbedingungen konnten nicht geladen werden. Bitte Netzwerkverbindung prüfen.';

  @override
  String get appEulaAgree => 'Ich stimme den Nutzungsbedingungen zu';

  @override
  String get appEulaStart => 'Los geht\'s';

  @override
  String get serviceRestoreRefreshingSocial => 'Social-Login wird überprüft...';

  @override
  String get serviceRestoreSocialLogin => 'Anmeldung mit Social-Konto...';

  @override
  String get serviceRestoreLocalLogin => 'Anmeldung mit gespeichertem Konto...';

  @override
  String get serviceRestoreRoomState =>
      'Rauminformationen werden wiederhergestellt...';

  @override
  String get serviceRestoreLoadingLobby => 'Lobby-Daten werden geladen...';

  @override
  String get serviceRestoreAutoLoginFailed =>
      'Automatische Anmeldung fehlgeschlagen.';

  @override
  String get serviceRestoreConnecting => 'Verbindung wird hergestellt...';

  @override
  String get serviceRestoreNeedsNickname =>
      'Ein Spitzname muss noch festgelegt werden.';

  @override
  String get serviceRestoreSocialFailed =>
      'Wiederherstellung der Social-Anmeldung fehlgeschlagen.';

  @override
  String get serviceRestoreSocialTokenExpired =>
      'Social-Login-Daten müssen erneut überprüft werden.';

  @override
  String get serviceRestoreLocalFailed =>
      'Anmeldung mit gespeichertem Konto fehlgeschlagen.';

  @override
  String get serviceRestoreAutoError =>
      'Fehler bei der automatischen Anmeldung.';

  @override
  String get serviceServerTimeout => 'Zeitüberschreitung der Serverantwort';

  @override
  String get serviceKicked => 'Du wurdest rausgeworfen';

  @override
  String get serviceRankingsLoadFailed =>
      'Rangliste konnte nicht geladen werden';

  @override
  String get serviceGoldHistoryLoadFailed =>
      'Gold-Verlauf konnte nicht geladen werden';

  @override
  String get serviceAdminUsersLoadFailed =>
      'Benutzerliste konnte nicht geladen werden';

  @override
  String get serviceAdminUserDetailLoadFailed =>
      'Benutzerdetails konnten nicht geladen werden';

  @override
  String get serviceAdminInquiriesLoadFailed =>
      'Anfragenliste konnte nicht geladen werden';

  @override
  String get serviceAdminReportsLoadFailed =>
      'Meldungsliste konnte nicht geladen werden';

  @override
  String get serviceAdminReportGroupLoadFailed =>
      'Meldungsdetails konnten nicht geladen werden';

  @override
  String get serviceAdminActionSuccess => 'Aktion abgeschlossen';

  @override
  String get serviceAdminActionFailed => 'Aktion fehlgeschlagen';

  @override
  String get serviceShopLoadFailed => 'Shop-Daten konnten nicht geladen werden';

  @override
  String get serviceInventoryLoadFailed =>
      'Inventar konnte nicht geladen werden';

  @override
  String get serviceInquiriesLoadFailed =>
      'Anfragenverlauf konnte nicht geladen werden';

  @override
  String get serviceNoticesLoadFailed =>
      'Mitteilungen konnten nicht geladen werden';

  @override
  String get serviceNicknameChanged => 'Nickname wurde geändert';

  @override
  String get serviceNicknameChangeFailed => 'Nickname-Änderung fehlgeschlagen';

  @override
  String get serviceRewardFailed => 'Belohnung konnte nicht vergeben werden';

  @override
  String get serviceRoomRestoreFallback =>
      'Rauminformationen konnten nicht wiederhergestellt werden. Zurück zur Lobby.';

  @override
  String get serviceInviteInGame =>
      'Während eines Spiels können keine Raumeinladungen gesendet werden';

  @override
  String get serviceInviteCooldown =>
      'Einladung bereits gesendet. Bitte versuche es gleich noch einmal';

  @override
  String get serviceAdShowFailed => 'Werbung kann nicht angezeigt werden';

  @override
  String get serviceAdLoadFailed => 'Werbung konnte nicht geladen werden';

  @override
  String serviceInquiryReply(String title) {
    return 'Antwort auf Anfrage erhalten: $title';
  }

  @override
  String get serviceInquiryDefault => 'Anfrage';

  @override
  String serviceChatBanned(String remaining) {
    return 'Chat eingeschränkt ($remaining verbleibend)';
  }

  @override
  String serviceChatBanHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String serviceChatBanMinutes(int minutes) {
    return '${minutes}min';
  }

  @override
  String serviceAdRewardSuccess(int remaining) {
    return '50 Gold erhalten! (Verbleibend: $remaining)';
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
  String get llRound => 'Runde';

  @override
  String get llPlay => 'Spielen';

  @override
  String get llConfirm => 'Bestätigen';

  @override
  String get llOk => 'OK';

  @override
  String get llRoundEnd => 'Runde beendet';

  @override
  String get llRoundWinner => 'Rundensieger';

  @override
  String get llRoundSharedWinners => 'Geteilte Sieger';

  @override
  String get llNextRoundAuto => 'Nächste Runde beginnt bald...';

  @override
  String get llGameEnd => 'Spiel beendet';

  @override
  String get llWins => 'Siege';

  @override
  String get llReturnIn => 'Zurück in';

  @override
  String get llGuardSelectTarget => 'Wache: Wähle ein Ziel und rate eine Karte';

  @override
  String get llGuardGuessCard => 'Rate, welche Karte der Spieler hat:';

  @override
  String get llSelectTargetFor => 'Wähle Ziel für:';

  @override
  String llGuardEffect(String name) {
    return '$name setzt die Wache ein...';
  }

  @override
  String llSpyEffect(String name) {
    return '$name setzt den Spion ein...';
  }

  @override
  String llBaronEffect(String name) {
    return '$name setzt den Baron ein...';
  }

  @override
  String llPrinceEffect(String name) {
    return '$name setzt den Prinzen ein...';
  }

  @override
  String llKingEffect(String name) {
    return '$name setzt den König ein...';
  }

  @override
  String llHandmaidEffect(String name) {
    return '$name hat die Zofe gespielt';
  }

  @override
  String llBlockedByHandmaid(String name, String card) {
    return '${name}s $card wurde durch die Zofe geblockt';
  }

  @override
  String llGuardCorrect(String actor, String target) {
    return '$actor hat die Karte von $target richtig erraten! Eliminiert!';
  }

  @override
  String llGuardWrong(String actor, String target) {
    return '$actor hat bei $target falsch geraten';
  }

  @override
  String llSpyReveal(String target) {
    return 'Karte von $target:';
  }

  @override
  String llSpySawYour(String actor) {
    return '$actor hat deine Karte gesehen';
  }

  @override
  String llSpyPeeked(String actor, String target) {
    return '$actor hat die Karte von $target angesehen';
  }

  @override
  String llBaronTie(String actor, String target) {
    return '$actor und $target spielten unentschieden';
  }

  @override
  String llBaronLose(String loser, String winner) {
    return '$loser wurde durch den Baron-Vergleich mit $winner eliminiert';
  }

  @override
  String llPrinceEliminated(String target) {
    return '$target musste die Prinzessin ablegen! Eliminiert!';
  }

  @override
  String llPrinceDiscard(String target) {
    return '$target hat abgelegt und eine neue Karte gezogen';
  }

  @override
  String llKingSwap(String actor, String target) {
    return '$actor und $target haben die Hände getauscht';
  }

  @override
  String get llEliminated => 'RAUS';

  @override
  String get llSetAsideFaceUp => 'Beiseitegelegt (offen)';

  @override
  String get llSetAsideHidden => 'Beiseitegelegt (verdeckt)';

  @override
  String get llPlayed => 'Gespielt:';

  @override
  String get llCardGuard => 'Wache';

  @override
  String get llCardSpy => 'Spion';

  @override
  String get llCardBaron => 'Baron';

  @override
  String get llCardHandmaid => 'Zofe';

  @override
  String get llCardPrince => 'Prinz';

  @override
  String get llCardKing => 'König';

  @override
  String get llCardCountess => 'Gräfin';

  @override
  String get llCardPrincess => 'Prinzessin';

  @override
  String get llCardGuideTitle => 'Kartenübersicht';

  @override
  String get llGuardPeek => 'Schauen';

  @override
  String llDiscardedCardsTitle(String playerName) {
    return 'Abgelegte Karten von $playerName';
  }

  @override
  String get llDescGuard =>
      '1 · Wache: Nenne einen Spieler und rate seine Karte. Richtig = eliminiert!';

  @override
  String get llDescSpy =>
      '2 · Spion: Sieh dir heimlich die Karte eines Spielers an.';

  @override
  String get llDescBaron =>
      '3 · Baron: Vergleiche Karten mit einem Spieler. Niedrigere Karte wird eliminiert!';

  @override
  String get llDescHandmaid =>
      '4 · Zofe: Bis zu deinem nächsten Zug vor allen Effekten geschützt.';

  @override
  String get llDescPrince =>
      '5 · Prinz: Zwinge einen Spieler, seine Karte abzuwerfen. Prinzessin = eliminiert!';

  @override
  String get llDescKing =>
      '6 · König: Tausche Karten mit einem anderen Spieler.';

  @override
  String get llDescCountess =>
      '7 · Gräfin: Muss gespielt werden, wenn du König oder Prinz hältst.';

  @override
  String get llDescPrincess =>
      '8 · Prinzessin: Wenn du diese Karte spielst, bist du eliminiert!';

  @override
  String get maintenanceTitle => 'Serverwartung';

  @override
  String maintenanceCountdown(String time) {
    return 'Verbleibend: $time';
  }

  @override
  String get maintenanceRetry => 'Erneut versuchen';

  @override
  String get maintenanceEnded => 'Wartung beendet, Neuverbindung...';

  @override
  String get goldHistoryShopPurchase => 'Shop-Kauf';

  @override
  String get goldHistoryIapPurchase => 'Gold-Aufladung';

  @override
  String get goldHistoryAttendance => 'Tägliche Anwesenheit';

  @override
  String attendanceBannerTitle(int day) {
    return 'Anwesenheit: Tag $day';
  }

  @override
  String attendanceBannerSubtitle(int reward) {
    final intl.NumberFormat rewardNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String rewardString = rewardNumberFormat.format(reward);

    return '+$rewardString Gold holen';
  }

  @override
  String attendanceBannerCompletedTitle(int day) {
    return 'Tag $day erledigt! 🎉';
  }

  @override
  String get attendanceBannerCompletedSubtitle =>
      'Komm morgen für die nächste Belohnung';

  @override
  String get attendanceDialogTitle => 'Tägliche Anwesenheit';

  @override
  String attendanceResetInfo(String clock) {
    return 'Täglicher Reset um $clock';
  }

  @override
  String get attendanceDoneToday => 'Heute eingecheckt! Komm morgen wieder 🎉';

  @override
  String get attendanceClaiming => 'Wird verarbeitet...';

  @override
  String attendanceWatchAdAndClaim(int reward) {
    final intl.NumberFormat rewardNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String rewardString = rewardNumberFormat.format(reward);

    return 'Werbung ansehen & $rewardString Gold erhalten';
  }

  @override
  String get attendanceAdNotReady =>
      'Werbung wird geladen. Bitte gleich nochmal versuchen.';

  @override
  String get attendanceAdLoading => 'Anzeige wird geladen…';

  @override
  String get goldHistoryIapRefund => 'Gold-Rückerstattung';

  @override
  String get goldHistoryLeaveDefeat => 'Aufgabe-Niederlage';

  @override
  String get goldHistoryRankedWin => 'Ranked-Sieg';

  @override
  String get goldHistoryCasualWin => 'Casual-Sieg';

  @override
  String get goldHistoryDraw => 'Unentschieden';

  @override
  String get goldHistoryRankedLoss => 'Ranked-Niederlage';

  @override
  String get goldHistoryCasualLoss => 'Casual-Niederlage';

  @override
  String get goldHistoryAdReward => 'Werbebelohnung';

  @override
  String get goldHistorySeasonReward => 'Saisonbelohnung';

  @override
  String get goldHistorySkLeaveDefeat => 'Skull King Aufgabe-Niederlage';

  @override
  String get goldHistorySkRankedWin => 'Skull King Ranked-Sieg';

  @override
  String get goldHistorySkCasualWin => 'Skull King Casual-Sieg';

  @override
  String get goldHistorySkRankedLoss => 'Skull King Ranked-Niederlage';

  @override
  String get goldHistorySkCasualLoss => 'Skull King Casual-Niederlage';

  @override
  String get goldHistoryAdminGrant => 'Admin-Zuweisung';

  @override
  String get goldHistoryAdminDeduct => 'Admin-Abzug';

  @override
  String goldHistoryFinalScore(String scoreA, String scoreB) {
    return 'Endstand $scoreA:$scoreB';
  }

  @override
  String goldHistorySeasonRank(String rank) {
    return 'Saisonrang: $rank';
  }

  @override
  String goldHistorySkRankScore(String rank, String score) {
    return 'Rang $rank ($score Pkt.)';
  }

  @override
  String goldHistoryAdminBy(String admin) {
    return 'Von Admin: $admin';
  }

  @override
  String get adminCenterTitle => 'Admin-Zentrum';

  @override
  String get adminTabInquiries => 'Anfragen';

  @override
  String get adminTabReports => 'Meldungen';

  @override
  String get adminTabUsers => 'Nutzer';

  @override
  String get adminActiveUsers => 'Aktiv';

  @override
  String get adminPendingInquiries => 'Offene Anfragen';

  @override
  String get adminPendingReports => 'Offene Meldungen';

  @override
  String get adminTotalUsers => 'Nutzer gesamt';

  @override
  String get adminTodayRevenue => 'Nettoumsatz heute (gesch.)';

  @override
  String get adminNewUsersToday => 'Neu heute';

  @override
  String get adminWeeklyActives => 'Aktive (Woche)';

  @override
  String get adminCasualGames => 'Casual-Spiele';

  @override
  String get adminRankedGames => 'Rangspiele';

  @override
  String get adminJoinedAt => 'Registriert';

  @override
  String get adminLastLogin => 'Letzte Anmeldung';

  @override
  String get adminNoUsers => 'Keine Nutzer anzuzeigen';

  @override
  String get adminSearchHint => 'Nach Nickname suchen';

  @override
  String get adminSearch => 'Suche';

  @override
  String get adminOnline => 'Online';

  @override
  String get adminOffline => 'Offline';

  @override
  String get adminUser => 'Nutzer';

  @override
  String get adminSubject => 'Betreff';

  @override
  String get adminNote => 'Notiz';

  @override
  String get adminResolved => 'Gelöst';

  @override
  String get adminReviewed => 'Überprüft';

  @override
  String get adminBasicInfo => 'Basisinformationen';

  @override
  String get adminUsername => 'Nickname';

  @override
  String get adminRating => 'Rating';

  @override
  String get adminGold => 'Gold';

  @override
  String get adminRecord => 'Bilanz';

  @override
  String get adminStatus => 'Status';

  @override
  String get adminCurrentRoom => 'Aktueller Raum';

  @override
  String get adminGoldAdjust => 'Gold anpassen';

  @override
  String get adminGoldAmount => 'Betrag';

  @override
  String get adminGoldHint => 'Positive Zahl eingeben';

  @override
  String get adminGoldValidation => 'Bitte eine gültige positive Zahl eingeben';

  @override
  String get adminGrant => 'Zuweisen';

  @override
  String get adminDeduct => 'Abziehen';

  @override
  String adminReportCount(int count) {
    return '$count Meldungen';
  }

  @override
  String adminReportRoom(String roomId) {
    return 'Raum: $roomId';
  }

  @override
  String adminInquiryTitle(int id) {
    return 'Anfrage #$id';
  }

  @override
  String adminReportTitle(String nickname) {
    return 'Meldung: $nickname';
  }

  @override
  String adminWinLoss(int wins, int losses) {
    return '${wins}S/${losses}N';
  }

  @override
  String get profileAllGames => 'Alle Spiele';

  @override
  String get profileBotSubtitle => 'Bot';

  @override
  String get profileBotHeadline => 'KI-Gegner';

  @override
  String get profileBotBody =>
      'Bots sind keine Konten – daher gibt es keine Statistiken, und Freundschaft, Blockieren und Melden gelten nicht.';

  @override
  String spectatorCardCount(int count) {
    return '$count Karten';
  }

  @override
  String spectatorTargetScore(int score) {
    return 'bis $score';
  }

  @override
  String get lobbyShareSheetTitle => 'Raum teilen';

  @override
  String get lobbyShareCopyLink => 'Link kopieren';

  @override
  String get lobbyShareKakao => 'Über KakaoTalk teilen';

  @override
  String get lobbyShareCopied => 'Link in die Zwischenablage kopiert';

  @override
  String get lobbySwitchToSpectator => 'Zuschauer werden';

  @override
  String get lobbySwitchToSpectatorDesc => 'Platz freigeben und nur zusehen';

  @override
  String get lobbyRoomTools => 'Raum-Werkzeuge';

  @override
  String get lobbyRoomPlaying => 'Läuft';

  @override
  String get lobbyNoRoomsForFilter =>
      'Keine Räume in diesem Spiel\nTippe auf „Alle“ für die anderen';

  @override
  String get lobbyAllowSpectators => 'Zuschauer erlauben';

  @override
  String get lobbyAllowSpectatorsDesc =>
      'Andere können diesen Raum ansehen. Aus = niemand kommt herein.';

  @override
  String get profilePhotoViewLarge => 'In voller Größe ansehen';

  @override
  String get profilePhotoDelete => 'Foto entfernen';

  @override
  String get profilePhotoDeleteConfirm =>
      'Profilfoto entfernen? Für den Rest deines Passes kannst du ein neues hochladen.';

  @override
  String get profilePhotoDeleted => 'Profilfoto entfernt';

  @override
  String get gameTapToClose => 'Zum Schließen tippen';

  @override
  String get profilePhotoUploadNotice =>
      'Hochgeladene Fotos werden automatisch geprüft und anderen Spielern gezeigt. Fotos anderer Personen und unangemessene Bilder werden nicht akzeptiert.';

  @override
  String get shopChargeGold => 'Gold kaufen';

  @override
  String get shopAdWatchTitle => 'Werbung für 50 Gold';

  @override
  String shopAdWatchProgress(int current, int max) {
    return 'Heute $current/$max';
  }

  @override
  String get shopAdRewardDoneSubtitle => 'Morgen wieder verfügbar';

  @override
  String get profilePrivateTitle => 'Dieses Profil ist privat';

  @override
  String get profilePrivateBadge => 'Privat';

  @override
  String get profilePrivateBody => 'Statistiken werden nur Freunden gezeigt';

  @override
  String get profilePrivateHidePhoto => 'Foto verbergen';

  @override
  String get profilePrivateHidePhotoDesc =>
      'Wenn aktiv, ist dein Profilbild auch im Warteraum und im Spiel für Nicht-Freunde verborgen';

  @override
  String get shopPreviewLabel => 'Vorschau';

  @override
  String get shopPreviewNickname => 'Nickname';

  @override
  String get shopButtonUnequip => 'Ablegen';

  @override
  String get customTitleEditTitle => 'Eigener Titel';

  @override
  String get customTitleHint => 'z. B. Ass (max. 4)';

  @override
  String get customTitleRule =>
      'Nur Buchstaben, Hangul und Ziffern, max. 4 Zeichen. Keine Emojis, Sonderzeichen oder Leerzeichen.';

  @override
  String get customTitleColorLabel => 'Farbe';

  @override
  String get customTitlePreviewLabel => 'Vorschau';

  @override
  String get customTitleSave => 'Übernehmen';

  @override
  String get customTitleButton => 'Titel schreiben';

  @override
  String get customTitleSaved => 'Titel übernommen';

  @override
  String get gameReportReasonTitle => 'Unangemessener Titel';

  @override
  String get gameReportDetailLabel => 'Details (optional)';

  @override
  String get shopFeatureInUse => 'Eingeschaltet';

  @override
  String get shopFeatureOff => 'Ausgeschaltet';

  @override
  String get shopPurchaseDonePassive2 =>
      'Kauf abgeschlossen.\nEs gilt sofort und läuft bis zum Ablauf. Du kannst es im Inventar aus- und einschalten.';

  @override
  String get shopCategoryProfile => 'Profil';

  @override
  String get shopCustomTitleSample => 'DeinTag';

  @override
  String get shopFeatureDisableTitle => 'Deaktivieren?';

  @override
  String get shopFeatureDisableBody =>
      'Die Laufzeit läuft weiter — das Ablaufdatum ändert sich nicht. Du kannst es jederzeit wieder aktivieren.';

  @override
  String get shopFeatureDisableConfirm => 'Deaktivieren';

  @override
  String get shopFeatureEnableTitle => 'Wieder aktivieren?';

  @override
  String get shopFeatureEnableBody =>
      'Gilt sofort und läuft bis zum Ablauf der Berechtigung.';

  @override
  String get shopFeatureEnableConfirm => 'Aktivieren';

  @override
  String get goldChargeTitle => 'Gold kaufen';

  @override
  String get goldPaymentProcessing => 'Zahlung wird verarbeitet ...';

  @override
  String get goldPaymentAlreadyProcessed =>
      'Diese Zahlung wurde bereits verarbeitet.';

  @override
  String get goldPaymentComplete => 'Zahlung abgeschlossen';

  @override
  String goldGranted(String amount) {
    return '+$amount Gold gutgeschrieben';
  }

  @override
  String goldBalanceNow(String amount) {
    return 'Guthaben: $amount';
  }

  @override
  String goldPaymentFailed(String message) {
    return 'Zahlung fehlgeschlagen: $message';
  }

  @override
  String get goldStoreLoadFailed =>
      'Die Produkte konnten nicht aus dem Store geladen werden.';

  @override
  String goldPurchaseStartFailed(String error) {
    return 'Der Kauf konnte nicht gestartet werden: $error';
  }

  @override
  String get goldIapUnavailable =>
      'In-App-Käufe sind auf diesem Gerät nicht verfügbar.';

  @override
  String get goldNoProducts => 'Zurzeit sind keine Gold-Pakete im Angebot.';

  @override
  String get goldUnit => 'Gold';

  @override
  String get goldBestValue => 'Top-Angebot';

  @override
  String goldBonusIncluded(String bonus) {
    return '+$bonus Bonus';
  }

  @override
  String get goldNoticeTitle => 'Vor dem Kauf';

  @override
  String get goldNoticeBody =>
      '• Gold ist kostenpflichtiger digitaler Inhalt und nur im Spiel verwendbar. Es kann nicht in Bargeld getauscht, bar erstattet oder übertragen werden.\n• Gold ist sofort nach dem Kauf nutzbar; bereits ausgegebenes Gold ist vom Widerruf (Erstattung) ausgenommen.';

  @override
  String get goldNoticeMore => 'Erstattungen und Zahlungssupport';

  @override
  String get goldNoticeDetails =>
      '• Erstattungen und Stornierungen richten sich nach den Richtlinien und Verfahren des Apple App Store / Google Play.\n• Minderjährige benötigen die Zustimmung ihrer Erziehungsberechtigten; Käufe ohne Zustimmung können storniert werden.\n• Fragen zur Zahlung: Einstellungen > Kontakt > „Zahlung & Erstattung“\n• Verkäuferinformationen und die vollständige Erstattungsrichtlinie stehen in den AGB und der Datenschutzerklärung in den Einstellungen.';

  @override
  String get goldBankSectionTitle => 'Per Banküberweisung kaufen';

  @override
  String get goldBankHowTo =>
      'Überweise auf das Konto unten und drücke dann bei deinem Paket auf [Zahlung bestätigen]. Gib den Namen des Einzahlers genau so ein, wie er auf der Überweisung steht.';

  @override
  String get goldBankLabelBank => 'Bank';

  @override
  String get goldBankLabelAccount => 'Kontonummer';

  @override
  String get goldBankLabelHolder => 'Kontoinhaber';

  @override
  String get goldBankCopy => 'Kopieren';

  @override
  String get goldBankCopied => 'Kontonummer kopiert';

  @override
  String get goldBankConfirm => 'Zahlung bestätigen';

  @override
  String get goldBankDialogTitle => 'Zahlungsbestätigung';

  @override
  String goldBankDialogAmount(Object price) {
    return 'Überweise zuerst $price, dann anfragen';
  }

  @override
  String get goldBankDepositorLabel => 'Name des Einzahlers';

  @override
  String get goldBankDepositorHint => 'Genau wie auf der Überweisung';

  @override
  String get goldBankSubmit => 'Anfrage senden';

  @override
  String get goldBankRequestSent =>
      'Deine Zahlungsmeldung wurde gesendet. Das Gold kommt, sobald ein Admin sie bestätigt.';

  @override
  String get goldBankRequestTimeout =>
      'Keine Antwort vom Server. Bitte versuche es gleich noch einmal.';

  @override
  String get goldBankUnavailable => 'Banküberweisung ist noch nicht verfügbar.';

  @override
  String get goldBankManualNotice =>
      'Banküberweisungen werden nicht automatisch verarbeitet. Ein Admin bestätigt die Zahlung, bevor das Gold gutgeschrieben wird — das kann dauern.';

  @override
  String get appForceUpdateBodyWeb =>
      'Eine neue Version ist da.\nLade die Seite neu, um weiterzuspielen.';

  @override
  String get appForceUpdateButtonWeb => 'Neu laden';

  @override
  String get loginGetTheApp => 'Auch als App verfügbar';

  @override
  String get goldHistoryBankDeposit => 'Überweisung bestätigt';

  @override
  String get goldBankContactChannel => 'Hilfe zur Zahlung (KakaoTalk)';

  @override
  String get midJoinButton => 'Mitspielen';

  @override
  String get midJoinConfirmTitle => 'In diese Partie einsteigen?';

  @override
  String get midJoinConfirmBody =>
      'Sie übernehmen zufällig einen der Bot-Plätze und spielen die laufende Hand sofort weiter. Was der Bot bereits angesagt oder gespielt hat, bleibt bestehen.';

  @override
  String get midJoinConfirmOk => 'Einsteigen';

  @override
  String get midLeaveButton => 'Aussteigen';

  @override
  String get midLeaveConfirmTitle => 'Aus dieser Partie aussteigen?';

  @override
  String midLeaveConfirmBody(int minutes) {
    return 'Ein Bot übernimmt Ihren Platz und die Partie läuft weiter. Dies wird als Spielabbruch gewertet, und Sie können $minutes Min. lang in keine laufende Partie einsteigen.';
  }

  @override
  String get midLeaveConfirmOk => 'Aussteigen';

  @override
  String get midJoinRoomBadge => 'Einstieg möglich';

  @override
  String get midJoinCreateOption => 'Einstieg in laufende Partie erlauben';

  @override
  String get midJoinCreateOptionHint =>
      'Zuschauer können einen Bot-Platz in einer laufenden Partie übernehmen. Wer eingestiegen ist, kann auch wieder aussteigen.';

  @override
  String midJoinNoticeJoined(String player) {
    return '$player ist eingestiegen';
  }

  @override
  String midJoinNoticeLeft(String player, String bot) {
    return '$player ist ausgestiegen — $bot übernimmt';
  }

  @override
  String get lobbyRoomRules => 'Raumregeln';

  @override
  String get lobbyAppliesImmediately => 'Wird sofort übernommen';

  @override
  String get lobbyRoomWaiting => 'Wartet';

  @override
  String get attendanceAppOnlyCta => 'In der App verfügbar';

  @override
  String get lobbyRandomAdjTichu =>
      'Fröhlich|Lebhaft|Feurig|Lodernd|Glücklich|Legendär|Höchst|Ungeschlagen|Gelassen|Erbittert|Elegant|Elektrisch|Heimlich|Strahlend|Tapfer|Still|Seltsam|Golden';

  @override
  String get lobbyRandomNounTichu =>
      'Tichu-Raum|Kartentisch|Showdown|Runde|Spiel|Duell|Herausforderung|Party|Treffen|Bühne|Platz|Finale|Fest|Kartenabend|Tisch|Liga';

  @override
  String get lobbyRandomAdjSk =>
      'Furchtbar|Legendär|Unbesiegbar|Erbarmungslos|Gierig|Höchst|Stürmisch|Verwegen|Neblig|Verflucht|Golden|Pechschwarz|Wogend|Waghalsig|Hungrig|Treibend';

  @override
  String get lobbyRandomNounSk =>
      'Piratenschiff|Schatzinsel|Seereise|Beutezug|Kapitän|Seeschlacht|Abenteuer|Krake|Wrack|Kompass|Leuchtturm|Gischt|Piratenflagge|Tiefsee|Hafen|Sturm';

  @override
  String get lobbyRandomAdjMighty =>
      'Beherzt|Entschlossen|Listig|Prächtig|Kühn|Einsam|Klug|Furchtlos|Lodernd|Kühl|Mitreißend|Heimlich|Stolz|Erfahren|Waghalsig|Standhaft';

  @override
  String get lobbyRandomNounMighty =>
      'Mighty-Raum|Giruda|Alleinspieler|Runde|Ansage|Duell|Showdown|Freund|Einsatz|Klassiker|Fest|Partie|Platz|Bühne|Finale|Tisch';

  @override
  String get lobbyRandomAdjLl =>
      'Heimlich|Süß|Schüchtern|Flatternd|Zärtlich|Elegant|Verborgen|Still|Beschwingt|Wehmütig|Reizend|Sachte|Fern|Behaglich|Niedlich|Funkelnd';

  @override
  String get lobbyRandomNounLl =>
      'Liebesbrief|Rendezvous|Geständnis|Briefkasten|Rose|Geheimnis|Flüstern|Teestube|Garten|Ball|Palast|Einladung|Umschlag|Versprechen|Spaziergang|Zettel';

  @override
  String get trickCardDragon => 'Drache';

  @override
  String get trickCardPhoenix => 'Phönix';

  @override
  String get trickCardMahjong => 'Mahjong';

  @override
  String get trickCardDog => 'Hund';

  @override
  String trickPhoenixOver(String beat) {
    return 'Phönix $beat';
  }

  @override
  String trickPair(String rank) {
    return '$rank-Paar';
  }

  @override
  String trickTriple(String rank) {
    return '$rank-Drilling';
  }

  @override
  String trickFullHouse(String rank) {
    return '$rank Full House';
  }

  @override
  String trickStraight(String rank, int count) {
    return '$rank-Straße ($count)';
  }

  @override
  String trickSteps(String rank, int count) {
    return '$rank-Treppe ($count)';
  }

  @override
  String get trickBombFour => 'Bombe (4)';

  @override
  String get trickBombStraightFlush => 'SF-Bombe';

  @override
  String trickCallSuffix(String rank) {
    return 'Ansage $rank';
  }

  @override
  String shopSaleWindow(String window) {
    return 'Verkauf $window';
  }

  @override
  String get couponSectionTitle => 'Gutschein';

  @override
  String get couponRedeemTitle => 'Gutschein einlösen';

  @override
  String get couponRedeemHint =>
      'Gib den Code genau so ein, wie er dasteht. Groß- und Kleinschreibung sowie Leerzeichen sind egal.';

  @override
  String get couponCodeLabel => 'Gutscheincode';

  @override
  String get couponRedeemButton => 'Einlösen';

  @override
  String couponRewardGold(int amount) {
    return '$amount Gold erhalten';
  }

  @override
  String get couponRewardItem => 'Gegenstand liegt in deinem Inventar';

  @override
  String couponRewardItemDays(int days) {
    return 'Gegenstand für $days Tage erhalten';
  }

  @override
  String get couponInNotice => 'Mit Gutschein';

  @override
  String get couponCopied => 'Code kopiert';

  @override
  String get marketingConsentTitle => 'Event-News erhalten?';

  @override
  String get marketingConsentBody =>
      'Wir schicken dir Pushes zu Angeboten, Events und Gutscheinen. Bei manchen gibt es Gold, wenn du sie antippst.';

  @override
  String get marketingConsentNote =>
      'Dies ist die Einwilligung in Werbenachrichten. Du kannst sie jederzeit unter Einstellungen > Benachrichtigungen abschalten; zwischen 21 und 8 Uhr senden wir nie. Spielhinweise wie Freundschaftsanfragen sind davon nicht betroffen.';

  @override
  String get marketingConsentAccept => 'Ja, gerne';

  @override
  String get marketingConsentDecline => 'Nein danke';

  @override
  String get settingsMarketingPush => 'Events und Angebote';

  @override
  String get settingsMarketingPushHint =>
      'Werbenachrichten. Nie zwischen 21 und 8 Uhr';

  @override
  String get settingsAttendancePush => 'Tägliche Erinnerung';

  @override
  String get settingsAttendancePushHint =>
      'Um 19 Uhr, falls die Tagesbelohnung noch offen ist';

  @override
  String get settingsAttendancePushBlocked =>
      'Aktiviere Events und Angebote, um sie zu erhalten';

  @override
  String get pushRewardTitle => 'Belohnung erhalten!';

  @override
  String pushRewardGold(int gold) {
    return '$gold Gold wurden gutgeschrieben';
  }

  @override
  String get pushRewardItem => 'Der Gegenstand wurde hinzugefügt';

  @override
  String get settingsMarketingPushBlocked =>
      'Benachrichtigungen sind aus, es wird nichts gesendet. Oben wieder einschalten';

  @override
  String get marketingSenderName => 'Tichu Online';

  @override
  String get marketingConfirmTitle => 'Event-News weiter erhalten?';

  @override
  String get marketingConfirmBody =>
      'Deine Einwilligung in Werbenachrichten ist zwei Jahre alt. Wir sind verpflichtet, noch einmal nachzufragen.';

  @override
  String get marketingConfirmSenderLabel => 'Absender';

  @override
  String get marketingConfirmDateLabel => 'Eingewilligt';

  @override
  String get marketingConfirmStatusLabel => 'Status';

  @override
  String get marketingConfirmStatusValue => 'Angemeldet';

  @override
  String get marketingConfirmKeep => 'Weiter erhalten';

  @override
  String get marketingConfirmStop => 'Nicht mehr senden';

  @override
  String get lobbyFilterAll => 'Alle';

  @override
  String get friendsLastSeenJustNow => 'Gerade eben online';

  @override
  String friendsLastSeenMinutes(int n) {
    return 'Vor $n Min. online';
  }

  @override
  String friendsLastSeenHours(int n) {
    return 'Vor $n Std. online';
  }

  @override
  String friendsLastSeenDays(int n) {
    return 'Vor $n T. online';
  }

  @override
  String get friendsLastSeenLongAgo => 'Vor über einem Monat online';

  @override
  String get chatToday => 'Heute';

  @override
  String get chatYesterday => 'Gestern';

  @override
  String chatDate(int y, int m, int d) {
    return '$d.$m.$y';
  }

  @override
  String get shopSheetCreateTitle => 'Titel erstellen';

  @override
  String get shopSheetRegisterPhoto => 'Foto festlegen';

  @override
  String get shopSheetEquipped => 'Ausgerüstet';

  @override
  String get mailboxTitle => 'Postfach';

  @override
  String get mailboxEmpty => 'Noch keine Post';

  @override
  String get mailboxEmptyHint => 'Briefe vom Team erscheinen hier.';

  @override
  String get mailboxUnreadBadge => 'Neu';

  @override
  String mailboxRewardGold(String amount) {
    return '$amount Gold';
  }

  @override
  String mailboxRewardItem(String item) {
    return '$item';
  }

  @override
  String mailboxRewardDays(int days) {
    return '$days Tage';
  }

  @override
  String get mailboxClaim => 'Abholen';

  @override
  String get mailboxClaimed => 'Abgeholt';

  @override
  String get mailboxExpired => 'Beendet';

  @override
  String mailboxExpiresAt(String date) {
    return 'Abholen bis $date';
  }

  @override
  String get mailboxClaimedToast => 'Belohnung abgeholt';

  @override
  String get mailboxFrom => 'Tichu Online Team';

  @override
  String get mailboxLoadFailed => 'Postfach konnte nicht geladen werden';

  @override
  String mailboxRetention(int days) {
    return 'Briefe werden $days Tage nach Erhalt automatisch gelöscht.';
  }

  @override
  String get mailboxDelete => 'Löschen';

  @override
  String get mailboxDeleteConfirm => 'Diesen Brief löschen?';

  @override
  String get mailboxDeleteConfirmBody =>
      'Er verschwindet aus deinem Postfach. Das lässt sich nicht rückgängig machen.';

  @override
  String get mailboxDeleted => 'Brief gelöscht';

  @override
  String get mailboxCancel => 'Abbrechen';

  @override
  String get goldHistoryMailClaim => 'Postfach-Belohnung';

  @override
  String get goldHistoryMailClaimed => 'Abgeholt';

  @override
  String get lobbyTakeSeat => 'Platz nehmen';

  @override
  String get lobbySpectatorLabel => 'Zuschauer';

  @override
  String lobbySpectatorMore(int count) {
    return '+$count weitere';
  }
}

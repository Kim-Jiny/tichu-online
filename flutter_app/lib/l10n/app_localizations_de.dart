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
  String get lobbySkullKingBadge => '☠️ Skull King';

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
  String lobbySkullKingPlayers(int count) {
    return 'Skull King · ${count}P';
  }

  @override
  String get lobbyStartGame => 'Spiel starten';

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
  String get lobbyRandomAdjTichu1 => 'Fröhlich';

  @override
  String get lobbyRandomAdjTichu2 => 'Spannend';

  @override
  String get lobbyRandomAdjTichu3 => 'Leidenschaftlich';

  @override
  String get lobbyRandomAdjTichu4 => 'Feurig';

  @override
  String get lobbyRandomAdjTichu5 => 'Glücklich';

  @override
  String get lobbyRandomAdjTichu6 => 'Legendär';

  @override
  String get lobbyRandomAdjTichu7 => 'Unschlagbar';

  @override
  String get lobbyRandomAdjTichu8 => 'Unbesiegbar';

  @override
  String get lobbyRandomNounTichu1 => 'Tichu-Raum';

  @override
  String get lobbyRandomNounTichu2 => 'Kartenspiel';

  @override
  String get lobbyRandomNounTichu3 => 'Duell';

  @override
  String get lobbyRandomNounTichu4 => 'Runde';

  @override
  String get lobbyRandomNounTichu5 => 'Spiel';

  @override
  String get lobbyRandomNounTichu6 => 'Kampf';

  @override
  String get lobbyRandomNounTichu7 => 'Herausforderung';

  @override
  String get lobbyRandomNounTichu8 => 'Party';

  @override
  String get lobbyRandomAdjSk1 => 'Furchteinflößend';

  @override
  String get lobbyRandomAdjSk2 => 'Legendär';

  @override
  String get lobbyRandomAdjSk3 => 'Unbesiegbar';

  @override
  String get lobbyRandomAdjSk4 => 'Gnadenlos';

  @override
  String get lobbyRandomAdjSk5 => 'Gierig';

  @override
  String get lobbyRandomAdjSk6 => 'Unschlagbar';

  @override
  String get lobbyRandomAdjSk7 => 'Stürmisch';

  @override
  String get lobbyRandomAdjSk8 => 'Kühn';

  @override
  String get lobbyRandomNounSk1 => 'Piratenschiff';

  @override
  String get lobbyRandomNounSk2 => 'Schatzinsel';

  @override
  String get lobbyRandomNounSk3 => 'Reise';

  @override
  String get lobbyRandomNounSk4 => 'Plünderung';

  @override
  String get lobbyRandomNounSk5 => 'Kapitän';

  @override
  String get lobbyRandomNounSk6 => 'Seeschlacht';

  @override
  String get lobbyRandomNounSk7 => 'Abenteuer';

  @override
  String get lobbyRandomNounSk8 => 'Kraken';

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
  String get skGameBonusHeader => 'Bonus';

  @override
  String get skGameScoreHeader => 'Punkte';

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
  String get gameAlreadyFriend => 'Bereits befreundet';

  @override
  String get gameRequestPending => 'Anfrage ausstehend';

  @override
  String get gameAddFriend => 'Freund hinzufügen';

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
      'Kartenzusammensetzung (67 Basiskarten)';

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
  String get rulesSkSpecialTigressTitle => 'Tigress — standardmäßig 3 Karten';

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
      'Am Ende der Runde gewinnt der überlebende Spieler mit der höchsten Karte (bei Gleichstand entscheidet die Gesamtkartensumme) ein Token.\n\nBenötigte Token zum Sieg:\n• 2 Spieler: 4 Token\n• 3 Spieler: 3 Token\n• 4 Spieler: 2 Token';

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
      '20 Punktkarten im Deck (A, K, Q, J, 10 × 4 Farben = 20).\n\n[Grundpunktzahl]\nBasis = (Gebot − minBid + 1) × 2\n• Bei Erfolg: + (gesammelte Punkte − Gebot)\n• Bei Misserfolg: + (Gebot − gesammelte Punkte)   ← größere Fehlschläge kosten mehr\n\n[Punkteverteilung]\n• Alleinspieler: Basis × 2\n• Freund: Basis × 1\n• Jeder Verteidiger: −Basis\nBei Misserfolg werden die Vorzeichen umgekehrt.\n\n[Multiplikatoren (auf Basis, stapelbar)]\n• Solo (kein Freund): ×2\n• Run (alle 20 Pkt): ×2\n• Ohne Trumpf (NT): ×2\n• Gebot 20: ×2\nMax. Multiplikator: ×16 (Solo + Run + NT + Gebot 20)\n\n[Erfolgs-Beispiel]\nGebot 13, 15 Pkt gesammelt, mit Freund:\nBasis = (1×2) + 2 = 4\nAlleinspieler +8, Freund +4, Verteidiger je −4\n\n[Misserfolgs-Beispiel]\nGebot 14, nur 5 Pkt (9 Pkt unter Gebot):\nBasis = (2×2) + 9 = 13\nAlleinspieler −26, Freund −13, Verteidiger je +13';

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
    return 'R$round $phase';
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
  String get mtPass => 'Passen';

  @override
  String get mtDealMiss => 'Deal-Miss';

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
  String get mtJokerLoses1st => 'Joker verliert im 1. Stich!';

  @override
  String get mtJokerLosesLast => 'Joker verliert im letzten Stich!';

  @override
  String get mtJokerSuit => 'Joker-Farbe: ';

  @override
  String get mtJokerCall => 'Joker-Ruf: ';

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
    return '$gold Gold';
  }

  @override
  String get shopHowToEarn => 'So verdienst du';

  @override
  String shopDesertionCount(int count) {
    return 'Verlassen $count';
  }

  @override
  String get shopGoldHistory => 'Gold-Verlauf';

  @override
  String shopGoldCurrent(int gold) {
    return 'Aktuelles Gold: $gold';
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
  String llBaronLose(String loser) {
    return '$loser wurde durch den Baron-Vergleich eliminiert';
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
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class L10nKo extends L10n {
  L10nKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Tichu Online';

  @override
  String get languageAuto => '자동 (시스템 언어)';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsAppInfo => '앱 정보';

  @override
  String get settingsAppVersion => '앱 버전';

  @override
  String get settingsNotLatestVersion => '최신 버전이 아닙니다';

  @override
  String get settingsUpdate => '업데이트';

  @override
  String get settingsLogout => '로그아웃';

  @override
  String get settingsDeleteAccount => '회원탈퇴';

  @override
  String get settingsDeleteAccountConfirm => '정말 탈퇴하시겠습니까?\n모든 데이터가 삭제됩니다.';

  @override
  String get settingsNickname => '닉네임';

  @override
  String get settingsSocialLink => '소셜 연동';

  @override
  String get settingsTermsOfService => '이용약관';

  @override
  String get settingsPrivacyPolicy => '개인정보처리방침';

  @override
  String get settingsNotices => '공지사항';

  @override
  String get settingsMyProfile => '내 프로필';

  @override
  String get settingsTheme => '테마';

  @override
  String get settingsSound => '사운드';

  @override
  String get settingsAdminCenter => '관리자 센터';

  @override
  String get commonOk => '확인';

  @override
  String get commonCancel => '취소';

  @override
  String get commonSave => '저장';

  @override
  String get commonClose => '닫기';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonConfirm => '확인';

  @override
  String get commonLink => '연동';

  @override
  String get commonError => '오류';

  @override
  String get settingsHeaderTitle => '설정';

  @override
  String get settingsNotificationsSection => '알림';

  @override
  String get settingsPushNotifications => '푸시 알림';

  @override
  String get settingsPushNotificationsDesc => '전체 알림을 켜고 끕니다';

  @override
  String get settingsInquiryNotifications => '문의 알림';

  @override
  String get settingsInquiryNotificationsDesc => '새 문의가 들어오면 푸시를 받습니다';

  @override
  String get settingsReportNotifications => '신고 알림';

  @override
  String get settingsReportNotificationsDesc => '새 신고가 들어오면 푸시를 받습니다';

  @override
  String get settingsAdminSection => '관리자';

  @override
  String get settingsAdminCenterDesc => '문의, 신고, 유저, 활성 유저를 확인합니다';

  @override
  String get settingsAccountSection => '계정';

  @override
  String get settingsProfileSubtitle => '레벨, 전적, 최근 매치 보기';

  @override
  String settingsSocialLinked(String provider) {
    return '$provider 연동됨';
  }

  @override
  String get settingsNoLinkedAccount => '연동된 계정 없음 (랭크전 이용 불가)';

  @override
  String get settingsInquirySection => '문의';

  @override
  String get settingsSubmitInquiry => '문의하기';

  @override
  String get settingsInquiryHistory => '문의 내역';

  @override
  String get settingsAccountManagement => '계정 관리';

  @override
  String get settingsDeleteAccountWithdraw => '탈퇴';

  @override
  String get settingsLinkComplete => '연동이 완료되었습니다';

  @override
  String settingsLinkFailed(String error) {
    return '연동 실패: $error';
  }

  @override
  String get noticeTitle => '공지사항';

  @override
  String get noticeEmpty => '등록된 공지사항이 없습니다';

  @override
  String get noticeRetry => '다시 시도';

  @override
  String get noticeCategoryRelease => '릴리즈';

  @override
  String get noticeCategoryUpdate => '업데이트';

  @override
  String get noticeCategoryPreview => '업데이트 예고';

  @override
  String get noticeCategoryGeneral => '공지';

  @override
  String get inquiryTitle => '문의하기';

  @override
  String get inquiryCategory => '카테고리';

  @override
  String get inquiryCategoryBug => '버그 신고';

  @override
  String get inquiryCategorySuggestion => '건의사항';

  @override
  String get inquiryCategoryOther => '기타';

  @override
  String get inquiryFieldTitle => '제목';

  @override
  String get inquiryFieldTitleHint => '제목을 입력해주세요';

  @override
  String get inquiryFieldContent => '내용';

  @override
  String get inquiryFieldContentHint => '내용을 입력해주세요';

  @override
  String get inquirySubmit => '제출';

  @override
  String get inquirySubmitted => '문의가 접수되었습니다';

  @override
  String get inquiryHistoryTitle => '문의 내역';

  @override
  String get inquiryEmpty => '등록된 문의가 없습니다';

  @override
  String get inquiryStatusResolved => '답변완료';

  @override
  String get inquiryStatusPending => '대기 중';

  @override
  String get inquiryAnswerLabel => '답변';

  @override
  String inquiryAnswerDate(String date) {
    return '답변일: $date';
  }

  @override
  String get inquiryNoAnswer => '아직 답변이 등록되지 않았습니다.';

  @override
  String get linkDialogTitle => '소셜 계정 연동';

  @override
  String get linkDialogContent => '연동할 소셜 계정을 선택하세요';

  @override
  String get textViewLoadFailed => '내용을 불러올 수 없습니다.';

  @override
  String get loginEnterUsername => '아이디를 입력하세요';

  @override
  String get loginEnterPassword => '비밀번호를 입력하세요';

  @override
  String get loginFailed => '로그인 실패';

  @override
  String loginSocialFailed(String error) {
    return '소셜 로그인 실패: $error';
  }

  @override
  String get loginSocialFailedGeneric => '소셜 로그인 실패';

  @override
  String get loginSubtitle => '팀 카드게임';

  @override
  String get loginTagline => '빠르게 다시 접속하고,\n불필요한 화면 왕복 없이 바로 게임으로 돌아가세요.';

  @override
  String get loginUsernameHint => '아이디';

  @override
  String get loginPasswordHint => '비밀번호';

  @override
  String get loginButton => '로그인';

  @override
  String get loginRegisterButton => '회원가입';

  @override
  String get loginQuickLogin => '간편 로그인';

  @override
  String get loginAutoLoginFailed => '자동 로그인에 실패했습니다';

  @override
  String get loginCheckSavedInfo => '저장된 로그인 정보를 다시 확인해주세요.';

  @override
  String get loginRetry => '다시 시도';

  @override
  String get loginManual => '직접 로그인';

  @override
  String get loginAutoLoggingIn => '자동 로그인 중...';

  @override
  String get loginLoggingIn => '로그인 중...';

  @override
  String get loginVerifyingAccount => '계정 정보를 확인하고 있습니다.';

  @override
  String get loginRegistrationComplete => '회원가입이 완료되었습니다. 로그인해주세요.';

  @override
  String get loginNicknameEmpty => '닉네임을 입력해주세요';

  @override
  String get loginNicknameLength => '닉네임은 2~10자여야 합니다';

  @override
  String get loginNicknameNoSpaces => '닉네임에 공백을 사용할 수 없습니다';

  @override
  String get loginServerUnavailable => '서버에 연결할 수 없습니다.';

  @override
  String get loginServerNoResponse => '서버 응답이 없습니다. 다시 시도해주세요.';

  @override
  String get loginUsernameMinLength => '아이디는 2글자 이상이어야 합니다';

  @override
  String get loginUsernameNoSpaces => '아이디에 공백을 사용할 수 없습니다';

  @override
  String get loginPasswordMinLength => '비밀번호는 4글자 이상이어야 합니다';

  @override
  String get loginPasswordMismatch => '비밀번호가 일치하지 않습니다';

  @override
  String get loginNicknameCheckRequired => '닉네임 중복 확인을 해주세요';

  @override
  String get loginServerTimeout => '서버 응답 시간 초과';

  @override
  String get loginRegisterTitle => '회원가입';

  @override
  String get loginUsernameLabel => '아이디';

  @override
  String get loginUsernameHintRegister => '2글자 이상, 공백 불가';

  @override
  String get loginPasswordLabel => '비밀번호';

  @override
  String get loginPasswordHintRegister => '4글자 이상';

  @override
  String get loginConfirmPasswordLabel => '비밀번호 확인';

  @override
  String get loginConfirmPasswordHint => '비밀번호를 다시 입력';

  @override
  String get loginSubmitRegister => '가입하기';

  @override
  String get loginNicknameLabel => '닉네임';

  @override
  String get loginNicknameHint => '2~10자, 공백 불가';

  @override
  String get loginCheckAvailability => '중복 확인';

  @override
  String get loginSetNicknameTitle => '닉네임 설정';

  @override
  String get loginSetNicknameDesc => '게임에서 사용할 닉네임을 설정해주세요';

  @override
  String get loginGetStarted => '시작하기';

  @override
  String get lobbyRoomInviteTitle => '방 초대';

  @override
  String lobbyRoomInviteMessage(String nickname) {
    return '$nickname님이 방에 초대했습니다!';
  }

  @override
  String get lobbyDecline => '거절';

  @override
  String get lobbyJoin => '참여';

  @override
  String get lobbyInviteFriendsTitle => '친구 초대';

  @override
  String get lobbyNoOnlineFriends => '초대 가능한 온라인 친구가 없습니다';

  @override
  String lobbyInviteSent(String nickname) {
    return '$nickname님에게 초대를 보냈습니다';
  }

  @override
  String get lobbyInvite => '초대';

  @override
  String get lobbySpectatorListTitle => '관전자 목록';

  @override
  String get lobbyNoSpectators => '관전 중인 사람이 없습니다';

  @override
  String get lobbyRoomSettingsTitle => '방 설정';

  @override
  String get lobbyEnterRoomTitle => '방 제목을 입력하세요';

  @override
  String get lobbyChange => '변경';

  @override
  String get lobbyCreateRoom => '새 방 만들기';

  @override
  String get lobbyCreateRoomSubtitle => '방 제목과 규칙을 정하면 바로 대기실이 열립니다.';

  @override
  String get lobbySelectGame => '게임 선택';

  @override
  String get lobbySelectGameDesc => '플레이할 게임을 선택합니다.';

  @override
  String get lobbyTichu => '티츄';

  @override
  String get lobbySkullKing => '스컬킹';

  @override
  String get lobbyMaxPlayers => '최대 인원';

  @override
  String lobbyPlayerCount(int count) {
    return '$count명';
  }

  @override
  String get lobbyExpansionOptional => '확장팩 (선택)';

  @override
  String get lobbyExpansionDesc => '기본 룰 카드에 특수 카드를 추가합니다. 중복 선택 가능.';

  @override
  String get lobbyExpKraken => '크라켄';

  @override
  String get lobbyExpKrakenDesc => '트릭 무효화';

  @override
  String get lobbyExpWhiteWhale => '화이트웨일';

  @override
  String get lobbyExpWhiteWhaleDesc => '특수카드 무력화';

  @override
  String get lobbyExpLoot => '보물';

  @override
  String get lobbyExpLootDesc => '보너스 점수';

  @override
  String get lobbyBasicInfo => '기본 정보';

  @override
  String get lobbyBasicInfoDesc => '먼저 방 이름과 공개 여부를 정합니다.';

  @override
  String get lobbyRoomName => '방 이름';

  @override
  String get lobbyRandom => '랜덤';

  @override
  String get lobbyPrivateRoom => '비공개 방';

  @override
  String get lobbyPrivateRoomDescRanked => '랭크전에서는 비공개 방을 만들 수 없습니다.';

  @override
  String get lobbyPrivateRoomDesc => '초대한 사람이나 비밀번호를 아는 사람만 들어올 수 있습니다.';

  @override
  String get lobbyPasswordHint => '비밀번호 (4자 이상)';

  @override
  String get lobbyRanked => '랭크전';

  @override
  String get lobbyRankedDesc => '점수는 1000점 고정이며 비공개 설정은 자동으로 꺼집니다.';

  @override
  String get lobbyGameSettings => '게임 설정';

  @override
  String get lobbyGameSettingsDescSk => '턴 시간을 정합니다.';

  @override
  String get lobbyGameSettingsDescTichu => '턴 시간과 목표 점수를 정합니다.';

  @override
  String get lobbyTimeLimit => '시간 제한';

  @override
  String get lobbySuffixSeconds => '초';

  @override
  String get lobbyTargetScore => '목표 점수';

  @override
  String get lobbySuffixPoints => '점';

  @override
  String get lobbyTimeLimitRange => '10~999';

  @override
  String get lobbyTargetScoreRange => '100~20000';

  @override
  String get lobbyTargetScoreFixed => '1000 (고정)';

  @override
  String get lobbyRankedFixedScoreInfo => '랭크전은 목표 점수 1000점으로 고정됩니다.';

  @override
  String get lobbyNormalSettingsInfo =>
      '시간 제한은 10~999초, 목표 점수는 100~20000점까지 설정할 수 있습니다.';

  @override
  String get lobbyEnterRoomName => '방 이름을 입력해주세요.';

  @override
  String get lobbyPasswordTooShort => '비밀번호는 4자 이상이어야 합니다.';

  @override
  String get lobbyDuplicateLoginKicked => '다른 기기에서 로그인되어 로그아웃되었습니다';

  @override
  String get lobbyRoomListTitle => '게임 방 리스트';

  @override
  String get lobbyEmptyRoomList => '방이 없어요!\n지금 바로 만들어볼까요?';

  @override
  String get lobbySkullKingBadge => '☠️ 스컬킹';

  @override
  String get lobbyTichuBadge => '티츄';

  @override
  String lobbyRoomTimeSec(int seconds) {
    return '$seconds초';
  }

  @override
  String lobbyRoomTimeAndScore(int seconds, int score) {
    return '$seconds초 · $score점';
  }

  @override
  String get lobbyExpKrakenShort => '크라켄';

  @override
  String get lobbyExpWhaleShort => '웨일';

  @override
  String get lobbyExpLootShort => '보물';

  @override
  String lobbyInProgress(int count) {
    return '관전 $count';
  }

  @override
  String get lobbySocialLinkRequired => '소셜 연동 필요';

  @override
  String get lobbySocialLinkRequiredDesc =>
      '랭크전은 소셜 계정 연동이 필요합니다.\n설정 > 소셜 연동에서 Google 또는 Kakao 계정을 연동해주세요.';

  @override
  String get lobbyJoinPrivateRoom => '비공개 방 입장';

  @override
  String get lobbyEnter => '입장';

  @override
  String get lobbySpectatePrivateRoom => '비공개 방 관전';

  @override
  String get lobbySpectate => '관전';

  @override
  String get lobbyPassword => '비밀번호';

  @override
  String get lobbyMessageHint => '메시지 입력...';

  @override
  String get lobbyChat => '채팅';

  @override
  String get lobbyViewProfile => '프로필 보기';

  @override
  String get lobbyAddFriend => '친구 추가';

  @override
  String get lobbyUnblock => '차단 해제';

  @override
  String get lobbyBlock => '차단하기';

  @override
  String get lobbyUnblocked => '차단이 해제되었습니다';

  @override
  String get lobbyBlocked => '차단되었습니다';

  @override
  String get lobbyFriendRequestSent => '친구 요청을 보냈습니다';

  @override
  String get lobbyReport => '신고하기';

  @override
  String get lobbyWaitingRoomTools => '대기실 도구';

  @override
  String get lobbyWaitingRoomToolsDesc => '게임 준비와 직접 관련 없는 기능은 여기에서 확인할 수 있어요.';

  @override
  String get lobbyFriendsDm => '친구 / DM';

  @override
  String lobbyUnreadDmCount(int count) {
    return '읽지 않은 요청과 DM이 $count개 있어요.';
  }

  @override
  String get lobbyFriendsDmDesc => '친구 목록과 DM 대화를 확인할 수 있어요.';

  @override
  String lobbyCurrentSpectators(int count) {
    return '현재 관전자 $count명을 확인할 수 있어요.';
  }

  @override
  String get lobbyMore => '더보기';

  @override
  String get lobbyRoomSettings => '방 설정';

  @override
  String get lobbySkullKingRanked => '스컬킹 - 랭크전';

  @override
  String get lobbyTichuRanked => '티츄 - 랭크전';

  @override
  String lobbySkullKingPlayers(int count) {
    return '스컬킹 · $count인';
  }

  @override
  String get lobbyStartGame => '게임 시작';

  @override
  String get lobbyReady => '준비';

  @override
  String get lobbyReadyDone => '준비 완료!';

  @override
  String lobbyReportTitle(String nickname) {
    return '$nickname 신고';
  }

  @override
  String get lobbyReportWarning => '신고는 운영팀이 확인합니다.\n허위 신고는 제재될 수 있어요.';

  @override
  String get lobbySelectReason => '사유 선택';

  @override
  String get lobbyReportDetailHint => '상세 사유를 입력해주세요 (선택)';

  @override
  String get lobbyReportReasonAbuse => '욕설/비방';

  @override
  String get lobbyReportReasonSpam => '도배/스팸';

  @override
  String get lobbyReportReasonNickname => '부적절한 닉네임';

  @override
  String get lobbyReportReasonGameplay => '게임 방해';

  @override
  String get lobbyReportReasonOther => '기타';

  @override
  String get lobbyProfileNotFound => '프로필을 찾을 수 없습니다';

  @override
  String get lobbyMyProfile => '내 프로필';

  @override
  String get lobbyPlayerProfile => '플레이어 프로필';

  @override
  String get lobbyAlreadyFriend => '이미 친구';

  @override
  String get lobbyRequestPending => '요청 중';

  @override
  String get lobbyTichuSeasonRanked => '티츄 시즌 랭킹전';

  @override
  String get lobbySkullKingSeasonRanked => '스컬킹 시즌 랭킹전';

  @override
  String get lobbyTichuRecord => '티츄 전적';

  @override
  String get lobbySkullKingRecord => '스컬킹 전적';

  @override
  String get lobbyStatRecord => '전적';

  @override
  String get lobbyStatWinRate => '승률';

  @override
  String lobbyRecordFormat(int games, int wins, int losses) {
    return '$games전 $wins승 $losses패';
  }

  @override
  String lobbyRecentMatches(int count) {
    return '최근 전적 ($count)';
  }

  @override
  String get lobbyRecentMatchesTitle => '최근 전적';

  @override
  String lobbyRecentMatchesDesc(int count) {
    return '최근 $count경기 결과를 확인할 수 있습니다.';
  }

  @override
  String get lobbySeeMore => '더보기';

  @override
  String get lobbyNoRecentMatches => '최근 전적이 없습니다';

  @override
  String get lobbyMatchDesertion => '탈';

  @override
  String get lobbyMatchDraw => '무';

  @override
  String get lobbyMatchWin => '승';

  @override
  String get lobbyMatchLoss => '패';

  @override
  String get lobbyMatchTypeSkullKing => '스컬킹';

  @override
  String get lobbyMatchTypeRanked => '랭크';

  @override
  String get lobbyMatchTypeNormal => '일반';

  @override
  String lobbyRankAndScore(String rank, int score) {
    return '$rank위 ($score점)';
  }

  @override
  String get lobbyMannerGood => '좋음';

  @override
  String get lobbyMannerNormal => '보통';

  @override
  String get lobbyMannerBad => '나쁨';

  @override
  String get lobbyMannerVeryBad => '아주 나쁨';

  @override
  String get lobbyMannerWorst => '최악';

  @override
  String lobbyManner(String label) {
    return '매너 $label';
  }

  @override
  String lobbyDesertions(int count) {
    return '탈주 $count';
  }

  @override
  String get lobbyKick => '강퇴';

  @override
  String lobbyKickConfirm(String playerName) {
    return '$playerName 님을 강퇴하시겠습니까?';
  }

  @override
  String get lobbyHost => '방장';

  @override
  String get lobbyBot => '봇';

  @override
  String get lobbyEmptySlot => '[빈 자리]';

  @override
  String get lobbyMaintenanceDefault => '서버 점검 예정';

  @override
  String lobbyRoomInfoSk(int seconds, int players, int maxPlayers) {
    return '$seconds초 · $players/$maxPlayers명';
  }

  @override
  String lobbyRoomInfoTichu(int seconds, int score) {
    return '$seconds초 · $score점';
  }

  @override
  String get lobbyRandomAdjTichu1 => '즐거운';

  @override
  String get lobbyRandomAdjTichu2 => '신나는';

  @override
  String get lobbyRandomAdjTichu3 => '열정의';

  @override
  String get lobbyRandomAdjTichu4 => '화끈한';

  @override
  String get lobbyRandomAdjTichu5 => '행운의';

  @override
  String get lobbyRandomAdjTichu6 => '전설의';

  @override
  String get lobbyRandomAdjTichu7 => '최강';

  @override
  String get lobbyRandomAdjTichu8 => '무적';

  @override
  String get lobbyRandomNounTichu1 => '티츄방';

  @override
  String get lobbyRandomNounTichu2 => '카드판';

  @override
  String get lobbyRandomNounTichu3 => '승부';

  @override
  String get lobbyRandomNounTichu4 => '한판';

  @override
  String get lobbyRandomNounTichu5 => '게임';

  @override
  String get lobbyRandomNounTichu6 => '대결';

  @override
  String get lobbyRandomNounTichu7 => '도전';

  @override
  String get lobbyRandomNounTichu8 => '파티';

  @override
  String get lobbyRandomAdjSk1 => '무시무시한';

  @override
  String get lobbyRandomAdjSk2 => '전설의';

  @override
  String get lobbyRandomAdjSk3 => '무적의';

  @override
  String get lobbyRandomAdjSk4 => '잔혹한';

  @override
  String get lobbyRandomAdjSk5 => '탐욕의';

  @override
  String get lobbyRandomAdjSk6 => '최강';

  @override
  String get lobbyRandomAdjSk7 => '폭풍의';

  @override
  String get lobbyRandomAdjSk8 => '대담한';

  @override
  String get lobbyRandomNounSk1 => '해적선';

  @override
  String get lobbyRandomNounSk2 => '보물섬';

  @override
  String get lobbyRandomNounSk3 => '항해';

  @override
  String get lobbyRandomNounSk4 => '약탈';

  @override
  String get lobbyRandomNounSk5 => '선장';

  @override
  String get lobbyRandomNounSk6 => '해전';

  @override
  String get lobbyRandomNounSk7 => '모험';

  @override
  String get lobbyRandomNounSk8 => '크라켄';

  @override
  String get skGameRecoveringGame => '게임 복구 중...';

  @override
  String get skGameCheckingState => '게임 상태 확인 중...';

  @override
  String get skGameReloadingRoom => '방 정보를 다시 불러오는 중...';

  @override
  String get skGameLoadingState => '게임 상태를 불러오는 중...';

  @override
  String get skGameSpectatorWaitingTitle => '스컬킹 대기실 관전';

  @override
  String get skGameSpectatorWaitingDesc =>
      '게임 시작 전 방 상태를 보고 있습니다. 시작되면 관전 화면으로 자동 전환됩니다.';

  @override
  String get skGameHost => '방장';

  @override
  String get skGameReady => '준비 완료';

  @override
  String get skGameWaiting => '대기 중';

  @override
  String get skGameSpectatorStandby => '관전 대기';

  @override
  String get skGameSpectatorListTitle => '관전자 목록';

  @override
  String get skGameNoSpectators => '관전 중인 사람이 없습니다';

  @override
  String get skGameAlwaysAccept => '항상 승인';

  @override
  String get skGameAlwaysReject => '항상 거절';

  @override
  String skGameRoundTrick(int round, int trick) {
    return '$round라운드 $trick번째';
  }

  @override
  String get skGameSpectating => '관전';

  @override
  String skGameBiddingInProgress(String name) {
    return '승리 예측 진행 중 · 선: $name';
  }

  @override
  String skGamePlayerTurn(String name) {
    return '$name 차례';
  }

  @override
  String get skGameLeaveTitle => '게임 나가기';

  @override
  String get skGameLeaveConfirm => '정말 게임에서 나가시겠습니까?';

  @override
  String get skGameLeaveButton => '나가기';

  @override
  String skGameLeaderLabel(String name) {
    return '선: $name';
  }

  @override
  String get skGameMyTurn => '내 턴';

  @override
  String skGameWaitingFor(String name) {
    return '$name 대기';
  }

  @override
  String skGameSecondsShort(int seconds) {
    return '$seconds초';
  }

  @override
  String get skGameTapToRequestCards => '상단 프로필을 탭하여 패 보기를 요청하세요';

  @override
  String skGameRequestingCardView(String name) {
    return '$name에게 패 보기 요청 중...';
  }

  @override
  String skGamePlayerHand(String name) {
    return '$name의 패';
  }

  @override
  String get skGameNoCards => '카드 없음';

  @override
  String skGameCardViewRejected(String name) {
    return '$name이(가) 요청을 거절했습니다. 다른 플레이어를 탭하세요.';
  }

  @override
  String skGameTimeout(String name) {
    return '$name 시간 초과!';
  }

  @override
  String skGameDesertionTimeout(String name) {
    return '$name 탈주! (시간 초과 3회)';
  }

  @override
  String skGameDesertionLeave(String name) {
    return '$name 님이 게임을 떠났습니다';
  }

  @override
  String skGameCardViewRequest(String name) {
    return '$name님이 패 보기를 요청했습니다';
  }

  @override
  String get skGameReject => '거부';

  @override
  String get skGameAllow => '허가';

  @override
  String get skGameChat => '채팅';

  @override
  String get skGameMessageHint => '메시지 입력...';

  @override
  String get skGameViewingMyHand => '내 패를 보는 중';

  @override
  String get skGameNoViewers => '보고 있는 사람 없음';

  @override
  String get skGameViewProfile => '프로필 보기';

  @override
  String get skGameBlock => '차단하기';

  @override
  String get skGameUnblock => '차단 해제';

  @override
  String get skGameScoreHistory => '점수 히스토리';

  @override
  String get skGameBiddingPhase => '승리 예측 중...';

  @override
  String get skGamePlayCard => '카드를 내주세요';

  @override
  String get skGameKrakenActivated => '🐙 크라켄 발동';

  @override
  String get skGameWhiteWhaleActivated => '🐋 화이트웨일 발동';

  @override
  String get skGameWhiteWhaleNullify => '🐋 화이트웨일 · 특수카드 무력화';

  @override
  String get skGameTrickVoided => '트릭 무효';

  @override
  String skGameLeadPlayer(String name) {
    return '$name 선 플레이어';
  }

  @override
  String skGameTrickWinner(String name) {
    return '$name 승리';
  }

  @override
  String get skGameCheckingCards => '카드 확인 중...';

  @override
  String skGameBonusWithLoot(int bonus, int loot) {
    return '보너스 +$bonus (💰 +$loot)';
  }

  @override
  String skGameBonus(int bonus) {
    return '보너스 +$bonus';
  }

  @override
  String skGameBidDone(int bid) {
    return '승리예측: $bid승';
  }

  @override
  String get skGameWaitingOthers => '다른 플레이어 대기 중...';

  @override
  String get skGameBidPrompt => '이번 라운드에서 몇 번 승리할지 예측해보세요';

  @override
  String skGameBidSubmit(int bid) {
    return '$bid승 예측';
  }

  @override
  String get skGameSelectNumber => '숫자를 선택하세요';

  @override
  String get skGamePlayCardButton => '카드 내기';

  @override
  String get skGameSelectCard => '카드를 선택하세요';

  @override
  String get skGameReset => '초기화';

  @override
  String get skGameTigressEscape => '백기';

  @override
  String get skGameTigressPirate => '해적';

  @override
  String skGameRoundResult(int round) {
    return '$round라운드 결과';
  }

  @override
  String get skGameBidTricks => '예측/획득';

  @override
  String get skGameBonusHeader => '보너스';

  @override
  String get skGameScoreHeader => '점수';

  @override
  String get skGameNextRoundPreparing => '다음 라운드 준비 중...';

  @override
  String get skGameGameOver => '게임 종료';

  @override
  String skGameAutoReturnCountdown(int seconds) {
    return '$seconds초 후 자동으로 대기실로 돌아갑니다';
  }

  @override
  String get skGameReturningToRoom => '대기실로 이동 중...';

  @override
  String get skGamePlayerProfile => '플레이어 프로필';

  @override
  String get skGameAlreadyFriend => '이미 친구';

  @override
  String get skGameRequestPending => '요청 중';

  @override
  String get skGameAddFriend => '친구 추가';

  @override
  String get skGameFriendRequestSent => '친구 요청을 보냈습니다';

  @override
  String get skGameBlockUser => '차단하기';

  @override
  String get skGameUnblockUser => '차단 해제';

  @override
  String get skGameUserBlocked => '차단되었습니다';

  @override
  String get skGameUserUnblocked => '차단이 해제되었습니다';

  @override
  String get skGameProfileNotFound => '프로필을 찾을 수 없습니다';

  @override
  String get skGameTichuRecord => '티츄 전적';

  @override
  String get skGameSkullKingRecord => '스컬킹 전적';

  @override
  String get skGameStatRecord => '전적';

  @override
  String get skGameStatWinRate => '승률';

  @override
  String skGameRecordFormat(int games, int wins, int losses) {
    return '$games전 $wins승 $losses패';
  }

  @override
  String get gameSparrowCall => '참새 콜';

  @override
  String get gameSelectNumberToCall => '부를 숫자를 선택하세요';

  @override
  String get gameNoCall => '콜 안 함';

  @override
  String get gameCancelPickAnother => '취소하고 다른 카드 고르기';

  @override
  String get gameRestoringGame => '게임 복구 중...';

  @override
  String get gameCheckingState => '게임 상태 확인 중...';

  @override
  String get gameRecheckingRoomState => '현재 방 상태를 다시 확인하고 있습니다.';

  @override
  String get gameReloadingRoom => '방 정보를 다시 불러오는 중...';

  @override
  String get gameWaitForRestore => '잠시만 기다리면 현재 게임 상태로 복구됩니다.';

  @override
  String get gamePreparingScreen => '게임 화면 준비 중...';

  @override
  String get gameAdjustingScreen => '화면 전환 상태를 다시 맞추고 있습니다.';

  @override
  String get gameTransitioningScreen => '게임 화면 전환 중...';

  @override
  String get gameRecheckingDestination => '현재 목적지 상태를 다시 확인하고 있습니다.';

  @override
  String get gameSoundEffects => '효과음';

  @override
  String get gameChat => '채팅';

  @override
  String get gameMessageHint => '메시지 입력...';

  @override
  String get gameMyProfile => '내 프로필';

  @override
  String get gamePlayerProfile => '플레이어 프로필';

  @override
  String get gameAlreadyFriend => '이미 친구';

  @override
  String get gameRequestPending => '요청 중';

  @override
  String get gameAddFriend => '친구 추가';

  @override
  String get gameFriendRequestSent => '친구 요청을 보냈습니다';

  @override
  String get gameUnblock => '차단 해제';

  @override
  String get gameBlock => '차단하기';

  @override
  String get gameUnblocked => '차단이 해제되었습니다';

  @override
  String get gameBlocked => '차단되었습니다';

  @override
  String get gameReport => '신고하기';

  @override
  String get gameClose => '닫기';

  @override
  String get gameProfileNotFound => '프로필을 찾을 수 없습니다';

  @override
  String get gameTichuSeasonRanked => '티츄 시즌 랭킹전';

  @override
  String get gameStatRecord => '전적';

  @override
  String get gameStatWinRate => '승률';

  @override
  String get gameOverallRecord => '전체 전적';

  @override
  String gameRecordFormat(int games, int wins, int losses) {
    return '$games전 $wins승 $losses패';
  }

  @override
  String get gameMannerGood => '좋음';

  @override
  String get gameMannerNormal => '보통';

  @override
  String get gameMannerBad => '나쁨';

  @override
  String get gameMannerVeryBad => '아주 나쁨';

  @override
  String get gameMannerWorst => '최악';

  @override
  String gameManner(String label) {
    return '매너 $label';
  }

  @override
  String gameDesertions(int count) {
    return '탈주 $count';
  }

  @override
  String get gameRecentMatchesTitle => '최근 전적';

  @override
  String gameRecentMatchesDesc(int count) {
    return '최근 $count경기 결과를 확인할 수 있습니다.';
  }

  @override
  String get gameRecentMatchesThree => '최근 전적 (3)';

  @override
  String get gameSeeMore => '더보기';

  @override
  String get gameNoRecentMatches => '최근 전적이 없습니다';

  @override
  String get gameMatchDesertion => '탈';

  @override
  String get gameMatchDraw => '무';

  @override
  String get gameMatchWin => '승';

  @override
  String get gameMatchLoss => '패';

  @override
  String get gameMatchTypeRanked => '랭크';

  @override
  String get gameMatchTypeNormal => '일반';

  @override
  String get gameViewProfile => '프로필 보기';

  @override
  String get gameCancel => '취소';

  @override
  String get gameReportReasonAbuse => '욕설/비방';

  @override
  String get gameReportReasonSpam => '도배/스팸';

  @override
  String get gameReportReasonNickname => '부적절한 닉네임';

  @override
  String get gameReportReasonGameplay => '게임 방해';

  @override
  String get gameReportReasonOther => '기타';

  @override
  String gameReportTitle(String nickname) {
    return '$nickname 신고';
  }

  @override
  String get gameReportWarning => '신고는 운영팀이 확인합니다.\n허위 신고는 제재될 수 있어요.';

  @override
  String get gameSelectReason => '사유 선택';

  @override
  String get gameReportDetailHint => '상세 사유를 입력해주세요 (선택)';

  @override
  String get gameReportSubmit => '신고하기';

  @override
  String get gameLeaveTitle => '게임 나가기';

  @override
  String get gameLeaveConfirm => '정말 게임을 나가시겠습니까?\n게임 중 나가면 팀에 피해가 됩니다.';

  @override
  String get gameLeave => '나가기';

  @override
  String get gameCallError => '콜된 숫자를 먼저 내야 합니다!';

  @override
  String gameTimeout(String playerName) {
    return '$playerName 시간 초과!';
  }

  @override
  String gameDesertionTimeout(String playerName) {
    return '$playerName 탈주! (시간 초과 3회)';
  }

  @override
  String gameDesertionLeave(String playerName) {
    return '$playerName 님이 게임을 떠났습니다';
  }

  @override
  String get gameSpectator => '관전자';

  @override
  String gameCardViewRequest(String nickname) {
    return '$nickname님이 패 보기를 요청했습니다';
  }

  @override
  String get gameReject => '거부';

  @override
  String get gameAllow => '허가';

  @override
  String get gameAlwaysReject => '항상 거절';

  @override
  String get gameAlwaysAllow => '항상 승인';

  @override
  String get gameSpectatorList => '관전자 목록';

  @override
  String get gameNoSpectators => '관전 중인 사람이 없습니다';

  @override
  String get gameViewingMyCards => '내 패를 보는 중';

  @override
  String get gameNoViewers => '보고 있는 사람 없음';

  @override
  String get gamePartner => '파트너';

  @override
  String get gameLeftPlayer => '좌측';

  @override
  String get gameRightPlayer => '우측';

  @override
  String get gameMyTurn => '내 턴!';

  @override
  String gamePlayerTurn(String name) {
    return '$name의 턴';
  }

  @override
  String gameCall(String rank) {
    return '콜 $rank';
  }

  @override
  String get gameMyTurnShort => '내 턴';

  @override
  String gamePlayerTurnShort(String name) {
    return '$name 턴';
  }

  @override
  String gamePlayerWaiting(String name) {
    return '$name 대기';
  }

  @override
  String gameTimerLabel(String turnLabel, int seconds) {
    return '$turnLabel $seconds초';
  }

  @override
  String get gameScoreHistory => '점수 기록';

  @override
  String get gameScoreHistorySubtitle => '라운드별 점수 변화와 현재 합계';

  @override
  String get gameNoCompletedRounds => '아직 완료된 라운드가 없습니다';

  @override
  String gameTeamLabel(String label) {
    return '팀 $label';
  }

  @override
  String gameDogPlayedBy(String name) {
    return '$name가 개를 냈어';
  }

  @override
  String get gameDogPlayed => '개가 나왔어';

  @override
  String get gamePlayedCards => '가 낸 패';

  @override
  String get gamePlay => '내기';

  @override
  String get gamePass => '패스';

  @override
  String get gameLargeTichuQuestion => '라지 티츄?';

  @override
  String get gameDeclare => '선언!';

  @override
  String get gameSmallTichuDeclare => '스몰 티츄 선언';

  @override
  String get gameSmallTichuConfirmTitle => '스몰 티츄 선언';

  @override
  String get gameSmallTichuConfirmContent =>
      '스몰 티츄를 선언하시겠습니까?\n성공 시 +100점, 실패 시 -100점';

  @override
  String get gameDeclareButton => '선언';

  @override
  String get gameSelectRecipient => '카드를 줄 상대 선택';

  @override
  String gameSelectExchangeCard(int count) {
    return '교환할 카드 선택 ($count/3)';
  }

  @override
  String get gameReset => '초기화';

  @override
  String get gameExchangeComplete => '교환 완료';

  @override
  String get gameDragonQuestion => '용 트릭을 누구에게 주시겠습니까?';

  @override
  String get gameSelectCallRank => '콜할 숫자를 선택하세요';

  @override
  String get gameGameEnd => '게임 종료!';

  @override
  String get gameRoundEnd => '라운드 종료!';

  @override
  String get gameMyTeamWin => '우리 팀 승리!';

  @override
  String get gameEnemyTeamWin => '상대 팀 승리!';

  @override
  String get gameDraw => '무승부!';

  @override
  String get gameThisRound => '이번 라운드: ';

  @override
  String get gameTotalScore => '총점: ';

  @override
  String get gameAutoReturnLobby => '3초 후 대기실로 이동...';

  @override
  String get gameAutoNextRound => '3초 후 자동 진행...';

  @override
  String gameRankedScore(int score) {
    return '랭크전 점수 $score';
  }

  @override
  String get gameRankDiamond => '다이아';

  @override
  String get gameRankGold => '골드';

  @override
  String get gameRankSilver => '실버';

  @override
  String get gameRankBronze => '브론즈';

  @override
  String gameFinishPosition(int position) {
    return '$position등!';
  }

  @override
  String gameCardCount(int count) {
    return '$count장';
  }

  @override
  String get gamePhaseLargeTichu => '라지 티츄 선언';

  @override
  String get gamePhaseDealing => '카드 분배 중';

  @override
  String get gamePhaseExchange => '카드 교환';

  @override
  String get gamePhasePlaying => '게임 진행 중';

  @override
  String get gamePhaseRoundEnd => '라운드 종료';

  @override
  String get gamePhaseGameEnd => '게임 종료';

  @override
  String get gameReceivedCards => '받은 카드';

  @override
  String get gameBadgeLarge => '라지';

  @override
  String get gameBadgeSmall => '스몰';

  @override
  String get gameNotAfk => '잠수 아님';

  @override
  String get spectatorRecovering => '관전 복구 중...';

  @override
  String get spectatorTransitioning => '관전 화면 전환 중...';

  @override
  String get spectatorRecheckingState => '현재 관전 상태를 다시 확인하고 있습니다.';

  @override
  String get spectatorWatching => '관전 중';

  @override
  String get spectatorWaitingForGame => '게임 시작 대기 중...';

  @override
  String get spectatorSit => '착석';

  @override
  String get spectatorHost => '방장';

  @override
  String get spectatorReady => '준비 완료';

  @override
  String get spectatorWaiting => '대기 중';

  @override
  String spectatorTeamWin(String team) {
    return 'Team $team 승리!';
  }

  @override
  String get spectatorDraw => '무승부!';

  @override
  String spectatorTeamScores(int scoreA, int scoreB) {
    return 'Team A: $scoreA | Team B: $scoreB';
  }

  @override
  String get spectatorAutoReturn => '3초 후 대기실로 이동...';

  @override
  String get spectatorPhaseLargeTichu => '라지 티츄';

  @override
  String get spectatorPhaseCardExchange => '카드 교환';

  @override
  String get spectatorPhasePlaying => '플레이 중';

  @override
  String get spectatorPhaseRoundEnd => '라운드 종료';

  @override
  String get spectatorPhaseGameEnd => '게임 종료';

  @override
  String get spectatorFinished => '완료';

  @override
  String spectatorRequesting(int count) {
    return '요청 중... ($count장)';
  }

  @override
  String spectatorRequestCardView(int count) {
    return '패 보기 요청 ($count장)';
  }

  @override
  String get spectatorSoundEffects => '효과음';

  @override
  String get spectatorListTitle => '관전자 목록';

  @override
  String get spectatorNoSpectators => '관전자가 없습니다';

  @override
  String get spectatorClose => '닫기';

  @override
  String get spectatorChat => '채팅';

  @override
  String get spectatorMessageHint => '메시지 입력...';

  @override
  String get spectatorNewTrick => '새 판 시작';

  @override
  String spectatorPlayedCards(String name) {
    return '$name가 낸 패';
  }

  @override
  String get rulesTitle => '게임 설명';

  @override
  String get rulesTabTichu => '티츄';

  @override
  String get rulesTabSkullKing => '스컬킹';

  @override
  String get rulesTichuGoalTitle => '게임 목표';

  @override
  String get rulesTichuGoalBody =>
      '4인 2팀(마주 본 두 사람이 한 팀)으로 진행하는 트릭테이킹 게임입니다. 상대팀보다 먼저 목표 점수에 도달하면 승리합니다.';

  @override
  String get rulesTichuCardCompositionTitle => '카드 구성 (총 56장)';

  @override
  String get rulesTichuNumberCards => '숫자 카드 (2 ~ A)';

  @override
  String get rulesTichuNumberCardsSub => '4 문양 × 13장';

  @override
  String get rulesTichuMahjong => '참새 (Mahjong)';

  @override
  String get rulesTichuMahjongSub => '게임을 시작하는 카드';

  @override
  String get rulesTichuDog => '개 (Dog)';

  @override
  String get rulesTichuDogSub => '리드권을 파트너에게 넘김';

  @override
  String get rulesTichuPhoenix => '불사조 (Phoenix)';

  @override
  String get rulesTichuPhoenixSub => '만능 카드 (-25점)';

  @override
  String get rulesTichuDragon => '용 (Dragon)';

  @override
  String get rulesTichuDragonSub => '가장 강한 카드 (+25점)';

  @override
  String get rulesTichuSpecialTitle => '특수 카드 규칙';

  @override
  String get rulesTichuSpecialMahjongTitle => '참새 (Mahjong)';

  @override
  String get rulesTichuSpecialMahjongLine1 => '이 카드를 가진 사람이 가장 먼저 게임을 시작합니다.';

  @override
  String get rulesTichuSpecialMahjongLine2 =>
      '참새 카드를 낼 때 원하는 숫자(2~14)를 선언할 수 있고, 다음 플레이어는 선언된 숫자를 포함한 조합을 반드시 내야 합니다. (해당 숫자를 가지고 있지 않으면 무시 가능)';

  @override
  String get rulesTichuSpecialDogTitle => '개 (Dog)';

  @override
  String get rulesTichuSpecialDogLine1 => '리드할 때만 낼 수 있으며, 즉시 리드권을 파트너에게 넘깁니다.';

  @override
  String get rulesTichuSpecialDogLine2 => '점수 계산에서는 0점입니다.';

  @override
  String get rulesTichuSpecialPhoenixTitle => '불사조 (Phoenix)';

  @override
  String get rulesTichuSpecialPhoenixLine1 =>
      '싱글로 낼 때는 앞에 낸 카드의 숫자 + 0.5로 취급됩니다. 단, 용 위에는 낼 수 없습니다.';

  @override
  String get rulesTichuSpecialPhoenixLine2 =>
      '조합(페어/트리플/풀하우스/스트레이트 등) 안에서 사용할 때는 어떤 숫자로도 대체할 수 있습니다.';

  @override
  String get rulesTichuSpecialPhoenixLine3 => '획득 시 -25점이므로 먹으면 손해입니다.';

  @override
  String get rulesTichuSpecialDragonTitle => '용 (Dragon)';

  @override
  String get rulesTichuSpecialDragonLine1 => '가장 강한 카드이며, 싱글로만 낼 수 있습니다.';

  @override
  String get rulesTichuSpecialDragonLine2 =>
      '획득 시 +25점이지만, 용으로 이긴 트릭은 상대팀 중 한 명에게 넘겨줘야 합니다.';

  @override
  String get rulesTichuDeclarationTitle => '티츄 선언';

  @override
  String get rulesTichuDeclarationBody =>
      '티츄는 \"이번 라운드에서 내가 1등으로 손패를 다 털겠다\"는 선언입니다. 성공하면 팀 점수가 올라가고 실패하면 감점됩니다.';

  @override
  String get rulesTichuLargeTichu => '라지 티츄';

  @override
  String get rulesTichuLargeTichuWhen => '처음 8장만 받았을 때 (나머지 6장을 보기 전) 선언';

  @override
  String get rulesTichuSmallTichu => '스몰 티츄';

  @override
  String get rulesTichuSmallTichuWhen => '14장을 모두 받은 후, 첫 카드를 한 장도 내기 전에 선언';

  @override
  String rulesTichuDeclSuccess(String points) {
    return '성공 $points';
  }

  @override
  String rulesTichuDeclFail(String points) {
    return '실패 $points';
  }

  @override
  String get rulesTichuFlowTitle => '진행 순서';

  @override
  String get rulesTichuFlowBody =>
      '1. 모든 플레이어가 먼저 8장씩 카드를 받습니다.\n2. 8장을 보고 원하면 라지 티츄를 선언할 수 있습니다.\n3. 나머지 6장을 받아 총 14장이 됩니다.\n4. 나를 제외한 3명의 플레이어에게 카드를 1장씩 교환(패스)합니다.\n5. 교환 후 카드를 한 장도 내기 전에 원하면 스몰 티츄를 선언할 수 있습니다.\n6. 참새(Mahjong)를 가진 사람이 먼저 카드를 내며 첫 리드를 시작합니다.';

  @override
  String get rulesTichuPlayTitle => '플레이 규칙';

  @override
  String get rulesTichuPlayBody =>
      '• 선 플레이어가 낸 조합과 같은 형태의 조합만 그 위에 낼 수 있습니다. (예: 싱글 위에는 더 높은 싱글, 페어 위에는 더 높은 페어)\n• 사용 가능한 조합:\n   - 싱글 (카드 1장)\n   - 페어 (같은 숫자 2장)\n   - 트리플 (같은 숫자 3장)\n   - 풀하우스 (트리플 + 페어)\n   - 스트레이트 (연속된 숫자 5장 이상)\n   - 연속 페어 (연속된 페어 2쌍 이상 = 4장 이상)\n• 본인 차례에 낼 카드가 없거나 내기 싫으면 패스할 수 있습니다.';

  @override
  String get rulesTichuBombTitle => '폭탄';

  @override
  String get rulesTichuBombBody =>
      '폭탄은 자신의 차례가 아니더라도 언제든 낼 수 있으며, 어떤 조합도 이길 수 있는 특수 조합입니다.\n\n• 포카드 폭탄: 같은 숫자 4장 (예: 7♠ 7♥ 7♦ 7♣)\n• 스트레이트 플러시 폭탄: 같은 문양으로 연속된 5장 이상\n\n폭탄끼리의 우열:\n  스트레이트 플러시 > 포카드\n  같은 종류끼리는 더 높은 숫자/더 긴 스트레이트가 우세';

  @override
  String get rulesTichuScoringTitle => '점수 계산';

  @override
  String get rulesTichuScoringBody =>
      '카드 점수:\n• 5: 5점\n• 10, K: 10점\n• 용: +25점 / 불사조: -25점\n• 나머지 카드: 0점\n\n라운드 정산:\n• 1등으로 손패를 다 턴 사람은 꼴찌(4등)가 그동안 먹은 트릭 점수를 모두 가져갑니다.\n• 꼴찌의 손에 남아있는 카드는 상대팀의 점수로 들어갑니다.\n• 마주 본 한 팀이 1등·2등으로 먼저 나가면 \"원더(Double Victory)\" — 해당 라운드 즉시 종료, 이긴 팀 +200점 (트릭 점수 계산 없음).\n• 티츄 선언 성공/실패 보너스가 여기에 더해집니다.';

  @override
  String get rulesTichuWinTitle => '승리 조건';

  @override
  String get rulesTichuWinBody =>
      '방 생성 시 설정한 목표 점수(기본 1000점)에 먼저 도달한 팀이 승리합니다. 랭크전은 1000점 고정입니다.';

  @override
  String get rulesSkGoalTitle => '게임 목표';

  @override
  String get rulesSkGoalBody =>
      '2~6명이 개인전으로 진행하는 트릭테이킹 게임입니다. 총 10 라운드 동안 매 라운드마다 자신이 이길 트릭 수를 정확히 예측해야 점수를 얻습니다.';

  @override
  String get rulesSkCardCompositionTitle => '카드 구성 (기본 총 67장)';

  @override
  String get rulesSkNumberCards => '숫자 카드 (1 ~ 13)';

  @override
  String get rulesSkNumberCardsSub => '4 문양 × 13장 (노랑 / 초록 / 보라 / 검정)';

  @override
  String get rulesSkEscape => 'Escape (도주)';

  @override
  String get rulesSkEscapeSub => '트릭을 이기지 않음';

  @override
  String get rulesSkPirate => 'Pirate (해적)';

  @override
  String get rulesSkPirateSub => '숫자 카드를 모두 이김';

  @override
  String get rulesSkMermaid => 'Mermaid (인어)';

  @override
  String get rulesSkMermaidSub => '스컬킹을 포획 (+50 보너스)';

  @override
  String get rulesSkSkullKing => 'Skull King (스컬킹)';

  @override
  String get rulesSkSkullKingSub => '해적을 이김 (해적당 +30 보너스)';

  @override
  String get rulesSkTigress => 'Tigress (티그리스)';

  @override
  String get rulesSkTigressSub => '해적 또는 도주 중 선택하여 사용';

  @override
  String get rulesSkIncludedByDefault => '기본 포함';

  @override
  String rulesSkCardCount(int count) {
    return '$count장';
  }

  @override
  String get rulesSkTrumpTitle => '검정 문양 = 트럼프';

  @override
  String get rulesSkTrumpBody =>
      '검정 숫자 카드는 다른 문양의 숫자 카드를 숫자에 상관없이 모두 이깁니다. 단, 리드 수트(첫 숫자 카드의 문양)를 따라 낼 수 있다면 반드시 따라야 하고, 해당 문양이 없을 때만 검정을 낼 수 있습니다.';

  @override
  String get rulesSkSpecialTitle => '특수 카드 규칙';

  @override
  String get rulesSkSpecialEscapeTitle => 'Escape (도주)';

  @override
  String get rulesSkSpecialEscapeLine1 =>
      '절대 트릭을 이기지 않습니다. 수트 팔로잉에 상관없이 언제든 낼 수 있습니다.';

  @override
  String get rulesSkSpecialEscapeLine2 =>
      '모든 플레이어가 도주만 낸 경우에는 가장 먼저 낸 플레이어(리드 플레이어)가 트릭을 가져갑니다.';

  @override
  String get rulesSkSpecialPirateTitle => 'Pirate (해적)';

  @override
  String get rulesSkSpecialPirateLine1 =>
      '모든 숫자 카드(검정 트럼프 포함)를 이깁니다. 같은 트릭에 여러 해적이 나오면 먼저 낸 해적이 이깁니다.';

  @override
  String get rulesSkSpecialPirateLine2 => '인어에게 이기지만 스컬킹에게는 패배합니다.';

  @override
  String get rulesSkSpecialMermaidTitle => 'Mermaid (인어)';

  @override
  String get rulesSkSpecialMermaidLine1 => '해적에게는 패배하지만, 스컬킹을 포획하여 이깁니다.';

  @override
  String get rulesSkSpecialMermaidLine2 => '인어가 스컬킹을 잡으면 해당 트릭 승자에게 +50 보너스.';

  @override
  String get rulesSkSpecialMermaidLine3 => '인어만 나온 경우 숫자 카드를 이깁니다.';

  @override
  String get rulesSkSpecialSkullKingTitle => 'Skull King (스컬킹)';

  @override
  String get rulesSkSpecialSkullKingLine1 => '해적을 이기며, 해적 1명당 +30 보너스를 얻습니다.';

  @override
  String get rulesSkSpecialSkullKingLine2 => '단, 인어에게는 포획당해 패배합니다.';

  @override
  String get rulesSkSpecialTigressTitle => 'Tigress (티그리스) — 기본 3장';

  @override
  String get rulesSkSpecialTigressLine1 => '카드를 낼 때 해적 또는 도주 중 하나를 선택합니다.';

  @override
  String get rulesSkSpecialTigressLine2 =>
      '해적으로 낸 티그리스는 해적과 동일하게 작동하며 스컬킹에게 +30 보너스도 포함됩니다.';

  @override
  String get rulesSkSpecialTigressLine3 =>
      '도주로 낸 티그리스는 도주와 동일하게 작동하며 트릭을 이기지 않습니다.';

  @override
  String get rulesSkSpecialTigressLine4 =>
      '해적/도주로 낸 티그리스는 카드 좌상단에 보라색 체크 마크가 표시되어 일반 해적/도주 카드와 구분됩니다.';

  @override
  String get rulesSkTigressPreviewTitle => '게임 중 표시 예시';

  @override
  String get rulesSkTigressChoiceEscape => '도주 선택';

  @override
  String get rulesSkTigressChoicePirate => '해적 선택';

  @override
  String get rulesSkFlowTitle => '진행 순서';

  @override
  String get rulesSkFlowBody =>
      '1. 라운드 N에서 각자 N장씩 카드를 받습니다. (1~10 라운드)\n2. 모든 플레이어가 동시에 자신이 이길 트릭 수를 예측(비드)합니다.\n3. 선 플레이어부터 카드를 내고, 수트 팔로잉 규칙에 따라 트릭을 진행합니다.\n4. 한 라운드가 끝나면 비드 성공/실패에 따라 점수를 계산합니다.';

  @override
  String get rulesSkScoringTitle => '점수 계산';

  @override
  String get rulesSkScoringBody =>
      '• 비드 0 성공 (트릭 0승): +10 × 라운드 번호\n• 비드 0 실패: -10 × 라운드 번호\n• 비드 N 성공 (정확히 N승): +20 × N + 보너스\n• 비드 N 실패: -10 × |차이| (보너스 없음)\n• 보너스는 비드를 정확히 맞혔을 때만 지급됩니다.';

  @override
  String get rulesSkExample1Title => '예시 1. 단순 비드 성공';

  @override
  String get rulesSkExample1Setup => '3라운드 · 비드 2 · 트릭 2승 · 보너스 없음';

  @override
  String get rulesSkExample1Calc => '20 × 2 = 40';

  @override
  String get rulesSkExample1Result => '+40점';

  @override
  String get rulesSkExample2Title => '예시 2. 비드 0 성공';

  @override
  String get rulesSkExample2Setup => '5라운드 · 비드 0 · 트릭 0승';

  @override
  String get rulesSkExample2Calc => '10 × 5 = 50';

  @override
  String get rulesSkExample2Result => '+50점';

  @override
  String get rulesSkExample3Title => '예시 3. 비드 실패';

  @override
  String get rulesSkExample3Setup => '5라운드 · 비드 3 · 트릭 1승 (차이 2)';

  @override
  String get rulesSkExample3Calc => '-10 × 2 = -20';

  @override
  String get rulesSkExample3Result => '-20점';

  @override
  String get rulesSkExample4Title => '예시 4. 스컬킹으로 해적 2명 포획';

  @override
  String get rulesSkExample4Setup => '3라운드 · 비드 2 · 트릭 2승 · 보너스 +60 (해적 2×30)';

  @override
  String get rulesSkExample4Calc => '(20 × 2) + 60 = 100';

  @override
  String get rulesSkExample4Result => '+100점';

  @override
  String get rulesSkExample5Title => '예시 5. 인어로 스컬킹 포획';

  @override
  String get rulesSkExample5Setup => '4라운드 · 비드 1 · 트릭 1승 · 보너스 +50 (인어×SK)';

  @override
  String get rulesSkExample5Calc => '(20 × 1) + 50 = 70';

  @override
  String get rulesSkExample5Result => '+70점';

  @override
  String get rulesSkExample6Title => '예시 6. 비드 0 실패 (트릭 먹힘)';

  @override
  String get rulesSkExample6Setup => '7라운드 · 비드 0 · 트릭 1승';

  @override
  String get rulesSkExample6Calc => '-10 × 7 = -70';

  @override
  String get rulesSkExample6Result => '-70점';

  @override
  String get rulesSkWinTitle => '승리 조건';

  @override
  String get rulesSkWinBody => '10 라운드가 모두 끝난 후 누적 점수가 가장 높은 플레이어가 승리합니다.';

  @override
  String get rulesSkExpansionTitle => '확장팩 (선택)';

  @override
  String get rulesSkExpansionBody =>
      '방 생성 시 각 확장팩을 개별적으로 선택할 수 있습니다. 확장팩 카드는 기본 덱에 추가로 섞입니다.';

  @override
  String get rulesSkExpKraken => '🐙 크라켄';

  @override
  String get rulesSkExpKrakenDesc =>
      '크라켄이 포함된 트릭은 무효가 됩니다. 아무도 트릭을 얻지 못하고 보너스도 지급되지 않습니다. 크라켄이 없었다면 이겼을 플레이어가 다음 트릭을 리드합니다.';

  @override
  String get rulesSkExpWhiteWhale => '🐋 화이트웨일';

  @override
  String get rulesSkExpWhiteWhaleDesc =>
      '모든 특수 카드의 효과를 무력화합니다. 트릭에서는 오직 숫자 카드만 비교하며, 수트와 무관하게 가장 높은 숫자가 승리합니다. 숫자 카드가 없는 경우 트릭이 무효가 됩니다.';

  @override
  String get rulesSkExpLoot => '💰 보물';

  @override
  String get rulesSkExpLootDesc =>
      '트릭을 이긴 사람이 트릭에 포함된 보물 1장당 +20 보너스를 얻고, 보물을 낸 각 플레이어도 자신의 보너스로 +20을 얻습니다. (비드 성공 시에만 지급)';

  @override
  String get friendsTitle => '친구';

  @override
  String get friendsTabFriends => '친구';

  @override
  String get friendsTabSearch => '검색';

  @override
  String get friendsTabRequests => '요청';

  @override
  String get friendsEmptyList => '친구가 없어요!\n검색 탭에서 친구를 추가해보세요.';

  @override
  String friendsStatusPlayingInRoom(String roomName) {
    return '$roomName에서 게임 중';
  }

  @override
  String get friendsStatusOnline => '온라인';

  @override
  String get friendsStatusOffline => '오프라인';

  @override
  String get friendsRestrictedDuringGame => '게임 중 제한';

  @override
  String get friendsDmBlockedDuringGame => '게임 중에는 DM 채팅방에 들어갈 수 없습니다';

  @override
  String get friendsInvited => '초대됨';

  @override
  String get friendsInvite => '초대';

  @override
  String friendsInviteSent(String nickname) {
    return '$nickname님에게 초대를 보냈습니다';
  }

  @override
  String get friendsJoinRoom => '입장';

  @override
  String get friendsSpectateRoom => '관전';

  @override
  String get friendsSearchHint => '닉네임으로 검색';

  @override
  String get friendsSearchPrompt => '닉네임을 입력하여 검색하세요';

  @override
  String get friendsSearchNoResults => '검색 결과가 없습니다';

  @override
  String get friendsStatusFriend => '친구';

  @override
  String get friendsRequestReceived => '요청 받음';

  @override
  String get friendsRequestSent => '요청 보냄';

  @override
  String friendsRequestSentSnackbar(String nickname) {
    return '$nickname님에게 친구 요청을 보냈습니다';
  }

  @override
  String get friendsAddFriend => '친구 추가';

  @override
  String get friendsNoRequests => '받은 요청이 없습니다';

  @override
  String friendsAccepted(String nickname) {
    return '$nickname님과 친구가 되었습니다';
  }

  @override
  String get friendsAccept => '수락';

  @override
  String get friendsReject => '거절';

  @override
  String get friendsDmEmpty => '메시지가 없습니다.\n첫 메시지를 보내보세요!';

  @override
  String get friendsDmInputHint => '메시지를 입력하세요';

  @override
  String get friendsRemoveTitle => '친구 삭제';

  @override
  String friendsRemoveConfirm(String nickname) {
    return '$nickname님을 친구 목록에서 삭제하시겠습니까?';
  }

  @override
  String friendsRemoved(String nickname) {
    return '$nickname님을 친구 목록에서 삭제했습니다';
  }

  @override
  String get rankingTitle => '랭킹';

  @override
  String get rankingTichu => '티츄';

  @override
  String get rankingSkullKing => '스컬킹';

  @override
  String get rankingNoData => '랭킹 데이터가 없어요';

  @override
  String rankingRecordWithWinRate(
    int total,
    int wins,
    int losses,
    int winRate,
  ) {
    return '전적 $total전 $wins승 $losses패 · 승률 $winRate%';
  }

  @override
  String get rankingSeasonScore => '시즌 점수';

  @override
  String get rankingProfileNotFound => '프로필을 찾을 수 없습니다';

  @override
  String get rankingTichuSeasonRanked => '티츄 시즌 랭킹전';

  @override
  String get rankingTichuRecord => '티츄 전적';

  @override
  String get rankingSkullKingSeasonRanked => '스컬킹 시즌 랭킹전';

  @override
  String get rankingSkullKingRecord => '스컬킹 전적';

  @override
  String get rankingStatRecord => '전적';

  @override
  String get rankingStatWinRate => '승률';

  @override
  String rankingRecordFormat(int games, int wins, int losses) {
    return '$games전 $wins승 $losses패';
  }

  @override
  String rankingGold(int gold) {
    return '$gold 골드';
  }

  @override
  String rankingDesertions(int count) {
    return '탈주 $count';
  }

  @override
  String get rankingRecentMatchesHeader => '최근 전적 (3)';

  @override
  String get rankingSeeMore => '더보기';

  @override
  String get rankingNoRecentMatches => '최근 전적이 없습니다';

  @override
  String get rankingBadgeDesertion => '탈';

  @override
  String get rankingBadgeDraw => '무';

  @override
  String rankingSkRankScore(String rank, int score) {
    return '$rank등 $score점';
  }

  @override
  String get rankingRecentMatchesTitle => '최근 전적';

  @override
  String get shopTitle => '상점';

  @override
  String shopGoldAmount(int gold) {
    return '$gold 골드';
  }

  @override
  String get shopHowToEarn => '획득 방법';

  @override
  String shopDesertionCount(int count) {
    return '탈주 $count';
  }

  @override
  String get shopGoldHistory => '골드 내역';

  @override
  String shopGoldCurrent(int gold) {
    return '현재 보유 골드 $gold';
  }

  @override
  String get shopGoldHistoryDesc =>
      '게임 결과, 광고 보상, 상점 구매, 시즌 보상 내역을 최근 순으로 보여줍니다.';

  @override
  String get shopGoldHistoryEmpty => '표시할 골드 내역이 아직 없습니다.';

  @override
  String get shopGoldChangeFallback => '골드 변동';

  @override
  String get shopGoldGuideTitle => '골드 획득 방법';

  @override
  String get shopGoldGuideDesc =>
      '골드는 게임 플레이와 보상으로 얻을 수 있고, 상점에서 아이템 구매에 사용됩니다.';

  @override
  String get shopGuideNormalWin => '일반전 승리';

  @override
  String get shopGuideNormalWinValue => '+10 골드';

  @override
  String get shopGuideNormalWinDesc => '티츄와 스컬킹 일반전 승리 시 기본 보상을 받습니다.';

  @override
  String get shopGuideNormalLoss => '일반전 패배';

  @override
  String get shopGuideNormalLossValue => '+3 골드';

  @override
  String get shopGuideNormalLossDesc => '패배해도 기본 참가 보상을 받을 수 있습니다.';

  @override
  String get shopGuideRankedWin => '랭킹전 승리';

  @override
  String get shopGuideRankedWinValue => '+20 골드';

  @override
  String get shopGuideRankedWinDesc => '랭킹전은 일반전 대비 2배 골드를 지급합니다.';

  @override
  String get shopGuideRankedLoss => '랭킹전 패배';

  @override
  String get shopGuideRankedLossValue => '+6 골드';

  @override
  String get shopGuideRankedLossDesc => '랭킹전 패배 보상도 일반전 대비 2배입니다.';

  @override
  String get shopGuideAdReward => '광고 보상';

  @override
  String get shopGuideAdRewardValue => '+50 골드';

  @override
  String get shopGuideAdRewardDesc => '광고 시청으로 하루 최대 5번까지 추가 골드를 받을 수 있습니다.';

  @override
  String get shopGuideSeasonReward => '시즌 보상';

  @override
  String get shopGuideSeasonRewardValue => '추가 지급';

  @override
  String get shopGuideSeasonRewardDesc => '시즌 순위에 따라 시즌 종료 시 추가 골드가 지급됩니다.';

  @override
  String get shopTabShop => '상점';

  @override
  String get shopTabInventory => '인벤토리';

  @override
  String get shopNoItems => '상점 아이템이 없어요';

  @override
  String get shopCategoryBanner => '배너';

  @override
  String get shopCategoryTitle => '칭호';

  @override
  String get shopCategoryTheme => '테마';

  @override
  String get shopCategoryUtil => '유틸';

  @override
  String get shopCategorySeason => '시즌';

  @override
  String get shopItemEmpty => '아이템이 없어요';

  @override
  String get shopItemOwned => '보유 중';

  @override
  String get shopButtonExtend => '연장';

  @override
  String get shopButtonPurchase => '구매';

  @override
  String get shopExtendTitle => '기간 연장';

  @override
  String shopExtendConfirm(String name, int days, int price) {
    return '이미 보유하고 있는 아이템입니다.\n$name의 기간을 $days일 연장하시겠습니까?\n\n비용: $price 골드';
  }

  @override
  String get shopExtendAction => '연장하기';

  @override
  String get shopNoInventoryItems => '보유한 아이템이 없어요';

  @override
  String get shopStatusActivated => '활성화됨';

  @override
  String get shopStatusInUse => '사용 중';

  @override
  String get shopPermanentOwned => '영구 보유';

  @override
  String get shopButtonUse => '사용';

  @override
  String get shopButtonEquip => '장착';

  @override
  String get shopTagSeason => '시즌 아이템';

  @override
  String get shopTagPermanent => '영구';

  @override
  String shopTagDuration(int days) {
    return '기간제 $days일';
  }

  @override
  String get shopTagDurationOnly => '기간제';

  @override
  String shopExpireDate(String date) {
    return '만료: $date';
  }

  @override
  String get shopExpireSoon => '만료 예정';

  @override
  String get shopPurchaseComplete => '구매 완료';

  @override
  String get shopExtendComplete => '기간 연장 완료';

  @override
  String shopExtendDone(String name) {
    return '$name 기간이 연장되었어요.';
  }

  @override
  String get shopPurchaseDoneConsumable => '구매가 완료되었습니다.\n인벤토리에서 사용해주세요.';

  @override
  String get shopPurchaseDonePassive => '구매가 완료되었습니다.\n구매 즉시 자동 활성화됩니다.';

  @override
  String get shopPurchaseDoneEquip => '구매가 완료되었습니다.\n바로 장착하시겠어요?';

  @override
  String get shopEquipNow => '장착하기';

  @override
  String get shopDetailCategoryBanner => '배너';

  @override
  String get shopDetailCategoryTitle => '칭호';

  @override
  String get shopDetailCategoryThemeSkin => '테마/카드 스킨';

  @override
  String get shopDetailCategoryUtility => '유틸리티';

  @override
  String get shopDetailCategoryItem => '아이템';

  @override
  String get shopDetailNormalItem => '일반 아이템';

  @override
  String get shopDetailPermanent => '영구';

  @override
  String shopDetailDuration(int days) {
    return '기간제 $days일';
  }

  @override
  String get shopEffectNicknameChange => '효과: 닉네임 1회 변경';

  @override
  String shopEffectLeaveReduce(String value) {
    return '효과: 탈주 -$value';
  }

  @override
  String get shopEffectStatsReset => '효과: 전체 전적(승/패/판수) 초기화';

  @override
  String get shopEffectSeasonStatsReset => '효과: 랭킹 전적(승/패/판수) 초기화';

  @override
  String shopPriceGold(int price) {
    return '$price 골드';
  }

  @override
  String get shopNicknameChangeTitle => '닉네임 변경';

  @override
  String get shopNicknameChangeDesc => '새로운 닉네임을 입력해주세요.\n(2~10자, 공백 불가)';

  @override
  String get shopNicknameChangeHint => '새 닉네임';

  @override
  String get shopNicknameChangeValidation => '닉네임은 2~10자여야 합니다';

  @override
  String get shopNicknameChangeButton => '변경';

  @override
  String get shopAdCannotShow => '광고를 표시할 수 없습니다';

  @override
  String shopAdWatchForGold(int current, int max) {
    return '광고 보고 50골드 받기 ($current/$max)';
  }

  @override
  String get shopAdRewardDone => '오늘의 광고 보상 완료';

  @override
  String get appForceUpdateTitle => '업데이트가 필요합니다';

  @override
  String get appForceUpdateBody => '새로운 버전이 출시되었습니다.\n원활한 이용을 위해 업데이트해주세요.';

  @override
  String get appForceUpdateButton => '업데이트';

  @override
  String get appEulaSubtitle => '이용약관';

  @override
  String get appEulaLoadFailed => '이용약관을 불러올 수 없습니다. 네트워크 연결을 확인해주세요.';

  @override
  String get appEulaAgree => '이용약관에 동의합니다';

  @override
  String get appEulaStart => '시작하기';

  @override
  String get serviceRestoreRefreshingSocial => '소셜 로그인 정보를 확인하는 중...';

  @override
  String get serviceRestoreSocialLogin => '소셜 계정으로 로그인하는 중...';

  @override
  String get serviceRestoreLocalLogin => '저장된 계정으로 로그인하는 중...';

  @override
  String get serviceRestoreRoomState => '방 정보를 복구하는 중...';

  @override
  String get serviceRestoreLoadingLobby => '대기실 정보를 불러오는 중...';

  @override
  String get serviceRestoreAutoLoginFailed => '자동 로그인에 실패했습니다.';

  @override
  String get serviceRestoreConnecting => '연결 중...';

  @override
  String get serviceRestoreNeedsNickname => '추가 닉네임 설정이 필요합니다.';

  @override
  String get serviceRestoreSocialFailed => '소셜 로그인 복구에 실패했습니다.';

  @override
  String get serviceRestoreSocialTokenExpired => '소셜 로그인 정보를 다시 확인해야 합니다.';

  @override
  String get serviceRestoreLocalFailed => '저장된 계정 로그인에 실패했습니다.';

  @override
  String get serviceRestoreAutoError => '자동 로그인 복구 중 오류가 발생했습니다.';

  @override
  String get serviceServerTimeout => '서버 응답 시간 초과';

  @override
  String get serviceKicked => '강퇴되었습니다';

  @override
  String get serviceRankingsLoadFailed => '랭킹을 불러오지 못했습니다';

  @override
  String get serviceGoldHistoryLoadFailed => '골드 내역을 불러오지 못했습니다';

  @override
  String get serviceAdminUsersLoadFailed => '유저 목록을 불러오지 못했습니다';

  @override
  String get serviceAdminUserDetailLoadFailed => '유저 정보를 불러오지 못했습니다';

  @override
  String get serviceAdminInquiriesLoadFailed => '문의 목록을 불러오지 못했습니다';

  @override
  String get serviceAdminReportsLoadFailed => '신고 목록을 불러오지 못했습니다';

  @override
  String get serviceAdminReportGroupLoadFailed => '신고 상세를 불러오지 못했습니다';

  @override
  String get serviceAdminActionSuccess => '처리되었습니다';

  @override
  String get serviceAdminActionFailed => '처리에 실패했습니다';

  @override
  String get serviceShopLoadFailed => '상점 정보를 불러오지 못했습니다';

  @override
  String get serviceInventoryLoadFailed => '인벤토리를 불러오지 못했습니다';

  @override
  String get serviceInquiriesLoadFailed => '문의 내역을 불러오지 못했습니다';

  @override
  String get serviceNoticesLoadFailed => '공지사항을 불러오지 못했습니다';

  @override
  String get serviceNicknameChanged => '닉네임이 변경되었습니다';

  @override
  String get serviceNicknameChangeFailed => '닉네임 변경에 실패했습니다';

  @override
  String get serviceRewardFailed => '보상 지급에 실패했습니다';

  @override
  String get serviceRoomRestoreFallback => '방 정보를 복구하지 못해 로비로 이동했습니다.';

  @override
  String get serviceInviteInGame => '게임 진행 중에는 방 초대를 보낼 수 없습니다';

  @override
  String get serviceInviteCooldown => '이미 초대를 보냈습니다. 잠시 후 다시 시도해주세요';

  @override
  String get serviceAdShowFailed => '광고를 표시할 수 없습니다';

  @override
  String get serviceAdLoadFailed => '광고를 불러올 수 없습니다';

  @override
  String serviceInquiryReply(String title) {
    return '문의 답변이 도착했어요: $title';
  }

  @override
  String get serviceInquiryDefault => '문의';

  @override
  String serviceChatBanned(String remaining) {
    return '채팅이 제한되었습니다 ($remaining 남음)';
  }

  @override
  String serviceChatBanHoursMinutes(int hours, int minutes) {
    return '$hours시간 $minutes분';
  }

  @override
  String serviceChatBanMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String serviceAdRewardSuccess(int remaining) {
    return '50골드를 받았습니다! (남은 횟수: $remaining)';
  }
}

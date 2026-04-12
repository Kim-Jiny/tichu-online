import 'app_localizations.dart';
import '../services/session_service.dart';

/// Map [RestorePhase] to a user-facing localized string.
String localizeRestorePhase(SessionService session, L10n l10n) {
  switch (session.restorePhase) {
    case RestorePhase.refreshingSocialToken:
      return l10n.serviceRestoreRefreshingSocial;
    case RestorePhase.restoringSocialSession:
      return l10n.serviceRestoreSocialLogin;
    case RestorePhase.restoringLocalSession:
      return l10n.serviceRestoreLocalLogin;
    case RestorePhase.restoringRoomState:
      return l10n.serviceRestoreRoomState;
    case RestorePhase.loadingLobbyData:
      return l10n.serviceRestoreLoadingLobby;
    case RestorePhase.failed:
      return localizeRestoreError(session.restoreErrorRaw, l10n)
          ?? l10n.serviceRestoreAutoLoginFailed;
    case RestorePhase.idle:
      return l10n.serviceRestoreConnecting;
  }
}

/// Map a service-layer error key to a localized string.
/// Returns null if the key is unrecognized (caller can fall back).
String? localizeRestoreError(String? key, L10n l10n) {
  if (key == null) return null;
  switch (key) {
    case 'needs_nickname':
      return l10n.serviceRestoreNeedsNickname;
    case 'social_restore_failed':
      return l10n.serviceRestoreSocialFailed;
    case 'social_token_expired':
      return l10n.serviceRestoreSocialTokenExpired;
    case 'local_restore_failed':
      return l10n.serviceRestoreLocalFailed;
    case 'auto_restore_error':
      return l10n.serviceRestoreAutoError;
    case 'server_timeout':
      return l10n.serviceServerTimeout;
    default:
      // Server-provided message or unknown key — pass through.
      return key;
  }
}

/// Map a service-layer error/status key from [GameService] to a localized
/// string. Returns the original value when the key is not recognised.
String localizeServiceMessage(String key, L10n l10n) {
  switch (key) {
    // login
    case 'login_failed':
      return l10n.loginFailed;
    // kick
    case 'kicked':
      return l10n.serviceKicked;
    // chat ban - handled separately (needs parameters)
    // rankings / admin / shop / inventory / inquiries / notices errors
    case 'rankings_load_failed':
      return l10n.serviceRankingsLoadFailed;
    case 'gold_history_load_failed':
      return l10n.serviceGoldHistoryLoadFailed;
    case 'admin_users_load_failed':
      return l10n.serviceAdminUsersLoadFailed;
    case 'admin_user_detail_load_failed':
      return l10n.serviceAdminUserDetailLoadFailed;
    case 'admin_inquiries_load_failed':
      return l10n.serviceAdminInquiriesLoadFailed;
    case 'admin_reports_load_failed':
      return l10n.serviceAdminReportsLoadFailed;
    case 'admin_report_group_load_failed':
      return l10n.serviceAdminReportGroupLoadFailed;
    case 'admin_action_success':
      return l10n.serviceAdminActionSuccess;
    case 'admin_action_failed':
      return l10n.serviceAdminActionFailed;
    case 'shop_load_failed':
      return l10n.serviceShopLoadFailed;
    case 'inventory_load_failed':
      return l10n.serviceInventoryLoadFailed;
    case 'inquiries_load_failed':
      return l10n.serviceInquiriesLoadFailed;
    case 'notices_load_failed':
      return l10n.serviceNoticesLoadFailed;
    case 'nickname_changed':
      return l10n.serviceNicknameChanged;
    case 'nickname_change_failed':
      return l10n.serviceNicknameChangeFailed;
    case 'reward_failed':
      return l10n.serviceRewardFailed;
    case 'room_restore_fallback':
      return l10n.serviceRoomRestoreFallback;
    case 'invite_in_game':
      return l10n.serviceInviteInGame;
    case 'invite_cooldown':
      return l10n.serviceInviteCooldown;
    case 'ad_show_failed':
      return l10n.serviceAdShowFailed;
    case 'ad_load_failed':
      return l10n.serviceAdLoadFailed;
    default:
      return key;
  }
}

/// Localize the inquiry banner message stored as "inquiry_reply:<title>".
String localizeInquiryBanner(String? raw, L10n l10n) {
  if (raw == null) return '';
  if (raw.startsWith('inquiry_reply:')) {
    final title = raw.substring('inquiry_reply:'.length);
    return l10n.serviceInquiryReply(title.isEmpty ? l10n.serviceInquiryDefault : title);
  }
  return raw;
}

/// Localize the chat-banned system message.
String localizeChatBanned(int remainingMinutes, L10n l10n) {
  final hours = remainingMinutes ~/ 60;
  final mins = remainingMinutes % 60;
  final display = hours > 0
      ? l10n.serviceChatBanHoursMinutes(hours, mins)
      : l10n.serviceChatBanMinutes(remainingMinutes);
  return l10n.serviceChatBanned(display);
}

/// Localize the ad reward success message.
String localizeAdRewardSuccess(int remaining, L10n l10n) {
  return l10n.serviceAdRewardSuccess(remaining);
}


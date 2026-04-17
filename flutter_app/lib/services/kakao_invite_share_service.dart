import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';

import 'game_service.dart';

class KakaoInviteShareService {
  KakaoInviteShareService._();

  static final KakaoInviteShareService instance = KakaoInviteShareService._();
  static const int _inviteTemplateId = 132295;

  Future<void> shareRoomInvite(GameService game) async {
    if (!game.isInWaitingRoom) {
      throw StateError(
        'Room invites are only available while waiting in a room.',
      );
    }

    final inviteUrl = await game.createShareInviteLink();
    if (inviteUrl == null || inviteUrl.isEmpty) {
      throw StateError('Invite link generation failed.');
    }
    final inviteToken = Uri.parse(inviteUrl).queryParameters['t'];
    if (inviteToken == null || inviteToken.isEmpty) {
      throw StateError('Invite token is missing.');
    }

    final gameTitle = _gameTitleFor(game.currentGameType);
    final templateArgs = {'gameTitle': gameTitle, 'inviteToken': inviteToken};
    final isAvailable = await ShareClient.instance
        .isKakaoTalkSharingAvailable();

    if (isAvailable) {
      final shareUri = await ShareClient.instance.shareCustom(
        templateId: _inviteTemplateId,
        templateArgs: templateArgs,
      );
      await ShareClient.instance.launchKakaoTalk(shareUri);
      return;
    }

    final webShareUri = await WebSharerClient.instance.makeCustomUrl(
      templateId: _inviteTemplateId,
      templateArgs: templateArgs,
    );
    final launched = await launchUrl(
      webShareUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Could not open the Kakao share page.');
    }
    debugPrint('[KakaoInviteShareService] Opened web share page: $webShareUri');
  }

  String _gameTitleFor(String gameType) {
    switch (gameType) {
      case 'skull_king':
        return '스컬킹';
      case 'love_letter':
        return '러브레터';
      case 'tichu':
      default:
        return '티츄';
    }
  }
}

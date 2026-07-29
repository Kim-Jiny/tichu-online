import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../l10n/app_localizations.dart';
import '../screens/photo_crop_screen.dart';
import '../services/game_service.dart';
import '../services/profile_photo_service.dart';
import 'profile_avatar.dart';

/// Header of the player-profile popup: avatar, nickname, and the friend /
/// block / report actions.
///
/// Six screens open a profile popup — lobby, the four game screens, and the
/// spectator screen — and each carried its own copy of this header. The bodies
/// below it genuinely differ per screen (the stats panels share as little as
/// 13% of their lines), but the headers were 73-75% identical, and that is
/// where every profile-related change has to land. The copies had already
/// drifted: the paid profile photo reached only the lobby's, and Skull King's
/// lost its report button somewhere along the way.
///
/// Tapping the avatar enlarges it, or opens the change flow when it is your
/// own — the reason this got extracted rather than pasted a sixth time.
class PlayerProfileHeader extends StatelessWidget {
  final String nickname;

  /// `game.profileFor(nickname)` — the popup already has it, and re-reading it
  /// here would race the load.
  final Map<String, dynamic>? profile;

  final GameService game;

  /// Line under the nickname, e.g. "플레이어 프로필". Ignored when
  /// [subtitleBuilder] is given.
  final String subtitle;

  /// Four of the six screens show a level/exp strip there instead of a plain
  /// caption, built from the loaded profile. Kept as a builder so this widget
  /// doesn't need to know how any of them render it.
  final Widget Function(Map? innerProfile)? subtitleBuilder;

  /// Bots have no account, so none of the actions apply.
  final bool isBot;

  /// Closes the popup this header sits in. Adding a friend dismisses it, the
  /// way every copy did.
  final VoidCallback onCloseDialog;

  /// Placeholder colours behind the person icon when there is no photo.
  /// Mighty's popup is green where the others are blue.
  final Color placeholderBackground;
  final Color placeholderForeground;

  const PlayerProfileHeader({
    super.key,
    required this.nickname,
    required this.profile,
    required this.game,
    required this.subtitle,
    required this.onCloseDialog,
    this.subtitleBuilder,
    this.isBot = false,
    this.placeholderBackground = const Color(0xFFE8F0F7),
    this.placeholderForeground = const Color(0xFF4F6B7A),
  });

  bool get _isMe => nickname == game.playerName;

  /// Whether this viewer may swap the photo: their own, and only while the
  /// paid item is active and unexpired. The server re-checks at token
  /// issuance, so this only decides what the tap offers.
  bool _canEditPhoto(Map? inner) {
    if (!_isMe) return false;
    if (inner?['profilePhotoStatus'] != 'active') return false;
    final expires = inner?['profilePhotoExpiresAt'] as String?;
    if (expires == null) return true;
    return DateTime.tryParse(expires)?.isAfter(DateTime.now()) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final inner = profile?['profile'] as Map?;
    // Our own photo comes from the live value rather than the fetched profile:
    // right after an upload the profile payload is still the old one.
    final rawPhoto =
        _isMe ? game.myPhotoUrl : inner?['photoUrl'] as String?;
    final resolved = game.resolvePhotoUrl(rawPhoto);
    final isBlockedUser = game.isBlocked(nickname);
    final editable = _canEditPhoto(inner);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildAvatar(context, resolved, isBlockedUser, editable),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3E312A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (subtitleBuilder != null)
                    subtitleBuilder!(inner)
                  else
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF84766E),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (!isBot && !_isMe) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _friendButton(context, l10n),
              _blockButton(context, l10n, isBlockedUser),
              _iconButton(
                icon: Icons.flag,
                color: const Color(0xFFE57373),
                tooltip: l10n.gameReport,
                onTap: () {
                  onCloseDialog();
                  showProfileReportDialog(context, nickname, game);
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    String? resolved,
    bool blocked,
    bool editable,
  ) {
    final avatar = ProfileAvatar(
      photoUrl: resolved,
      size: 38,
      borderRadius: 12,
      blocked: blocked,
      fallback: SizedBox(
        width: 38,
        height: 38,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: placeholderBackground,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Icon(Icons.person_outline, color: placeholderForeground),
        ),
      ),
    );

    // Nothing to tap when there is neither a photo to enlarge nor a right to
    // replace one — a dead tap target reads as a broken button.
    final showsPhoto = resolved != null && !blocked;
    if (!showsPhoto && !editable) return avatar;

    return GestureDetector(
      onTap: () {
        if (editable) {
          changeProfilePhoto(context, game);
        } else {
          showEnlargedProfilePhoto(context, resolved!, nickname);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: editable
                    ? const Color(0xFF6C63FF)
                    : Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(
                editable ? Icons.edit : Icons.zoom_in,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendButton(BuildContext context, L10n l10n) {
    if (game.friends.contains(nickname)) {
      return _iconButton(
        icon: Icons.check,
        color: const Color(0xFFBDBDBD),
        tooltip: l10n.gameAlreadyFriend,
        onTap: () {},
      );
    }
    if (game.sentFriendRequests.contains(nickname)) {
      return _iconButton(
        icon: Icons.hourglass_top,
        color: const Color(0xFFBDBDBD),
        tooltip: l10n.gameRequestPending,
        onTap: () {},
      );
    }
    return _iconButton(
      icon: Icons.person_add,
      color: const Color(0xFF81C784),
      tooltip: l10n.gameAddFriend,
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        game.addFriendAction(nickname);
        onCloseDialog();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.gameFriendRequestSent)),
        );
      },
    );
  }

  Widget _blockButton(BuildContext context, L10n l10n, bool blocked) {
    return _iconButton(
      icon: blocked ? Icons.block : Icons.shield_outlined,
      color: blocked ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
      tooltip: blocked ? l10n.gameUnblock : l10n.gameBlock,
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        if (blocked) {
          game.unblockUserAction(nickname);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.gameUnblocked)),
          );
        } else {
          game.blockUserAction(nickname);
          messenger.showSnackBar(SnackBar(content: Text(l10n.gameBlocked)));
        }
      },
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// Full-screen look at someone's profile photo. Pinch to zoom, tap to leave.
void showEnlargedProfilePhoto(
  BuildContext context,
  String url,
  String nickname,
) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  // A plain Image, not ProfileAvatar: that one is built to
                  // crop to a fixed square, which is the opposite of what
                  // "let me see it properly" means.
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              nickname,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One change at a time. The upload no longer blocks the screen, so nothing
/// stops a second tap — and the server invalidates the previous token when it
/// issues a new one, which would fail the upload already in flight.
bool _changeInFlight = false;

/// Pick a source, crop, upload — the flow behind tapping your own avatar.
///
/// The upload runs in the background. An earlier version threw a full-screen
/// barrier over everything until it finished, which was fine in a lobby and
/// bad everywhere else: the barrier outlived the screen it was raised on, so a
/// host starting the game mid-upload left the player unable to touch their own
/// first turn. Nothing here is worth blocking a game for — it is a cosmetic
/// that can land whenever it lands.
Future<void> changeProfilePhoto(BuildContext context, GameService game) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (_changeInFlight) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.profilePhotoUploadBusy)));
    return;
  }
  // Both taken before the first await: the sheet and the picker are long
  // enough gaps that the context can be gone by the time we come back.
  final navigator = Navigator.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              l10n.profilePhotoSourceTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded,
                color: Color(0xFF6C63FF)),
            title: Text(l10n.profilePhotoFromCamera),
            onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded,
                color: Color(0xFF6C63FF)),
            title: Text(l10n.profilePhotoFromGallery),
            onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return; // dismissed the sheet

  // An OverlayEntry rather than a dialog route: insert/remove are synchronous,
  // and it rides above whatever screen the player moves to while the upload
  // runs. It ignores pointers, so riding along costs them nothing.
  OverlayEntry? notice;
  final PhotoUploadResult result;
  _changeInFlight = true;
  try {
    result = await ProfilePhotoService.pickAndUpload(
      game,
      source: source,
      // Square it here rather than letting the server centre-crop blind —
      // that is what was lopping the top off portraits.
      crop: (bytes) => navigator.push(
        MaterialPageRoute(builder: (_) => PhotoCropScreen(bytes: bytes)),
      ),
      // Upload can take the full 30s timeout on a bad connection. Say so, or
      // the photo simply doesn't change and the user assumes it failed.
      onUploadBegin: () {
        notice = OverlayEntry(
          builder: (_) => _UploadingNotice(label: l10n.profilePhotoUploading),
        );
        overlay.insert(notice!);
      },
    );
  } finally {
    notice?.remove();
    _changeInFlight = false;
  }

  if (result.cancelled) return;

  // A denial can only be undone in system settings, so a snackbar telling them
  // to go there is a dead end — offer to take them.
  if (result.error == 'camera_denied' || result.error == 'photo_denied') {
    final camera = result.error == 'camera_denied';
    // The context this was called with belongs to the profile dialog, which is
    // very likely gone by now — the user was off in the system picker. The
    // navigator outlives all of it.
    if (!navigator.mounted) return;
    await _promptOpenSettings(
      navigator.context,
      title: camera
          ? l10n.profilePhotoCameraDeniedTitle
          : l10n.profilePhotoPhotoDeniedTitle,
      body: camera
          ? l10n.profilePhotoCameraDeniedBody
          : l10n.profilePhotoPhotoDeniedBody,
    );
    return;
  }

  final String msg;
  if (result.ok) {
    msg = l10n.profilePhotoChanged;
  } else if (result.error == 'no_active_item') {
    msg = l10n.profilePhotoNeedItem;
  } else if (result.error == 'image_rejected') {
    msg = l10n.profilePhotoRejected;
  } else if (result.error == 'moderation_unavailable') {
    msg = l10n.profilePhotoModerationDown;
  } else {
    msg = l10n.profilePhotoUploadFailed;
  }
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

/// Ask whether to jump to the system settings page for this app, and go there
/// if they say yes.
///
/// The channel is hand-rolled on both platforms (MainActivity.kt,
/// AppDelegate.swift). url_launcher can open `app-settings:` on iOS but has no
/// Android equivalent, and a permissions plugin would add a pod to a project
/// that has already lost time to CocoaPods conflicts.
const _appSettingsChannel = MethodChannel('com.jiny.tichuOnline/app_settings');

Future<void> _promptOpenSettings(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final l10n = L10n.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.profilePhotoOpenSettings),
        ),
      ],
    ),
  );
  if (go != true) return;
  try {
    await _appSettingsChannel.invokeMethod<bool>('openAppSettings');
  } on PlatformException {
    // Nothing useful to say — they are already looking at instructions that
    // name the settings screen.
  } on MissingPluginException {
    // Desktop/web builds have no host side; the dialog text still stands.
  }
}

/// A strip that says the upload is running, without taking the screen away.
/// Wrapped in IgnorePointer so every tap goes straight through to the game
/// underneath — the whole point of moving the upload to the background.
class _UploadingNotice extends StatelessWidget {
  final String label;
  const _UploadingNotice({required this.label});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 12,
      right: 12,
      bottom: media.padding.bottom + 16,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Report someone. One copy for all six popups; Skull King and the lobby had
/// no report button at all because neither had a copy of this.
void showProfileReportDialog(
  BuildContext context,
  String nickname,
  GameService game,
) {
  final reasonController = TextEditingController();
  final l10n = L10n.of(context);
  final reasons = [
    l10n.gameReportReasonAbuse,
    l10n.gameReportReasonSpam,
    l10n.gameReportReasonNickname,
    l10n.gameReportReasonGameplay,
    l10n.gameReportReasonOther,
  ];
  String? selectedReason;
  final rootMessenger = ScaffoldMessenger.of(context);

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setLocalState) {
        final media = MediaQuery.of(ctx);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.flag, color: Color(0xFFE57373)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.gameReportTitle(nickname),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: media.size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF0C7C7)),
                      ),
                      child: Text(
                        l10n.gameReportWarning,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9A4A4A),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.gameSelectReason,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: reasons.map((r) {
                        final isSelected = selectedReason == r;
                        return InkWell(
                          onTap: () => setLocalState(() => selectedReason = r),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFDDECF7)
                                  : const Color(0xFFF6F2F0),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF9EC5E6)
                                    : const Color(0xFFE2D8D4),
                              ),
                            ),
                            child: Text(
                              r,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? const Color(0xFF3E6D8E)
                                    : const Color(0xFF6A5A52),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: l10n.gameReportDetailHint,
                        filled: true,
                        fillColor: const Color(0xFFF7F2F0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0D6D1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0D6D1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFB9A8A1)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.gameCancel),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () {
                        final detail = reasonController.text.trim();
                        final reason = detail.isEmpty
                            ? selectedReason!
                            : '${selectedReason!} / $detail';
                        Navigator.pop(ctx);
                        game.reportResultSuccess = null;
                        game.reportResultMessage = null;
                        game.reportUserAction(nickname, reason);
                        // Drop the listener on a timer too, in case the server
                        // never answers — otherwise it outlives the dialog.
                        late void Function() listener;
                        Timer? cleanupTimer;
                        listener = () {
                          if (game.reportResultMessage != null) {
                            game.removeListener(listener);
                            cleanupTimer?.cancel();
                            final success = game.reportResultSuccess == true;
                            rootMessenger.showSnackBar(
                              SnackBar(
                                content: Text(game.reportResultMessage!),
                                backgroundColor:
                                    success ? null : const Color(0xFFE57373),
                              ),
                            );
                            game.reportResultSuccess = null;
                            game.reportResultMessage = null;
                          }
                        };
                        game.addListener(listener);
                        cleanupTimer = Timer(const Duration(seconds: 10), () {
                          game.removeListener(listener);
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.gameReportSubmit),
              ),
            ],
          ),
        );
      },
    ),
  );
}

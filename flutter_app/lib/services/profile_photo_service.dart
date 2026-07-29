import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'game_service.dart';

/// Outcome of a pick-and-upload attempt. [cancelled] means the user backed out
/// of the picker (not an error to surface). [error] is a machine reason the
/// caller maps to a localized message.
class PhotoUploadResult {
  final bool ok;
  final bool cancelled;
  final String? url;
  final String? error;
  const PhotoUploadResult.success(this.url)
      : ok = true,
        cancelled = false,
        error = null;
  const PhotoUploadResult.cancelled()
      : ok = false,
        cancelled = true,
        url = null,
        error = null;
  const PhotoUploadResult.failure(this.error)
      : ok = false,
        cancelled = false,
        url = null;
}

/// Profile-photo picking + upload. The app is otherwise WebSocket-only; this is
/// the one HTTP multipart flow. Steps: pick from gallery or camera -> request a
/// one-time WS upload token -> POST the image to /upload/profile-photo. The
/// server strips EXIF, squares to 512, and re-encodes, so no client-side crop
/// is needed.
class ProfilePhotoService {
  static final ImagePicker _picker = ImagePicker();

  static MediaType _mediaTypeFor(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) {
      final parts = mime.split('/');
      return MediaType(parts[0], parts.length > 1 ? parts[1] : 'jpeg');
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  /// Pick an image and upload it as the caller's profile photo.
  ///
  /// [source] is the user's choice of camera or gallery. Neither needs a
  /// permission we declare ourselves: iOS 14+ picks through PHPicker (out of
  /// process, no prompt) and asks for the camera under NSCameraUsageDescription
  /// on its own, while on Android both go out as intents to the system apps.
  static Future<PhotoUploadResult> pickAndUpload(
    GameService game, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
    } on PlatformException catch (e) {
      // Worth separating from a generic failure: the user has to go to system
      // Settings to undo it, and "upload failed, try again" would send them
      // round the same loop forever.
      if (e.code == 'camera_access_denied' || e.code == 'photo_access_denied') {
        return const PhotoUploadResult.failure('camera_denied');
      }
      return const PhotoUploadResult.failure('picker_error');
    } catch (_) {
      return const PhotoUploadResult.failure('picker_error');
    }
    if (file == null) return const PhotoUploadResult.cancelled();

    // One-time token (server also re-checks eligibility on the HTTP request).
    final tok = await game.requestUploadToken();
    if (tok.token == null) {
      return PhotoUploadResult.failure(tok.error ?? 'no_token');
    }

    try {
      final bytes = await file.readAsBytes();
      final uri = Uri.parse('${game.httpBase}/upload/profile-photo');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${tok.token}'
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'avatar.jpg',
          contentType: _mediaTypeFor(file),
        ));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final url = body['url'] as String?;
        game.setMyPhotoUrl(game.resolvePhotoUrl(url));
        return PhotoUploadResult.success(url);
      }
      String reason = 'upload_failed';
      try {
        reason = (jsonDecode(resp.body) as Map<String, dynamic>)['error']
                as String? ??
            reason;
      } catch (_) {}
      return PhotoUploadResult.failure(reason);
    } catch (_) {
      return const PhotoUploadResult.failure('network_error');
    }
  }
}

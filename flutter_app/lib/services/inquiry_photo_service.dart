import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'game_service.dart';
import 'profile_photo_service.dart';

/// One picture attached to an inquiry that is still being written. [bytes] is
/// only for the thumbnail; what the server wants back on submit is [key].
class InquiryAttachment {
  final Uint8List bytes;
  final String key;
  const InquiryAttachment(this.bytes, this.key);
}

/// Outcome of attaching one picture. Mirrors PhotoUploadResult: [cancelled] is
/// the user backing out of the picker, not an error to show.
class InquiryPhotoResult {
  final InquiryAttachment? attachment;
  final bool cancelled;
  final String? error;
  const InquiryPhotoResult.success(InquiryAttachment this.attachment)
    : cancelled = false,
      error = null;
  const InquiryPhotoResult.cancelled()
    : attachment = null,
      cancelled = true,
      error = null;
  const InquiryPhotoResult.failure(this.error)
    : attachment = null,
      cancelled = false;
}

/// Picks a picture and uploads it for an inquiry. One instance per open
/// inquiry form: it holds the server token, which covers several uploads, so
/// attaching three pictures costs one WS round trip rather than three.
class InquiryPhotoSession {
  static final ImagePicker _picker = ImagePicker();

  String? _token;
  int _usesLeft = 0;
  DateTime _issuedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // The server token lives 10 minutes; asking again a minute early avoids a 401
  // on an upload the user did nothing wrong in.
  static const _tokenLife = Duration(minutes: 9);

  bool get _tokenUsable =>
      _token != null &&
      _usesLeft > 0 &&
      DateTime.now().difference(_issuedAt) < _tokenLife;

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

  Future<InquiryPhotoResult> pickAndUpload(GameService game) async {
    ProfilePhotoService.configurePicker();
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      if (e.code == 'photo_access_denied') {
        return const InquiryPhotoResult.failure('photo_denied');
      }
      return const InquiryPhotoResult.failure('picker_error');
    } catch (_) {
      return const InquiryPhotoResult.failure('picker_error');
    }
    if (file == null) return const InquiryPhotoResult.cancelled();

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return const InquiryPhotoResult.failure('picker_error');
    }

    // Asked for after picking, for the same reason the avatar flow does it:
    // the user's own deliberation shouldn't eat the token's lifetime.
    if (!_tokenUsable) {
      final tok = await game.requestInquiryUploadToken();
      if (tok.token == null) {
        return InquiryPhotoResult.failure(tok.error ?? 'no_token');
      }
      _token = tok.token;
      _usesLeft = tok.maxPhotos;
      _issuedAt = DateTime.now();
    }
    // Spent before the request, not after: the server counts an attempt as a
    // use even when the upload then fails, so a retry must not assume it's free.
    _usesLeft -= 1;

    try {
      final uri = Uri.parse('${game.httpBase}/upload/inquiry-photo');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $_token'
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: file.name.isNotEmpty ? file.name : 'photo.jpg',
            contentType: _mediaTypeFor(file),
          ),
        );
      final streamed = await req.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final key = body['key'] as String?;
        if (key == null) {
          return const InquiryPhotoResult.failure('upload_failed');
        }
        return InquiryPhotoResult.success(InquiryAttachment(bytes, key));
      }
      var reason = 'upload_failed';
      try {
        reason =
            (jsonDecode(resp.body) as Map<String, dynamic>)['error']
                as String? ??
            reason;
      } catch (_) {}
      return InquiryPhotoResult.failure(reason);
    } catch (_) {
      return const InquiryPhotoResult.failure('network_error');
    }
  }
}

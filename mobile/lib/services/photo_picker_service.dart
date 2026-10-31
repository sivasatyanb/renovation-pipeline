import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

/// Container for a picked room photo's binary data and metadata.
class PickedRoomPhoto {
  final Uint8List bytes;
  final String mimeType;
  final String label;

  PickedRoomPhoto({
    required this.bytes,
    required this.mimeType,
    required this.label,
  });
}

/// Service for picking photos from gallery, camera, or bundled sample asset.
class PhotoPickerService {
  final ImagePicker _picker;

  PhotoPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Pick an image from the device's photo gallery.
  Future<PickedRoomPhoto?> pickFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return PickedRoomPhoto(
        bytes: bytes,
        mimeType: _detectMimeType(file.path),
        label: file.name.isNotEmpty ? file.name : 'Gallery Photo',
      );
    } catch (_) {
      return null;
    }
  }

  /// Pick an image from the device camera.
  Future<PickedRoomPhoto?> pickFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return PickedRoomPhoto(
        bytes: bytes,
        mimeType: _detectMimeType(file.path),
        label: file.name.isNotEmpty ? file.name : 'Camera Photo',
      );
    } catch (_) {
      return null;
    }
  }

  /// Load the bundled sample room photo fixture.
  Future<PickedRoomPhoto> loadSampleRoom() async {
    final byteData =
        await rootBundle.load('assets/shared/fixtures/demo_render/before.jpg');
    final bytes = byteData.buffer.asUint8List();
    return PickedRoomPhoto(
      bytes: bytes,
      mimeType: 'image/jpeg',
      label: 'Sample Japandi Room',
    );
  }
}

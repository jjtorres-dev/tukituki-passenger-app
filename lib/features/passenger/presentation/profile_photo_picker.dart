import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Foto ya leída en memoria, lista para preview local y para subir.
class PickedProfilePhoto {
  const PickedProfilePhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// Formatos que el backend acepta para `PASSENGER_PROFILE_PHOTO`
/// (`IMAGE_MIME_TYPES` en `storage-category.policy.ts`) — nunca PDF.
const List<String> profilePhotoAllowedContentTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

const Map<String, String> _extensionContentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// La foto seleccionada no está en un formato que el backend acepta
/// para esta categoría.
class ProfilePhotoUnsupportedFormatException implements Exception {
  const ProfilePhotoUnsupportedFormatException();
}

typedef ProfilePhotoPicker = Future<PickedProfilePhoto?> Function(ImageSource);

/// Punto de inyección mínimo para pruebas: reemplaza la selección real
/// de imagen sin acoplar la pantalla a `image_picker` dentro de los
/// tests (mismo criterio que `driverOnboardingPhotoPickerOverride` en
/// el conductor).
@visibleForTesting
ProfilePhotoPicker? profilePhotoPickerOverride;

Future<PickedProfilePhoto?> pickProfilePhoto(ImageSource source) {
  final override = profilePhotoPickerOverride;

  if (override != null) {
    return override(source);
  }

  return _pickFromDevice(source);
}

Future<PickedProfilePhoto?> _pickFromDevice(ImageSource source) async {
  final picker = ImagePicker();

  final xFile = await picker.pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1600,
  );

  if (xFile == null) {
    // El usuario canceló cámara/galería: no es un error.
    return null;
  }

  final bytes = await xFile.readAsBytes();
  final contentType = xFile.mimeType ?? _guessContentType(xFile.path);

  if (contentType == null ||
      !profilePhotoAllowedContentTypes.contains(contentType)) {
    throw const ProfilePhotoUnsupportedFormatException();
  }

  return PickedProfilePhoto(bytes: bytes, contentType: contentType);
}

String? _guessContentType(String path) {
  final dotIndex = path.lastIndexOf('.');

  if (dotIndex == -1 || dotIndex == path.length - 1) {
    return null;
  }

  final extension = path.substring(dotIndex + 1).toLowerCase();

  return _extensionContentTypes[extension];
}

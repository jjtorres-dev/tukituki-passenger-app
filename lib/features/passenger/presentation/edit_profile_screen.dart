import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/passenger_colors.dart';
import '../../../core/theme/passenger_spacing.dart';
import '../../../core/theme/passenger_typography.dart';
import '../../../core/widgets/tuki_text_field.dart';
import '../data/passenger_photo_uploader.dart';
import '../data/passenger_profile_repository.dart';
import '../data/passenger_storage_repository.dart';
import '../domain/passenger_profile.dart';
import 'passenger_avatar.dart';
import 'profile_photo_picker.dart';

/// Pantalla "Editar perfil" (PROFILE-MENU-R1).
///
/// Se abre desde la cabecera del menú de perfil de Home por
/// `Navigator.push` (mismo patrón que `OfferFareScreen` /
/// `SearchDestinationScreen`), **no** por una ruta de `go_router`: no
/// participa del resolver de sesión (`splash_screen.dart`), a
/// diferencia de `CompleteProfileScreen`, que es parte del gate de
/// identidad y por eso rebota por `/splash`.
///
/// Recibe los valores iniciales por constructor. **Contrato de pop**:
/// la pantalla devuelve por `Navigator.pop` el `PassengerProfile` más
/// fresco tras CUALQUIER mutación exitosa —foto (subir / reemplazar /
/// quitar) o nombre/correo—, o `null` si nunca hubo una. Esa regla
/// aplica por igual a "Guardar cambios", a la flecha de "Volver" y al
/// caso "sin cambios": la foto se sube al instante (no al guardar), así
/// que salir con la flecha después de cambiarla igual tiene que
/// propagar el perfil nuevo a Home.
///
/// No importa nada privado de `complete_profile_screen.dart`: los
/// validadores 2–80 y el `_FieldLabel` se duplican a propósito, misma
/// convención de duplicación deliberada entre pantallas que ya usa el
/// repo (Haversine, rango de oferta, formateo de soles).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialFirstName,
    required this.initialLastName,
    required this.initialEmail,
    required this.initialPhoneE164,
    this.initialPhotoUrl,
  });

  final String initialFirstName;
  final String initialLastName;

  /// Correo actual del pasajero, o `null` si todavía no cargó uno.
  final String? initialEmail;

  /// Teléfono actual (E.164). Se muestra como solo lectura — no se
  /// puede editar desde esta pantalla.
  final String initialPhoneE164;

  /// Foto de perfil actual (URL resuelta por el backend), o `null` si el
  /// pasajero todavía no cargó una. Opcional a propósito: el menú
  /// lateral la pasará en la sub-etapa 2c; hoy, abierta desde Home,
  /// entra `null` y el pasajero puede cargar una desde acá.
  final String? initialPhotoUrl;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _firstNameController = TextEditingController(
    text: widget.initialFirstName,
  );
  late final TextEditingController _lastNameController = TextEditingController(
    text: widget.initialLastName,
  );
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );

  bool _loading = false;
  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;

  /// URL de la foto que se muestra en el avatar ahora mismo. Arranca en
  /// `widget.initialPhotoUrl` y se actualiza tras subir/quitar. `null`
  /// ⇒ ícono genérico.
  late String? _photoUrlActual = widget.initialPhotoUrl;

  /// `true` mientras corre una operación de foto (pick → presign →
  /// upload → complete → refetch, o quitar). Bloquea el disparador de
  /// foto y "Guardar cambios".
  bool _uploadingPhoto = false;

  /// Error de la última operación de foto, mostrado debajo del botón de
  /// foto con el mismo tratamiento visual que `_emailError`.
  String? _photoError;

  /// Perfil más fresco tras cualquier mutación exitosa (foto o
  /// nombre/correo). Es lo que se devuelve por `pop` — ver contrato en
  /// el doc de la clase. `null` mientras no hubo ninguna mutación.
  PassengerProfile? _profileResult;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Mismos límites que `CreatePassengerProfileDto` en el Backend
  // (2–80 caracteres, con `trim`). Duplicados a propósito desde
  // `CompleteProfileScreen` — ver nota de la clase.
  String? _validateFirstName(String value) {
    final text = value.trim();

    if (text.length < 2) {
      return 'Ingresa tus nombres';
    }

    if (text.length > 80) {
      return 'Máximo 80 caracteres';
    }

    return null;
  }

  String? _validateLastName(String value) {
    final text = value.trim();

    if (text.length < 2) {
      return 'Ingresa tus apellidos';
    }

    if (text.length > 80) {
      return 'Máximo 80 caracteres';
    }

    return null;
  }

  // Validación laxa a propósito: nunca debe rechazar algo que el
  // Backend (`@IsEmail()`) sí aceptaría — el Backend es la fuente de
  // verdad del formato. Vacío es válido (el campo es opcional); si hay
  // algo, solo se atrapan typos evidentes (falta `@`, sin punto en el
  // dominio, espacios) y el tope de 255 caracteres del Backend.
  static final RegExp _laxEmailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _validateEmail(String value) {
    final text = value.trim();

    if (text.isEmpty) {
      return null;
    }

    if (text.length > 255) {
      return 'Máximo 255 caracteres';
    }

    if (!_laxEmailPattern.hasMatch(text)) {
      return 'Ingresa un correo válido';
    }

    return null;
  }

  bool get _formValid =>
      _validateFirstName(_firstNameController.text) == null &&
      _validateLastName(_lastNameController.text) == null &&
      _validateEmail(_emailController.text) == null;

  void _handleFieldChanged() {
    // Feedback en vivo del estado del botón (mismo criterio que
    // `OfferFareScreen` con `_amountValid`). Solo se limpia un error ya
    // visible; no se muestra uno nuevo hasta intentar guardar.
    if (_firstNameError != null ||
        _lastNameError != null ||
        _emailError != null) {
      setState(() {
        _firstNameError = _validateFirstName(_firstNameController.text);
        _lastNameError = _validateLastName(_lastNameController.text);
        _emailError = _validateEmail(_emailController.text);
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _save() async {
    final firstNameError = _validateFirstName(_firstNameController.text);
    final lastNameError = _validateLastName(_lastNameController.text);
    final emailError = _validateEmail(_emailController.text);

    setState(() {
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
      _emailError = emailError;
    });

    if (firstNameError != null || lastNameError != null || emailError != null) {
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    final emailNow = _emailController.text.trim();
    final emailInitial = (widget.initialEmail ?? '').trim();
    final emailChanged = emailNow != emailInitial;

    // Sin cambios de nombre/correo → no se llama al backend. Se
    // devuelve `_profileResult`: `null` si tampoco se tocó la foto, o el
    // perfil ya refrescado si la foto sí cambió antes.
    if (firstName == widget.initialFirstName.trim() &&
        lastName == widget.initialLastName.trim() &&
        !emailChanged) {
      Navigator.pop(context, _profileResult);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final repository = ref.read(passengerProfileRepositoryProvider);

    try {
      // `email` solo se pasa si cambió: así el repo deja la clave fuera
      // del body (centinela) cuando no se tocó, y manda `null` explícito
      // cuando se vació un correo que tenía valor (= borrar en Backend).
      final PassengerProfile updated = emailChanged
          ? await repository.updateMyProfile(
              firstName: firstName,
              lastName: lastName,
              email: emailNow.isEmpty ? null : emailNow,
            )
          : await repository.updateMyProfile(
              firstName: firstName,
              lastName: lastName,
            );

      if (!mounted) {
        return;
      }

      _profileResult = updated;
      Navigator.pop(context, _profileResult);
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo guardar tu perfil.';

      final statusCode = error.response?.statusCode;
      if (statusCode == 400) {
        message = 'Revisa los datos ingresados.';
      } else if (statusCode == 404) {
        message = 'No encontramos tu perfil.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar tu perfil.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Abre la hoja con las opciones de foto y dirige según lo elegido.
  /// Guard `_uploadingPhoto`/`_loading` al frente para que un segundo
  /// toque mientras una operación corre no abra otra hoja.
  Future<void> _openPhotoSheet() async {
    if (_uploadingPhoto || _loading) {
      return;
    }

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: PassengerColors.crema,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PassengerSpacing.radioHojaCrema),
        ),
      ),
      builder: (_) => _PhotoSourceSheet(canRemove: _photoUrlActual != null),
    );

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _PhotoAction.camera:
        await _uploadFromSource(ImageSource.camera);
      case _PhotoAction.gallery:
        await _uploadFromSource(ImageSource.gallery);
      case _PhotoAction.remove:
        await _removePhoto();
    }
  }

  /// pick → presign → PUT al bucket → complete → refetch del perfil.
  /// `mounted` se re-chequea después de cada await porque son varios
  /// saltos async y la pantalla puede cerrarse en el medio.
  Future<void> _uploadFromSource(ImageSource source) async {
    setState(() {
      _uploadingPhoto = true;
      _photoError = null;
    });

    final storage = ref.read(passengerStorageRepositoryProvider);
    final uploader = ref.read(passengerPhotoUploaderProvider);
    final profileRepo = ref.read(passengerProfileRepositoryProvider);

    try {
      final picked = await pickProfilePhoto(source);

      // `null` ⇒ el usuario canceló cámara/galería: no es un error, se
      // aborta en silencio (el `finally` apaga el spinner).
      if (picked == null || !mounted) {
        return;
      }

      final presigned = await storage.presignProfilePhotoUpload(
        contentType: picked.contentType,
        fileSize: picked.bytes.length,
      );
      if (!mounted) {
        return;
      }

      await uploader.upload(
        uploadUrl: presigned.uploadUrl,
        contentType: presigned.contentType,
        bytes: picked.bytes,
      );
      if (!mounted) {
        return;
      }

      await storage.completeProfilePhotoUpload(objectKey: presigned.objectKey);
      if (!mounted) {
        return;
      }

      // El endpoint de complete no devuelve el perfil; un GET trae la
      // `photoUrl` recién resuelta por el backend.
      final refreshedJson = await profileRepo.getMyProfile();
      if (!mounted) {
        return;
      }

      if (refreshedJson != null) {
        final refreshed = PassengerProfile.fromJson(refreshedJson);
        setState(() {
          _profileResult = refreshed;
          _photoUrlActual = refreshed.photoUrl;
        });
      }
    } on ProfilePhotoUnsupportedFormatException {
      _setPhotoError('Elige una foto en formato JPG, PNG o WEBP.');
    } on PlatformException {
      _setPhotoError(
        'No pudimos acceder a la cámara o galería. Revisa los permisos.',
      );
    } on DioException catch (error) {
      final isPresign = error.requestOptions.path.contains(
        'storage/uploads/presign',
      );

      if (isPresign && error.response?.statusCode == 400) {
        _setPhotoError('La foto es demasiado grande. Prueba con otra.');
      } else {
        _setPhotoError('No pudimos subir tu foto. Inténtalo nuevamente.');
      }
    } catch (error) {
      debugPrint('Error inesperado actualizando la foto de perfil: $error');
      _setPhotoError('No pudimos actualizar tu foto.');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
        });
      }
    }
  }

  /// DELETE `passengers/me/photo` — ya devuelve el perfil actualizado,
  /// sin GET extra.
  Future<void> _removePhoto() async {
    setState(() {
      _uploadingPhoto = true;
      _photoError = null;
    });

    final profileRepo = ref.read(passengerProfileRepositoryProvider);

    try {
      final updated = await profileRepo.removeMyPhoto();
      if (!mounted) {
        return;
      }

      setState(() {
        _profileResult = updated;
        _photoUrlActual = updated.photoUrl; // queda `null`
      });
    } catch (error) {
      debugPrint('Error quitando la foto de perfil: $error');
      _setPhotoError('No pudimos quitar tu foto. Inténtalo nuevamente.');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
        });
      }
    }
  }

  void _setPhotoError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _photoError = message;
    });
  }

  /// Preview ampliado de la foto de perfil al tocar el avatar. Mismo
  /// mecanismo que `_showDriverPhotoViewer` en
  /// `ride_searching_screen.dart` (R4.3C): `showDialog` liviano, sin
  /// ruta nueva — se cierra con tap fuera (`barrierDismissible`), el
  /// botón X o el back de Android. Sin `Hero` ni `InteractiveViewer`,
  /// igual que el precedente. Duplicado a propósito: el del conductor
  /// es un método de `_State` acoplado a esa pantalla (constantes
  /// privadas, nombre del conductor) que acá no aplica — mismo criterio
  /// de duplicación de piezas chicas del repo.
  void _showPhotoViewer(String photoUrl) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          key: const ValueKey('edit-profile-photo-viewer'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(dialogContext).size.width * 0.85,
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    photoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        key: const ValueKey('edit-profile-photo-viewer-error'),
                        width: 220,
                        height: 220,
                        color: PassengerColors.blanco,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar la foto',
                          textAlign: TextAlign.center,
                          style: PassengerTypography.cuerpo.copyWith(
                            color: PassengerColors.textoSecundario,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  key: const ValueKey('edit-profile-photo-viewer-close'),
                  icon: const Icon(Icons.close, color: PassengerColors.blanco),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    shape: const CircleBorder(),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PassengerColors.crema,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: (_loading || _uploadingPhoto)
                        ? null
                        : () => Navigator.pop(context, _profileResult),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                  Text(
                    'Editar perfil',
                    style: PassengerTypography.tituloSeccion.copyWith(
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: PassengerSpacing.margenLateralPantalla,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _buildPhotoBlock(),
                    const SizedBox(
                      height: PassengerSpacing.espacioEntreCampos,
                    ),
                    const _FieldLabel('Nombres'),
                    const SizedBox(
                      height: PassengerSpacing.espacioEtiquetaCampo,
                    ),
                    TukiTextField(
                      controller: _firstNameController,
                      hintText: 'Juan José',
                      textInputAction: TextInputAction.next,
                      errorText: _firstNameError,
                      autofillHints: const [AutofillHints.givenName],
                      onChanged: (_) => _handleFieldChanged(),
                    ),
                    const SizedBox(
                      height: PassengerSpacing.espacioEntreCampos,
                    ),
                    const _FieldLabel('Apellidos'),
                    const SizedBox(
                      height: PassengerSpacing.espacioEtiquetaCampo,
                    ),
                    TukiTextField(
                      controller: _lastNameController,
                      hintText: 'Torres Solano',
                      textInputAction: TextInputAction.done,
                      errorText: _lastNameError,
                      autofillHints: const [AutofillHints.familyName],
                      onChanged: (_) => _handleFieldChanged(),
                    ),
                    const SizedBox(
                      height: PassengerSpacing.espacioEntreCampos,
                    ),
                    const _FieldLabel('Correo electrónico (opcional)'),
                    const SizedBox(
                      height: PassengerSpacing.espacioEtiquetaCampo,
                    ),
                    TukiTextField(
                      controller: _emailController,
                      hintText: 'juan@ejemplo.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      errorText: _emailError,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) => _handleFieldChanged(),
                    ),
                    const SizedBox(
                      height: PassengerSpacing.espacioEntreCampos,
                    ),
                    const _FieldLabel('Número de celular'),
                    const SizedBox(
                      height: PassengerSpacing.espacioEtiquetaCampo,
                    ),
                    _ReadOnlyPhoneRow(phoneE164: widget.initialPhoneE164),
                    const SizedBox(
                      height: PassengerSpacing.espacioEntreCampos,
                    ),
                  ],
                ),
              ),
            ),
            _buildCtaFooter(),
          ],
        ),
      ),
    );
  }

  /// Bloque de foto arriba de "Nombres": avatar de 96px centrado (con
  /// spinner encima mientras sube), botón "Cambiar foto" / "Agregar
  /// foto" según haya foto o no, y la línea de error `_photoError`
  /// debajo con el mismo tratamiento visual que el error de un
  /// `TukiTextField`.
  Widget _buildPhotoBlock() {
    final hasPhoto = _photoUrlActual != null;

    // El avatar es tocable (abre el visor ampliado) solo si hay una
    // foto real y no hay una subida en curso. Sin foto no hay nada que
    // agrandar; durante la subida el avatar muestra el spinner. El
    // botón "Cambiar foto" / "Agregar foto" de abajo es una zona de tap
    // aparte, nunca se superpone con esta.
    final photoTappable = hasPhoto && !_uploadingPhoto;

    final Widget avatar = PassengerAvatar(
      photoUrl: _photoUrlActual,
      diameter: 96,
      overlay: _uploadingPhoto
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PassengerColors.blanco,
              ),
            )
          : null,
    );

    return Column(
      children: [
        if (photoTappable)
          GestureDetector(
            key: const ValueKey('edit-profile-photo-avatar-tap'),
            onTap: () => _showPhotoViewer(_photoUrlActual!),
            child: avatar,
          )
        else
          avatar,
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('edit-profile-photo-trigger'),
          onPressed: (_uploadingPhoto || _loading) ? null : _openPhotoSheet,
          child: Text(
            hasPhoto ? 'Cambiar foto' : 'Agregar foto',
            style: PassengerTypography.enlace.copyWith(
              color: PassengerColors.acento,
            ),
          ),
        ),
        if (_photoError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _photoError!,
              textAlign: TextAlign.center,
              style: PassengerTypography.pista.copyWith(
                color: PassengerColors.error,
              ),
            ),
          ),
      ],
    );
  }

  /// Botón principal siguiendo `sistema-de-diseno.md` §5: fondo
  /// `amarilloCTA`/radio `radioCampoBoton` habilitado; deshabilitado
  /// sin relleno, borde 1.5px `bordeBotonInactivo`, texto
  /// `textoBotonInactivo`, con la línea explicativa `notaBotonInactivo`
  /// (12/500) debajo — mismo `WidgetStateProperty.resolveWith` que
  /// `OfferFareScreen` y `register_screen.dart`.
  Widget _buildCtaFooter() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final canSave = _formValid && !_loading && !_uploadingPhoto;

    return Container(
      decoration: const BoxDecoration(
        color: PassengerColors.crema,
        border: Border(top: BorderSide(color: PassengerColors.bordeSuave)),
      ),
      child: SafeArea(
        top: false,
        bottom: !keyboardVisible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: PassengerSpacing.alturaBotonPrincipal,
                child: FilledButton(
                  key: const ValueKey('edit-profile-save-button'),
                  onPressed: canSave ? _save : null,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? PassengerColors.crema
                          : PassengerColors.amarilloCTA,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? PassengerColors.textoBotonInactivo
                          : PassengerColors.textoPrimario,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? const BorderSide(
                              color: PassengerColors.bordeBotonInactivo,
                              width: 1.5,
                            )
                          : BorderSide.none,
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          PassengerSpacing.radioCampoBoton,
                        ),
                      ),
                    ),
                    textStyle: WidgetStatePropertyAll(
                      PassengerTypography.botonPrincipal,
                    ),
                    elevation: const WidgetStatePropertyAll(0),
                  ),
                  child: _loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: PassengerColors.textoPrimario,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('Guardando...'),
                          ],
                        )
                      : const Text('Guardar cambios'),
                ),
              ),
              if (!_formValid) ...[
                const SizedBox(height: 8),
                Text(
                  'Revisa los datos: nombres y apellidos de 2 a 80 '
                  'caracteres y, si cargas un correo, que tenga un formato '
                  'válido.',
                  style: PassengerTypography.notaBotonInactivo.copyWith(
                    color: PassengerColors.textoSecundario,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de solo lectura para el número de celular.
///
/// NO es un campo editable a propósito: el teléfono es la identidad de
/// login (`User.phoneE164`, único) y no se puede cambiar desde acá
/// hasta que exista un flujo de reverificación (OTP-R3). Sin
/// `TextField`, sin foco, sin `onTap` — solo texto dentro de un
/// contenedor visualmente distinto de un campo activo (fondo `crema`,
/// borde `bordeSuave`, candado) más una nota debajo.
class _ReadOnlyPhoneRow extends StatelessWidget {
  const _ReadOnlyPhoneRow({required this.phoneE164});

  final String phoneE164;

  @override
  Widget build(BuildContext context) {
    final display = phoneE164.trim().isEmpty ? 'No disponible' : phoneE164;

    return Semantics(
      label: 'Número de celular, no editable: $display',
      readOnly: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: PassengerColors.crema,
              borderRadius: BorderRadius.circular(
                PassengerSpacing.radioCampoBoton,
              ),
              border: Border.all(color: PassengerColors.bordeSuave),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    display,
                    style: PassengerTypography.cuerpo.copyWith(
                      color: PassengerColors.textoSecundario,
                    ),
                  ),
                ),
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: PassengerColors.textoSecundario,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No puedes cambiar tu número desde aquí.',
            style: PassengerTypography.notaBotonInactivo.copyWith(
              color: PassengerColors.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que el usuario elige en la hoja de opciones de foto.
enum _PhotoAction { camera, gallery, remove }

/// Hoja inferior con las fuentes de foto. "Quitar foto" solo aparece
/// cuando ya hay una cargada, y en estilo destructivo (`error`).
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet({required this.canRemove});

  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('edit-profile-photo-sheet-camera'),
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: PassengerColors.verdeMarca,
              ),
              title: Text(
                'Tomar una foto',
                style: PassengerTypography.cuerpo.copyWith(
                  color: PassengerColors.textoPrimario,
                ),
              ),
              onTap: () => Navigator.pop(context, _PhotoAction.camera),
            ),
            ListTile(
              key: const ValueKey('edit-profile-photo-sheet-gallery'),
              leading: const Icon(
                Icons.photo_library_outlined,
                color: PassengerColors.verdeMarca,
              ),
              title: Text(
                'Elegir de galería',
                style: PassengerTypography.cuerpo.copyWith(
                  color: PassengerColors.textoPrimario,
                ),
              ),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            if (canRemove)
              ListTile(
                key: const ValueKey('edit-profile-photo-sheet-remove'),
                leading: const Icon(
                  Icons.delete_outline,
                  color: PassengerColors.error,
                ),
                title: Text(
                  'Quitar foto',
                  style: PassengerTypography.cuerpo.copyWith(
                    color: PassengerColors.error,
                  ),
                ),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
            ListTile(
              key: const ValueKey('edit-profile-photo-sheet-cancel'),
              title: Text(
                'Cancelar',
                style: PassengerTypography.cuerpo.copyWith(
                  color: PassengerColors.textoSecundario,
                ),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta encima de un campo (13/600 `verdeMarca`), ver
/// `sistema-de-diseno.md` §5 "Campo de texto". Mismo widget que
/// `login_screen.dart` / `register_screen.dart` / `complete_profile_screen.dart`,
/// duplicado a propósito (es privado en cada archivo).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PassengerTypography.etiquetaCampo.copyWith(
        color: PassengerColors.verdeMarca,
      ),
    );
  }
}

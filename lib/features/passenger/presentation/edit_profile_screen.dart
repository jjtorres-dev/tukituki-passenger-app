import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/passenger_colors.dart';
import '../../../core/theme/passenger_spacing.dart';
import '../../../core/theme/passenger_typography.dart';
import '../../../core/widgets/tuki_text_field.dart';
import '../data/passenger_profile_repository.dart';
import '../domain/passenger_profile.dart';

/// Pantalla "Editar perfil" (PROFILE-MENU-R1).
///
/// Se abre desde la cabecera del menú de perfil de Home por
/// `Navigator.push` (mismo patrón que `OfferFareScreen` /
/// `SearchDestinationScreen`), **no** por una ruta de `go_router`: no
/// participa del resolver de sesión (`splash_screen.dart`), a
/// diferencia de `CompleteProfileScreen`, que es parte del gate de
/// identidad y por eso rebota por `/splash`.
///
/// Recibe los valores iniciales por constructor. Al guardar devuelve el
/// `PassengerProfile` actualizado por `Navigator.pop`; si no hubo
/// cambios reales (tras `trim`) hace `pop(null)` sin tocar la red.
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
  });

  final String initialFirstName;
  final String initialLastName;

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

  bool _loading = false;
  String? _firstNameError;
  String? _lastNameError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
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

  bool get _formValid =>
      _validateFirstName(_firstNameController.text) == null &&
      _validateLastName(_lastNameController.text) == null;

  void _handleFieldChanged() {
    // Feedback en vivo del estado del botón (mismo criterio que
    // `OfferFareScreen` con `_amountValid`). Solo se limpia un error ya
    // visible; no se muestra uno nuevo hasta intentar guardar.
    if (_firstNameError != null || _lastNameError != null) {
      setState(() {
        _firstNameError = _validateFirstName(_firstNameController.text);
        _lastNameError = _validateLastName(_lastNameController.text);
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _save() async {
    final firstNameError = _validateFirstName(_firstNameController.text);
    final lastNameError = _validateLastName(_lastNameController.text);

    setState(() {
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
    });

    if (firstNameError != null || lastNameError != null) {
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    // Sin cambios reales → no se llama al backend, se vuelve sin
    // resultado (Home conserva el perfil que ya tenía).
    if (firstName == widget.initialFirstName.trim() &&
        lastName == widget.initialLastName.trim()) {
      Navigator.pop(context, null);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    try {
      final PassengerProfile updated = await ref
          .read(passengerProfileRepositoryProvider)
          .updateMyProfile(firstName: firstName, lastName: lastName);

      if (!mounted) {
        return;
      }

      Navigator.pop(context, updated);
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
                    onPressed: _loading ? null : () => Navigator.pop(context),
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

  /// Botón principal siguiendo `sistema-de-diseno.md` §5: fondo
  /// `amarilloCTA`/radio `radioCampoBoton` habilitado; deshabilitado
  /// sin relleno, borde 1.5px `bordeBotonInactivo`, texto
  /// `textoBotonInactivo`, con la línea explicativa `notaBotonInactivo`
  /// (12/500) debajo — mismo `WidgetStateProperty.resolveWith` que
  /// `OfferFareScreen` y `register_screen.dart`.
  Widget _buildCtaFooter() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final canSave = _formValid && !_loading;

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
                  'Ingresa nombres y apellidos (2 a 80 caracteres) para '
                  'guardar.',
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

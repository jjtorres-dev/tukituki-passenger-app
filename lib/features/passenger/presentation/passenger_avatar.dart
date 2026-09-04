import 'package:flutter/material.dart';

import '../../../core/theme/passenger_colors.dart';

/// Avatar del pasajero, reutilizable.
///
/// Sin [photoUrl] (o vacío) dibuja el mismo círculo `acento` con
/// `Icons.person` blanco que usaba el `_Avatar` privado del menú de
/// perfil. Con [photoUrl] muestra la imagen recortada en círculo; si la
/// carga falla, cae SIEMPRE al ícono genérico — nunca deja el avatar en
/// blanco.
///
/// [overlay] se dibuja centrado encima (p. ej. un spinner mientras se
/// sube una foto nueva).
class PassengerAvatar extends StatelessWidget {
  const PassengerAvatar({
    super.key,
    this.photoUrl,
    this.diameter = 40,
    this.overlay,
  });

  final String? photoUrl;
  final double diameter;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPhoto)
            ClipOval(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              ),
            )
          else
            _fallback(),
          if (overlay != null)
            ClipOval(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: overlay),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: PassengerColors.acento,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        color: PassengerColors.blanco,
        size: diameter * 0.55,
      ),
    );
  }
}

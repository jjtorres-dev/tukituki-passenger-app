import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/passenger_colors.dart';
import '../theme/passenger_spacing.dart';
import '../theme/passenger_typography.dart';

/// Red de seguridad del router: se muestra ante cualquier ruta que
/// `go_router` no logra resolver (vía `errorBuilder` en [appRouter]).
///
/// Reemplaza al `ErrorScreen` por defecto de go_router, cuyo botón
/// "Home" navega a `/` — una ruta que no existe en esta app y dejaba al
/// usuario sin salida (fue exactamente lo que pasó cuando una
/// notificación push abría la app cerrada con una ruta inválida; ver
/// `push_message_handler.dart` y el rename `route` → `screen` del
/// backend).
///
/// El único botón navega a `/splash`, el resolver de sesión: siempre
/// existe y decide el destino real del pasajero (Home, Login o
/// Completar perfil).
///
/// Mismo criterio que `RouteNotFoundScreen` de la app del conductor.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PassengerColors.crema,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PassengerSpacing.margenLateralPantalla,
            28,
            PassengerSpacing.margenLateralPantalla,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: PassengerColors.verdeMarca,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.explore_off_rounded,
                            color: PassengerColors.amarilloCTA,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Pantalla no encontrada',
                          textAlign: TextAlign.center,
                          style: PassengerTypography.tituloPantalla.copyWith(
                            color: PassengerColors.verdeMarca,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'La pantalla que intentabas abrir no está '
                          'disponible. Volvamos al inicio para continuar.',
                          textAlign: TextAlign.center,
                          style: PassengerTypography.subtitulo.copyWith(
                            color: PassengerColors.textoSecundario,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: PassengerSpacing.alturaBotonPrincipal,
                child: FilledButton(
                  key: const Key('route-not-found-home-button'),
                  onPressed: () => context.go('/splash'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PassengerColors.amarilloCTA,
                    foregroundColor: PassengerColors.textoPrimario,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        PassengerSpacing.radioCampoBoton,
                      ),
                    ),
                    textStyle: PassengerTypography.botonPrincipal,
                  ),
                  child: const Text('Volver al inicio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

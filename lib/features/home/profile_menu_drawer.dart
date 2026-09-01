import 'package:flutter/material.dart';

import '../../core/theme/passenger_colors.dart';
import '../../core/theme/passenger_spacing.dart';
import '../../core/theme/passenger_typography.dart';
import '../passenger/domain/passenger_profile.dart';

/// Panel de menú de perfil (PROFILE-MENU-R1), montado en el slot
/// `Scaffold.drawer` de Home y abierto SOLO por tap del botón de 3
/// rayas (`drawerEnableOpenDragGesture: false` — nunca por swipe, para
/// no competir con el `EagerGestureRecognizer` del `GoogleMap`).
///
/// Con `drawerEnableOpenDragGesture: false`, Flutter desmonta este
/// widget mientras el drawer está cerrado y lo vuelve a montar en cada
/// apertura, así que `initState`/`_runLoad()` corre fresco por
/// apertura y `initialProfile` se re-lee siempre — no hace falta
/// `didUpdateWidget` ni key de generación.
///
/// Cabecera tocable con el nombre y la calificación del pasajero, y un
/// único ítem debajo: "Cerrar sesión". Maneja su propio estado
/// `loading/failed/loaded` para poder reintentar la carga sin cerrar el
/// panel.
///
/// La confirmación del logout NO vive acá: [onLogout] se dispara
/// directo y Home muestra el diálogo de "¿Seguro?".
class ProfileMenuDrawer extends StatefulWidget {
  const ProfileMenuDrawer({
    super.key,
    required this.initialProfile,
    required this.loader,
    required this.onEditProfile,
    required this.onLogout,
  });

  /// Último perfil conocido por Home (valor "tibio"): se muestra al
  /// instante mientras el refresh corre en segundo plano.
  final PassengerProfile? initialProfile;

  /// Vuelve a pedir el perfil al backend. Devuelve `null` si falló o si
  /// el backend respondió 404. Home pasa acá su propio `_loadProfile`,
  /// que además refresca el estado de Home como efecto secundario.
  final Future<PassengerProfile?> Function() loader;

  final VoidCallback onEditProfile;
  final VoidCallback onLogout;

  @override
  State<ProfileMenuDrawer> createState() => _ProfileMenuDrawerState();
}

class _ProfileMenuDrawerState extends State<ProfileMenuDrawer> {
  PassengerProfile? _profile;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _runLoad();
  }

  Future<void> _runLoad() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final loaded = await widget.loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        if (loaded != null) {
          _profile = loaded;
        } else if (_profile == null) {
          // El refresh falló/404 y no hay nada cacheado que mostrar.
          _failed = true;
        }
        // Con cache, un refresh fallido se ignora en silencio.
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        if (_profile == null) {
          _failed = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: PassengerColors.crema,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Misma franja de status bar que el body de Home: iconos
            // claros sobre `verdeMarca`, no sobre `crema`.
            SizedBox(
              height: MediaQuery.paddingOf(context).top,
              child: const ColoredBox(color: PassengerColors.verdeMarca),
            ),
            _buildHeader(),
            const Divider(height: 1, color: PassengerColors.bordeSuave),
            InkWell(
              key: const ValueKey('profile-menu-logout'),
              onTap: widget.onLogout,
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: PassengerSpacing.margenLateralPantalla,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.logout,
                      size: 22,
                      color: PassengerColors.textoPrimario,
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final profile = _profile;

    if (profile != null) {
      return InkWell(
        key: const ValueKey('profile-menu-header'),
        onTap: widget.onEditProfile,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PassengerSpacing.margenLateralPantalla,
            vertical: 12,
          ),
          child: Row(
            children: [
              const _Avatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile.firstName} ${profile.lastName}'.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PassengerTypography.cuerpo.copyWith(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildRating(profile),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: PassengerColors.textoSecundario,
              ),
            ],
          ),
        ),
      );
    }

    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PassengerSpacing.margenLateralPantalla,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _Avatar(),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'No pudimos cargar tu perfil',
                    style: TextStyle(
                      color: PassengerColors.textoSecundario,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('profile-menu-retry'),
                onPressed: _loading ? null : _runLoad,
                child: Text(
                  'Reintentar',
                  style: PassengerTypography.enlace.copyWith(
                    color: PassengerColors.acento,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Cargando, sin nada cacheado.
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PassengerSpacing.margenLateralPantalla,
        vertical: 12,
      ),
      child: Row(
        children: [
          _Avatar(),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Cargando tu perfil…',
              style: TextStyle(
                color: PassengerColors.textoSecundario,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRating(PassengerProfile profile) {
    if (!profile.hasRating) {
      return Container(
        key: const ValueKey('profile-menu-new-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: PassengerColors.inactivo,
          borderRadius: BorderRadius.circular(PassengerSpacing.radioPildora),
        ),
        child: const Text(
          'Nuevo',
          style: TextStyle(
            color: PassengerColors.textoSecundario,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return _StarRow(average: profile.ratingAverage);
  }
}

/// Ícono de persona genérico en círculo `acento` (blanco sobre verde) —
/// mismo tratamiento que el punto de "Origen" en
/// `_buildOriginDestinationCard`. Sin foto real: subir foto de perfil
/// está fuera de alcance en este checkpoint.
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: PassengerColors.acento,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person,
        color: PassengerColors.blanco,
        size: 22,
      ),
    );
  }
}

/// 5 estrellas, redondeando el promedio al 0.5 más cercano.
/// `Icons.star` (llena) / `Icons.star_half` (media) / `Icons.star_border`
/// (vacía) por posición. Mismo color de estrella que `_RatingSection`
/// en `ride_receipt_screen.dart` (`amarilloCTA` para llena/media,
/// `bordeSuave` para vacía).
class _StarRow extends StatelessWidget {
  const _StarRow({required this.average});

  final double average;

  @override
  Widget build(BuildContext context) {
    final rounded = (average * 2).round() / 2;

    return Row(
      key: const ValueKey('profile-menu-rating'),
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final position = index + 1;

        final IconData icon;
        if (rounded >= position) {
          icon = Icons.star;
        } else if (rounded >= position - 0.5) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }

        return Icon(
          icon,
          size: 18,
          color: icon == Icons.star_border
              ? PassengerColors.bordeSuave
              : PassengerColors.amarilloCTA,
        );
      }),
    );
  }
}

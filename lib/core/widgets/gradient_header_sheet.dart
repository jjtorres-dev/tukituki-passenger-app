import 'package:flutter/material.dart';

import '../theme/passenger_colors.dart';
import '../theme/passenger_spacing.dart';

/// Reparte el alto de una pantalla de auth entre un header con
/// degradado y una hoja crema, dejando que el CONTENIDO de la hoja
/// mande: la hoja mide lo que su contenido necesita (padding superior
/// e inferior ceñidos, sin estirarse) y el header absorbe todo el
/// espacio sobrante de la pantalla, hasta un máximo razonable.
///
/// El límite del header se expresa como [headerMinLogoHeight] +
/// 2×[PassengerSpacing.superposicionHojaCrema] (el mínimo en el que el
/// header solo tiene aire justo para que la superposición de la hoja
/// nunca tape el logo) más [headerGrowthBudget] (cuánto más puede
/// crecer por encima de ese mínimo antes de tope). Cuando el header
/// llega a su tope, el sobrante entre el tope y el resto de la
/// pantalla vuelve a la hoja como padding extra (se centra el
/// contenido dentro de ese espacio de más) en vez de quedar como aire
/// vacío detrás del header.
///
/// Con el teclado abierto, el mismo cálculo hace que el header se
/// comprima (nunca por debajo de su mínimo) y que la hoja pueda
/// crecer y hacer scroll, igual que antes de este cambio.
class GradientHeaderSheet extends StatelessWidget {
  const GradientHeaderSheet({
    super.key,
    required this.logoAsset,
    required this.sheetChildren,
    this.tagline,
    this.leadingAction,
    this.logoAspectRatio = 1024 / 1536,
    this.headerMinLogoWidth = 92,
    this.headerMaxLogoWidth = 150,
    this.headerGrowthBudget = 220,
    this.headerLogoGap = 8,
    this.taglineHeight = 20,
    this.sheetTopPadding = 28,
    this.sheetBottomPadding = 20,
    this.gradientColors = const [
      PassengerColors.verdeClaro,
      PassengerColors.verdeMarca,
      PassengerColors.verdeProfundo,
    ],
    this.gradientStops = const [0.0, 0.55, 1.0],
  });

  final String logoAsset;
  final List<Widget> sheetChildren;

  /// Se oculta cuando el header se comprime a su mínimo (sin importar
  /// la razón: teclado, pantalla baja, etc.).
  final Widget? tagline;

  /// Widget opcional a la izquierda del header (p. ej. la flecha de
  /// volver de Register). Se pinta aparte del logo, en un `Stack`, para
  /// que el logo se siga centrando en el ancho completo del header sin
  /// que este widget le quite espacio ni lo desplace.
  final Widget? leadingAction;

  final double logoAspectRatio;
  final double headerMinLogoWidth;
  final double headerMaxLogoWidth;
  final double headerGrowthBudget;
  final double headerLogoGap;
  final double taglineHeight;
  final double sheetTopPadding;
  final double sheetBottomPadding;
  final List<Color> gradientColors;
  final List<double> gradientStops;

  @override
  Widget build(BuildContext context) {
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final minLogoHeight = headerMinLogoWidth * logoAspectRatio;
    final headerMinHeight =
        statusBarInset +
        minLogoHeight +
        2 * PassengerSpacing.superposicionHojaCrema;
    final headerMaxHeight = headerMinHeight + headerGrowthBudget;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final sheetMinHeight = (totalHeight - headerMaxHeight).clamp(
          0.0,
          totalHeight,
        );
        final sheetMaxHeight = (totalHeight - headerMinHeight).clamp(
          0.0,
          totalHeight,
        );

        return Column(
          children: [
            Expanded(
              child: _Header(
                logoAsset: logoAsset,
                tagline: tagline,
                leadingAction: leadingAction,
                logoAspectRatio: logoAspectRatio,
                headerMinLogoWidth: headerMinLogoWidth,
                headerMaxLogoWidth: headerMaxLogoWidth,
                headerMinHeight: headerMinHeight,
                headerMaxHeight: headerMaxHeight,
                headerLogoGap: headerLogoGap,
                taglineHeight: taglineHeight,
                statusBarInset: statusBarInset,
                gradientColors: gradientColors,
                gradientStops: gradientStops,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: sheetMinHeight,
                maxHeight: sheetMaxHeight,
              ),
              child: Transform.translate(
                offset: const Offset(
                  0,
                  -PassengerSpacing.superposicionHojaCrema,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: PassengerColors.crema,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(PassengerSpacing.radioHojaCrema),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: LayoutBuilder(
                      builder: (context, sheetConstraints) {
                        final availableContentHeight =
                            sheetConstraints.minHeight -
                            sheetTopPadding -
                            sheetBottomPadding;

                        return SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            PassengerSpacing.margenLateralPantalla,
                            sheetTopPadding,
                            PassengerSpacing.margenLateralPantalla,
                            sheetBottomPadding,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: availableContentHeight > 0
                                  ? availableContentHeight
                                  : 0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: sheetChildren,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.logoAsset,
    required this.tagline,
    required this.leadingAction,
    required this.logoAspectRatio,
    required this.headerMinLogoWidth,
    required this.headerMaxLogoWidth,
    required this.headerMinHeight,
    required this.headerMaxHeight,
    required this.headerLogoGap,
    required this.taglineHeight,
    required this.statusBarInset,
    required this.gradientColors,
    required this.gradientStops,
  });

  final String logoAsset;
  final Widget? tagline;
  final Widget? leadingAction;
  final double logoAspectRatio;
  final double headerMinLogoWidth;
  final double headerMaxLogoWidth;
  final double headerMinHeight;
  final double headerMaxHeight;
  final double headerLogoGap;
  final double taglineHeight;
  final double statusBarInset;
  final List<Color> gradientColors;
  final List<double> gradientStops;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, headerConstraints) {
        final headerHeight = headerConstraints.maxHeight;
        final logoScale = headerMaxHeight > headerMinHeight
            ? ((headerHeight - headerMinHeight) /
                      (headerMaxHeight - headerMinHeight))
                  .clamp(0.0, 1.0)
            : 0.0;
        final logoWidth =
            headerMinLogoWidth +
            (headerMaxLogoWidth - headerMinLogoWidth) * logoScale;
        final logoHeight = logoWidth * logoAspectRatio;

        final availableForContent = (headerHeight - statusBarInset).clamp(
          0.0,
          headerHeight,
        );
        // Igual criterio que el enlace "¿Olvidaste tu contraseña?" de
        // la hoja: con el teclado abierto se oculta porque el espacio
        // es escaso justo cuando el usuario está escribiendo, no
        // porque el header se haya comprimido por otra razón (p. ej.
        // una pantalla baja, donde sigue cabiendo perfectamente).
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        final showTagline = tagline != null && !keyboardVisible;

        final contentBlockHeight =
            logoHeight + (showTagline ? headerLogoGap + taglineHeight : 0);
        final topGap = ((availableForContent - contentBlockHeight) / 2)
            .clamp(0.0, availableForContent);
        final logoCenterY = statusBarInset + topGap + logoHeight / 2;
        final gradientCenterY = ((logoCenterY / headerHeight) * 2 - 1).clamp(
          -1.0,
          1.0,
        );

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, gradientCenterY),
              radius: 1.0,
              colors: gradientColors,
              stops: gradientStops,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: statusBarInset),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        logoAsset,
                        width: logoWidth,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      if (showTagline) ...[
                        SizedBox(height: headerLogoGap),
                        tagline!,
                      ],
                    ],
                  ),
                ),
              ),
              // Se pinta aparte del Center de arriba, en el mismo
              // Stack, para que el logo se siga centrando en el ancho
              // completo del header sin que esto le quite espacio.
              if (leadingAction != null)
                Padding(
                  padding: EdgeInsets.only(top: statusBarInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leadingAction,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

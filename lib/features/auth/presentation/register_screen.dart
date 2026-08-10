import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'otp_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _cream = Color(0xFFFFF9EC);
  static const Color _fieldFill = Color(0xFFFFFDF7);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF6F7E72);

  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading || !_acceptedTerms) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').trim();

    final phoneE164 = '+51$phone';
    final password = _passwordController.text;

    try {
      final repository = ref.read(authRepositoryProvider);

      await repository.registerPassenger(
        phoneE164: phoneE164,
        password: password,
      );

      final debugOtp = await repository.requestOtp(phoneE164: phoneE164);

      if (!mounted) {
        return;
      }

      context.push(
        '/otp',
        extra: OtpArguments(
          phoneE164: phoneE164,
          password: password,
          debugOtp: debugOtp,
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo crear la cuenta.';

      if (error.response?.statusCode == 409) {
        message =
            'Este número ya está registrado. '
            'Intenta iniciar sesión.';
      } else if (error.response?.statusCode == 400) {
        message = 'Revisa los datos ingresados.';
      } else if (error.response?.statusCode == 429) {
        message =
            'Espera un momento antes de solicitar '
            'otro código.';
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
        const SnackBar(content: Text('Ocurrió un error inesperado.')),
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
    final compact = MediaQuery.sizeOf(context).height < 700;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _darkGreen,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHero(compact: compact, keyboardVisible: keyboardVisible),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _cream,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        keyboardVisible ? 14 : 24,
                        24,
                        keyboardVisible ? 12 : 20,
                      ),
                      child: _buildForm(keyboardVisible),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero({required bool compact, required bool keyboardVisible}) {
    final logoWidth = keyboardVisible ? 78.0 : (compact ? 116.0 : 132.0);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_darkGreen, _green],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          keyboardVisible ? 2 : (compact ? 6 : 10),
          8,
          keyboardVisible ? 6 : (compact ? 12 : 18),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Volver',
                onPressed: _loading
                    ? null
                    : () {
                        context.pop();
                      },
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/tukituki_logo.png',
                  width: logoWidth,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                SizedBox(height: keyboardVisible ? 1 : 5),
                Text(
                  'Crea tu cuenta de pasajero',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool keyboardVisible) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crea tu cuenta',
            style: TextStyle(
              color: _primaryText,
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Completa tus datos para comenzar.',
            style: TextStyle(
              color: _secondaryText,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
          SizedBox(height: keyboardVisible ? 14 : 22),
          _buildPhoneField(),
          const SizedBox(height: 14),
          _buildPasswordField(),
          const SizedBox(height: 9),
          _buildPasswordStrength(),
          const SizedBox(height: 12),
          _buildConfirmationField(keyboardVisible),
          SizedBox(height: keyboardVisible ? 10 : 14),
          _buildTermsAcceptance(),
          SizedBox(height: keyboardVisible ? 10 : 14),
          _buildSubmitButton(),
          const SizedBox(height: 10),
          _buildLoginLink(),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      cursorColor: _green,
      style: const TextStyle(
        color: _primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Número de celular',
        hintText: '999 999 999',
        filled: true,
        fillColor: _fieldFill,
        prefixIconConstraints: const BoxConstraints(minWidth: 78),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 16, right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+51',
                style: TextStyle(
                  color: _darkGreen,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 10),
              SizedBox(
                height: 24,
                child: VerticalDivider(width: 1, thickness: 1, color: _border),
              ),
            ],
          ),
        ),
        border: _fieldBorder(_border),
        enabledBorder: _fieldBorder(_border),
        focusedBorder: _fieldBorder(_green, width: 2),
        errorBorder: _fieldBorder(const Color(0xFFB3261E)),
        focusedErrorBorder: _fieldBorder(const Color(0xFFB3261E), width: 2),
      ),
      validator: (value) {
        final phone = value?.replaceAll(' ', '').trim() ?? '';

        if (!RegExp(r'^[0-9]{9}$').hasMatch(phone)) {
          return 'Ingresa un número válido de 9 dígitos';
        }

        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      onChanged: (_) {
        setState(() {});
      },
      cursorColor: _green,
      style: const TextStyle(
        color: _primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Contraseña',
        filled: true,
        fillColor: _fieldFill,
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: _secondaryText,
        ),
        suffixIcon: IconButton(
          tooltip: _obscurePassword
              ? 'Mostrar contraseña'
              : 'Ocultar contraseña',
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: _secondaryText,
          ),
        ),
        border: _fieldBorder(_border),
        enabledBorder: _fieldBorder(_border),
        focusedBorder: _fieldBorder(_green, width: 2),
        errorBorder: _fieldBorder(const Color(0xFFB3261E)),
        focusedErrorBorder: _fieldBorder(const Color(0xFFB3261E), width: 2),
      ),
      validator: (value) {
        if (value == null || value.length < 8) {
          return 'Usa al menos 8 caracteres';
        }

        if (value.length > 64) {
          return 'La contraseña es demasiado larga';
        }

        final hasLowercase = RegExp(r'[a-z]').hasMatch(value);
        final hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
        final hasNumber = RegExp(r'[0-9]').hasMatch(value);

        if (!hasLowercase || !hasUppercase || !hasNumber) {
          return 'La contraseña debe incluir mayúscula, minúscula y número';
        }

        return null;
      },
    );
  }

  Widget _buildConfirmationField(bool keyboardVisible) {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmation,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      scrollPadding: EdgeInsets.only(bottom: keyboardVisible ? 190 : 20),
      cursorColor: _green,
      style: const TextStyle(
        color: _primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Confirmar contraseña',
        filled: true,
        fillColor: _fieldFill,
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: _secondaryText,
        ),
        suffixIcon: IconButton(
          tooltip: _obscureConfirmation
              ? 'Mostrar confirmación'
              : 'Ocultar confirmación',
          onPressed: () {
            setState(() {
              _obscureConfirmation = !_obscureConfirmation;
            });
          },
          icon: Icon(
            _obscureConfirmation
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: _secondaryText,
          ),
        ),
        border: _fieldBorder(_border),
        enabledBorder: _fieldBorder(_border),
        focusedBorder: _fieldBorder(_green, width: 2),
        errorBorder: _fieldBorder(const Color(0xFFB3261E)),
        focusedErrorBorder: _fieldBorder(const Color(0xFFB3261E), width: 2),
      ),
      validator: (value) {
        if (value != _passwordController.text) {
          return 'Las contraseñas no coinciden';
        }

        return null;
      },
    );
  }

  Widget _buildPasswordStrength() {
    final strength = _passwordStrength;
    final color = switch (strength) {
      _PasswordStrength.weak => const Color(0xFFB45309),
      _PasswordStrength.medium => const Color(0xFFD59A00),
      _PasswordStrength.strong => _green,
    };
    final level = switch (strength) {
      _PasswordStrength.weak => 1,
      _PasswordStrength.medium => 2,
      _PasswordStrength.strong => 3,
    };
    final label = switch (strength) {
      _PasswordStrength.weak => 'Débil',
      _PasswordStrength.medium => 'Media',
      _PasswordStrength.strong => 'Fuerte',
    };

    return Semantics(
      label: 'Fortaleza de contraseña: $label',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Fortaleza',
                style: TextStyle(
                  color: _secondaryText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: index < level ? color : _border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  _PasswordStrength get _passwordStrength {
    final password = _passwordController.text;
    var score = 0;

    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;

    if (score >= 5) {
      return _PasswordStrength.strong;
    }

    if (score >= 3) {
      return _PasswordStrength.medium;
    }

    return _PasswordStrength.weak;
  }

  Widget _buildTermsAcceptance() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _acceptedTerms,
          activeColor: _green,
          checkColor: Colors.white,
          side: const BorderSide(color: _secondaryText, width: 1.5),
          onChanged: _loading
              ? null
              : (value) {
                  setState(() {
                    _acceptedTerms = value ?? false;
                  });
                },
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Acepto los Términos y Condiciones y la Política de Privacidad',
              style: TextStyle(
                color: _secondaryText,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _loading || !_acceptedTerms ? null : _register,
        style: FilledButton.styleFrom(
          backgroundColor: _ctaYellow,
          foregroundColor: _darkGreen,
          disabledBackgroundColor: _border,
          disabledForegroundColor: _secondaryText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: _loading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _darkGreen,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Creando cuenta...'),
                ],
              )
            : const Text('Crear cuenta'),
      ),
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: _loading
          ? null
          : () {
              context.pop();
            },
      style: TextButton.styleFrom(
        foregroundColor: _green,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      child: const Text(
        '¿Ya tienes cuenta? Inicia sesión',
        textAlign: TextAlign.center,
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

enum _PasswordStrength { weak, medium, strong }

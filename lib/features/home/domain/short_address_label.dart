/// Versión corta de una dirección completa, usada por las tarjetas de
/// origen/destino de `home_screen.dart` y `offer_fare_screen.dart`
/// (`FARE-PANEL-R1`, etapa 5) y por la etiqueta del marcador flotante
/// de origen (`HOME-LAYOUT-R1`).
///
/// Heurística — nos quedamos con lo que hay antes de la primera coma.
/// Es frágil a propósito documentada, no una solución robusta: depende
/// de que el backend siga devolviendo `"calle y número,
/// distrito/ciudad, código postal, país"` (el formato de
/// `formatted_address` de Google Geocoding para direcciones de Perú).
/// Investigado (2026-08-25): el backend hoy SOLO expone ese string
/// completo — el tipo `GoogleGeocodingResponse` de
/// `google-geocoding.service.ts` (tukituki-backend) descarta el array
/// `address_components` que Google sí devuelve (con
/// `street_number`/`route` ya separados), y no hay ningún campo corto
/// en `OriginAddressResponseDto` ni en `FareQuoteLocationResponseDto`.
/// Agregar ese campo en el backend sería la solución correcta a
/// futuro, pero requeriría tocar `google-geocoding.service.ts` —
/// fuera de alcance de esta app.
///
/// Formatos que esta heurística rompe hoy: cualquier dirección sin
/// coma (la deja tal cual, sin acortar — ver el `commaIndex <= 0` de
/// abajo); una dirección donde la calle/número en sí contenga una
/// coma antes del punto que el usuario esperaría cortar (p. ej. un
/// interior/departamento tipo `"Jr. Lima 250, Int. 4, Tarapoto..."`
/// se corta en `"Jr. Lima 250"`, que en este caso sí es lo deseado,
/// pero no hay garantía de que Google mantenga siempre esa forma); y
/// direcciones fuera de Perú con otro orden de componentes (esta app
/// no opera fuera de Tarapoto hoy, así que no es un caso real todavía).
String shortAddressLabel(String address) {
  final trimmed = address.trim();
  final commaIndex = trimmed.indexOf(',');

  if (commaIndex <= 0) {
    return trimmed;
  }

  return trimmed.substring(0, commaIndex).trim();
}

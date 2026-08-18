/// Formatea un nombre para mostrar en UI: nombre + inicial del primer
/// apellido ("Juan Pérez" -> "Juan P."). Nunca se persiste el resultado
/// en Backend ni en almacenamiento local — se deriva solo para
/// presentación, en cada punto donde se necesite mostrarlo.
///
/// Defensivo ante datos legacy/incompletos: recorta espacios en los
/// extremos, nunca produce "null" ni un "." suelto, y nunca introduce
/// espacios dobles. Si ambos campos están vacíos, devuelve una cadena
/// vacía — el llamador decide qué mostrar en ese caso (p.ej. omitir la
/// fila del nombre), en vez de que este helper imponga un placeholder
/// como "Pasajero"/"Conductor"/"Usuario".
String displayCompactName(String? firstName, String? lastName) {
  final first = firstName?.trim() ?? '';
  final last = lastName?.trim() ?? '';

  if (first.isEmpty) {
    return '';
  }

  if (last.isEmpty) {
    return first;
  }

  final initial = last[0].toUpperCase();

  return '$first $initial.';
}

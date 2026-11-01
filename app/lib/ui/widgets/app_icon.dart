import 'package:flutter/material.dart';

/// El ícono de la app (frente de ómnibus azul marino sobre naranja), dibujado
/// con las mismas formas que el ícono adaptable de Android
/// (android/app/src/main/res/drawable/ic_launcher_foreground.xml), para que
/// la pantalla de inicio de sesión muestre exactamente el mismo ícono.
class AppIcon extends StatelessWidget {
  final double size;

  const AppIcon({super.key, this.size = 96});

  static const background = Color(0xFFFFA500);
  static const foreground = Color(0xFF000080);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'MiRuta',
      image: true,
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: _AppIconPainter())),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  // Rectángulo redondeado en coordenadas del ícono (lienzo de 108 × 108).
  static RRect _r(double left, double top, double right, double bottom, double radius) =>
      RRect.fromLTRBR(left, top, right, bottom, Radius.circular(radius));

  static Rect _circle(double x, double y, double radius) => Rect.fromCircle(center: Offset(x, y), radius: radius);

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo naranja con las esquinas redondeadas, como lo muestran los lanzadores.
    final bounds = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(size.width * 0.23));
    canvas.clipRRect(shape);
    canvas.drawRect(bounds, Paint()..color = AppIcon.background);

    // De Android solo se ve la zona central de 72 × 72 del lienzo de 108 × 108,
    // y el dibujo está reducido al 72 % alrededor del centro.
    canvas.scale(size.width / 72);
    canvas.translate(-18, -18);
    canvas.translate(54, 54);
    canvas.scale(0.72);
    canvas.translate(-54, -54);

    final paint = Paint()..color = AppIcon.foreground;

    // Carrocería con los huecos del letrero, el parabrisas, los faros y la rejilla.
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(_r(32, 24, 76, 76, 9))
      ..addRRect(_r(41, 28.5, 67, 33, 2.25))
      ..addRRect(_r(37, 37, 71, 57, 4))
      ..addOval(_circle(41.5, 66, 3.6))
      ..addOval(_circle(66.5, 66, 3.6))
      ..addRRect(_r(49, 64.5, 59, 67.5, 1.5));
    canvas.drawPath(body, paint);

    // Espejos, sus brazos y las ruedas.
    for (final part in [
      _r(25, 38, 30, 49, 2.5),
      _r(78, 38, 83, 49, 2.5),
      _r(28.75, 40.75, 35.25, 43.25, 1.25),
      _r(72.75, 40.75, 79.25, 43.25, 1.25),
      _r(36, 72, 45, 82, 2.5),
      _r(63, 72, 72, 82, 2.5),
    ]) {
      canvas.drawRRect(part, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Google, email, and Telegram marks in one row.
class SignInBrandRow extends StatelessWidget {
  const SignInBrandRow({
    super.key,
    required this.onGoogle,
    required this.onEmail,
    required this.onTelegram,
  });

  final VoidCallback onGoogle;
  final VoidCallback onEmail;
  final VoidCallback onTelegram;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SignInBrandButton(
          label: 'Sign in with Google',
          onPressed: onGoogle,
          child: const _Mark(mark: _BrandMark.google),
        ),
        const SizedBox(width: 18),
        SignInBrandButton(
          label: 'Sign in with email',
          onPressed: onEmail,
          child: const _EmailMark(),
        ),
        const SizedBox(width: 18),
        SignInBrandButton(
          label: 'Sign in with Telegram',
          onPressed: onTelegram,
          child: const _Mark(mark: _BrandMark.telegram),
        ),
      ],
    );
  }
}

class _EmailMark extends StatelessWidget {
  const _EmailMark();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(Icons.mail_outline, color: Color(0xFF1B3A2F), size: 26),
    );
  }
}

class SignInBrandButton extends StatelessWidget {
  const SignInBrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: 48, height: 48, child: child),
          ),
        ),
      ),
    );
  }
}

enum _BrandMark { google, telegram }

class _Mark extends StatelessWidget {
  const _Mark({required this.mark});

  final _BrandMark mark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BrandPainter(mark), size: const Size(48, 48));
  }
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.mark);

  final _BrandMark mark;

  @override
  void paint(Canvas canvas, Size size) {
    switch (mark) {
      case _BrandMark.google:
        _paintGoogle(canvas, size);
      case _BrandMark.telegram:
        _paintCutout(
          canvas,
          size,
          const Color(0xFF2AABEE),
          _telegram,
          const Size(24, 24),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.mark != mark;
}

void _paintGoogle(Canvas canvas, Size size) {
  canvas.drawCircle(
    size.center(Offset.zero),
    size.width / 2,
    Paint()..color = Colors.white,
  );
  final inset = size.width * 0.16;
  final side = size.width - inset * 2;
  canvas.save();
  canvas.translate(inset, inset);
  for (final part in _google) {
    canvas.drawPath(
      _scale(_svg(part.$1), const Size(48, 48), side),
      Paint()..color = part.$2,
    );
  }
  canvas.restore();
}

void _paintCutout(
  Canvas canvas,
  Size size,
  Color color,
  String source,
  Size viewBox,
) {
  canvas.drawCircle(
    size.center(Offset.zero),
    size.width / 2,
    Paint()..color = Colors.white,
  );
  final mark = _svg(source)..fillType = PathFillType.evenOdd;
  canvas.drawPath(_scale(mark, viewBox, size.width), Paint()..color = color);
}

Path _scale(Path source, Size viewBox, double side) {
  final matrix = Matrix4.identity()
    ..scaleByDouble(side / viewBox.width, side / viewBox.height, 1, 1);
  return source.transform(matrix.storage);
}

const _google = <(String, Color)>[
  (
    'M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z',
    Color(0xFFFFC107),
  ),
  (
    'M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z',
    Color(0xFFFF3D00),
  ),
  (
    'M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z',
    Color(0xFF4CAF50),
  ),
  (
    'M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z',
    Color(0xFF1976D2),
  ),
];

const _telegram =
    'M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.492-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z';

final _token = RegExp(
  r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?',
);

Path _svg(String data) {
  final tokens = _token
      .allMatches(data)
      .map((match) => match.group(0)!)
      .toList();
  final path = Path();
  var index = 0;
  var command = '';
  var current = Offset.zero;
  var start = Offset.zero;
  Offset? cubicControl;

  double read() => double.parse(tokens[index++]);
  bool isCommand(String token) => token.length == 1 && !_isNumber(token);

  while (index < tokens.length) {
    if (isCommand(tokens[index])) command = tokens[index++];
    final relative = command == command.toLowerCase();
    switch (command.toUpperCase()) {
      case 'M':
        final point = _abs(relative, current, Offset(read(), read()));
        path.moveTo(point.dx, point.dy);
        current = start = point;
        cubicControl = null;
        command = relative ? 'l' : 'L';
      case 'L':
        final point = _abs(relative, current, Offset(read(), read()));
        path.lineTo(point.dx, point.dy);
        current = point;
        cubicControl = null;
      case 'H':
        final x = relative ? current.dx + read() : read();
        path.lineTo(x, current.dy);
        current = Offset(x, current.dy);
        cubicControl = null;
      case 'V':
        final y = relative ? current.dy + read() : read();
        path.lineTo(current.dx, y);
        current = Offset(current.dx, y);
        cubicControl = null;
      case 'C':
        final c1 = _abs(relative, current, Offset(read(), read()));
        final c2 = _abs(relative, current, Offset(read(), read()));
        final point = _abs(relative, current, Offset(read(), read()));
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, point.dx, point.dy);
        cubicControl = c2;
        current = point;
      case 'S':
        final reflected = _reflect(current, cubicControl);
        final c2 = _abs(relative, current, Offset(read(), read()));
        final point = _abs(relative, current, Offset(read(), read()));
        path.cubicTo(
          reflected.dx,
          reflected.dy,
          c2.dx,
          c2.dy,
          point.dx,
          point.dy,
        );
        cubicControl = c2;
        current = point;
      case 'A':
        final rx = read();
        final ry = read();
        final rotation = read();
        final large = read() != 0;
        final sweep = read() != 0;
        final point = _abs(relative, current, Offset(read(), read()));
        _arc(path, current, rx, ry, rotation, large, sweep, point);
        current = point;
        cubicControl = null;
      case 'Z':
        path.close();
        current = start;
        cubicControl = null;
      default:
        throw FormatException('Unsupported SVG command $command');
    }
  }
  return path;
}

bool _isNumber(String token) => double.tryParse(token) != null;

Offset _abs(bool relative, Offset current, Offset point) {
  return relative ? current + point : point;
}

Offset _reflect(Offset current, Offset? control) {
  if (control == null) return current;
  return Offset(2 * current.dx - control.dx, 2 * current.dy - control.dy);
}

void _arc(
  Path path,
  Offset from,
  double rx,
  double ry,
  double rotationDegrees,
  bool largeArc,
  bool sweep,
  Offset to,
) {
  if (from == to) return;
  if (rx == 0 || ry == 0) {
    path.lineTo(to.dx, to.dy);
    return;
  }
  rx = rx.abs();
  ry = ry.abs();
  final rotation = rotationDegrees * math.pi / 180;
  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);
  final dx = (from.dx - to.dx) / 2;
  final dy = (from.dy - to.dy) / 2;
  final x1 = cosR * dx + sinR * dy;
  final y1 = -sinR * dx + cosR * dy;
  var rxSq = rx * rx;
  var rySq = ry * ry;
  final lambda = (x1 * x1) / rxSq + (y1 * y1) / rySq;
  if (lambda > 1) {
    final scale = math.sqrt(lambda);
    rx *= scale;
    ry *= scale;
    rxSq = rx * rx;
    rySq = ry * ry;
  }
  final sign = largeArc == sweep ? -1.0 : 1.0;
  final coefSq =
      ((rxSq * rySq - rxSq * y1 * y1 - rySq * x1 * x1) /
              (rxSq * y1 * y1 + rySq * x1 * x1))
          .clamp(0.0, double.infinity);
  final coef = sign * math.sqrt(coefSq);
  final cx1 = coef * rx * y1 / ry;
  final cy1 = coef * -ry * x1 / rx;
  final cx = cosR * cx1 - sinR * cy1 + (from.dx + to.dx) / 2;
  final cy = sinR * cx1 + cosR * cy1 + (from.dy + to.dy) / 2;

  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final length = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    final value = length == 0 ? 0.0 : (dot / length).clamp(-1.0, 1.0);
    final result = math.acos(value);
    return ux * vy - uy * vx < 0 ? -result : result;
  }

  final startAngle = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry);
  var sweepAngle = angle(
    (x1 - cx1) / rx,
    (y1 - cy1) / ry,
    (-x1 - cx1) / rx,
    (-y1 - cy1) / ry,
  );
  if (!sweep && sweepAngle > 0) sweepAngle -= 2 * math.pi;
  if (sweep && sweepAngle < 0) sweepAngle += 2 * math.pi;

  final segments = math.max(1, (sweepAngle.abs() / (math.pi / 2)).ceil());
  final delta = sweepAngle / segments;
  for (var i = 0; i < segments; i++) {
    final t1 = startAngle + delta * i;
    final t2 = t1 + delta;
    final alpha =
        math.sin(delta) *
        (math.sqrt(4 + 3 * math.pow(math.tan(delta / 2), 2)) - 1) /
        3;
    Offset onEllipse(double theta) {
      final x = rx * math.cos(theta);
      final y = ry * math.sin(theta);
      return Offset(cosR * x - sinR * y + cx, sinR * x + cosR * y + cy);
    }

    Offset derivative(double theta) {
      final x = -rx * math.sin(theta);
      final y = ry * math.cos(theta);
      return Offset(cosR * x - sinR * y, sinR * x + cosR * y);
    }

    final p1 = onEllipse(t1);
    final p2 = onEllipse(t2);
    final d1 = derivative(t1);
    final d2 = derivative(t2);
    path.cubicTo(
      p1.dx + alpha * d1.dx,
      p1.dy + alpha * d1.dy,
      p2.dx - alpha * d2.dx,
      p2.dy - alpha * d2.dy,
      p2.dx,
      p2.dy,
    );
  }
}

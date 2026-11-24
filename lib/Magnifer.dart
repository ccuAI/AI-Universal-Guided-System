import 'package:flutter/material.dart';

class CustomMagnifier extends StatefulWidget {
  const CustomMagnifier({super.key});

  @override
  State<CustomMagnifier> createState() =>
      _CustomMagnifierState();
}

class _CustomMagnifierState extends State<CustomMagnifier> {
  Offset _position = const Offset(60, 100);

  final double _size = 180;
  final double _scale = 2.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _size
            .clamp(0.0, constraints.biggest.shortestSide)
            .toDouble();

        final maxX = constraints.maxWidth - size;
        final maxY = constraints.maxHeight - size;

        final x = _position.dx.clamp(0.0, maxX).toDouble();
        final y = _position.dy.clamp(0.0, maxY).toDouble();

        return Stack(
          children: [
            Positioned(
              left: x,
              top: y,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    _position = Offset(
                      (x + details.delta.dx)
                          .clamp(0.0, maxX)
                          .toDouble(),
                      (y + details.delta.dy)
                          .clamp(0.0, maxY)
                          .toDouble(),
                    );
                  });
                },
                child: RawMagnifier(
                  size: Size(size, size),
                  magnificationScale: _scale,
                  focalPointOffset: Offset.zero,
                  decoration: const MagnifierDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        color: Colors.blue,
                        width: 3,
                      ),
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
import 'dart:typed_data';

import 'package:flutter/material.dart';

void createInteractiveImageViewer(Uint8List imageBytes, int imageWidth, int imageHeight, BuildContext context) {
  showDialog(
      context: context,
      builder: (innerContext) {
        return Dialog(
          child: LayoutBuilder(
              builder: (innerContext, constraints) {

                double aspectRatio = imageWidth / imageHeight;
                double translationY = 0.5*(constraints.maxHeight - (constraints.maxWidth / aspectRatio));
                double minScale = constraints.maxWidth / imageWidth;
                final scaleMatrix = Matrix4.identity()..scale(minScale);
                scaleMatrix.setEntry(1, 3, translationY);
                final viewTransformationController = TransformationController(scaleMatrix);
                return InteractiveViewer(
                    constrained: false,
                    clipBehavior: Clip.none,
                    minScale: minScale,
                    maxScale: 1,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    transformationController: viewTransformationController,
                    child: Image.memory(imageBytes)
                );
              }
          ),
        );
      }
  );
}
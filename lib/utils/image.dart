import 'package:image/image.dart' as img;
import 'dart:typed_data';

img.Image convertYuvToRgb(List<Uint8List> yuvPlanes, int width, int height, List<int> bytesPerRow) {

  final Uint8List yBytes = yuvPlanes[0];
  final Uint8List uBytes = yuvPlanes[1];
  final Uint8List vBytes = yuvPlanes[2];

  // Row strides determine the number of bytes in each row of the plane's data.
  // This might be wider than the actual image width due to padding.
  final int yRowStride = bytesPerRow[0];
  final int uvRowStride = bytesPerRow[1]; // Assume U/V planes have same stride
  // Pixel strides determine the distance between consecutive pixel values in a row.
  // For YUV420p, Y pixel stride is 1. U/V pixel stride is usually 1 for separate planes.
  // If it were 2, it might indicate interleaved U/V or padding between pixels.
  final int uvPixelStride = 1;

  // Create the img.Image object to store the RGB result
  img.Image image = img.Image(width: width, height: height); // Defaults to RGB format

  // --- Pixel-by-pixel conversion ---
  int yIndex = 0; // Current index in the Y plane byte buffer

  for (int y = 0; y < height; y++) {
    int uIndex = (y ~/ 2) * uvRowStride; // Start index for U row
    int vIndex = (y ~/ 2) * uvRowStride; // Start index for V row
    int yRowStartIndex = y * yRowStride; // Start index for Y row

    for (int x = 0; x < width; x++) {
      yIndex = yRowStartIndex + x;

      // Calculate the corresponding indices in the U and V planes.
      // U/V planes are subsampled (height/2, width/2).
      // Correct for pixel stride if it's not 1 (though usually 1 for planar).
      int uvIndex = uIndex + (x ~/ 2) * uvPixelStride;

      // Ensure indices are within bounds (robustness check)
      if (yIndex >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
        // Handle potential out-of-bounds access, perhaps due to stride issues
        // Setting to black or skipping might be options. Let's set to black.
        image.setPixelRgb(x, y, 0, 0, 0);
        continue;
      }

      // Get the Y, U, V values for the current pixel (x, y)
      final int yValue = yBytes[yIndex];
      // Use the same uvIndex for both U and V because they correspond to the same 2x2 block
      // in the Y plane for YUV420p.
      final int uValue = uBytes[uvIndex];
      final int vValue = vBytes[uvIndex];

      // --- YUV to RGB calculation ---
      // Standard conversion formulas (adjust coefficients slightly if needed based on range/standard)
      // Using integer arithmetic for potential speedup, can use double as well.
      // Values are typically in the range [0, 255] for Y, U, V (video range).
      final int y_ = yValue;
      final int u_ = uValue - 128; // Center U around 0
      final int v_ = vValue - 128; // Center V around 0

      // Calculate R, G, B values
      // Using common coefficients (derived from ITU-R BT.601 standard)
      int r = (y_ + 1.402 * v_).round();
      int g = (y_ - 0.344136 * u_ - 0.714136 * v_).round();
      int b = (y_ + 1.772 * u_).round();

      // Clamp the values to the valid RGB range [0, 255]
      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      // Set the pixel in the img.Image object
      image.setPixelRgb(x, y, r, g, b);
    }
  }

  return image;
}

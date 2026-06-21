import 'package:flutter/material.dart';

/// Shared "candy pack" palette — used by both the home pile and the dex so the
/// cigarette pack looks identical everywhere.

/// Soften harsh brand primaries into a brighter, candy-like color so packs read
/// as cute against the dark stage rather than grungy.
Color cuteify(Color c) {
  final h = HSLColor.fromColor(c);
  return h
      .withSaturation((h.saturation * 0.85).clamp(0.0, 0.72))
      .withLightness(h.lightness.clamp(0.46, 0.74))
      .toColor();
}

/// Lighten (amt > 0) or darken (amt < 0) a pack color while keeping it off
/// pure-black, for the gradient top / extruded side shades.
Color packShade(Color c, double amt) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness + amt).clamp(0.22, 0.95)).toColor();
}

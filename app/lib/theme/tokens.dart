import 'package:flutter/painting.dart';

/// Klora Fitness design tokens, copied from DESIGN.md (the web app's klora.css uses the same set).
/// A coaching gym tracker drawn as a rack of coated pastel hand-weights, where load is colour.
class K {
  K._();

  static const hotRose = Color(0xFFCF3A76);
  static const hotRoseDeep = Color(0xFFB02A62);
  static const hotRoseNight = Color(0xFFE06D9B);

  static const blushGround = Color(0xFFFBEFF4);
  static const blushRaised = Color(0xFFFDF6F9);
  static const blushSlab = Color(0xFFFFFBFC);
  static const blushSlab2 = Color(0xFFF7E6ED);
  static const blushSlab3 = Color(0xFFEFD5E0);
  static const plumInk = Color(0xFF3A1D2C);

  static const plumNight = Color(0xFF1A0F16);
  static const plumNightRaised = Color(0xFF22141D);
  static const plumSlab = Color(0xFF2C1B26);
  static const plumSlab2 = Color(0xFF3A2532);
  static const plumSlab3 = Color(0xFF4A3040);
  static const nightInk = Color(0xFFFCF0F5);

  static const rackRose = Color(0xFFF7C3D6), rackRoseInk = Color(0xFF5C1033);
  static const rackLilac = Color(0xFFD9CBF5), rackLilacInk = Color(0xFF33206B);
  static const rackMint = Color(0xFFBFE7D4), rackMintInk = Color(0xFF114A33);
  static const rackButter = Color(0xFFF8E6A0), rackButterInk = Color(0xFF5A4100);
  static const rackPeach = Color(0xFFFBD2BD), rackPeachInk = Color(0xFF6B2A0C);
  static const rackSky = Color(0xFFC6E0F7), rackSkyInk = Color(0xFF123A63);

  /// The rack, in order: a load chip picks its pastel by index (e.g. exercise or muscle group).
  static const rack = [
    (rackRose, rackRoseInk),
    (rackLilac, rackLilacInk),
    (rackMint, rackMintInk),
    (rackButter, rackButterInk),
    (rackPeach, rackPeachInk),
    (rackSky, rackSkyInk),
  ];

  static const font = 'Rubik';
  static const radius = 18.0;
  static const radiusSm = 12.0;
  static const radiusPill = 999.0;
}

/// Surface roles resolved for the current brightness.
class KSurfaces {
  final Color ground, raised, slab, slab2, slab3, ink, inkSoft, accent, onAccent;
  const KSurfaces({
    required this.ground,
    required this.raised,
    required this.slab,
    required this.slab2,
    required this.slab3,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onAccent,
  });

  static const light = KSurfaces(
    ground: K.blushGround,
    raised: K.blushRaised,
    slab: K.blushSlab,
    slab2: K.blushSlab2,
    slab3: K.blushSlab3,
    ink: K.plumInk,
    inkSoft: Color(0x993A1D2C),
    accent: K.hotRose,
    onAccent: Color(0xFFFFFFFF),
  );

  static const dark = KSurfaces(
    ground: K.plumNight,
    raised: K.plumNightRaised,
    slab: K.plumSlab,
    slab2: K.plumSlab2,
    slab3: K.plumSlab3,
    ink: K.nightInk,
    inkSoft: Color(0x99FCF0F5),
    accent: K.hotRoseNight,
    onAccent: K.plumNight,
  );
}

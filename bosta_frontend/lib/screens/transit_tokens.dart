import 'package:flutter/material.dart';

@immutable
class TransitTokens extends ThemeExtension<TransitTokens> {
  const TransitTokens({
    required this.routePrimary,
    required this.sheetSurface,
    required this.markerNormal,
    required this.markerSelected,
    required this.markerDelayed,
    required this.chipSurface,
    required this.etaPositive,
  });

  final Color routePrimary;
  final Color sheetSurface;
  final Color markerNormal;
  final Color markerSelected;
  final Color markerDelayed;
  final Color chipSurface;
  final Color etaPositive;

  @override
  TransitTokens copyWith({
    Color? routePrimary,
    Color? sheetSurface,
    Color? markerNormal,
    Color? markerSelected,
    Color? markerDelayed,
    Color? chipSurface,
    Color? etaPositive,
  }) {
    return TransitTokens(
      routePrimary: routePrimary ?? this.routePrimary,
      sheetSurface: sheetSurface ?? this.sheetSurface,
      markerNormal: markerNormal ?? this.markerNormal,
      markerSelected: markerSelected ?? this.markerSelected,
      markerDelayed: markerDelayed ?? this.markerDelayed,
      chipSurface: chipSurface ?? this.chipSurface,
      etaPositive: etaPositive ?? this.etaPositive,
    );
  }

  @override
  ThemeExtension<TransitTokens> lerp(
      ThemeExtension<TransitTokens>? other, double t) {
    if (other is! TransitTokens) {
      return this;
    }
    return TransitTokens(
      routePrimary: Color.lerp(routePrimary, other.routePrimary, t)!,
      sheetSurface: Color.lerp(sheetSurface, other.sheetSurface, t)!,
      markerNormal: Color.lerp(markerNormal, other.markerNormal, t)!,
      markerSelected: Color.lerp(markerSelected, other.markerSelected, t)!,
      markerDelayed: Color.lerp(markerDelayed, other.markerDelayed, t)!,
      chipSurface: Color.lerp(chipSurface, other.chipSurface, t)!,
      etaPositive: Color.lerp(etaPositive, other.etaPositive, t)!,
    );
  }
}
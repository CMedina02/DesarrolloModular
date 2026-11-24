import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/app/app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: InventarioComercialApp(),
    ),
  );
}

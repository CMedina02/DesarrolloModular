import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/app/router.dart';
import 'package:inventario_comercial/app/theme.dart';

/// Root widget of the Inventario Comercial 1.0 client.
class InventarioComercialApp extends ConsumerWidget {
  const InventarioComercialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Inventario Comercial 1.0',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

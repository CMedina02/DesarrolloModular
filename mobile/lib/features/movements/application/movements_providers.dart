import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/movements/data/movements_repository.dart';

final movementsRepositoryProvider = Provider<MovementsRepository>(
  (ref) => MovementsRepository(ref.watch(apiClientProvider)),
);

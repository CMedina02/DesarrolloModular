import 'package:flutter/material.dart';
import 'package:inventario_comercial/core/models/enums.dart';

enum AppDestinationId {
  businesses,
  users,
  modules,
  products,
  categories,
  movements,
  history,
  employees,
  profile,
}

@immutable
class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
  });

  final AppDestinationId id;
  final String label;
  final IconData icon;
  final String description;
}

/// Returns the permitted navigation destinations for [role].
List<AppDestination> destinationsForRole(UserRole role) {
  switch (role) {
    case UserRole.platformAdmin:
      return const [
        AppDestination(
          id: AppDestinationId.businesses,
          label: 'Empresas',
          icon: Icons.store_outlined,
          description:
              'Alta, consulta y activación de empresas en la instalación (F04).',
        ),
        AppDestination(
          id: AppDestinationId.users,
          label: 'Usuarios',
          icon: Icons.people_outline,
          description:
              'Administración de cuentas ADMIN y EMPLOYEE por empresa (F04).',
        ),
        AppDestination(
          id: AppDestinationId.modules,
          label: 'Módulos',
          icon: Icons.extension_outlined,
          description:
              'Habilitación y deshabilitación del módulo Inventario por empresa (F04).',
        ),
        AppDestination(
          id: AppDestinationId.profile,
          label: 'Perfil',
          icon: Icons.person_outline,
          description: 'Información de la cuenta y cierre de sesión.',
        ),
      ];
    case UserRole.admin:
      return const [
        AppDestination(
          id: AppDestinationId.products,
          label: 'Catálogo',
          icon: Icons.inventory_2_outlined,
          description:
              'Consulta, alta, edición y desactivación de productos de tu empresa (F06).',
        ),
        AppDestination(
          id: AppDestinationId.categories,
          label: 'Categorías',
          icon: Icons.category_outlined,
          description: 'Gestión de categorías de inventario de tu empresa (F05).',
        ),
        AppDestination(
          id: AppDestinationId.movements,
          label: 'Movimientos',
          icon: Icons.swap_horiz,
          description:
              'Registro de entradas, salidas y ajustes de existencias (F07).',
        ),
        AppDestination(
          id: AppDestinationId.history,
          label: 'Historial',
          icon: Icons.history,
          description:
              'Consulta paginada y filtrada del historial de movimientos (F08).',
        ),
        AppDestination(
          id: AppDestinationId.employees,
          label: 'Empleados',
          icon: Icons.badge_outlined,
          description:
              'Administración de cuentas EMPLOYEE de tu empresa (F04).',
        ),
        AppDestination(
          id: AppDestinationId.profile,
          label: 'Perfil',
          icon: Icons.person_outline,
          description: 'Información de la cuenta y cierre de sesión.',
        ),
      ];
    case UserRole.employee:
      return const [
        AppDestination(
          id: AppDestinationId.products,
          label: 'Catálogo',
          icon: Icons.inventory_2_outlined,
          description:
              'Consulta de productos activos de tu empresa (F06).',
        ),
        AppDestination(
          id: AppDestinationId.categories,
          label: 'Categorías',
          icon: Icons.category_outlined,
          description: 'Consulta de categorías de tu empresa (F05).',
        ),
        AppDestination(
          id: AppDestinationId.movements,
          label: 'Movimientos',
          icon: Icons.swap_horiz,
          description: 'Registro de entradas y salidas de inventario (F07).',
        ),
        AppDestination(
          id: AppDestinationId.profile,
          label: 'Perfil',
          icon: Icons.person_outline,
          description: 'Información de la cuenta y cierre de sesión.',
        ),
      ];
  }
}

/// Returns the section title matching the authenticated user's role.
String sectionTitleForRole(UserRole role) {
  switch (role) {
    case UserRole.platformAdmin:
      return 'Administración de instalación';
    case UserRole.admin:
      return 'Administración de empresa';
    case UserRole.employee:
      return 'Operación de inventario';
  }
}

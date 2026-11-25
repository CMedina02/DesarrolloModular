import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/business.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';

/// User management screen for `PLATFORM_ADMIN` (ADMIN + EMPLOYEE) and `ADMIN`
/// (EMPLOYEE only within their own business).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  bool get _isPlatformAdmin => currentUser.role == UserRole.platformAdmin;

  Future<void> _openCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String businessId,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        businessId: businessId,
        actorRole: currentUser.role,
      ),
    );
    if (created == true) {
      ref.invalidate(businessUsersProvider(businessId));
    }
  }

  Future<void> _openEditDialog(
    BuildContext context,
    WidgetRef ref,
    String businessId,
    User targetUser,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        businessId: businessId,
        actorRole: currentUser.role,
        existing: targetUser,
      ),
    );
    if (updated == true) {
      ref.invalidate(businessUsersProvider(businessId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_isPlatformAdmin) {
      final businessesAsync = ref.watch(businessesProvider);
      return businessesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorRetry(
          message: error is ApiException
              ? error.userMessage
              : 'No se pudieron cargar las empresas.',
          onRetry: () => ref.invalidate(businessesProvider),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Primero registra una empresa para administrar sus cuentas.',
                ),
              ),
            );
          }

          final selectedId = ref.watch(selectedBusinessIdProvider);
          final activeBusinessId =
              page.items.any((b) => b.id == selectedId)
                  ? selectedId!
                  : page.items.first.id;

          return Column(
            children: [
              _BusinessSelectorBar(
                businesses: page.items,
                selectedBusinessId: activeBusinessId,
                onChanged: (id) {
                  ref.read(selectedBusinessIdProvider.notifier).select(id);
                },
              ),
              Expanded(
                child: _UsersListBody(
                  businessId: activeBusinessId,
                  actorRole: currentUser.role,
                  onCreate: () =>
                      _openCreateDialog(context, ref, activeBusinessId),
                  onEdit: (user) =>
                      _openEditDialog(context, ref, activeBusinessId, user),
                ),
              ),
            ],
          );
        },
      );
    }

    final businessId = currentUser.businessId;
    if (businessId == null) {
      return const Center(
        child: Text('Tu perfil no tiene una empresa asociada.'),
      );
    }

    return _UsersListBody(
      businessId: businessId,
      actorRole: currentUser.role,
      onCreate: () => _openCreateDialog(context, ref, businessId),
      onEdit: (user) => _openEditDialog(context, ref, businessId, user),
    );
  }
}

class _BusinessSelectorBar extends StatelessWidget {
  const _BusinessSelectorBar({
    required this.businesses,
    required this.selectedBusinessId,
    required this.onChanged,
  });

  final List<Business> businesses;
  final String selectedBusinessId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DropdownButtonFormField<String>(
        key: const Key('users_business_selector'),
        initialValue: selectedBusinessId,
        decoration: const InputDecoration(
          labelText: 'Empresa seleccionada',
          border: OutlineInputBorder(),
        ),
        items: businesses
            .map(
              (b) => DropdownMenuItem<String>(
                value: b.id,
                child: Text('${b.name}${b.isActive ? '' : ' (Inactiva)'}'),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _UsersListBody extends ConsumerWidget {
  const _UsersListBody({
    required this.businessId,
    required this.actorRole,
    required this.onCreate,
    required this.onEdit,
  });

  final String businessId;
  final UserRole actorRole;
  final VoidCallback onCreate;
  final ValueChanged<User> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(businessUsersProvider(businessId));
    final theme = Theme.of(context);
    final createLabel =
        actorRole == UserRole.admin ? 'Nuevo empleado' : 'Nuevo usuario';

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_user_fab'),
        onPressed: onCreate,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(createLabel),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorRetry(
          message: error is ApiException
              ? error.userMessage
              : 'No se pudieron cargar los usuarios.',
          onRetry: () => ref.invalidate(businessUsersProvider(businessId)),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      actorRole == UserRole.admin
                          ? 'No hay empleados registrados en tu empresa.'
                          : 'No hay usuarios registrados en esta empresa.',
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: page.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = page.items[index];
              return Card(
                color: theme.colorScheme.surfaceContainerLow,
                child: ListTile(
                  leading: Icon(
                    user.isActive
                        ? Icons.person_outline
                        : Icons.person_off_outlined,
                  ),
                  title: Text(user.name),
                  subtitle: Text(
                    '${user.email} · ${user.role.apiValue} · '
                    '${user.isActive ? 'Activo' : 'Inactivo'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Editar cuenta',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => onEdit(user),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog({
    required this.businessId,
    required this.actorRole,
    this.existing,
  });

  final String businessId;
  final UserRole actorRole;
  final User? existing;

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  static const _minimumPasswordLength = 8;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  late UserRole _selectedRole;
  late bool _isActive;
  bool _submitting = false;
  String? _errorMessage;

  bool get _canAssignAdmin => widget.actorRole == UserRole.platformAdmin;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _emailController =
        TextEditingController(text: widget.existing?.email ?? '');
    _selectedRole = _canAssignAdmin
        ? (widget.existing?.role ?? UserRole.employee)
        : UserRole.employee;
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final roleToSend = _canAssignAdmin ? _selectedRole : UserRole.employee;

    try {
      final repo = ref.read(adminRepositoryProvider);
      if (widget.existing == null) {
        await repo.createUser(
          widget.businessId,
          UserCreateRequest(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            role: roleToSend,
            password: _passwordController.text,
            isActive: _isActive,
          ),
        );
      } else {
        await repo.updateUser(
          widget.businessId,
          widget.existing!.id,
          UserUpdateRequest(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            role: roleToSend,
            isActive: _isActive,
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.userMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = 'No se pudo guardar la cuenta.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);
    final allowedRoles = _canAssignAdmin
        ? const [UserRole.admin, UserRole.employee]
        : const [UserRole.employee];

    return AlertDialog(
      title: Text(
        isEdit
            ? 'Editar cuenta'
            : (_canAssignAdmin ? 'Nuevo usuario de empresa' : 'Nuevo empleado'),
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    key: const Key('user_form_error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const Key('user_name_field'),
                  controller: _nameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Ingresa el nombre.';
                    if (trimmed.length > 150) return 'Máximo 150 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('user_email_field'),
                  controller: _emailController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty || !trimmed.contains('@')) {
                      return 'Ingresa un correo válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  key: const Key('user_role_field'),
                  initialValue: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    border: const OutlineInputBorder(),
                    helperText: _canAssignAdmin
                        ? null
                        : 'Solo PLATFORM_ADMIN puede asignar el rol ADMIN.',
                  ),
                  items: allowedRoles
                      .map(
                        (role) => DropdownMenuItem<UserRole>(
                          value: role,
                          child: Text(role.apiValue),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _submitting || !_canAssignAdmin
                      ? null
                      : (role) {
                          if (role != null) {
                            setState(() => _selectedRole = role);
                          }
                        },
                ),
                if (!isEdit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('user_password_field'),
                    controller: _passwordController,
                    enabled: !_submitting,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña (mínimo $_minimumPasswordLength caracteres)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final length = value?.runes.length ?? 0;
                      if (length < _minimumPasswordLength) {
                        return 'La contraseña debe tener al menos $_minimumPasswordLength caracteres.';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cuenta activa'),
                  value: _isActive,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('user_save_button'),
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Guardar cambios' : 'Crear'),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

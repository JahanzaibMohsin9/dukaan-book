import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/auth/presentation/controllers/auth_form_controller.dart';
import 'package:dukaan_book/features/notifications/data/notification_service.dart';
import 'package:dukaan_book/features/notifications/data/notification_settings_repository.dart';
import 'package:dukaan_book/features/settings/data/settings_repository.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(authRepositoryProvider);
    final authState = ref.watch(authFormControllerProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final notificationPrefs = ref.watch(notificationPreferencesProvider);
    final activeShop = ref.watch(activeShopProfileProvider);
    final unsyncedCount = syncStatus.asData?.value.unsyncedCount ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shop settings',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Profile, sync status, reminders, app lock, and language will settle here as the app grows.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            activeShop.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
              data: (shop) => _ShopProfileCard(profile: shop),
            ),
            const SizedBox(height: 20),
            syncStatus.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
              data: (status) => _SyncSettingsCard(status: status),
            ),
            const SizedBox(height: 20),
            notificationPrefs.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
              data: (preferences) => _NotificationSettingsCard(
                preferences: preferences,
                unsyncedCount: unsyncedCount,
              ),
            ),
            const SizedBox(height: 20),
            _DataManagementCard(unsyncedCount: unsyncedCount),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: authState.isLoading || !repository.isConfigured
                  ? null
                  : () =>
                        ref.read(authFormControllerProvider.notifier).signOut(),
              icon: authState.isLoading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncSettingsCard extends ConsumerWidget {
  const _SyncSettingsCard({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final lastSync = status.lastSuccessfulSyncAt;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sync status',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (status.isSyncing)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    status.hasPendingWork
                        ? Icons.cloud_upload_rounded
                        : Icons.cloud_done_rounded,
                    color: status.hasPendingWork
                        ? AppTheme.clay
                        : AppTheme.leaf,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${status.unsyncedCount} pending local changes'),
            const SizedBox(height: 6),
            Text(
              lastSync == null
                  ? 'Last successful sync: not yet'
                  : 'Last successful sync: ${lastSync.toLocal()}',
            ),
            if (status.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                status.lastError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.clay,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: userId == null || status.isSyncing
                  ? null
                  : () => ref.read(syncServiceProvider).syncNow(userId: userId),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Conflicts use last-write-wins for profile, account, and category details. Posted synced transactions stay auditable: corrections are recorded through reversal and replacement entries.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProfileCard extends ConsumerStatefulWidget {
  const _ShopProfileCard({required this.profile});

  final ShopSettingsProfile? profile;

  @override
  ConsumerState<_ShopProfileCard> createState() => _ShopProfileCardState();
}

class _ShopProfileCardState extends ConsumerState<_ShopProfileCard> {
  bool _isSaving = false;

  Future<void> _editProfile(ShopSettingsProfile profile) async {
    final result = await showDialog<_ShopProfileEditDraft>(
      context: context,
      builder: (context) => _ShopProfileEditDialog(profile: profile),
    );
    if (result == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateShopProfile(
            profile: profile,
            shopName: result.shopName,
            city: result.city,
            phone: result.phone,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shop profile updated.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Shop profile',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: profile == null || _isSaving
                      ? null
                      : () => _editProfile(profile),
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (profile == null)
              const Text('No active shop profile found.')
            else ...[
              Text(profile.name),
              const SizedBox(height: 4),
              SelectableText('Shared shop ID: ${profile.id}'),
              const SizedBox(height: 4),
              Text('City: ${profile.city ?? 'Not set'}'),
              const SizedBox(height: 2),
              Text('Phone: ${profile.phone ?? 'Not set'}'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: profile.id));
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Shared shop ID copied.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy shop ID'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataManagementCard extends ConsumerStatefulWidget {
  const _DataManagementCard({required this.unsyncedCount});

  final int unsyncedCount;

  @override
  ConsumerState<_DataManagementCard> createState() =>
      _DataManagementCardState();
}

class _DataManagementCardState extends ConsumerState<_DataManagementCard> {
  bool _isExporting = false;
  bool _isClearing = false;

  Future<void> _exportBackup() async {
    if (_isExporting) {
      return;
    }
    setState(() {
      _isExporting = true;
    });

    try {
      final backup = await ref
          .read(settingsRepositoryProvider)
          .createLocalDatabaseBackup();
      await Share.shareXFiles(
        [XFile(backup.filePath)],
        text:
            'Dukaan Book local backup (${(backup.fileSizeBytes / 1024).toStringAsFixed(1)} KB)',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local database backup exported.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup export failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _clearCache() async {
    if (_isClearing) {
      return;
    }

    final pendingUnsynced = await ref
        .read(settingsRepositoryProvider)
        .pendingUnsyncedCount();
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear local cache?'),
        content: Text(
          pendingUnsynced > 0
              ? 'Sync warning: $pendingUnsynced pending changes exist. Clear cache will remove sync metadata and synced outbox logs, but keep pending local changes. Continue?'
              : 'This clears sync metadata and synced outbox logs from this device. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear cache'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isClearing = true;
    });

    try {
      await ref.read(settingsRepositoryProvider).clearLocalCache();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local cache cleared safely.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data management',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text('${widget.unsyncedCount} unsynced local changes right now.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportBackup,
              icon: _isExporting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.backup_rounded),
              label: const Text('Export local backup'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _isClearing ? null : _clearCache,
              icon: _isClearing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cleaning_services_rounded),
              label: const Text('Clear local cache'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProfileEditDraft {
  const _ShopProfileEditDraft({
    required this.shopName,
    required this.city,
    required this.phone,
  });

  final String shopName;
  final String? city;
  final String? phone;
}

class _ShopProfileEditDialog extends StatefulWidget {
  const _ShopProfileEditDialog({required this.profile});

  final ShopSettingsProfile profile;

  @override
  State<_ShopProfileEditDialog> createState() => _ShopProfileEditDialogState();
}

class _ShopProfileEditDialogState extends State<_ShopProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _cityController = TextEditingController(text: widget.profile.city ?? '');
    _phoneController = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _ShopProfileEditDraft(
        shopName: _nameController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit shop profile'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Shop name'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Shop name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'City (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _NotificationSettingsCard extends ConsumerStatefulWidget {
  const _NotificationSettingsCard({
    required this.preferences,
    required this.unsyncedCount,
  });

  final NotificationPreferences preferences;
  final int unsyncedCount;

  @override
  ConsumerState<_NotificationSettingsCard> createState() =>
      _NotificationSettingsCardState();
}

class _NotificationSettingsCardState
    extends ConsumerState<_NotificationSettingsCard> {
  bool _isRequestingPermission = false;

  Future<bool> _requestPermission() async {
    if (_isRequestingPermission) {
      return false;
    }

    setState(() {
      _isRequestingPermission = true;
    });

    final service = ref.read(notificationServiceProvider);
    try {
      final granted = await service.requestPermission();
      ref.invalidate(notificationPermissionProvider);
      if (!mounted) {
        return granted;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Notifications enabled.'
                : 'Notification permission denied. You can enable it in Android settings later.',
          ),
        ),
      );
      return granted;
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermission = false;
        });
      }
    }
  }

  Future<void> _applySchedules(NotificationPreferences preferences) {
    return ref
        .read(notificationServiceProvider)
        .applySchedules(
          preferences: preferences,
          unsyncedCount: widget.unsyncedCount,
        );
  }

  Future<bool> _ensurePermissionIfNeeded() async {
    final service = ref.read(notificationServiceProvider);
    final hasPermission = await service.isPermissionGranted();
    if (hasPermission) {
      return true;
    }
    return _requestPermission();
  }

  Future<void> _toggleDailyReminder(bool enabled) async {
    if (enabled) {
      final allowed = await _ensurePermissionIfNeeded();
      if (!allowed) {
        return;
      }
    }

    final repository = ref.read(notificationSettingsRepositoryProvider);
    await repository.setDailyClosingReminderEnabled(enabled);
    await _applySchedules(
      widget.preferences.copyWith(dailyClosingReminderEnabled: enabled),
    );
  }

  Future<void> _toggleUnsyncedReminder(bool enabled) async {
    if (enabled) {
      final allowed = await _ensurePermissionIfNeeded();
      if (!allowed) {
        return;
      }
    }

    final repository = ref.read(notificationSettingsRepositoryProvider);
    await repository.setUnsyncedReminderEnabled(enabled);
    await _applySchedules(
      widget.preferences.copyWith(unsyncedReminderEnabled: enabled),
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: widget.preferences.dailyClosingReminderTime,
      helpText: 'Select daily reminder time',
    );
    if (picked == null) {
      return;
    }

    final repository = ref.read(notificationSettingsRepositoryProvider);
    await repository.setDailyClosingReminderTime(picked);
    await _applySchedules(
      widget.preferences.copyWith(dailyClosingReminderTime: picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(notificationPermissionProvider);
    final isPermissionGranted = permission.asData?.value == true;
    final formattedTime = DateFormat('h:mm a').format(
      DateTime(
        2026,
        1,
        1,
        widget.preferences.dailyClosingReminderTime.hour,
        widget.preferences.dailyClosingReminderTime.minute,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              permission.isLoading
                  ? 'Checking permission status...'
                  : isPermissionGranted
                  ? 'Permission status: allowed'
                  : 'Permission status: required on Android 13+',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isRequestingPermission ? null : _requestPermission,
              icon: _isRequestingPermission
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_rounded),
              label: const Text('Enable notifications'),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily closing reminder'),
              subtitle: Text('Alert me daily at $formattedTime'),
              value: widget.preferences.dailyClosingReminderEnabled,
              onChanged: _toggleDailyReminder,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickReminderTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text('Reminder time: $formattedTime'),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unsynced pending-data reminder'),
              subtitle: Text(
                widget.unsyncedCount > 0
                    ? '${widget.unsyncedCount} pending changes currently queued'
                    : 'Will remind only when unsynced changes exist',
              ),
              value: widget.preferences.unsyncedReminderEnabled,
              onChanged: _toggleUnsyncedReminder,
            ),
            const SizedBox(height: 4),
            const Text(
              'If permission is denied, reminders stay off and the app continues without blocking core workflows.',
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/files/app_file_pick_result.dart';
import '../../../../core/files/selected_app_file.dart';
import '../../../../core/utils/result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/entities/company_document.dart';
import '../../domain/services/document_file_validator.dart';
import '../../domain/value_objects/document_file_rules.dart';
import '../controllers/document_controllers.dart';
import '../providers/document_providers.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.documentsTitle)),
        body: Center(child: Text(l10n.dashboardNoActiveCompany)),
      );
    }

    final canManage = activeCompany.role.canManageDocuments;
    final documentsAsync = ref.watch(
      documentsProvider(activeCompany.companyId),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.documentsTitle)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('documents-upload-fab'),
              onPressed: () => _startUpload(
                context,
                ref,
                companyId: activeCompany.companyId,
              ),
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.documentsUpload),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: documentsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            final message = error is StateError
                ? error.message
                : l10n.documentsLoadError;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  FilledButton(
                    onPressed: () => ref.invalidate(
                      documentsProvider(activeCompany.companyId),
                    ),
                    child: Text(l10n.documentsRetry),
                  ),
                ],
              ),
            );
          },
          data: (documents) {
            if (documents.isEmpty) {
              return Center(child: Text(l10n.documentsEmpty));
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(documentsProvider(activeCompany.companyId));
                await ref.read(
                  documentsProvider(activeCompany.companyId).future,
                );
              },
              child: ListView.separated(
                itemCount: documents.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final document = documents[index];
                  return _DocumentListTile(
                    document: document,
                    canManage: canManage,
                    companyId: activeCompany.companyId,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _startUpload(
    BuildContext context,
    WidgetRef ref, {
    required String companyId,
  }) async {
    final l10n = AppLocalizations.of(context);
    final pickResult = await ref
        .read(appFilePickerProvider)
        .pickDocumentUploadFile();
    final SelectedAppFile picked;
    switch (pickResult) {
      case AppFilePickCancelled():
        return;
      case AppFilePickFailure(:final message):
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      case AppFilePickSuccess(:final file):
        picked = file;
    }

    final validation = DocumentFileValidator.validate(
      fileName: picked.name,
      declaredMimeType: picked.mimeType,
      bytes: picked.bytes,
    );
    if (validation is DocumentFileValidationFailure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(validation.message)));
      }
      return;
    }

    if (!context.mounted) {
      return;
    }
    final suggested = DocumentFileValidator.suggestedTitleFromFileName(
      picked.name,
    );
    final titleController = TextEditingController(text: suggested);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.documentsUpload),
          content: TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: l10n.documentTitleLabel,
              border: const OutlineInputBorder(),
            ),
            maxLength: DocumentFileRules.maxTitleLength,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('documents-upload-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.documentsUploadConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      titleController.dispose();
      return;
    }

    final uploadController = ref.read(
      documentUploadControllerProvider(companyId).notifier,
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final ok = await uploadController.upload(
      title: titleController.text,
      originalFileName: picked.name,
      declaredMimeType: picked.mimeType,
      bytes: Uint8List.fromList(picked.bytes),
    );
    titleController.dispose();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      final state = ref.read(documentUploadControllerProvider(companyId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.documentsUploadSuccess
                : (state.errorMessage ?? l10n.documentsUploadError),
          ),
        ),
      );
      uploadController.clearFeedback();
    }
  }
}

class _DocumentListTile extends ConsumerWidget {
  const _DocumentListTile({
    required this.document,
    required this.canManage,
    required this.companyId,
  });

  final CompanyDocument document;
  final bool canManage;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd('it').format(document.createdAt.toLocal());
    final sizeLabel = _formatSize(document.sizeBytes);
    final typeLabel = document.isPdf
        ? 'PDF'
        : document.mimeType.replaceFirst('image/', '').toUpperCase();

    return ListTile(
      leading: Icon(
        document.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
      ),
      title: Text(document.title),
      subtitle: Text(
        [
          document.originalFileName,
          typeLabel,
          sizeLabel,
          date,
          if (document.isArchived) l10n.documentArchived,
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: document.isArchived
              ? theme.colorScheme.onSurfaceVariant
              : null,
        ),
      ),
      trailing: PopupMenuButton<String>(
        key: Key('document-menu-${document.id}'),
        onSelected: (value) async {
          switch (value) {
            case 'open':
              await _open(context, ref);
            case 'rename':
              await _rename(context, ref);
            case 'archive':
              await _setArchived(context, ref, archived: true);
            case 'restore':
              await _setArchived(context, ref, archived: false);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'open', child: Text(l10n.documentOpen)),
          if (canManage)
            PopupMenuItem(value: 'rename', child: Text(l10n.documentRename)),
          if (canManage && !document.isArchived)
            PopupMenuItem(value: 'archive', child: Text(l10n.documentArchive)),
          if (canManage && document.isArchived)
            PopupMenuItem(value: 'restore', child: Text(l10n.documentRestore)),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final signed = await ref
        .read(createDocumentSignedUrlUseCaseProvider)
        .call(companyId: companyId, documentId: document.id);
    if (!context.mounted) {
      return;
    }
    switch (signed) {
      case Error(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      case Success(:final value):
        final launcher = ref.read(documentUrlLauncherProvider);
        final opened = await launcher.launch(value);
        if (!opened && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.documentOpenFailed)));
        }
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: document.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.documentRename),
          content: TextField(
            key: const Key('document-rename-field'),
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.documentTitleLabel,
              border: const OutlineInputBorder(),
            ),
            maxLength: DocumentFileRules.maxTitleLength,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      controller.dispose();
      return;
    }
    final ok = await ref
        .read(documentMutationControllerProvider(companyId).notifier)
        .rename(documentId: document.id, title: controller.text);
    controller.dispose();
    if (!context.mounted) {
      return;
    }
    final state = ref.read(documentMutationControllerProvider(companyId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.documentRenameSuccess
              : (state.errorMessage ?? l10n.documentRenameError),
        ),
      ),
    );
    ref
        .read(documentMutationControllerProvider(companyId).notifier)
        .clearFeedback();
  }

  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref, {
    required bool archived,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(documentMutationControllerProvider(companyId).notifier)
        .setArchived(documentId: document.id, isArchived: archived);
    if (!context.mounted) {
      return;
    }
    final state = ref.read(documentMutationControllerProvider(companyId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (archived
                    ? l10n.documentArchiveSuccess
                    : l10n.documentRestoreSuccess)
              : (state.errorMessage ?? l10n.documentArchiveError),
        ),
      ),
    );
    ref
        .read(documentMutationControllerProvider(companyId).notifier)
        .clearFeedback();
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/company_document.dart';
import '../controllers/document_controllers.dart';

Future<void> showDocumentDeleteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String companyId,
  required CompanyDocument document,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _DocumentDeleteDialog(companyId: companyId, document: document),
  );
}

class _DocumentDeleteDialog extends ConsumerStatefulWidget {
  const _DocumentDeleteDialog({
    required this.companyId,
    required this.document,
  });

  final String companyId;
  final CompanyDocument document;

  @override
  ConsumerState<_DocumentDeleteDialog> createState() =>
      _DocumentDeleteDialogState();
}

class _DocumentDeleteDialogState extends ConsumerState<_DocumentDeleteDialog> {
  bool _deleting = false;

  Future<void> _confirm() async {
    if (_deleting) {
      return;
    }
    setState(() => _deleting = true);
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(documentMutationControllerProvider(widget.companyId).notifier)
        .deletePermanently(documentId: widget.document.id);
    if (!mounted) {
      return;
    }
    final state = ref.read(
      documentMutationControllerProvider(widget.companyId),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.documentDeleteSuccess
              : (state.errorMessage ?? l10n.documentDeleteError),
        ),
      ),
    );
    ref
        .read(documentMutationControllerProvider(widget.companyId).notifier)
        .clearFeedback();
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.documentDeleteConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.document.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(l10n.documentDeleteIrreversible),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('document-delete-confirm'),
          onPressed: _deleting ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.documentDeleteConfirmAction),
        ),
      ],
    );
  }
}

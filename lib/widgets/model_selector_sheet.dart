import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

Future<void> showModelSelectorSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ModelSelectorSheet(),
  );
}

class _ModelSelectorSheet extends StatelessWidget {
  const _ModelSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text('Choose a model', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => settings.refreshModels(),
                  ),
                ],
              ),
            ),
            if (settings.status == ConnectionStatus.checking)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (settings.status == ConnectionStatus.failed)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Could not connect to 9Router.\n${settings.lastError ?? ''}',
                  style: const TextStyle(color: AppColors.error),
                ),
              )
            else if (settings.availableModels.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No models found. Check your 9Router setup in Settings.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: settings.availableModels.length,
                  itemBuilder: (context, index) {
                    final model = settings.availableModels[index];
                    final selected = settings.selectedModel == model;
                    return ListTile(
                      title: Text(model),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: AppColors.accent)
                          : null,
                      onTap: () {
                        settings.selectModel(model);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

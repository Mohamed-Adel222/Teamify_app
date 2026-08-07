import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../data/models/university_option_model.dart';
import '../services/app_services.dart';
import 'widgets.dart';

/// Single Option Tile component in University Search Bottom Sheet.
class UniversityOptionTile extends StatelessWidget {
  final UniversityOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const UniversityOptionTile({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: TCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                option.isCustom ? Icons.edit_note_outlined : Icons.school_outlined,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (option.city != null || option.type != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (option.type != null) option.type,
                        if (option.city != null) option.city,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Searchable Bottom Sheet for University Selection.
class UniversitySearchBottomSheet extends StatefulWidget {
  final UniversityOption? selectedOption;
  final ValueChanged<UniversityOption> onSelected;

  const UniversitySearchBottomSheet({
    super.key,
    this.selectedOption,
    required this.onSelected,
  });

  @override
  State<UniversitySearchBottomSheet> createState() =>
      _UniversitySearchBottomSheetState();
}

class _UniversitySearchBottomSheetState
    extends State<UniversitySearchBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<UniversityOption> _all = const [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await context.read<AppServices>().universities.list();
    if (!mounted) return;
    result.when(
      success: (data) => setState(() {
        _all = data;
        _loading = false;
      }),
      failure: (error) => setState(() {
        _error = error;
        _loading = false;
      }),
    );
  }

  List<UniversityOption> get _filteredUniversities {
    final query = _searchQuery.toLowerCase().trim();
    final all = _all;
    if (query.isEmpty) return all;

    final normQuery = UniversityOption.normalizeUniversityName(query);

    // Filter while preserving "Other" at the bottom
    final matches = all.where((u) {
      if (u.id == 'uni_other') return false; // handle separately
      final nameMatch = u.name.toLowerCase().contains(query);
      final normNameMatch = u.normalizedName.contains(normQuery);
      final cityMatch = (u.city ?? '').toLowerCase().contains(query);
      final typeMatch = (u.type ?? '').toLowerCase().contains(query);
      final aliasMatch = u.aliases.any(
        (a) =>
            a.toLowerCase().contains(query) ||
            UniversityOption.normalizeUniversityName(a).contains(normQuery),
      );
      return nameMatch || normNameMatch || cityMatch || typeMatch || aliasMatch;
    }).toList();

    final otherOption = all.where((u) => u.id == 'uni_other').firstOrNull;
    if (otherOption != null) matches.add(otherOption);
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final options = _filteredUniversities;
    final hasOnlyOther = options.length == 1 && options.first.id == 'uni_other';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select University',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                icon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                border: InputBorder.none,
                hintText: 'Search by name, abbreviation (AUC, GUC…), city, type',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (hasOnlyOther && _searchQuery.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                'No matching university found. Select Other to add your university.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          // Universities List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            TButton(label: 'Retry', onTap: _load),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: options.length,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemBuilder: (ctx, idx) {
                          final item = options[idx];
                          final isSel = widget.selectedOption?.id == item.id;
                          return UniversityOptionTile(
                            option: item,
                            isSelected: isSel,
                            onTap: () {
                              widget.onSelected(item);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Custom University Input Field when "Other" is selected.
class CustomUniversityField extends StatelessWidget {
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;

  const CustomUniversityField({
    super.key,
    required this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator ?? UniversityOption.validateCustomUniversityName,
      decoration: const InputDecoration(
        labelText: 'Enter your university name',
        hintText: 'e.g. Nile Valley Institute of Technology',
        prefixIcon: Icon(Icons.edit_note_outlined, color: AppColors.primary),
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Main Form Selector Field for University.
class UniversitySelectorField extends StatelessWidget {
  final UniversityOption? selectedOption;
  final ValueChanged<UniversityOption?> onSelected;
  final FormFieldValidator<String>? validator;

  const UniversitySelectorField({
    super.key,
    required this.selectedOption,
    required this.onSelected,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = selectedOption != null ? selectedOption!.name : '';

    return FormField<String>(
      initialValue: displayText,
      validator: (v) {
        if (selectedOption == null) {
          return 'University selection is required.';
        }
        return null;
      },
      builder: (fieldState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => UniversitySearchBottomSheet(
                    selectedOption: selectedOption,
                    onSelected: (opt) {
                      onSelected(opt);
                      fieldState.didChange(opt.name);
                    },
                  ),
                );
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'University *',
                  prefixIcon:
                      const Icon(Icons.school_outlined, color: AppColors.primary),
                  suffixIcon: selectedOption != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            onSelected(null);
                            fieldState.didChange(null);
                          },
                        )
                      : const Icon(Icons.keyboard_arrow_down,
                          color: AppColors.textSecondary),
                  border: const OutlineInputBorder(),
                  errorText: fieldState.errorText,
                ),
                child: Text(
                  displayText.isNotEmpty ? displayText : 'Select your university',
                  style: TextStyle(
                    fontSize: 14,
                    color: displayText.isNotEmpty
                        ? theme.colorScheme.onSurface
                        : AppColors.textHint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Your university helps Teamify recommend relevant teammates and teams.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }
}

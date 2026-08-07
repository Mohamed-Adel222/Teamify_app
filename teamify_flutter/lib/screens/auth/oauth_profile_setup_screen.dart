import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

import '../../data/registration_options.dart';

/// Collects profile fields after Google/GitHub sign-up (same data as email register).
class OAuthProfileSetupScreen extends StatefulWidget {
  const OAuthProfileSetupScreen({super.key});

  @override
  State<OAuthProfileSetupScreen> createState() =>
      _OAuthProfileSetupScreenState();
}

class _OAuthProfileSetupScreenState extends State<OAuthProfileSetupScreen> {
  bool _loading = false;
  bool _isStudent = false;

  String _professionalField = '';
  String _experienceLevel = 'Beginner';
  String _availability = '';
  String _currentLevel = 'Beginner';
  String _major = 'Computer Science';
  String _lookingForTeam = '';
  final List<String> _selectedSkills = [];

  static const _levelOptions = [
    'Beginner',
    'Junior',
    'Mid-Level',
    'Senior',
    'Expert',
  ];

  static List<String> get _majorOptions => RegistrationOptions.majors;
  static List<String> get _skillsOptions => RegistrationOptions.skills;

  @override
  void initState() {
    super.initState();
    final user = context.read<SessionController>().currentUser;
    _isStudent = user?.isStudent ?? false;
    if (_selectedSkills.isEmpty) {
      _selectedSkills.addAll(
        _isStudent ? ['Flutter', 'UI/UX Design'] : ['UI Design', 'UX Design'],
      );
    }
  }

  Future<void> _submit() async {
    if (_loading) return;

    if (_isStudent) {
      if (_major.isEmpty || _currentLevel.isEmpty || _selectedSkills.isEmpty) {
        _showError('Please complete major, level, and skills.');
        return;
      }
    } else {
      if (_professionalField.isEmpty ||
          _experienceLevel.isEmpty ||
          _availability.isEmpty ||
          _selectedSkills.isEmpty) {
        _showError(
            'Please complete field, experience, availability, and skills.');
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final session = context.read<SessionController>();
      final payload = <String, dynamic>{
        'user_type': _isStudent ? 'student' : 'freelancer',
        'skills': _selectedSkills,
      };
      if (_isStudent) {
        payload['current_level'] = _currentLevel;
        payload['major'] = _major;
        if (_lookingForTeam.isNotEmpty) {
          payload['looking_for_team'] = _lookingForTeam.toLowerCase() == 'yes';
        }
      } else {
        payload['professional_field'] = _professionalField;
        payload['experience_level'] = _experienceLevel;
        payload['availability'] = _availability;
      }

      final res =
          await context.read<AppServices>().users.updateProfile(payload);
      if (!mounted) return;
      res.when(
        success: (updated) {
          if (updated != null) {
            session.setCurrentUser(updated);
          }
          final route = _isStudent ? R.studentHome : R.freelancerHome;
          Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
        },
        failure: (e) => _showError(e),
      );
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSingleSelect(
    String title,
    List<String> options,
    String current,
    ValueChanged<String> onSelect,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            ...options.map(
              (opt) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  opt,
                  style: TextStyle(
                    color: opt == current
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        opt == current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: opt == current
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  onSelect(opt);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSkillsPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Primary Skills',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _skillsOptions.map((skill) {
                  final selected = _selectedSkills.contains(skill);
                  return FilterChip(
                    label: Text(skill),
                    selected: selected,
                    onSelected: (val) {
                      setModal(() {
                        if (val) {
                          _selectedSkills.add(skill);
                        } else {
                          _selectedSkills.remove(skill);
                        }
                      });
                      setState(() {});
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.1),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              TButton(label: 'Done', onTap: () => Navigator.pop(ctx)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().currentUser;
    final name = user?.primaryName ?? 'there';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $name',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete your profile so teammates can find you in projects.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              if (!_isStudent && (user?.userType.isEmpty ?? true)) ...[
                const Text(
                  'Account type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _typeChip('Freelancer', !_isStudent, () {
                        setState(() => _isStudent = false);
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _typeChip('Student', _isStudent, () {
                        setState(() => _isStudent = true);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              if (_isStudent) ...[
                _label('Current Level'),
                GestureDetector(
                  onTap: () => _showSingleSelect(
                    'Current Level',
                    _levelOptions,
                    _currentLevel,
                    (v) => setState(() => _currentLevel = v),
                  ),
                  child: _pickerField(_currentLevel),
                ),
                const SizedBox(height: 16),
                _label('Major'),
                GestureDetector(
                  onTap: () => _showSingleSelect(
                    'Major',
                    _majorOptions,
                    _major,
                    (v) => setState(() => _major = v),
                  ),
                  child: _pickerField(_major),
                ),
                const SizedBox(height: 16),
                _label('Looking for a team?'),
                ...['Yes', 'No'].map(
                  (v) => _radioRow(v, _lookingForTeam, (val) {
                    setState(() => _lookingForTeam = val);
                  }),
                ),
              ] else ...[
                _label('Professional Field'),
                ...[
                  'Designer',
                  'Developer',
                  'Marketer',
                  'Project Manager',
                  'Content Creator',
                  'Other',
                ].map(
                  (f) => _radioRow(f, _professionalField, (v) {
                    setState(() => _professionalField = v);
                  }),
                ),
                const SizedBox(height: 16),
                _label('Experience Level'),
                GestureDetector(
                  onTap: () => _showSingleSelect(
                    'Experience Level',
                    _levelOptions,
                    _experienceLevel,
                    (v) => setState(() => _experienceLevel = v),
                  ),
                  child: _pickerField(_experienceLevel),
                ),
                const SizedBox(height: 16),
                _label('Availability'),
                ...['Full Time', 'Part Time', 'Freelancer'].map(
                  (a) => _radioRow(a, _availability, (v) {
                    setState(() => _availability = v);
                  }),
                ),
              ],
              const SizedBox(height: 16),
              _label('Primary Skills'),
              GestureDetector(
                onTap: _showSkillsPicker,
                child: _pickerField(
                  _selectedSkills.isEmpty
                      ? 'Select skills'
                      : _selectedSkills.join(', '),
                ),
              ),
              const SizedBox(height: 32),
              TButton(
                label: _loading ? 'Saving…' : 'Continue',
                onTap: _loading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
        ),
      );

  Widget _pickerField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _radioRow(
    String label,
    String groupValue,
    ValueChanged<String> onChanged,
  ) {
    final selected = groupValue == label;
    return GestureDetector(
      onTap: () => onChanged(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

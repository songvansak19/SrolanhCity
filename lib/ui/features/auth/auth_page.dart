import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/assistant/assistant_bubble_suppressor.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../shell/main_shell.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  bool _otpRequested = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePhoneSubmit(Bilingual tr) async {
    final repo = ReportScope.read(context);
    final phone = _phoneController.text.trim();
    if (phone.length < 6) {
      setState(() {
        _errorMessage = tr.primary(
          'សូមបញ្ចូលលេខទូរស័ព្ទយ៉ាងតិច ៦ ខ្ទង់',
          'Please enter a phone number with at least 6 digits.',
        );
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    if (!_otpRequested) {
      if (repo.isOnline && repo.apiService.isConfigured) {
        await repo.apiService.requestPhoneOtp(phone);
      }
      if (!mounted) return;
      setState(() {
        _otpRequested = true;
        _submitting = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNode.requestFocus();
      });
      return;
    }

    final otp = _otpController.text.trim();
    if (otp.length < 4 || int.tryParse(otp) == null) {
      setState(() {
        _submitting = false;
        _errorMessage = tr.primary(
          'សូមបញ្ចូលលេខកូដ OTP ៤–៨ ខ្ទង់',
          'Please enter a 4–8 digit OTP code.',
        );
      });
      return;
    }

    final name = _nameController.text.trim();
    await repo.signInWithPhone(
      phoneNumber: phone,
      otpCode: otp,
      displayName: name,
    );
    if (!mounted) return;
    _enterApp();
  }

  Future<void> _handleGuestSignIn() async {
    final repo = ReportScope.read(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    await repo.signInAsGuest();
    if (!mounted) return;
    _enterApp();
  }

  void _enterApp() {
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return AssistantBubbleSuppressor(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                tooltip: tr.primary('ប្តូរភាសា', 'Switch language'),
                avatar: const Icon(
                  Icons.language,
                  size: 16,
                  color: AppColors.teal,
                ),
                label: Text(
                  repo.settings.englishFirst ? 'EN · ខ្មែរ' : 'ខ្មែរ · EN',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                onPressed: () {
                  repo.updateSettings(
                    repo.settings.copyWith(
                      englishFirst: !repo.settings.englishFirst,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.tealSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 32,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        tr.primary(
                          'ចូលគណនី SrolanhCity',
                          'Sign in to SrolanhCity',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr.primary(
                        'ប្រើលេខទូរស័ព្ទដើម្បីរក្សាទុករបាយការណ៍ ឬបន្តជាភ្ញៀវភ្លាមៗ',
                        'Use your phone number to save reports, or continue as a guest right away.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('auth-phone-field'),
                      controller: _phoneController,
                      enabled: !_submitting,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: InputDecoration(
                        labelText: tr.primary('លេខទូរស័ព្ទ', 'Phone number'),
                        hintText: '012 345 678',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('auth-name-field'),
                      controller: _nameController,
                      enabled: !_submitting,
                      textInputAction: _otpRequested
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: const [AutofillHints.name],
                      onSubmitted: _otpRequested
                          ? null
                          : (_) => unawaited(_handlePhoneSubmit(tr)),
                      decoration: InputDecoration(
                        labelText: tr.primary(
                          'ឈ្មោះបង្ហាញ (ជម្រើស)',
                          'Display name (optional)',
                        ),
                        hintText: tr.primary('សុខា', 'Sokha'),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (_otpRequested) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('auth-otp-field'),
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        enabled: !_submitting,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: 8,
                        onSubmitted: (_) => unawaited(_handlePhoneSubmit(tr)),
                        decoration: InputDecoration(
                          labelText: tr.primary('លេខកូដ OTP', 'OTP code'),
                          hintText: '123456',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ExcludeSemantics(
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: AppColors.danger,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: double.infinity,
                        minHeight: 50,
                      ),
                      child: FilledButton(
                        key: const Key('auth-submit-btn'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _submitting
                            ? null
                            : () => unawaited(_handlePhoneSubmit(tr)),
                        child: Text(
                          _otpRequested
                              ? tr.primary('បញ្ជាក់ និងចូល', 'Verify & Sign in')
                              : tr.primary('ផ្ញើលេខកូដ OTP', 'Send OTP'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            tr.primary('ឬ', 'or'),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: double.infinity,
                        minHeight: 50,
                      ),
                      child: OutlinedButton.icon(
                        key: const Key('auth-guest-btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.tealDark,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          side: const BorderSide(color: AppColors.teal),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _submitting
                            ? null
                            : () => unawaited(_handleGuestSignIn()),
                        icon: const Icon(Icons.person_outline_rounded),
                        label: Text(
                          tr.primary('បន្តជាភ្ញៀវ', 'Continue as Guest'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

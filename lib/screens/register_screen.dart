import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_snack_bar.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    var completed = false;

    try {
      await AuthService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      completed = true;
    } on AuthException catch (error) {
      if (!mounted) return;
      AppSnackBar.showError(context, error.message);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Lỗi đăng ký: $error');
    } finally {
      if (mounted && !completed) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIcon: Icon(icon, size: 21),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF475569),
      ),
      errorStyle: const TextStyle(fontSize: 12, height: 1.2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Đăng ký tài khoản'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDBEAFE),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person_add_alt_1,
                                      size: 40,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Tạo tài khoản mới',
                                  textAlign: TextAlign.center,
                                  style: textTheme.titleLarge?.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Nhập thông tin của bạn để bắt đầu sử dụng bản đồ.',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    height: 1.35,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                TextFormField(
                                  controller: _fullNameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [AutofillHints.name],
                                  style: const TextStyle(fontSize: 15),
                                  decoration: _inputDecoration(
                                    'Họ và tên',
                                    Icons.badge_outlined,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Vui lòng nhập họ và tên';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  style: const TextStyle(fontSize: 15),
                                  decoration: _inputDecoration(
                                    'Email',
                                    Icons.email_outlined,
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) {
                                      return 'Vui lòng nhập email';
                                    }
                                    if (!email.contains('@')) {
                                      return 'Email không hợp lệ';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  style: const TextStyle(fontSize: 15),
                                  decoration:
                                      _inputDecoration(
                                        'Mật khẩu',
                                        Icons.lock_outline,
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          tooltip: _obscurePassword
                                              ? 'Hiện mật khẩu'
                                              : 'Ẩn mật khẩu',
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                          ),
                                        ),
                                      ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Vui lòng nhập mật khẩu';
                                    }
                                    if (value.length < 6) {
                                      return 'Mật khẩu tối thiểu 6 ký tự';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) {
                                    if (!_isLoading) _register();
                                  },
                                ),
                                const SizedBox(height: 22),
                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: const Color(
                                        0xFFE2E8F0,
                                      ),
                                      disabledForegroundColor: const Color(
                                        0xFF64748B,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: _isLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.person_add_alt_1),
                                    label: Text(
                                      _isLoading ? 'Đang đăng ký' : 'Đăng ký',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () => Navigator.of(context).pop(false),
                                  icon: const Icon(Icons.login, size: 18),
                                  label: const Text(
                                    'Đã có tài khoản? Đăng nhập',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

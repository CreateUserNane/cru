import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiBaseOverride = String.fromEnvironment('API_BASE_URL');
String get _apiBase {
  if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
  final platform = defaultTargetPlatform;
  if (kIsWeb ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux) {
    return 'http://localhost:8000/api';
  }
  return 'http://10.0.2.2:8000/api';
}

const _tokenKey = 'cru_api_token';
const _canvas = Color(0xfff1f4f7);
const _surface = Color(0xffffffff);
const _ink = Color(0xff172a3a);
const _muted = Color(0xff6f7d89);
const _line = Color(0xffdce4ea);
const _accent = Color(0xff2169d5);
const _lime = Color(0xffe6efff);
const _danger = Color(0xffa43e45);

class CruUser {
  const CruUser({required this.username, required this.email});
  final String username;
  final String email;
  factory CruUser.fromJson(Map<String, dynamic> json) => CruUser(
    username: json['username'] as String,
    email: json['email'] as String,
  );
}

class AuthApi {
  static const _storage = FlutterSecureStorage();
  final _client = http.Client();

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse('$_apiBase/$path');
    final token = auth ? await _storage.read(key: _tokenKey) : null;
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final response = switch (method) {
      'POST' => await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      ),
      'PUT' => await _client.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      ),
      _ => await _client.get(uri, headers: headers),
    };
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = data['errors'] as Map<String, dynamic>?;
      final field = errors?.keys.first;
      final details = field == null ? null : errors?[field];
      final message = details is List && details.isNotEmpty
          ? details.first.toString()
          : (data['message'] ?? 'Request failed.').toString();
      if ((field == 'name' || field == 'username') &&
          message.contains('required')) {
        throw Exception('Enter a username to continue.');
      }
      throw Exception(
        message.replaceAll('The name field', 'The username field'),
      );
    }
    return data;
  }

  Future<CruUser?> restore() async {
    if (await _storage.read(key: _tokenKey) == null) return null;
    try {
      final data = await _request('user', auth: true);
      return CruUser.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      return null;
    }
  }

  Future<CruUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _request(path, method: 'POST', body: body);
    await _storage.write(key: _tokenKey, value: data['token'] as String);
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<CruUser> signup(String username, String email, String password) async {
    final data = await _request(
      'register',
      method: 'POST',
      body: {'username': username, 'email': email, 'password': password},
    );
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<CruUser> login(String email, String password) =>
      _authenticate('login', {'email': email, 'password': password});

  Future<CruUser> update(
    String username,
    String email,
    String? password,
  ) async {
    final body = <String, dynamic>{'username': username, 'email': email};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final data = await _request('user', method: 'PUT', body: body, auth: true);
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _request('logout', method: 'POST', auth: true);
    } finally {
      await _storage.delete(key: _tokenKey);
    }
  }
}

void main() => runApp(const CruApp());

class CruApp extends StatefulWidget {
  const CruApp({super.key});

  @override
  State<CruApp> createState() => _CruAppState();
}

class _CruAppState extends State<CruApp> {
  final _api = AuthApi();
  CruUser? _user;
  bool _loading = true;
  bool _hasAccount = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final user = await _api.restore();
    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
      });
    }
  }

  Future<void> _createAccount(
    String name,
    String email,
    String password,
  ) async {
    await _api.signup(name, email, password);
    if (mounted) {
      setState(() {
        _hasAccount = true;
      });
    }
  }

  Future<void> _signIn(String email, String password) async {
    final user = await _api.login(email, password);
    if (mounted) {
      setState(() {
        _user = user;
        _hasAccount = true;
      });
    }
  }

  Future<void> _updateProfile(
    String name,
    String email,
    String? password,
  ) async {
    final user = await _api.update(name, email, password);
    if (mounted) setState(() => _user = user);
  }

  Future<void> _signOut() async {
    try {
      await _api.logout();
    } finally {
      if (mounted) setState(() => _user = null);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MAXX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _canvas,
      fontFamily: 'Arial',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.light,
      ),
    ),
    home: _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _user != null
        ? ProfileScreen(
            user: _user!,
            onSave: _updateProfile,
            onSignOut: _signOut,
          )
        : AuthScreen(
            onCreate: _createAccount,
            onSignIn: _signIn,
            hasAccount: _hasAccount,
          ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onCreate,
    required this.onSignIn,
    required this.hasAccount,
  });
  final Future<void> Function(String, String, String) onCreate;
  final Future<void> Function(String, String) onSignIn;
  final bool hasAccount;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signup = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  String? _success;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _signup = !widget.hasAccount;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_signup) {
        await widget.onCreate(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
        if (mounted) {
          setState(() {
            _signup = false;
            _password.clear();
            _success = 'Account created. Log in to continue.';
          });
        }
      } else {
        await widget.onSignIn(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    body: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _ink,
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 42),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Text(
                            'MAXX',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 35),
                      const Text(
                        'More of what\nbrings you together.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'YOUR CIRCLE, ONE PLACE',
                        style: TextStyle(
                          color: Color(0xffb9c8d5),
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _line),
                    ),
                    child: _authForm(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _authForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 2),
      Text(
        _signup ? 'Create account' : 'Welcome back',
        style: const TextStyle(
          color: _ink,
          fontSize: 34,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        _signup
            ? 'A little space to keep up with your people.'
            : 'Pick up where your people are.',
        style: const TextStyle(color: _muted, fontSize: 15, height: 1.45),
      ),
      const SizedBox(height: 28),
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_signup) ...[
              _Field(
                controller: _name,
                label: 'Username',
                validator: (value) => (value == null || value.trim().length < 2)
                    ? 'Enter at least 2 characters.'
                    : null,
              ),
              const SizedBox(height: 18),
            ],
            _Field(
              controller: _email,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              validator: (value) =>
                  (value == null ||
                      !value.contains('@') ||
                      !value.contains('.'))
                  ? 'Enter a valid email address.'
                  : null,
            ),
            const SizedBox(height: 18),
            _Field(
              controller: _password,
              label: 'Password',
              obscure: !_showPassword,
              onChanged: (_) => setState(() {}),
              suffix: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                  color: _muted,
                ),
              ),
              validator: (value) => (value == null || value.length < 6)
                  ? 'Use at least 6 characters.'
                  : null,
            ),
            if (_signup && _password.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PasswordStrength(score: _passwordStrength),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: _danger, fontSize: 13),
              ),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(
                _success!,
                style: const TextStyle(color: Color(0xff367258), fontSize: 13),
              ),
            ],
            const SizedBox(height: 26),
            _PrimaryButton(
              label: _signup ? 'Create account' : 'Log in',
              onPressed: _submit,
              busy: _busy,
            ),
            const SizedBox(height: 18),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _signup ? 'Already registered? ' : 'New to MAXX? ',
                  style: const TextStyle(color: _muted, fontSize: 14),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _signup = !_signup;
                    _error = null;
                    _success = null;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(_signup ? 'Log in' : 'Create account'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  int get _passwordStrength {
    final value = _password.text;
    var score = value.length >= 6 ? 1 : 0;
    if (RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value)) {
      score++;
    }
    if (value.length >= 10 || RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      score++;
    }
    return score.clamp(0, 3).toInt();
  }
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final labels = ['Add a longer password', 'Getting there', 'Good', 'Strong'];
    final colors = [
      const Color(0xffdce4ea),
      const Color(0xffd56a51),
      const Color(0xffdfa53b),
      const Color(0xff32916c),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                decoration: BoxDecoration(
                  color: index < score
                      ? colors[score]
                      : const Color(0xffe6eaee),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          labels[score],
          style: TextStyle(
            color: score < 2 ? _muted : colors[score],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.onSave,
    required this.onSignOut,
  });
  final CruUser user;
  final Future<void> Function(String, String, String?) onSave;
  final Future<void> Function() onSignOut;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _editing = false;
  bool _saving = false;
  String? _notice;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _name.text.trim(),
        _email.text.trim(),
        _password.text,
      );
      if (mounted) {
        setState(() {
          _editing = false;
          _notice = 'Your details are up to date.';
          _password.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _Brand(),
                      IconButton(
                        tooltip: 'Log out',
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout_rounded, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                    decoration: BoxDecoration(
                      color: _surface,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: _lime,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              widget.user.username[0].toUpperCase(),
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.user.username,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.user.email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Account details',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 29,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _editing
                        ? 'Update your login details.'
                        : 'Your profile information.',
                    style: const TextStyle(color: _muted, fontSize: 15),
                  ),
                  const SizedBox(height: 30),
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Field(
                          controller: _name,
                          label: 'Username',
                          enabled: _editing,
                          validator: (value) =>
                              (value == null || value.trim().length < 2)
                              ? 'Enter at least 2 characters.'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        _Field(
                          controller: _email,
                          label: 'Email address',
                          enabled: _editing,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              (value == null ||
                                  !value.contains('@') ||
                                  !value.contains('.'))
                              ? 'Enter a valid email address.'
                              : null,
                        ),
                        if (_editing) ...[
                          const SizedBox(height: 18),
                          _Field(
                            controller: _password,
                            label: 'New password (optional)',
                            obscure: true,
                            validator: (value) =>
                                (value != null &&
                                    value.isNotEmpty &&
                                    value.length < 6)
                                ? 'Use at least 6 characters.'
                                : null,
                          ),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _notice!,
                            style: TextStyle(
                              color: _notice!.contains('up to date')
                                  ? const Color(0xff367258)
                                  : _danger,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        if (_editing)
                          Row(
                            children: [
                              Expanded(
                                child: _PrimaryButton(
                                  label: 'Save changes',
                                  icon: Icons.check_rounded,
                                  onPressed: _save,
                                  busy: _saving,
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: () => setState(() {
                                  _editing = false;
                                  _name.text = widget.user.username;
                                  _email.text = widget.user.email;
                                  _password.clear();
                                }),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ink,
                                  side: const BorderSide(color: _line),
                                  minimumSize: const Size(52, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(Icons.close_rounded),
                              ),
                            ],
                          )
                        else
                          _PrimaryButton(
                            label: 'Edit account',
                            icon: Icons.edit_outlined,
                            onPressed: () => setState(() {
                              _editing = true;
                              _notice = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Text(
    'MAXX',
    style: TextStyle(
      color: _ink,
      fontSize: 23,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscure, enabled;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    onChanged: onChanged,
    validator: validator,
    keyboardType: keyboardType,
    obscureText: obscure,
    enabled: enabled,
    style: const TextStyle(
      fontSize: 15,
      color: _ink,
      fontWeight: FontWeight.w500,
    ),
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      labelStyle: const TextStyle(color: _muted, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: _accent, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      errorStyle: const TextStyle(color: _danger, fontSize: 12, height: 1.2),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _accent.withValues(alpha: .65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    ),
  );
}

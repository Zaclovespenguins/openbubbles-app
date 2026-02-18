import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/app/layouts/setup/pages/sync/qr_code_scanner.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart';

class PasswordEditorPanel extends StatefulWidget {
  final api.PasswordManagerDefaultAnisetteProvider provider;
  final PasswordGroupType groupType;
  final String? id;
  final api.PasswordManagerMeta? passwordMeta;
  final api.WifiPassword? wifiPassword;

  const PasswordEditorPanel({
    super.key,
    required this.provider,
    required this.groupType,
    this.id,
    this.passwordMeta,
    this.wifiPassword,
  });

  @override
  State<PasswordEditorPanel> createState() => _PasswordEditorPanelState();
}

class _PasswordEditorPanelState extends OptimizedState<PasswordEditorPanel> {
  late final TextEditingController _serverController;
  late final TextEditingController _accountController;
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  bool _showPassword = false;
  final List<TextEditingController> _altDomainControllers = [];
  api.PasswordManagerTotp? _totp;

  bool _saving = false;

  bool get _isWifi => widget.groupType == PasswordGroupType.wifi;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: widget.passwordMeta?.srvr ?? "",
    );
    _accountController = TextEditingController(
      text: widget.passwordMeta?.acct ?? "",
    );
    _ssidController = TextEditingController(
      text: widget.wifiPassword?.acct ?? "",
    );
    _passwordController = TextEditingController(
      text: _isWifi
          ? _decodeWifiPassword(widget.wifiPassword)
          : _readPassword(widget.passwordMeta),
    );
    if (widget.passwordMeta != null) {
      final data = widget.passwordMeta!.getPasswordData();
      for (final domain in data.altDomains) {
        _altDomainControllers.add(TextEditingController(text: domain.domain));
      }
      _totp = data.totp;
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _accountController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    for (final controller in _altDomainControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _validate();
    return SettingsScaffold(
      title: widget.id == null ? "Create Password" : "Edit Password",
      initialHeader: _isWifi ? "Wi-Fi" : "Website",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      fab: error != null || _saving
          ? null
          : FloatingActionButton(
              backgroundColor: context.theme.colorScheme.primary,
              child: Icon(
                iOS ? CupertinoIcons.check_mark : Icons.done,
                color: context.theme.colorScheme.onPrimary,
                size: 25,
              ),
              onPressed: _save,
            ),
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            [
              SettingsSection(
                backgroundColor: tileColor,
                children: _isWifi ? _buildWifiFields(context) : _buildWebFields(context),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error,
                    style: context.theme.textTheme.bodyMedium!.copyWith(
                      color: context.theme.colorScheme.error,
                    ),
                  ),
                ),
              if (widget.id != null)
                const SizedBox(height: 12),
              if (widget.id != null)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Delete Entry",
                      trailing: Icon(
                        iOS ? CupertinoIcons.trash : Icons.delete_outline,
                        color: context.theme.colorScheme.error,
                      ),
                      onTap: _saving ? null : _confirmDelete,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildWebFields(BuildContext context) {
    return [
      _buildTextField(
        context,
        controller: _serverController,
        label: "Server",
        enabled: widget.id == null,
      ),
      const SettingsDivider(),
      _buildTextField(
        context,
        controller: _accountController,
        label: "Account",
      ),
      const SettingsDivider(),
      _buildTextField(
        context,
        controller: _passwordController,
        label: "Password",
        obscureText: !_showPassword,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword
                ? Icons.visibility_off
                : Icons.visibility,
          ),
        ),
      ),
      const SettingsDivider(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          "Secondary Servers",
          style: context.theme.textTheme.bodyLarge,
        ),
      ),
      for (var i = 0; i < _altDomainControllers.length; i++) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _altDomainControllers[i],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: "Domain",
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: context.theme.colorScheme.outline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: context.theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeAltDomain(i),
                icon: Icon(
                  iOS ? CupertinoIcons.delete : Icons.delete_outline,
                  color: context.theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: OutlinedButton.icon(
          onPressed: _addAltDomain,
          icon: const Icon(Icons.add),
          label: const Text("Add Secondary Server"),
        ),
      ),
      const SettingsDivider(),
      _buildTotpSection(context),
    ];
  }

  List<Widget> _buildWifiFields(BuildContext context) {
    return [
      _buildTextField(
        context,
        controller: _ssidController,
        label: "SSID",
      ),
      const SettingsDivider(),
      _buildTextField(
        context,
        controller: _passwordController,
        label: "Password",
        obscureText: !_showPassword,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword
                ? (iOS ? CupertinoIcons.eye_slash : Icons.visibility_off)
                : (iOS ? CupertinoIcons.eye : Icons.visibility),
          ),
        ),
      ),
    ];
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        onChanged: (_) => setState(() {}),
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffixIcon,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: context.theme.colorScheme.outline,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: context.theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  String? _validate() {
    if (_isWifi) {
      if (_ssidController.text.trim().isEmpty) {
        return "Please enter an SSID.";
      }
    } else {
      if (_serverController.text.trim().isEmpty) {
        return "Please enter a server.";
      }
      if (_accountController.text.trim().isEmpty) {
        return "Please enter an account.";
      }
    }
    if (_passwordController.text.trim().isEmpty) {
      return "Please enter a password.";
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      showSnackbar("Error", error);
      return;
    }
    setState(() => _saving = true);

    final id = widget.id ?? const Uuid().v4().toUpperCase();
    try {
      if (_isWifi) {
        final entry = _buildWifiEntry(
          existing: widget.wifiPassword,
        );
        await api.saveWifiPassword(
          passwords: widget.provider,
          id: id,
          entry: entry,
        );
      } else {
        final templateHistory = widget.passwordMeta == null
            ? await _maybeLoadPasswordHistoryTemplate()
            : null;
        final entry = _buildPasswordEntry(
          id: id,
          existing: widget.passwordMeta,
          historyTemplate: templateHistory,
        );
        await api.savePassword(
          passwords: widget.provider,
          id: id,
          entry: entry,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error, stack) {
      Logger.error("Failed to save password", error: error, trace: stack);
      final message = error is StateError
          ? error.message.toString()
          : "Unable to save password. $error";
      showSnackbar("Error", message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  int _nowDate() {
    return DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  Future<List<api.PasswordManagerMetaChange>?>
      _maybeLoadPasswordHistoryTemplate() async {
    final entries = await api.getPasswords(passwords: widget.provider);
    if (entries.isEmpty) {
      return null;
    }
    return entries.values.first.getPasswordData().history;
  }

  api.PasswordManagerMeta _buildPasswordEntry({
    required String id,
    api.PasswordManagerMeta? existing,
    List<api.PasswordManagerMetaChange>? historyTemplate,
  }) {
    final now = _nowDate();
    final existingData = existing?.getPasswordData();
    final server = _serverController.text.trim();
    final account = _accountController.text.trim();
    final history = _buildHistory(
      existingHistory: existingData?.history ?? historyTemplate,
      id: id,
      isNew: existing == null,
      existingMeta: existing,
      server: server,
      account: account,
      password: _passwordController.text,
    );
    final altDomains = _collectAltDomains();
    final data = api.PasswordManagerMeta.getData(
      data: api.PasswordManagerMetaData(
        history: history,
        altDomains: altDomains,
        totp: _totp,
        ctxt: existingData?.ctxt ?? const {},
      ),
    );
    return api.PasswordManagerMeta(
      cdat: existing?.cdat ?? now,
      mdat: now,
      srvr: server,
      acct: account,
      agrp: "com.apple.password-manager",
      data: data,
    );
  }

  List<api.PasswordManagerMetaChange> _buildHistory({
    required List<api.PasswordManagerMetaChange>? existingHistory,
    required String id,
    required bool isNew,
    required api.PasswordManagerMeta? existingMeta,
    required String server,
    required String account,
    required String password,
  }) {
    final history = existingHistory == null
        ? <api.PasswordManagerMetaChange>[]
        : List<api.PasswordManagerMetaChange>.from(existingHistory);
    final now = _nowDate();
    if (history.isEmpty) {
      return [
        api.PasswordManagerMetaChange(
          date: now,
          password: password,
          oldPassword: null,
          id: id,
          typ: "pwcr",
        ),
      ];
    }

    final last = history.last;
    final priorPassword = last.password;
    final passwordChanged = priorPassword != password;
    final serverChanged =
        existingMeta != null && existingMeta.srvr.trim() != server;
    final accountChanged =
        existingMeta != null && existingMeta.acct.trim() != account;
    final shouldAppend = !isNew &&
        passwordChanged;

    final updated = api.PasswordManagerMetaChange(
      date: now,
      password: password,
      oldPassword: shouldAppend ? priorPassword : (isNew ? null : priorPassword),
      id: id,
      typ: "pwch",
    );

    if (isNew) {
      return [updated];
    }
    if (shouldAppend) {
      return [...history, updated];
    }
    return history;
  }

  api.WifiPassword _buildWifiEntry({api.WifiPassword? existing}) {
    final now = _nowDate();
    return api.WifiPassword(
      cdat: existing?.cdat ?? now,
      mdat: now,
      acct: _ssidController.text.trim(),
      svce: "AirPort",
      data: Uint8List.fromList(utf8.encode(_passwordController.text)),
    );
  }

  String _readPassword(api.PasswordManagerMeta? entry) {
    if (entry == null) return "";
    final data = entry.getPasswordData();
    if (data.history.isEmpty) return "";
    return data.history.last.password;
  }

  String _decodeWifiPassword(api.WifiPassword? entry) {
    if (entry == null) return "";
    try {
      return utf8.decode(entry.data);
    } catch (_) {
      return "";
    }
  }

  Widget _buildTotpSection(BuildContext context) {
    if (_totp == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: OutlinedButton.icon(
          onPressed: _promptAddTotp,
          icon: const Icon(Icons.add),
          label: const Text("Add TOTP Code"),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TOTP",
            style: context.theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _copyTotpUri,
                icon: const Icon(Icons.link),
                label: const Text("Copy Link"),
              ),
              OutlinedButton.icon(
                onPressed: _deleteTotp,
                icon: Icon(
                  iOS ? CupertinoIcons.trash : Icons.delete_outline,
                ),
                label: const Text("Delete"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _deleteTotp() {
    setState(() => _totp = null);
  }

  Future<void> _copyTotpUri() async {
    final uri = _totp == null
        ? ""
        : (_totp!.originalUrl?.trim().isNotEmpty == true
            ? _totp!.originalUrl!.trim()
            : _buildTotpUri(_totp!));
    if (uri.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: uri));
    showSnackbar("Copied", "TOTP link copied to clipboard.");
  }

  Future<void> _promptAddTotp() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add TOTP"),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "TOTP URI or Secret",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                final scanned = await _scanTotpQr();
                if (scanned == null) return;
                if (_applyTotpInput(scanned)) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Scan QR"),
            ),
            TextButton(
              onPressed: () {
                final input = controller.text.trim();
                if (_applyTotpInput(input)) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  bool _applyTotpInput(String input) {
    if (input.isEmpty) {
      showSnackbar("Error", "Please enter a TOTP URI or secret.");
      return false;
    }
    try {
      final totp = _parseTotpInput(input);
      setState(() => _totp = totp);
      return true;
    } catch (error) {
      showSnackbar("Error", error.toString());
      return false;
    }
  }

  api.PasswordManagerTotp _parseTotpInput(String input) {
    if (input.toLowerCase().startsWith("otpauth://")) {
      return _parseTotpUri(input);
    }
    final secret = _decodeBase32(input);
    if (secret.isEmpty) {
      throw StateError("Invalid base32 secret.");
    }
    return api.PasswordManagerTotp(
      secret: secret,
      digits: 6,
      issuer: null,
      period: 30,
      initialDate: 0,
      algorithm: 0,
      accountName: null,
    );
  }

  api.PasswordManagerTotp _parseTotpUri(String input) {
    final uri = Uri.parse(input);
    if (uri.scheme != "otpauth") {
      throw StateError("Invalid otpauth URI.");
    }
    if (uri.host != "totp") {
      throw StateError("Only TOTP URIs are supported.");
    }
    final secretParam = uri.queryParameters["secret"];
    if (secretParam == null || secretParam.trim().isEmpty) {
      throw StateError("Missing secret in TOTP URI.");
    }
    final secret = _decodeBase32(secretParam);
    if (secret.isEmpty) {
      throw StateError("Invalid TOTP secret.");
    }
    final issuer = uri.queryParameters["issuer"];
    final digits = int.tryParse(uri.queryParameters["digits"] ?? "") ?? 6;
    final period = int.tryParse(uri.queryParameters["period"] ?? "") ?? 30;
    final algorithmLabel =
        (uri.queryParameters["algorithm"] ?? "SHA1").toUpperCase();
    final algorithm = switch (algorithmLabel) {
      "SHA1" => 0,
      "SHA256" => 1,
      "SHA512" => 2,
      _ => -1,
    };
    if (algorithm == -1) {
      throw StateError("Unsupported TOTP algorithm: $algorithmLabel");
    }
    final label = uri.pathSegments.isEmpty ? "" : uri.pathSegments.last;
    String? account;
    if (label.contains(":")) {
      final parts = label.split(":");
      account = parts.sublist(1).join(":");
    } else if (label.isNotEmpty) {
      account = label;
    }
    return api.PasswordManagerTotp(
      secret: secret,
      digits: digits,
      issuer: issuer?.trim().isEmpty ?? true ? null : issuer,
      period: period,
      initialDate: 0,
      algorithm: algorithm,
      accountName: account?.trim().isEmpty ?? true ? null : account,
    );
  }

  String _buildTotpUri(api.PasswordManagerTotp totp) {
    final secret = _encodeBase32(totp.secret);
    if (secret.isEmpty) return "";
    final algorithmLabel = switch (totp.algorithm) {
      0 => "SHA1",
      1 => "SHA256",
      2 => "SHA512",
      _ => "SHA1",
    };
    final query = <String, String>{
      "secret": secret,
      "digits": totp.digits.toString(),
      "period": totp.period.toString(),
      "algorithm": algorithmLabel,
    };
    return Uri(
      scheme: "otpauth",
      host: "totp",
      queryParameters: query,
    ).toString();
  }

  Future<String?> _scanTotpQr() async {
    PermissionStatus status = await Permission.camera.status;
    if (!status.isPermanentlyDenied && !status.isGranted) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        showSnackbar("Error", "Camera permission required for QR scanning!");
        return null;
      }
    } else if (status.isPermanentlyDenied) {
      showSnackbar("Error",
          "Camera permission permanently denied, please modify permissions.");
      return null;
    }

    try {
      Uint8List? response = await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (BuildContext context) {
            return QRCodeScanner();
          },
        ),
      );
      if (response == null || response.isEmpty) {
        throw StateError("No data was scanned.");
      }
      return utf8.decode(response);
    } catch (error) {
      showSnackbar("Error", error.toString());
      return null;
    }
  }

  Uint8List _decodeBase32(String input) {
    final normalized = input
        .trim()
        .replaceAll(" ", "")
        .replaceAll("=", "")
        .toUpperCase();
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    var buffer = 0;
    var bitsLeft = 0;
    final out = <int>[];
    for (final ch in normalized.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(ch));
      if (index == -1) {
        return Uint8List(0);
      }
      buffer = (buffer << 5) | index;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }

  String _encodeBase32(Uint8List bytes) {
    if (bytes.isEmpty) return "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    var buffer = 0;
    var bitsLeft = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        final index = (buffer >> (bitsLeft - 5)) & 31;
        bitsLeft -= 5;
        out.write(alphabet[index]);
      }
    }
    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 31;
      out.write(alphabet[index]);
    }
    return out.toString();
  }

  void _addAltDomain() {
    setState(() {
      _altDomainControllers.add(TextEditingController());
    });
  }

  void _removeAltDomain(int index) {
    setState(() {
      final controller = _altDomainControllers.removeAt(index);
      controller.dispose();
    });
  }

  List<api.PasswordManagerAltDomain> _collectAltDomains() {
    final domains = <String>{};
    for (final controller in _altDomainControllers) {
      final value = controller.text.trim();
      if (value.isEmpty) continue;
      domains.add(value);
    }
    return domains.map((domain) => api.PasswordManagerAltDomain(domain: domain)).toList();
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => areYouSure(
        context,
        title: "Delete Entry?",
        content: const Text("Are you sure you want to delete this entry?"),
        onNo: () => Navigator.of(context).pop(),
        onYes: () async {
          Navigator.of(context).pop();
          await _deleteEntry();
        },
      ),
    );
  }

  Future<void> _deleteEntry() async {
    final id = widget.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      switch (widget.groupType) {
        case PasswordGroupType.web:
          await api.deletePassword(passwords: widget.provider, id: id);
          break;
        case PasswordGroupType.passkeys:
          await api.deletePasskey(passwords: widget.provider, id: id);
          break;
        case PasswordGroupType.codes:
          await api.deletePassword(passwords: widget.provider, id: id);
          break;
        case PasswordGroupType.wifi:
          await api.deleteWifiPassword(passwords: widget.provider, id: id);
          break;
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      Logger.error("Failed to delete entry", error: e, trace: s);
      showSnackbar("Error", "Unable to delete entry. $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

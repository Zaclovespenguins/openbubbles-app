import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/helpers/types/helpers/date_helpers.dart';
import 'package:flutter/material.dart';
import 'package:cbor/simple.dart';

class CredentialField {
  final String label;
  final String value;

  const CredentialField(this.label, this.value);
}

abstract class CredentialItem {
  String get title;
  String get subtitle;
  IconData get icon;
  Color get color;
  List<CredentialField> get fields;
}

class BasicCredentialItem implements CredentialItem {
  @override
  final String title;
  @override
  final String subtitle;
  @override
  final IconData icon;
  @override
  final Color color;
  @override
  final List<CredentialField> fields;

  const BasicCredentialItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.fields,
  });
}

class CredentialEntry {
  final String id;
  final PasswordGroupType groupType;
  final CredentialItem item;
  final api.PasswordManagerMeta? passwordMeta;
  final api.WifiPassword? wifiPassword;

  const CredentialEntry({
    required this.id,
    required this.groupType,
    required this.item,
    this.passwordMeta,
    this.wifiPassword,
  });

  bool get isEditable =>
      groupType == PasswordGroupType.web || groupType == PasswordGroupType.wifi;
}

enum PasswordGroupType {
  web,
  passkeys,
  codes,
  wifi,
}

class PasswordGroupStyle {
  final IconData icon;
  final Color color;

  const PasswordGroupStyle(this.icon, this.color);
}

PasswordGroupStyle styleForPasswordGroup(PasswordGroupType type) {
  switch (type) {
    case PasswordGroupType.web:
      return const PasswordGroupStyle(Icons.public, Colors.blueAccent);
    case PasswordGroupType.passkeys:
      return const PasswordGroupStyle(Icons.key, Colors.deepPurple);
    case PasswordGroupType.codes:
      return const PasswordGroupStyle(Icons.security, Colors.teal);
    case PasswordGroupType.wifi:
      return const PasswordGroupStyle(Icons.wifi, Colors.orangeAccent);
  }
}

CredentialItem buildPasswordCredential({
  required api.PasswordManagerMeta meta,
  required api.PasswordManagerMetaData data,
  required PasswordGroupType groupType,
}) {
  final style = styleForPasswordGroup(groupType);
  final server = meta.srvr.trim();
  final account = meta.acct.trim();
  final title = server.isNotEmpty ? server : account;
  final subtitle = account;

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Saved Password",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      ..._buildCommonFields(meta),
      if (account.isNotEmpty) CredentialField("Account", account),
      if (server.isNotEmpty) CredentialField("Server", server),
      ..._buildPasswordFields(data),
    ],
  );
}

CredentialItem buildPasskeyCredential({required api.Passkey passkey}) {
  final style = styleForPasswordGroup(PasswordGroupType.passkeys);
  final label = passkey.labl.trim();
  final title = label;
  final tag = cbor.decode(passkey.atag) as Map<dynamic, dynamic>;
  final subtitle = tag["name"];

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Passkey",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      if (label.isNotEmpty) CredentialField("Site", label),
      if (passkey.agrp.trim().isNotEmpty)
      CredentialField("Created", _formatPlistDate(passkey.cdat)),
      CredentialField("Modified", _formatPlistDate(passkey.mdat)),
      CredentialField("Account", subtitle),
      // ..._bytesField("Attachment Tag", passkey.atag),
      // ..._bytesField("Key Label", passkey.klbl),
      // ..._bytesField("Data", passkey.data),
    ],
  );
}

CredentialItem buildWifiCredential({required api.WifiPassword wifi}) {
  final style = styleForPasswordGroup(PasswordGroupType.wifi);
  final ssid = wifi.acct.trim();
  final title = ssid;
  const subtitle = "WPA2 Personal";

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Wi-Fi Password",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      if (ssid.isNotEmpty) CredentialField("SSID", ssid),
      CredentialField("Created", _formatPlistDate(wifi.cdat)),
      CredentialField("Modified", _formatPlistDate(wifi.mdat)),
      ..._wifiPasswordField(wifi.data),
    ],
  );
}

List<CredentialField> _buildCommonFields(api.PasswordManagerMeta meta) {
  return [
    CredentialField("Created", _formatPlistDate(meta.cdat)),
    CredentialField("Modified", _formatPlistDate(meta.mdat)),
  ];
}

List<CredentialField> _buildPasswordFields(api.PasswordManagerMetaData data) {
  final fields = <CredentialField>[];
  final password = _currentPassword(data);
  if (password != null && password.isNotEmpty) {
    fields.add(CredentialField("Password", password));
  }
  if (data.altDomains.isNotEmpty) {
    fields.add(
      CredentialField(
        "Alternate Domains",
        data.altDomains.map((domain) => domain.domain).join(", "),
      ),
    );
  }
  return fields;
}

String? _currentPassword(api.PasswordManagerMetaData data) {
  if (data.history.isEmpty) {
    return null;
  }
  return data.history.last.password;
}

String _formatBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    return "";
  }
  return base64Encode(bytes);
}

String _formatPlistDate(int date) {
  if (date <= 0) return "";
  final dateTime =
      DateTime.fromMillisecondsSinceEpoch(date, isUtc: true).toLocal();
  return buildFullDate(dateTime);
}

List<CredentialField> _bytesField(String label, Uint8List bytes) {
  if (bytes.isEmpty) {
    return const [];
  }
  return [CredentialField(label, _formatBytes(bytes))];
}

List<CredentialField> _wifiPasswordField(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const [];
  }
  final password = _formatUtf8(bytes);
  if (password.isEmpty) {
    return const [];
  }
  return [CredentialField("Password", password)];
}

String _formatUtf8(Uint8List bytes) {
  if (bytes.isEmpty) {
    return "";
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return "";
  }
}

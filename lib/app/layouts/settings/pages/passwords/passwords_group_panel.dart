import 'package:bluebubbles/app/layouts/settings/pages/passwords/credential_detail_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_editor_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/passwords_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:get/get.dart';

class PasswordsGroupPanel extends StatefulWidget {
  final String title;
  final PasswordGroupType groupType;
  final api.PasswordManagerDefaultAnisetteProvider provider;

  const PasswordsGroupPanel({
    super.key,
    required this.title,
    required this.groupType,
    required this.provider,
  });

  @override
  State<PasswordsGroupPanel> createState() => _PasswordsGroupPanelState();
}

class _PasswordsGroupPanelState extends OptimizedState<PasswordsGroupPanel> {
  late Future<List<CredentialEntry>> _credentialsFuture;

  @override
  void initState() {
    super.initState();
    _credentialsFuture = _loadCredentials(widget.groupType);
  }

  Future<List<CredentialEntry>> _loadCredentials(PasswordGroupType type) async {
    switch (type) {
      case PasswordGroupType.web:
        final entries = await api.getPasswords(passwords: widget.provider);
        final items = entries.entries
            .map((entry) {
              final data = entry.value.getPasswordData();
              if (data.history.isEmpty) {
                return null;
              }
              return CredentialEntry(
                id: entry.key,
                groupType: type,
                item: buildPasswordCredential(
                  meta: entry.value,
                  data: data,
                  groupType: type,
                ),
                passwordMeta: entry.value,
              );
            })
            .whereType<CredentialEntry>()
            .toList(growable: false);
        items.sort(
          (a, b) => (b.passwordMeta?.mdat ?? 0).compareTo(
            a.passwordMeta?.mdat ?? 0,
          ),
        );
        return items;
      case PasswordGroupType.passkeys:
        final entries = await api.getPasskeys(passwords: widget.provider);
        final items = entries.entries
            .map(
              (entry) => CredentialEntry(
                id: entry.key,
                groupType: type,
                item: buildPasskeyCredential(passkey: entry.value),
              ),
            )
            .toList(growable: false);
        items.sort(
          (a, b) => (entries[b.id]?.mdat ?? 0).compareTo(
            entries[a.id]?.mdat ?? 0,
          ),
        );
        return items;
      case PasswordGroupType.codes:
        final entries = await api.getPasswords(passwords: widget.provider);
        final items = <CredentialEntry>[];
        for (final entry in entries.entries) {
          final data = entry.value.getPasswordData();
          if (data.totp == null) {
            continue;
          }
          items.add(
            CredentialEntry(
              id: entry.key,
              groupType: type,
              item: buildPasswordCredential(
                meta: entry.value,
                data: data,
                groupType: type,
              ),
              passwordMeta: entry.value,
            ),
          );
        }
        items.sort(
          (a, b) => (b.passwordMeta?.mdat ?? 0).compareTo(
            a.passwordMeta?.mdat ?? 0,
          ),
        );
        return items;
      case PasswordGroupType.wifi:
        final entries = await api.getWifiPasswords(passwords: widget.provider);
        final items = entries.entries
            .map(
              (entry) => CredentialEntry(
                id: entry.key,
                groupType: type,
                item: buildWifiCredential(wifi: entry.value),
                wifiPassword: entry.value,
              ),
            )
            .toList(growable: false);
        items.sort(
          (a, b) => (b.wifiPassword?.mdat ?? 0).compareTo(
            a.wifiPassword?.mdat ?? 0,
          ),
        );
        return items;
    }
  }

  EdgeInsets get _sectionPadding {
    if (ss.settings.skin.value == Skins.iOS) {
      return const EdgeInsets.symmetric(horizontal: 20);
    }
    if (ss.settings.skin.value == Skins.Samsung) {
      return const EdgeInsets.symmetric(vertical: 5);
    }
    return EdgeInsets.zero;
  }

  double get _sectionRadius {
    if (ss.settings.skin.value == Skins.Samsung) {
      return 25;
    }
    if (ss.settings.skin.value == Skins.iOS) {
      return 10;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: widget.title,
      initialHeader: "Credentials",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      headerColor: headerColor,
      tileColor: tileColor,
      fab: _buildFab(context),
      bodySlivers: [
        FutureBuilder<List<CredentialEntry>>(
          future: _credentialsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildStatusSliver(
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _buildStatusSliver(
                child: Text(
                  "Unable to load credentials. ${snapshot.error}",
                  style: context.theme.textTheme.bodyMedium,
                ),
              );
            }

            final credentials = snapshot.data ?? const <CredentialEntry>[];
            if (credentials.isEmpty) {
              return _buildStatusSliver(
                child: Text(
                  "No credentials saved in this group.",
                  style: context.theme.textTheme.bodyMedium,
                ),
              );
            }

            return SliverPadding(
              padding: _sectionPadding,
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = credentials[index];
                    final isFirst = index == 0;
                    final isLast = index == credentials.length - 1;
                    return ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isFirst ? _sectionRadius : 0),
                        topRight: Radius.circular(isFirst ? _sectionRadius : 0),
                        bottomLeft: Radius.circular(isLast ? _sectionRadius : 0),
                        bottomRight: Radius.circular(isLast ? _sectionRadius : 0),
                      ),
                      child: Container(
                        color: tileColor,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCredentialTile(entry),
                            if (!isLast) const SettingsDivider(),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: credentials.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCredentialTile(CredentialEntry entry) {
    Future<void> openDetails() async {
      final result = await ns.pushSettings(
        context,
        CredentialDetailPanel(
          credential: entry,
          provider: widget.provider,
        ),
      );
      if (result == true && mounted) {
        setState(
          () => _credentialsFuture = _loadCredentials(widget.groupType),
        );
      }
    }
    if (widget.groupType == PasswordGroupType.codes) {
      final totp = entry.passwordMeta?.getPasswordData().totp;
      return TotpCodeListTile(
        title: entry.item.title,
        subtitle: entry.item.subtitle,
        totp: totp,
        tileColor: tileColor,
        onLongPress: openDetails,
      );
    }
    return SettingsTile(
      backgroundColor: tileColor,
      title: entry.item.title,
      subtitle: entry.item.subtitle,
      onTap: openDetails,
      leading: CredentialAvatar(credential: entry.item),
      trailing: const NextButton(),
    );
  }

  SliverList _buildStatusSliver({required Widget child}) {
    return SliverList(
      delegate: SliverChildListDelegate(
        [
          SettingsSection(
            backgroundColor: tileColor,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildFab(BuildContext context) {
    if (widget.groupType != PasswordGroupType.web &&
        widget.groupType != PasswordGroupType.wifi) {
      return null;
    }
    return FloatingActionButton(
      backgroundColor: context.theme.colorScheme.primary,
      child: Icon(
        Icons.add,
        color: context.theme.colorScheme.onPrimary,
        size: 22,
      ),
      onPressed: () async {
        final result = await ns.pushSettings(
          context,
          PasswordEditorPanel(
            provider: widget.provider,
            groupType: widget.groupType,
          ),
        );
        if (result == true && mounted) {
          setState(
            () => _credentialsFuture = _loadCredentials(widget.groupType),
          );
        }
      },
    );
  }
}

class TotpCodeListTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final api.PasswordManagerTotp? totp;
  final Color tileColor;
  final VoidCallback? onLongPress;

  const TotpCodeListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.totp,
    required this.tileColor,
    this.onLongPress,
  });

  @override
  State<TotpCodeListTile> createState() => _TotpCodeListTileState();
}

class _TotpCodeListTileState extends State<TotpCodeListTile>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _expiryMicros = 0;
  String _code = "";

  @override
  void initState() {
    super.initState();
    _refreshCode();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshCode() {
    final totp = widget.totp;
    if (totp == null) {
      _code = "";
      _expiryMicros = 0;
      return;
    }
    final (code, expiry) = totp.generateOtp();
    _expiryMicros = expiry.toInt() * 1000000;
    _code = code.toString().padLeft(totp.digits, '0');
  }

  void _tick() {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    if (nowMicros >= _expiryMicros) {
      _refreshCode();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _copyCode() async {
    if (_code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _code));
    showSnackbar("Copied", "TOTP code copied to clipboard.");
  }

  @override
  Widget build(BuildContext context) {
    final totp = widget.totp;
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final periodMicros = (totp?.period ?? 0) * 1000000;
    final remainingMicros = (_expiryMicros - nowMicros).clamp(0, periodMicros);
    final progress = periodMicros == 0
        ? 0.0
        : (1.0 - (remainingMicros / periodMicros)).clamp(0.0, 1.0);
    return SettingsTile(
      backgroundColor: widget.tileColor,
      title: widget.title,
      subtitle: _code.isEmpty ? widget.subtitle : _code,
      onTap: _copyCode,
      onLongPress: widget.onLongPress,
      trailing: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          backgroundColor: context.theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
    );
  }
}

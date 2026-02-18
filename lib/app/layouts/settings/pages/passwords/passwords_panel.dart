import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/passwords_group_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/ui/ui_helpers.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:get/get.dart';

class PasswordsPanel extends StatefulWidget {
  const PasswordsPanel({super.key});

  @override
  State<PasswordsPanel> createState() => _PasswordsPanelState();
}

class _PasswordsPanelState extends OptimizedState<PasswordsPanel> {
  api.PasswordManagerDefaultAnisetteProvider? manager;
  bool _isCheckingClique = true;
  bool _isInClique = false;
  bool _isJoiningClique = false;

  @override
  void initState() {
    super.initState();
    _refreshCliqueStatus();
  }

  Future<void> _refreshCliqueStatus() async {
    final keychain = pushService.state?.icloudServices?.keychain;
    if (keychain == null) {
      if (!mounted) return;
      setState(() {
        _isInClique = false;
        _isCheckingClique = false;
      });
      return;
    }

    final inClique = await api.isInClique(keychain: keychain);
    if (inClique && manager == null) {
      manager = api.getPasswordManager(keychain: keychain);
      api.syncPasswords(passwords: manager!);
    }
    if (!mounted) return;
    setState(() {
      _isInClique = inClique;
      _isCheckingClique = false;
    });
  }

  Future<void> _joinClique() async {
    if (_isJoiningClique) return;
    final keychain = pushService.state?.icloudServices?.keychain;
    if (keychain == null) {
      showSnackbar(
        "Relog required!",
        "Relog required to use Passwords! Relog in Settings -> Reconfigure",
      );
      return;
    }

    setState(() => _isJoiningClique = true);
    try {
      await pushService.joinClique();
      await _refreshCliqueStatus();
    } finally {
      if (mounted) {
        setState(() => _isJoiningClique = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;

    if (_isCheckingClique) {
      return SettingsScaffold(
        title: "Passwords",
        initialHeader: null,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        headerColor: headerColor,
        tileColor: tileColor,
        bodySlivers: [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (!_isInClique) {
      return SettingsScaffold(
        title: "Passwords",
        initialHeader: null,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        headerColor: headerColor,
        tileColor: tileColor,
        bodySlivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              [
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "iCloud Keychain",
                ),
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Join iCloud Keychain Clique",
                      subtitle:
                          "Join this device to iCloud Keychain to view passwords, passkeys, codes, and Wi-Fi credentials.",
                      onTap: _isJoiningClique ? null : _joinClique,
                      trailing: _isJoiningClique
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.theme.colorScheme.primary,
                              ),
                            )
                          : const NextButton(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SettingsScaffold(
      title: "Passwords",
      initialHeader: null,
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      headerColor: headerColor,
      tileColor: tileColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            [
              if (isAndroid)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Configure device password and passkey providers",
                      subtitle:
                          "Enable to use iCloud Passkeys and Passwords on this device. To autofill passwords, set to preferred provider.",
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.settings,
                        materialIcon: Icons.settings,
                        containerColor: Colors.indigo,
                      ),
                      onTap: () async {
                        await mcs
                            .invokeMethod("open-autofill-provider-settings");
                      },
                      trailing: const NextButton(),
                    ),
                  ],
                ),
              SettingsHeader(
                    iosSubtitle: iosSubtitle,
                    materialSubtitle: materialSubtitle,
                    text: "Groups"),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  _buildGroupTile(
                    title: "Web Passwords",
                    subtitle: "Saved logins and recovery codes",
                    iosIcon: CupertinoIcons.globe,
                    materialIcon: Icons.public,
                    color: Colors.blueAccent,
                    groupType: PasswordGroupType.web,
                  ),
                  const SettingsDivider(),
                  _buildGroupTile(
                    title: "Passkeys",
                    subtitle: "Device-backed sign-ins",
                    iosIcon: Icons.key,
                    materialIcon: Icons.key,
                    color: Colors.deepPurple,
                    groupType: PasswordGroupType.passkeys,
                  ),
                  const SettingsDivider(),
                  _buildGroupTile(
                    title: "Codes",
                    subtitle: "Credentials with one-time codes",
                    iosIcon: CupertinoIcons.number,
                    materialIcon: Icons.security,
                    color: Colors.teal,
                    groupType: PasswordGroupType.codes,
                  ),
                  const SettingsDivider(),
                  _buildGroupTile(
                    title: "Wi-Fi Codes",
                    subtitle: "Saved networks and passphrases",
                    iosIcon: CupertinoIcons.wifi,
                    materialIcon: Icons.wifi,
                    color: Colors.orangeAccent,
                    groupType: PasswordGroupType.wifi,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTile({
    required String title,
    required String subtitle,
    required IconData iosIcon,
    required IconData materialIcon,
    required Color color,
    required PasswordGroupType groupType,
  }) {
    return SettingsTile(
      backgroundColor: tileColor,
      title: title,
      subtitle: subtitle,
      onTap: () {
        if (manager == null) return;
        ns.pushSettings(
          context,
          PasswordsGroupPanel(
            title: title,
            groupType: groupType,
            provider: manager!,
          ),
        );
      },
      leading: SettingsLeadingIcon(
        iosIcon: iosIcon,
        materialIcon: materialIcon,
        containerColor: color,
      ),
      trailing: const NextButton(),
    );
  }
}

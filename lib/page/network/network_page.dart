import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/lan_discovery_client.dart';
import 'package:pixez/network/network_mode.dart';

class NetworkPage extends StatefulWidget {
  final bool? automaticallyImplyLeading;

  const NetworkPage({Key? key, this.automaticallyImplyLeading})
    : super(key: key);

  @override
  _NetworkPageState createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late bool _automaticallyImplyLeading;
  late TextEditingController _textEditingController;
  bool _isScanning = false;
  List<DiscoveredServer> _discoveredServers = [];

  void _scanLanServers() async {
    if (!mounted) return;
    setState(() => _isScanning = true);
    final results = await lanDiscoveryClient.scan();
    if (!mounted) return;
    setState(() {
      _discoveredServers = results;
      _isScanning = false;
    });
  }

  @override
  void initState() {
    _textEditingController = TextEditingController(
      text: userSetting.pictureSource,
    );
    _automaticallyImplyLeading = widget.automaticallyImplyLeading ?? false;
    super.initState();
    if (userSetting.isServerMode) {
      _scanLanServers();
    }
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Observer(
        builder: (_) {
          return ListView(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                iconTheme: IconThemeData(
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
                automaticallyImplyLeading: _automaticallyImplyLeading,
                elevation: 0.0,
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  I18n.of(context).network,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  I18n.of(context).network_tip,
                  style: TextStyle(fontSize: 12.0, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildNetworkModeSetting(context),
              ),
              Visibility(
                visible: userSetting.networkMode.allowsImageSource,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(
                            I18n.of(context).image_site,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge!.color,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.refresh_outlined),
                            onPressed: () async {
                              userSetting.setPictureSource(ImageHost);
                              splashStore.setHost(ImageHost);
                              splashStore.helloWord = "= w =";
                              splashStore.maybeFetch();
                            },
                          ),
                        ),
                        ListTile(
                          title: Text(
                            I18n.of(context).default_title,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge!.color,
                            ),
                          ),
                          selected: userSetting.pictureSource == ImageHost,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          onTap: () async {
                            userSetting.setPictureSource(ImageHost);
                            splashStore.setHost(ImageHost);
                            splashStore.helloWord = "= w =";
                            splashStore.maybeFetch();
                          },
                        ),
                        ListTile(
                          title: Text(
                            ImageCatHost,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge!.color,
                            ),
                          ),
                          selected: userSetting.pictureSource == ImageCatHost,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          onTap: () async {
                            userSetting.setPictureSource(ImageCatHost);
                            splashStore.setHost(ImageCatHost);
                          },
                        ),
                        ListTile(
                          selected:
                              userSetting.pictureSource != ImageHost &&
                              userSetting.pictureSource != ImageCatHost,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          title: Theme(
                            data: Theme.of(context).copyWith(
                              primaryColor: Theme.of(
                                context,
                              ).colorScheme.secondary,
                            ),
                            child: TextField(
                              maxLines: 1,
                              controller: _textEditingController,
                              decoration: InputDecoration(
                                hintText: 'Host',
                                suffixIcon: IconButton(
                                  onPressed: () async {
                                    if (_textEditingController.text.isEmpty)
                                      return;
                                    if (_textEditingController.text
                                        .trim()
                                        .contains(" ")) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text("illegal"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }
                                    final host = _textEditingController.text
                                        .trim();
                                    await userSetting.setPictureSource(host);
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(FocusNode());
                                  },
                                  icon: Icon(Icons.check, color: Colors.black),
                                ),
                                labelText: I18n.of(context).custom_host,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildPixezServerSetting(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPixezServerSetting(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text('Pixez-s 无头服务端'),
            subtitle: Text(
              userSetting.isServerMode
                  ? '已启用（通过本地/远程服务端代理）'
                  : '未启用（单机直连 Pixiv）',
            ),
            value: userSetting.isServerMode,
            onChanged: (val) async {
              await userSetting.setServerMode(val);
              setState(() {});
              if (val && _discoveredServers.isEmpty) {
                _scanLanServers();
              }
            },
          ),
          if (userSetting.isServerMode) ...[
            Divider(height: 1),
            ListTile(
              title: Text('服务端地址'),
              subtitle: Text(userSetting.serverUrl),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () => _editServerUrl(context),
              ),
            ),
            ListTile(
              title: Text('局域网服务自动发现'),
              subtitle: Text(
                _isScanning
                    ? '正在扫描局域网服务...'
                    : (_discoveredServers.isEmpty
                        ? '未发现服务（点击右侧按钮扫描）'
                        : '发现 ${_discoveredServers.length} 个可用服务端'),
              ),
              trailing: _isScanning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: _scanLanServers,
                    ),
            ),
            if (_discoveredServers.isNotEmpty)
              ..._discoveredServers.map((server) {
                final isSelected = userSetting.serverUrl == server.primaryUrl;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.dns_outlined,
                    color: isSelected ? Colors.green : null,
                  ),
                  title: Text(server.hostName),
                  subtitle: Text(server.primaryUrl),
                  onTap: () async {
                    await userSetting.setServerUrl(server.primaryUrl);
                    setState(() {});
                  },
                );
              }),
          ],
        ],
      ),
    );
  }

  void _editServerUrl(BuildContext context) {
    final controller = TextEditingController(text: userSetting.serverUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设置 Pixez-s 服务端地址'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'http://192.168.1.100:8080',
            labelText: 'URL 地址',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await userSetting.setServerUrl(newUrl);
                setState(() {});
              }
              Navigator.of(ctx).pop();
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkModeSetting(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(I18n.of(context).network_mode),
            subtitle: Text(I18n.of(context).network_mode_restart_may_required),
          ),
          _buildModeGroup(
            context,
            title: I18n.of(context).network_mode_oauth,
            groupValue: userSetting.oauthNetworkMode,
            onChanged: userSetting.setOAuthNetworkMode,
          ),
          Divider(height: 1),
          _buildModeGroup(
            context,
            title: I18n.of(context).network_mode_api_service,
            groupValue: userSetting.networkMode,
            onChanged: userSetting.setNetworkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildModeGroup(
    BuildContext context, {
    required String title,
    required NetworkMode groupValue,
    required Future Function(NetworkMode value) onChanged,
  }) {
    return Column(
      children: [
        ListTile(title: Text(title)),
        RadioGroup<NetworkMode>(
          groupValue: groupValue,
          onChanged: (value) async {
            if (value == null || value == groupValue) return;
            await onChanged(value);
          },
          child: Column(
            children: NetworkMode.selectableValues.map((mode) {
              return RadioListTile<NetworkMode>(
                value: mode,
                title: Text(_networkModeTitle(context, mode)),
                subtitle: Text(_networkModeMessage(context, mode)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _networkModeTitle(BuildContext context, NetworkMode mode) {
    switch (mode) {
      case NetworkMode.compat:
        return I18n.of(context).network_mode_compat;
      case NetworkMode.ech:
        return I18n.of(context).network_mode_ech;
      case NetworkMode.standard:
        return I18n.of(context).network_mode_standard;
    }
  }

  String _networkModeMessage(BuildContext context, NetworkMode mode) {
    switch (mode) {
      case NetworkMode.compat:
        return 'bypass sni,doh';
      case NetworkMode.ech:
        return 'ech';
      case NetworkMode.standard:
        return 'standard';
    }
  }
}

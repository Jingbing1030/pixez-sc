import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/lan_discovery_client.dart';
import 'package:pixez/network/network_mode.dart';
import 'package:pixez/service/embedded_server_manager.dart';

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
    if (!EmbeddedServerManager.isSupported) {
      return Card(
        child: Column(
          children: [
            SwitchListTile(
              title: Text('Pixez-s 外置服务端'),
              subtitle: Text(
                userSetting.isServerMode
                    ? '已启用（通过远程/本地服务端代理）'
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
              _buildRemoteServerControls(context),
            ],
          ],
        ),
      );
    }

    final isEmbedded = userSetting.serverType == 'embedded';
    final serverRunning = embeddedServerManager.isRunning;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text('Pixez-s 服务端模式'),
            subtitle: Text(
              userSetting.isServerMode
                  ? (isEmbedded
                      ? '已启用：内置服务端（本机自建 All-in-One）'
                      : '已启用：外置服务端（远程 NAS/服务器）')
                  : '未启用（单机直连 Pixiv）',
            ),
            value: userSetting.isServerMode,
            onChanged: (val) async {
              if (val) {
                await userSetting.setServerMode(true);
                if (userSetting.serverType == 'disabled') {
                  await userSetting.setServerType('embedded');
                }
                if (userSetting.serverType == 'embedded') {
                  await embeddedServerManager.start();
                } else if (_discoveredServers.isEmpty) {
                  _scanLanServers();
                }
              } else {
                await userSetting.setServerMode(false);
                if (embeddedServerManager.isRunning) {
                  await embeddedServerManager.stop();
                }
              }
              setState(() {});
            },
          ),
          if (userSetting.isServerMode) ...[
            Divider(height: 1),
            ListTile(
              title: Text('服务端部署类型'),
              subtitle: Text(isEmbedded ? '内置服务端（本机运行）' : '外置独立服务端（局域网/远程）'),
              trailing: DropdownButton<String>(
                value: userSetting.serverType == 'disabled' ? 'embedded' : userSetting.serverType,
                underline: SizedBox(),
                items: [
                  DropdownMenuItem(value: 'embedded', child: Text('内置服务端 (本机)')),
                  DropdownMenuItem(value: 'remote', child: Text('外置服务端 (远程/NAS)')),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  await userSetting.setServerType(val);
                  if (val == 'embedded') {
                    await embeddedServerManager.start();
                  } else {
                    if (embeddedServerManager.isRunning) {
                      await embeddedServerManager.stop();
                    }
                    if (_discoveredServers.isEmpty) {
                      _scanLanServers();
                    }
                  }
                  setState(() {});
                },
              ),
            ),
            if (isEmbedded) ...[
              Divider(height: 1),
              ListTile(
                leading: Icon(
                  serverRunning ? Icons.check_circle : Icons.pause_circle_outline,
                  color: serverRunning ? Colors.green : Colors.grey,
                ),
                title: Text(serverRunning ? '内置服务端正在运行' : '内置服务端已停止'),
                subtitle: Text(
                  serverRunning
                      ? '监听端口: ${embeddedServerManager.actualPort ?? userSetting.embeddedPort}' +
                          (embeddedServerManager.lanIps.isNotEmpty && userSetting.embeddedLanShare
                              ? '\n局域网共享: http://${embeddedServerManager.lanIps.first}:${embeddedServerManager.actualPort}'
                              : '')
                      : (embeddedServerManager.lastError != null
                          ? '启动失败: ${embeddedServerManager.lastError}'
                          : '点击右侧按钮启动'),
                ),
                trailing: TextButton.icon(
                  icon: Icon(serverRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(serverRunning ? '停止' : '启动'),
                  onPressed: () async {
                    if (serverRunning) {
                      await embeddedServerManager.stop();
                    } else {
                      await embeddedServerManager.start();
                    }
                    setState(() {});
                  },
                ),
              ),
              SwitchListTile(
                title: Text('开机/启动应用时自启'),
                subtitle: Text('打开 Pixez-cs 时自动在后台启动内置服务端'),
                value: userSetting.embeddedAutoStart,
                onChanged: (val) async {
                  await userSetting.setEmbeddedAutoStart(val);
                  setState(() {});
                },
              ),
              SwitchListTile(
                title: Text('允许局域网共享'),
                subtitle: Text('开启 UDP 广播并在 0.0.0.0 监听，允许家中其他设备连入此手机/电脑'),
                value: userSetting.embeddedLanShare,
                onChanged: (val) async {
                  await userSetting.setEmbeddedLanShare(val);
                  if (serverRunning) {
                    await embeddedServerManager.restart();
                  }
                  setState(() {});
                },
              ),
            ] else ...[
              Divider(height: 1),
              _buildRemoteServerControls(context),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRemoteServerControls(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text('外置服务端地址'),
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

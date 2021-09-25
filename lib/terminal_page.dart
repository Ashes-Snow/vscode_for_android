import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:global_repository/global_repository.dart';
import 'package:pseudo_terminal_utils/pseudo_terminal_utils.dart';
import 'package:termare_pty/termare_pty.dart';
import 'package:termare_view/termare_view.dart';
import 'package:vscode_for_android/assets_utils.dart';
import 'plugin_util.dart';

String prootDistroPath = '${RuntimeEnvir.usrPath}/var/lib/proot-distro';
String lockFile = RuntimeEnvir.dataPath + '/cache/init_lock';
String source = '''
deb [trusted=yes] http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ hirsute main universe multiverse
deb [trusted=yes] http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ hirsute-updates main universe multiverse
deb [trusted=yes] http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ hirsute-security main universe multiverse
''';

String colorEcho = '''
colorEcho(){
  echo -e "\x1b[31m\$@\x1b[0m"
}
''';

String installVsCodeScriptWithoutFullLinux = '''
$colorEcho
install_vs_code(){
  colorEcho - 安装依赖
  apt-get install -y libllvm
  apt-get install -y clang
  apt-get install -y nodejs
  apt-get install -y python
  apt-get install -y yarn
  colorEcho - 解压 Vs Code Arm64
  cd ~
  unzip code-server-3.11.1-linux-arm64.zip
  colorEcho - 执行 yarn install
  cd code-server-3.11.1-linux-arm64
  yarn config set registry https://registry.npm.taobao.org --global
  yarn config set disturl https://npm.taobao.org/dist --global
  npm config set registry https://registry.npm.taobao.org
  yarn install
}
''';

String installVsCodeScriptWithFullLinux = '''
$colorEcho
install_vs_code(){
  cd ~
  colorEcho - 安装Ubuntu Linux
  unzip proot-distro.zip >/dev/null
  cd ~/proot-distro
  bash ./install.sh
  apt-get install -y proot
  proot-distro install ubuntu
  echo '$source' > $prootDistroPath/installed-rootfs/ubuntu/etc/apt/sources.list
  cd $prootDistroPath/installed-rootfs/ubuntu/home
  colorEcho - 解压 Vs Code Arm64
  unzip ~/code-server-3.11.1-linux-arm64.zip >/dev/null
  cd code-server-3.11.1-linux-arm64
}
''';

// TODO 加上端口的kill
String startVsCodeScript = '''
start_vs_code(){
  mkdir -p $prootDistroPath/installed-rootfs/ubuntu/root/.config/code-server 2>/dev/null
  echo '
  bind-addr: 0.0.0.0:8080
  auth: none
  password: none
  cert: false
  ' > $prootDistroPath/installed-rootfs/ubuntu/root/.config/code-server/config.yaml
  echo -e "\x1b[31m- 启动中..\x1b[0m"
  proot-distro login ubuntu -- /home/code-server-3.11.1-linux-arm64/bin/code-server
}
''';

String initShell = '''
$installVsCodeScriptWithFullLinux
$startVsCodeScript
function initApp(){
  cd ${RuntimeEnvir.usrPath}/
  echo 准备符号链接...
  for line in `cat SYMLINKS.txt`
  do
    OLD_IFS="\$IFS"
    IFS="←"
    arr=(\$line)
    IFS="\$OLD_IFS"
    ln -s \${arr[0]} \${arr[3]}
  done
  rm -rf SYMLINKS.txt
  TMPDIR=/data/data/com.nightmare.termare/files/usr/tmp
  filename=bootstrap
  rm -rf "\$TMPDIR/\$filename*"
  rm -rf "\$TMPDIR/*"
  chmod -R 0777 ${RuntimeEnvir.binPath}/*
  chmod -R 0777 ${RuntimeEnvir.usrPath}/lib/* 2>/dev/null
  chmod -R 0777 ${RuntimeEnvir.usrPath}/libexec/* 2>/dev/null
  apt update
  rm -rf $lockFile
  export LD_PRELOAD=${RuntimeEnvir.usrPath}/lib/libtermux-exec.so
  install_vs_code
  start_vs_code
  bash
}
''';

class TerminalPage extends StatefulWidget {
  const TerminalPage({Key key}) : super(key: key);

  @override
  _TerminalPageState createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  PseudoTerminal pseudoTerminal;
  bool vsCodeStaring = false;
  Widget webview;
  bool hasBash() {
    final File bashFile = File(RuntimeEnvir.binPath + '/bash');
    final bool exist = bashFile.existsSync();
    return exist;
  }

  final TermareController controller = TermareController();
  Future<void> createPtyTerm() async {
    if (Platform.isAndroid) {
      if (!hasBash()) {
        // 初始化后 bash 应该存在
        initTerminal(controller);
        return;
      }
    }
    pseudoTerminal = TerminalUtil.getShellTerminal(exec: 'bash');
    await pseudoTerminal.defineTermFunc(startVsCodeScript);
    setState(() {});
    vsCodeListien();
    startVsCode(pseudoTerminal);
  }

  Future<void> startVsCode(PseudoTerminal pseudoTerminal) async {
    vsCodeStaring = true;
    setState(() {});
    pseudoTerminal.write('''clear && start_vs_code\n''');
  }

  Future<void> vsCodeListien() async {
    // WebView.platform = SurfaceAndroidWebView();
    final Completer completer = Completer();
    pseudoTerminal.out.listen((event) {
      if (event.contains('http://0.0.0.0:8080')) {
        completer.complete();
      }
      Log.w('event -> $event');
    });
    await completer.future;
    PlauginUtil.openWebView();
    // webview = const Scaffold(
    //   body: WebView(
    //     initialUrl: 'http://127.0.0.1:8080',
    //     javascriptMode: JavascriptMode.unrestricted,
    //   ),
    // );
    setState(() {});
    // Navigator.of(context).push(
    //   CustomRoute(
    //     const Scaffold(
    //       body: WebView(
    //         initialUrl: 'http://127.0.0.1:8080',
    //         javascriptMode: JavascriptMode.unrestricted,
    //       ),
    //     ),
    //   ),
    // );
    Future.delayed(const Duration(milliseconds: 2000), () {
      vsCodeStaring = false;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [],
      );
      setState(() {});
    });
  }

  Future<void> initTerminal(TermareController controller) async {
    // 这个 await 为了不弹太快
    // AssetsUtils
    // await Future.delayed(const Duration(milliseconds: 300));
    // await showDialog(
    //   context: context,
    //   builder: (_) {
    //     return DownloadBootPage();
    //   },
    // );
    pseudoTerminal = TerminalUtil.getShellTerminal(useIsolate: false);
    vsCodeListien();
    pseudoTerminal.startPolling();
    await pseudoTerminal.defineTermFunc(
      initShell,
      tmpFilePath: RuntimeEnvir.filesPath + '/define',
    );
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 100));
    controller.write('解压资源中...\r\n');
    await AssetsUtils.copyAssetToPath(
      'assets/bootstrap-aarch64.zip',
      RuntimeEnvir.tmpPath + '/bootstrap-aarch64.zip',
    );
    await AssetsUtils.copyAssetToPath(
      'assets/proot-distro.zip',
      RuntimeEnvir.homePath + '/proot-distro.zip',
    );
    Directory('$prootDistroPath/dlcache').createSync(
      recursive: true,
    );
    await AssetsUtils.copyAssetToPath(
      'assets/code-server-3.11.1-linux-arm64.zip',
      RuntimeEnvir.homePath + '/code-server-3.11.1-linux-arm64.zip',
    );
    await AssetsUtils.copyAssetToPath(
      'assets/ubuntu-aarch64-pd-v2.3.1.tar.xz',
      '$prootDistroPath/dlcache/ubuntu-aarch64-pd-v2.3.1.tar.xz',
    );
    await installModule(RuntimeEnvir.tmpPath + '/bootstrap-aarch64.zip');
    pseudoTerminal.write('initApp\n');
  }

  Future<void> installModule(String modulePath) async {
    // Read the Zip file from disk.
    final bytes = File(modulePath).readAsBytesSync();
    // Decode the Zip file
    final archive = ZipDecoder().decodeBytes(bytes);
    // Extract the contents of the Zip archive to disk.
    final int total = archive.length;
    int count = 0;
    // print('total -> $total count -> $count');
    for (final file in archive) {
      final filename = file.name;
      final String path = '${RuntimeEnvir.usrPath}/$filename';
      print(path);
      if (file.isFile) {
        final data = file.content as List<int>;
        await File(path).create(recursive: true);
        await File(path).writeAsBytes(data);
      } else {
        Directory(path).create(
          recursive: true,
        );
      }
      count++;
      print('total -> $total count -> $count');
      setState(() {});
    }
    File(modulePath).delete();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    createPtyTerm();
  }

  @override
  Widget build(BuildContext context) {
    if (pseudoTerminal == null) {
      return const SizedBox();
    }
    return WillPopScope(
      onWillPop: () async {
        pseudoTerminal.write('\x03');
        return true;
      },
      child: Stack(
        children: [
          TermarePty(
            controller: controller,
            pseudoTerminal: pseudoTerminal,
          ),
          if (vsCodeStaring)
            Material(
              color: Colors.black,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SpinKitDualRing(
                      color: Theme.of(context).primaryColor,
                      size: 18.w,
                      lineWidth: 2.w,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    const Text(
                      'VS Code 启动中...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (webview != null)
            Opacity(
              opacity: vsCodeStaring ? 0 : 1.0,
              child: webview,
            ),
        ],
      ),
    );
  }
}
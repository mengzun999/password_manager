import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

abstract class NoBackStatefulPage<T extends ConsumerStatefulWidget> extends ConsumerState<T> {
  String get title;
  List<Widget>? get actions => null;
  Widget buildContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          actions: actions,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            // ✅ 只给状态栏区域加背景
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).padding.top,
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            // ✅ 主体内容
            SafeArea(
              child: buildContent(context),
            ),
          ],
        ),
      ),
    );
  }
}
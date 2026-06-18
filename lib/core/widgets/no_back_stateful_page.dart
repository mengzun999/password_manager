import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class NoBackStatefulPage<T extends ConsumerStatefulWidget> extends ConsumerState<T> {
  String get title;
  List<Widget>? get actions => null;
  Widget buildContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,  // ✅ 添加这行
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          actions: actions,
          backgroundColor: Colors.transparent,  // ✅ 添加这行
          elevation: 0,  // ✅ 添加这行
        ),
        body: SafeArea(
          child: buildContent(context),
        ),
      ),
    );
  }
}
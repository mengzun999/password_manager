import 'package:flutter/material.dart';

abstract class NoBackPage extends StatelessWidget {
  const NoBackPage({super.key});

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
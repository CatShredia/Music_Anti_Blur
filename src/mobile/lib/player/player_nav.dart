import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void openPlayer(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.routerDelegate.currentConfiguration.uri.path == '/player') {
    return;
  }
  router.push('/player');
}

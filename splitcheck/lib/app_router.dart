import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/receipt/pages/create_receipt_page.dart';
import 'features/receipt/pages/public_receipt_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const CreateReceiptPage()),
    GoRoute(
      path: '/r/:slug',
      builder: (context, state) =>
          PublicReceiptPage(slug: state.pathParameters['slug']!),
    ),
  ],
  errorBuilder: (context, state) =>
      const Scaffold(body: Center(child: Text('Not found'))),
);

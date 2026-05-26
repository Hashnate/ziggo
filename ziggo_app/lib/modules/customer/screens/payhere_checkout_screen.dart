// PayHere hosted-checkout WebView.
//
// Loads a tiny HTML page that auto-submits a form with the signed PayHere
// fields to the hosted checkout URL. The user pays. PayHere then redirects
// to our `return_url` (success) or `cancel_url` (cancel). We watch for
// those navigations and pop the screen.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayHereCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final Map<String, dynamic> formFields;

  const PayHereCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.formFields,
  });

  @override
  State<PayHereCheckoutScreen> createState() => _PayHereCheckoutScreenState();
}

class _PayHereCheckoutScreenState extends State<PayHereCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (_) {},
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('https://ziggo.app/payhere/return')) {
            // PayHere considers this a successful redirect — pop with true.
            Navigator.of(context).pop(true);
            return NavigationDecision.prevent;
          }
          if (url.startsWith('https://ziggo.app/payhere/cancel')) {
            Navigator.of(context).pop(false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_buildAutoSubmitForm());
  }

  /// Build a one-page HTML form that auto-submits to PayHere. This is the
  /// standard pattern from PayHere's docs — the form posts the signed
  /// fields, the user lands on the hosted payment page.
  String _buildAutoSubmitForm() {
    final inputs = widget.formFields.entries.map((e) {
      final v = (e.value ?? '').toString();
      final escaped = const HtmlEscape().convert(v);
      return '<input type="hidden" name="${e.key}" value="$escaped">';
    }).join('\n');
    final action = const HtmlEscape().convert(widget.checkoutUrl);
    return '''
<!doctype html>
<html><head><meta charset="utf-8"><title>Redirecting to PayHere…</title>
<style>body{font-family:-apple-system,Roboto,sans-serif;background:#f5f6fa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#333}</style>
</head>
<body>
  <div>Connecting to PayHere…</div>
  <form id="phForm" method="post" action="$action">
$inputs
  </form>
  <script>document.getElementById('phForm').submit();</script>
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with PayHere'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

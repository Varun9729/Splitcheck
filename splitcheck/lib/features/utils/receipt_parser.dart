// utils/receipt_parser.dart

import 'package:splitcheck/models/receipt_model.dart';

class ParsedReceipt {
  final List<ReceiptItem> items;
  final double subtotal;
  final double tax;
  final double tip;
  final double total;

  ParsedReceipt({
    required this.items,
    this.subtotal = 0.0,
    this.tax = 0.0,
    this.tip = 0.0,
    this.total = 0.0,
  });
}

String normalize(String line) {
  return line
      .replaceAll(RegExp(r'[^\w\s\.\$\d]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

ParsedReceipt parseReceiptText(String text) {
  final lines = text.split('\n');
  final items = <ReceiptItem>[];

  double subtotal = 0.0;
  double tax = 0.0;
  double tip = 0.0;
  double total = 0.0;

  // Collect all quantity items and all standalone prices
  List<Map<String, dynamic>> allItems = [];
  List<double> allPrices = [];

  print("=== STEP 1: COLLECTING ITEMS AND PRICES ===");

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final normalized = normalize(line);
    print("Line $i: '$line' -> '$normalized'");

    // Skip unwanted lines
    if (line.contains('[') ||
        normalized.contains('tip') && normalized.contains('%') ||
        RegExp(r'^[A-Za-z\s]+,\s*[A-Z]{2}\s+\d{5}').hasMatch(line) ||
        _isHeaderLine(normalized, i) ||
        _isFooterLine(normalized)) {
      print("  -> Skipped");
      continue;
    }

    // ✅ Extra: Inline subtotal/tax/tip/total like "Subtotal 45.67"
    final inlineTotalMatch = RegExp(
      r'^(subtotal|tax|tip|total)\s+\$?(\d+(?:\.\d{1,2})?)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (inlineTotalMatch != null) {
      final label = inlineTotalMatch.group(1)!.toLowerCase();
      final price = double.tryParse(inlineTotalMatch.group(2)!) ?? 0.0;
      if (price > 0.0) {
        if (label == "subtotal") {
          subtotal = price;
          print("  -> Inline subtotal: \$${price}");
        } else if (label == "tax") {
          tax = price;
          print("  -> Inline tax: \$${price}");
        } else if (label == "tip") {
          tip = price;
          print("  -> Inline tip: \$${price}");
        } else if (label == "total") {
          total = price;
          print("  -> Inline total: \$${price}");
        }
        continue;
      }
    }

    // Collect quantity items
    final quantityMatch = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (quantityMatch != null) {
      final quantity = int.tryParse(quantityMatch.group(1)!) ?? 1;
      final name = quantityMatch.group(2)!.trim();

      if (name.length >= 3 && !_isSystemLine(name)) {
        allItems.add({'name': name, 'quantity': quantity});
        print("  -> Item: $quantity x '$name'");
        continue;
      }
    }

    // Collect totals with next-line prices
    if (_parseTotalLine(normalized) && i + 1 < lines.length) {
      final nextLine = lines[i + 1].trim();
      final nextPriceMatch = RegExp(
        r'^\s*\$?(\d+(?:\.\d{1,2})?)\s*$',
      ).firstMatch(nextLine);

      if (nextPriceMatch != null) {
        final price = double.tryParse(nextPriceMatch.group(1)!) ?? 0.0;

        // Only accept reasonable prices for totals
        if (price > 0.50) {
          if (normalized == 'subtotal') {
            subtotal = price;
            print("  -> Subtotal: \$${price}");
          } else if (normalized == 'tax') {
            tax = price;
            print("  -> Tax: \$${price}");
          } else if (normalized == 'total' && total == 0.0 && price < 2000) {
            total = price;
            print("  -> Total: \$${price}");
          }

          i++; // Skip next line
          continue;
        }
      }
    }

    // Collect standalone prices
    final priceMatch = RegExp(
      r'^\s*(?:\$?\s*(\d+(?:\.\d{1,2})?)|\s*(\d+(?:\.\d{1,2})?)\$)\s*$',
    ).firstMatch(line);

    if (priceMatch != null) {
      final price = double.tryParse(
        priceMatch.group(1) ?? priceMatch.group(2) ?? '',
      );
      if (price! > 0) {
        // Check for handwritten total (priority over label totals)
        if (subtotal > 0 && tax > 0) {
          final receiptTotal = subtotal + tax;
          if (price > receiptTotal + 1.0) {
            tip = double.parse((price - receiptTotal).toStringAsFixed(2));
            total = price;
            print(
              "  -> Handwritten total: \$${price}, calculated tip: \$${tip}",
            );
            continue;
          }
        }

        allPrices.add(price);
        print("  -> Price: \$${price}");
      }
      continue;
    }
  }

  print("=== STEP 2: ASSIGNING PRICES TO ITEMS ===");
  print("Items found: ${allItems.length}");
  print("Prices found: ${allPrices.length}");

  // Assign first N prices to items
  int itemCount = allItems.length;

  for (int i = 0; i < itemCount && i < allPrices.length; i++) {
    final item = allItems[i];
    final price = allPrices[i];
    final name = item['name'] as String;
    final quantity = item['quantity'] as int;

    print("Assigning \$${price} to $quantity x '$name'");

    for (int j = 0; j < quantity; j++) {
      items.add(ReceiptItem(itemName: name, itemPrice: price / quantity));
    }
  }

  // Assign remaining prices to totals if not already set
  List<double> remainingPrices = allPrices.skip(itemCount).toList();
  remainingPrices.sort();

  print("=== STEP 3: ASSIGNING REMAINING PRICES TO TOTALS ===");
  print("Remaining prices: ${remainingPrices.map((p) => '\$${p}').join(', ')}");

  for (final price in remainingPrices) {
    if (tax == 0.0 && price < 20) {
      tax = price;
      print("Assigned tax: \$${price}");
    } else if (subtotal == 0.0 && price > 20) {
      subtotal = price;
      print("Assigned subtotal: \$${price}");
    } else if (total == 0.0 && price > subtotal) {
      total = price;
      print("Assigned total: \$${price}");
    }
  }

  // Calculate missing values
  if (total == 0.0) {
    total = subtotal + tax + tip;
  }

  if (tip == 0.0 && total > subtotal + tax + 0.5) {
    tip = double.parse((total - subtotal - tax).toStringAsFixed(2));
  }

  print("=== FINAL RESULTS ===");
  print("Items: ${items.length}");
  print("Subtotal: \$${subtotal.toStringAsFixed(2)}");
  print("Tax: \$${tax.toStringAsFixed(2)}");
  print("Tip: \$${tip.toStringAsFixed(2)}");
  print("Total: \$${total.toStringAsFixed(2)}");

  return ParsedReceipt(
    items: items,
    subtotal: subtotal,
    tax: tax,
    tip: tip,
    total: total,
  );
}

bool _isHeaderLine(String normalized, int lineIndex) {
  if (lineIndex < 3) return true;

  final patterns = [
    'server',
    'check',
    'ordered',
    'table',
    'guest',
    'date',
    'time',
    'visa',
    'mastercard',
    'credit',
    'card',
    'phone',
    'address',
    'street',
    'avenue',
    'road',
    'city',
    'state',
    'zip',
    'authorization',
    'auth',
    'approval',
    'approved',
    'transaction',
  ];

  for (final pattern in patterns) {
    if (normalized.contains(pattern)) return true;
  }

  return RegExp(r'\d+.*(st|street|ave|avenue)').hasMatch(normalized) ||
      RegExp(r'\d{1,2}[/\-:]\d{1,2}').hasMatch(normalized) ||
      normalized.length < 3;
}

bool _isFooterLine(String normalized) {
  final patterns = [
    'credit card',
    'visa',
    'mastercard',
    'authorization',
    'approval',
    'payment id',
    'transaction',
    'contactless',
    'application',
    'card reader',
    'amount',
    'sale',
    'approved',
    'signature',
  ];

  for (final pattern in patterns) {
    if (normalized.contains(pattern)) return true;
  }
  return false;
}

bool _parseTotalLine(String normalized) {
  return normalized == 'subtotal' ||
      normalized == 'tax' ||
      normalized == 'tip' ||
      normalized == 'total';
}

bool _isSystemLine(String name) {
  final lowerName = name.toLowerCase();

  // Only skip if it's clearly a system keyword, not drinks/food items
  const patterns = [
    'auth',
    'approval',
    'transaction',
    'card',
    'payment',
    'visa',
    'mastercard',
    'sale',
    'approved',
    'amount',
    'application',
    'subtotal',
    'total',
    'tax',
    'server',
    'check',
    'tip',
  ];

  for (final pattern in patterns) {
    if (lowerName.contains(pattern)) {
      return true;
    }
  }
  return false;
}

ParsedReceipt setManualTip(ParsedReceipt receipt, double manualTip) {
  return ParsedReceipt(
    items: receipt.items,
    subtotal: receipt.subtotal,
    tax: receipt.tax,
    tip: manualTip,
    total: receipt.subtotal + receipt.tax + manualTip,
  );
}

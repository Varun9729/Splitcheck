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
      .replaceAll(RegExp(r'[^\w\s\.\$\d]'), '') // keep numbers and $ for prices
      .replaceAll(RegExp(r'\s+'), ' ') // collapse spaces
      .trim()
      .toLowerCase();
}

ParsedReceipt parseReceiptText(String text) {
  final lines = text.split('\n');
  final items = <ReceiptItem>[];

  // More flexible regex patterns to handle variable spacing
  final itemWithQuantityRegex = RegExp(
    r'^\s*(\d+)\s+(.+?)\s+\$?(\d+(?:\.\d{1,2})?)\s*$',
  );
  final itemRegex = RegExp(r'^(.+?)\s+\$?(\d+(?:\.\d{1,2})?)\s*$');
  final totalLineRegex = RegExp(r'(.+?)\s+\$?(\d+(?:\.\d{1,2})?)\s*$');

  double subtotal = 0.0;
  double tax = 0.0;
  double tip = 0.0;
  double total = 0.0;

  // Debug: print raw text and line splitting
  print("=== RAW TEXT ===");
  print("Text length: ${text.length}");
  print("Raw text: '$text'");
  print("=== SPLIT LINES ===");
  print("Total lines: ${lines.length}");

  for (int i = 0; i < lines.length; i++) {
    print("Raw line $i: '${lines[i]}' (length: ${lines[i].length})");
  }

  print("=== PARSING LINES ===");

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final cleanLine = line.trim();
    if (cleanLine.isEmpty) continue;

    print("Line $i: '$cleanLine'");

    final normalized = normalize(cleanLine);
    print("  Normalized: '$normalized'");

    // Skip obvious non-item lines
    if (_isHeaderLine(normalized) || _isFooterLine(normalized)) {
      print("  -> Skipped (header/footer)");
      continue;
    }

    // Check for totals first (subtotal, tax, tip, total)
    if (_parseTotalLine(normalized)) {
      final match = totalLineRegex.firstMatch(cleanLine);
      if (match != null) {
        final price = double.tryParse(match.group(2)!) ?? 0.0;
        print("  -> Total line: ${match.group(1)} = \$${price}");

        if (normalized.contains('subtotal')) {
          subtotal = price;
        } else if (normalized.contains('tax')) {
          tax = price;
        } else if (normalized.contains('tip') ||
            normalized.contains('gratuity')) {
          tip = price;
        } else if (normalized.contains('total') &&
            !normalized.contains('subtotal')) {
          total = price;
        }
      }
      continue;
    }

    // Try to parse as item with quantity (e.g., "1 Reyka $22.00")
    final quantityMatch = itemWithQuantityRegex.firstMatch(cleanLine);
    if (quantityMatch != null) {
      final quantity = int.tryParse(quantityMatch.group(1)!) ?? 1;
      final name = quantityMatch.group(2)!.trim();
      final price = double.tryParse(quantityMatch.group(3)!) ?? 0.0;

      print("  -> Quantity item: $quantity x '$name' = \$${price}");

      // Only add if it looks like a real item
      if (price > 0 && price < 1000 && !_isSystemLine(name)) {
        // For your receipt format, each line is actually one item, not quantity
        items.add(ReceiptItem(itemName: name, itemPrice: price));
        print("    Added: '$name' \$${price}");
      }
      continue;
    }

    // Try to parse as regular item (e.g., "Martini di Amalfi $24.00")
    final itemMatch = itemRegex.firstMatch(cleanLine);
    if (itemMatch != null) {
      final name = itemMatch.group(1)!.trim();
      final price = double.tryParse(itemMatch.group(2)!) ?? 0.0;

      print("  -> Regular item: '$name' = \$${price}");

      // Only add if it looks like a real item
      if (price > 0 && price < 1000 && !_isSystemLine(name)) {
        items.add(ReceiptItem(itemName: name, itemPrice: price));
        print("    Added: '$name' \$${price}");
      }
    } else {
      print("  -> No match");
    }
  }

  // If no tip was found in OCR but we have a total > subtotal + tax,
  // calculate tip from the difference
  if (tip == 0.0 && total > 0.0 && subtotal > 0.0) {
    final calculatedTip = total - subtotal - tax;
    if (calculatedTip > 0) {
      tip = calculatedTip;
      print("Calculated tip from total: \$${tip}");
    }
  }

  print("=== FINAL RESULTS ===");
  print("Items: ${items.length}");
  print("Subtotal: \$${subtotal}");
  print("Tax: \$${tax}");
  print("Tip: \$${tip}");
  print("Total: \$${total}");

  return ParsedReceipt(
    items: items,
    subtotal: subtotal,
    tax: tax,
    tip: tip,
    total: total,
  );
}

bool _isHeaderLine(String normalized) {
  return normalized.contains('server') ||
      normalized.contains('check') ||
      normalized.contains('ordered') ||
      normalized.contains('table') ||
      normalized.contains('guest') ||
      normalized.contains('date') ||
      normalized.contains('time') ||
      normalized.contains('pm') ||
      normalized.contains('am') ||
      normalized.contains('mariner') ||
      normalized.contains('soho') ||
      normalized.contains('thompson') ||
      normalized.contains('street') ||
      normalized.contains('new york');
}

bool _isFooterLine(String normalized) {
  return normalized.contains('credit card') ||
      normalized.contains('visa') ||
      normalized.contains('mastercard') ||
      normalized.contains('authorization') ||
      normalized.contains('approval') ||
      normalized.contains('payment id') ||
      normalized.contains('transaction') ||
      normalized.contains('contactless') ||
      normalized.contains('application') ||
      normalized.contains('card reader') ||
      normalized.contains('amount') ||
      normalized.contains('sale') ||
      normalized.contains('approved') ||
      normalized.contains('bbpos');
}

bool _parseTotalLine(String normalized) {
  return normalized.contains('subtotal') ||
      normalized.contains('tax') ||
      normalized.contains('tip') ||
      normalized.contains('gratuity') ||
      (normalized.contains('total') && !normalized.contains('subtotal'));
}

bool _isSystemLine(String name) {
  final lowerName = name.toLowerCase();
  return lowerName.contains('auth') ||
      lowerName.contains('approval') ||
      lowerName.contains('transaction') ||
      lowerName.contains('card') ||
      lowerName.contains('payment') ||
      lowerName.length < 3; // Increased from 2 to 3
}

// Helper function to manually set tip if OCR missed handwritten tip
ParsedReceipt setManualTip(ParsedReceipt receipt, double manualTip) {
  return ParsedReceipt(
    items: receipt.items,
    subtotal: receipt.subtotal,
    tax: receipt.tax,
    tip: manualTip,
    total: receipt.subtotal + receipt.tax + manualTip,
  );
}

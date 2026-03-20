class ParsedTransaction {
  const ParsedTransaction({
    required this.amount,
    required this.direction,
    required this.sourceApp,
    required this.title,
    required this.content,
    required this.happenedAt,
    required this.fingerprint,
    this.counterparty,
    this.category = 'other',
    this.note,
  });

  final double amount;
  final String direction;
  final String sourceApp;
  final String title;
  final String content;
  final DateTime happenedAt;
  final String fingerprint;
  final String? counterparty;
  final String category;
  final String? note;
}

class PaymentParser {
  static const _wechatPackage = 'com.tencent.mm';
  static const _alipayPackage = 'com.eg.android.AlipayGphone';
  static const _bocPackage = 'com.chinamworld.bocmbci';

  static ParsedTransaction? parse({
    required String packageName,
    required String title,
    required String content,
    required DateTime happenedAt,
  }) {
    final normalizedTitle = title.trim();
    final normalizedContent = content.trim();
    final mergedText = '$normalizedTitle $normalizedContent';

    if (!_isSupportedNotification(packageName, mergedText)) {
      return null;
    }

    final amount = _extractAmount(mergedText);
    if (amount == null) {
      return null;
    }

    final direction = _detectDirection(mergedText);
    if (direction == null) {
      return null;
    }

    return ParsedTransaction(
      amount: amount,
      direction: direction,
      sourceApp: _sourceName(packageName, mergedText),
      title: normalizedTitle,
      content: normalizedContent,
      happenedAt: happenedAt,
      fingerprint: '$packageName|$normalizedTitle|$normalizedContent',
      counterparty: _extractCounterparty(mergedText, packageName),
      category: _detectCategory(mergedText),
      note: _buildNote(packageName, normalizedTitle, normalizedContent),
    );
  }

  static bool _isSupportedPackage(String packageName) {
    return packageName == _wechatPackage ||
        packageName == _alipayPackage ||
        packageName == _bocPackage;
  }

  static bool _isSupportedNotification(String packageName, String text) {
    if (_isSupportedPackage(packageName)) {
      return true;
    }

    return _looksLikeBocNotification(text);
  }

  static String _displayName(String packageName) {
    if (packageName == _wechatPackage) {
      return '微信';
    }
    if (packageName == _alipayPackage) {
      return '支付宝';
    }
    if (packageName == _bocPackage) {
      return '中国银行';
    }
    return packageName;
  }

  static String _sourceName(String packageName, String text) {
    if (_looksLikeBocNotification(text)) {
      return '中国银行';
    }
    return _displayName(packageName);
  }

  static bool _looksLikeBocNotification(String text) {
    return text.contains('中国银行') ||
        text.contains('95566') ||
        text.contains('中行') ||
        text.contains('手机银行动账');
  }

  static double? _extractAmount(String text) {
    final patterns = <RegExp>[
      RegExp(r'([￥¥])\s*([0-9]+(?:\.[0-9]{1,2})?)'),
      RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*元'),
      RegExp(r'金额[:：]?\s*([0-9]+(?:\.[0-9]{1,2})?)'),
      RegExp(r'(?:收入|支出|转出|转入|存入|扣款|付款|消费)[人民币]*\s*([0-9]+(?:\.[0-9]{1,2})?)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }

      final rawValue = match.group(match.groupCount);
      if (rawValue == null) {
        continue;
      }

      return double.tryParse(rawValue);
    }

    return null;
  }

  static String? _detectDirection(String text) {
    const incomeKeywords = <String>[
      '收款',
      '到账',
      '已存入',
      '已收钱',
      '转入',
      '收入',
      '收入人民币',
      '存入零钱',
      '收钱码',
      '转入',
      '入账',
    ];
    const expenseKeywords = <String>[
      '支出',
      '支出人民币',
      '支付',
      '付款',
      '消费',
      '扣款',
      '转账给',
      '成功买单',
      '已支付',
      '转出',
    ];

    if (incomeKeywords.any(text.contains)) {
      return 'income';
    }
    if (expenseKeywords.any(text.contains)) {
      return 'expense';
    }
    return null;
  }

  static String _detectCategory(String text) {
    if (text.contains('餐') || text.contains('外卖') || text.contains('奶茶')) {
      return 'food';
    }
    if (text.contains('打车') || text.contains('出行') || text.contains('地铁')) {
      return 'transport';
    }
    if (text.contains('转账')) {
      return 'transfer';
    }
    return 'other';
  }

  static String? _extractCounterparty(String text, String packageName) {
    final patterns = <RegExp>[
      RegExp(r'付款给(.+?)(?:\s|，|。|￥|¥|[0-9])'),
      RegExp(r'转账给(.+?)(?:\s|，|。|￥|¥|[0-9])'),
      RegExp(r'来自(.+?)(?:的转账|向你转账|付款|收款)'),
      RegExp(r'你已收款(.+?)(?:\s|，|。|￥|¥|[0-9])'),
      RegExp(r'对方[:：](.+?)(?:\s|，|。|￥|¥|[0-9])'),
      RegExp(r'商户[:：](.+?)(?:\s|，|。|￥|¥|[0-9])'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    if (packageName == _wechatPackage && text.contains('微信支付')) {
      return '微信支付';
    }
    if (packageName == _alipayPackage && text.contains('支付宝')) {
      return '支付宝';
    }
    if ((packageName == _bocPackage || _looksLikeBocNotification(text)) &&
        text.contains('中国银行')) {
      return '中国银行账户';
    }
    return null;
  }

  static String? _buildNote(String packageName, String title, String content) {
    final details = <String>[];
    if (title.isNotEmpty) {
      details.add(title);
    }
    if (content.isNotEmpty && content != title) {
      details.add(content);
    }
    if (details.isEmpty) {
      return _displayName(packageName);
    }
    return details.join(' | ');
  }
}

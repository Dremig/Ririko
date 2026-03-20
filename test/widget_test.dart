import 'package:flutter_test/flutter_test.dart';

import 'package:ririko/src/domain/payment_parser.dart';

void main() {
  test('parses wechat expense notification', () {
    final parsed = PaymentParser.parse(
      packageName: 'com.tencent.mm',
      title: '微信支付',
      content: '微信支付收款助手提醒你，付款给便利店￥18.60',
      happenedAt: DateTime(2026, 3, 20, 12, 0),
    );

    expect(parsed, isNotNull);
    expect(parsed!.direction, 'expense');
    expect(parsed.amount, 18.6);
    expect(parsed.sourceApp, '微信');
  });

  test('parses alipay income notification', () {
    final parsed = PaymentParser.parse(
      packageName: 'com.eg.android.AlipayGphone',
      title: '支付宝通知',
      content: '你已收款88.00元，已存入余额',
      happenedAt: DateTime(2026, 3, 20, 13, 0),
    );

    expect(parsed, isNotNull);
    expect(parsed!.direction, 'income');
    expect(parsed.amount, 88.0);
    expect(parsed.sourceApp, '支付宝');
  });

  test('parses boc app expense notification', () {
    final parsed = PaymentParser.parse(
      packageName: 'com.chinamworld.bocmbci',
      title: '中国银行',
      content: '您尾号1234账户支出人民币25.00，余额123.45。',
      happenedAt: DateTime(2026, 3, 20, 14, 0),
    );

    expect(parsed, isNotNull);
    expect(parsed!.direction, 'expense');
    expect(parsed.amount, 25.0);
    expect(parsed.sourceApp, '中国银行');
  });

  test('parses boc sms-style notification from message app', () {
    final parsed = PaymentParser.parse(
      packageName: 'com.android.mms',
      title: '95566',
      content: '中国银行：您尾号5678账户收入人民币100.00，余额888.88。',
      happenedAt: DateTime(2026, 3, 20, 15, 0),
    );

    expect(parsed, isNotNull);
    expect(parsed!.direction, 'income');
    expect(parsed.amount, 100.0);
    expect(parsed.sourceApp, '中国银行');
  });
}

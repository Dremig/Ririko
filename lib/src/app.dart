import 'dart:async';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:share_plus/share_plus.dart';

import 'data/app_database.dart';

class RirikoApp extends StatelessWidget {
  const RirikoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ririko 自动记账',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D7A54),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        useMaterial3: true,
      ),
      home: const AutoBookkeepingPage(),
    );
  }
}

class AutoBookkeepingPage extends StatefulWidget {
  const AutoBookkeepingPage({super.key});

  @override
  State<AutoBookkeepingPage> createState() => _AutoBookkeepingPageState();
}

class _AutoBookkeepingPageState extends State<AutoBookkeepingPage>
    with WidgetsBindingObserver {
  AppDatabase? _database;
  final _currencyFormatter = NumberFormat.currency(locale: 'zh_CN', symbol: '¥');
  final _dateTimeFormatter = DateFormat('MM-dd HH:mm');
  final _dayFormatter = DateFormat('yyyy-MM-dd EEE', 'zh_CN');
  final _timeFormatter = DateFormat('HH:mm');

  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _transactions = const [];
  double _monthIncome = 0;
  double _monthExpense = 0;
  bool _isPermissionGranted = false;
  bool _isLoading = true;
  bool _listenerAvailable = false;
  bool _isExporting = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final database = await AppDatabase.open();
    _database = database;
    await _reloadData();
    await _setupListener();
  }

  Future<void> _setupListener() async {
    if (!_isAndroid) {
      if (!mounted) {
        return;
      }
      setState(() {
        _listenerAvailable = false;
        _isLoading = false;
      });
      return;
    }

    bool granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      granted = await NotificationListenerService.requestPermission();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _listenerAvailable = true;
      _isPermissionGranted = granted;
      _isLoading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reloadData());
    }
  }

  Future<void> _reloadData() async {
    final database = _database;
    if (database == null) {
      return;
    }

    final logs = await database.getRecentLogs();
    final transactions = await database.getRecentTransactions();
    final summary = await database.getCurrentMonthSummary();

    if (!mounted) {
      return;
    }
    setState(() {
      _logs = logs;
      _transactions = transactions;
      _monthIncome = summary['income'] ?? 0;
      _monthExpense = summary['expense'] ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_listenerAvailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ririko 自动记账')),
        body: const _UnsupportedView(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ririko 自动记账'),
          actions: [
            IconButton(
              tooltip: '重新检查权限',
              onPressed: _setupListener,
              icon: const Icon(Icons.verified_user_outlined),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _reloadData,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '导出 xlsx',
              onPressed: _isExporting ? null : _exportXlsx,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '账单'),
              Tab(text: '通知日志'),
            ],
          ),
        ),
        body: !_isPermissionGranted
            ? _PermissionView(onRetry: _setupListener)
            : TabBarView(
                children: [
                  _buildTransactionsTab(),
                  _buildLogsTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openManualEntry,
          icon: const Icon(Icons.add),
          label: const Text('手动记账'),
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          incomeLabel: _currencyFormatter.format(_monthIncome),
          expenseLabel: _currencyFormatter.format(_monthExpense),
          balanceLabel: _currencyFormatter.format(_monthIncome - _monthExpense),
        ),
        const SizedBox(height: 16),
        Text(
          '每日支出明细',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildDailyExpenseSection(),
        const SizedBox(height: 16),
        Text(
          '全部账单',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_transactions.isEmpty)
          const _EmptyHint(
            text: '还没有识别到账单。\n授予通知权限后，即使不打开 Ririko，也会在后台记录微信、支付宝和银行卡动账通知。',
          )
        else
          ..._transactions.map(_buildTransactionTile),
      ],
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> item) {
    final isIncome = item['direction'] == 'income';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final happenedAt = DateTime.tryParse(item['happenedAt'] as String? ?? '');
    final counterparty = item['counterparty'] as String?;
    final category = item['category'] as String? ?? 'other';
    final title = item['sourceTitle'] as String? ?? '';
    final note = item['note'] as String?;
    final subtitleParts = <String>[
      item['sourceApp'] as String? ?? '',
      if (counterparty != null && counterparty.isNotEmpty) counterparty,
      _categoryLabel(category),
    ]..removeWhere((part) => part.isEmpty);
    final titleLine = note == null || note.isEmpty ? title : '$title · $note';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isIncome ? const Color(0xFFDDF4E8) : const Color(0xFFF8DDD8),
          child: Icon(
            isIncome ? Icons.south_west : Icons.north_east,
            color: isIncome ? const Color(0xFF1D7A54) : const Color(0xFFB6533A),
          ),
        ),
        title: Text(
          '${isIncome ? '+' : '-'}${_currencyFormatter.format(amount)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isIncome ? const Color(0xFF1D7A54) : const Color(0xFFB6533A),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${subtitleParts.join(' · ')}\n$titleLine',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              happenedAt == null ? '--' : _dateTimeFormatter.format(happenedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openEditTransaction(item),
      ),
    );
  }

  Widget _buildDailyExpenseSection() {
    final grouped = <DateTime, List<Map<String, dynamic>>>{};

    for (final item in _transactions) {
      if (item['direction'] != 'expense') {
        continue;
      }
      final happenedAt = _parseDateTime(item['happenedAt']);
      if (happenedAt == null) {
        continue;
      }
      final dayKey = DateTime(happenedAt.year, happenedAt.month, happenedAt.day);
      grouped.putIfAbsent(dayKey, () => []).add(item);
    }

    if (grouped.isEmpty) {
      return const _EmptyHint(text: '暂无支出记录。');
    }

    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      children: [
        for (final day in days)
          _buildDailyExpenseCard(day: day, items: grouped[day]!),
      ],
    );
  }

  Widget _buildDailyExpenseCard({
    required DateTime day,
    required List<Map<String, dynamic>> items,
  }) {
    final sortedItems = [...items]
      ..sort(
        (a, b) => (_parseDateTime(b['happenedAt']) ?? DateTime(1970)).compareTo(
          _parseDateTime(a['happenedAt']) ?? DateTime(1970),
        ),
      );
    final total = sortedItems.fold<double>(
      0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dayFormatter.format(day),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '共 ${_currencyFormatter.format(total)}',
                  style: const TextStyle(
                    color: Color(0xFFB6533A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < sortedItems.length; index++) ...[
              _buildDailyExpenseRow(sortedItems[index]),
              if (index != sortedItems.length - 1) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDailyExpenseRow(Map<String, dynamic> item) {
    final happenedAt = _parseDateTime(item['happenedAt']);
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final title = (item['sourceTitle'] as String? ?? '').trim();
    final counterparty = (item['counterparty'] as String? ?? '').trim();
    final category = _categoryLabel(item['category'] as String? ?? 'other');
    final details = <String>[
      category,
      if (counterparty.isNotEmpty) counterparty,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            happenedAt == null ? '--' : _timeFormatter.format(happenedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? '未命名支出' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                details.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '-${_currencyFormatter.format(amount)}',
          style: const TextStyle(
            color: Color(0xFFB6533A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildLogsTab() {
    if (_logs.isEmpty) {
      return const Center(
        child: _EmptyHint(
          text: '暂无通知记录。\n授权完成后，后台收到的支付通知会自动出现在这里。',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final item = _logs[index];
        final packageName = item['packageName'] as String? ?? '';
        final title = item['title'] as String? ?? '';
        final content = item['content'] as String? ?? '';
        final time = item['time'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('$packageName · $title'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$content\n$time',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'food':
        return '餐饮';
      case 'transport':
        return '出行';
      case 'transfer':
        return '转账';
      default:
        return '其他';
    }
  }

  Future<void> _openManualEntry() async {
    final database = _database;
    if (database == null) {
      return;
    }

    final result = await showModalBottomSheet<_ManualEntryResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _ManualEntrySheet(),
    );

    if (result == null) {
      return;
    }

    await database.insertManualTransaction(
      amount: result.amount,
      direction: result.direction,
      sourceApp: '手动录入',
      title: result.title,
      category: result.category,
      counterparty: result.counterparty,
      content: result.content,
      note: result.note,
      happenedAt: result.happenedAt,
    );
    await _reloadData();
  }

  Future<void> _openEditTransaction(Map<String, dynamic> item) async {
    final database = _database;
    if (database == null) {
      return;
    }

    final id = (item['id'] as num?)?.toInt();
    if (id == null) {
      _showMessage('当前账单无法编辑：缺少 id');
      return;
    }

    final result = await showModalBottomSheet<_ManualEntryResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ManualEntrySheet(
        sheetTitle: '编辑账单',
        submitLabel: '保存修改',
        initial: _ManualEntryInitial(
          amount: (item['amount'] as num?)?.toDouble() ?? 0,
          direction: item['direction'] as String? ?? 'expense',
          title: item['sourceTitle'] as String? ?? '',
          content: item['sourceContent'] as String? ?? '',
          category: item['category'] as String? ?? 'other',
          happenedAt: _parseDateTime(item['happenedAt']) ?? DateTime.now(),
          counterparty: item['counterparty'] as String?,
          note: item['note'] as String?,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    await database.updateTransaction(
      id: id,
      amount: result.amount,
      direction: result.direction,
      title: result.title,
      content: result.content,
      category: result.category,
      happenedAt: result.happenedAt,
      counterparty: result.counterparty,
      note: result.note,
    );
    await _reloadData();
    _showMessage('账单已更新');
  }

  Future<void> _exportXlsx() async {
    final database = _database;
    if (database == null || _isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final rows = await database.getAllTransactions();
      if (rows.isEmpty) {
        _showMessage('暂无账单可导出');
        return;
      }

      final workbook = xlsx.Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();
      const sheetName = '账单';
      if (defaultSheet != null && defaultSheet != sheetName) {
        workbook.rename(defaultSheet, sheetName);
      }
      final sheet = workbook[sheetName];

      sheet.appendRow([
        xlsx.TextCellValue('日期'),
        xlsx.TextCellValue('时间'),
        xlsx.TextCellValue('收支'),
        xlsx.TextCellValue('金额'),
        xlsx.TextCellValue('分类'),
        xlsx.TextCellValue('对方/商户'),
        xlsx.TextCellValue('标题'),
        xlsx.TextCellValue('内容'),
        xlsx.TextCellValue('备注'),
        xlsx.TextCellValue('来源'),
      ]);

      for (final item in rows) {
        final happenedAt = _parseDateTime(item['happenedAt']);
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        sheet.appendRow([
          xlsx.TextCellValue(
            happenedAt == null ? '--' : DateFormat('yyyy-MM-dd').format(happenedAt),
          ),
          xlsx.TextCellValue(
            happenedAt == null ? '--' : DateFormat('HH:mm:ss').format(happenedAt),
          ),
          xlsx.TextCellValue(_directionLabel(item['direction'] as String? ?? '')),
          xlsx.DoubleCellValue(amount),
          xlsx.TextCellValue(
            _categoryLabel(item['category'] as String? ?? 'other'),
          ),
          xlsx.TextCellValue(item['counterparty'] as String? ?? ''),
          xlsx.TextCellValue(item['sourceTitle'] as String? ?? ''),
          xlsx.TextCellValue(item['sourceContent'] as String? ?? ''),
          xlsx.TextCellValue(item['note'] as String? ?? ''),
          xlsx.TextCellValue(item['sourceApp'] as String? ?? ''),
        ]);
      }

      final bytes = workbook.encode();
      if (bytes == null) {
        _showMessage('导出失败：无法生成文件');
        return;
      }

      final fileName =
          'ririko_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          title: 'Ririko 账单导出',
          subject: 'Ririko 账单导出',
          text: 'Ririko 账单导出',
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          fileNameOverrides: [fileName],
        ),
      );
      _showMessage('已生成并打开导出分享：$fileName');
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _directionLabel(String direction) {
    switch (direction) {
      case 'income':
        return '收入';
      case 'expense':
        return '支出';
      default:
        return direction;
    }
  }

  DateTime? _parseDateTime(Object? raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _database?.close();
    super.dispose();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.incomeLabel,
    required this.expenseLabel,
    required this.balanceLabel,
  });

  final String incomeLabel;
  final String expenseLabel;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D7A54), Color(0xFF2B9B70)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本月自动记账',
            style: textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            balanceLabel,
            style: textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _SummaryMetric(label: '收入', value: incomeLabel)),
              const SizedBox(width: 12),
              Expanded(child: _SummaryMetric(label: '支出', value: expenseLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_active_outlined, size: 60, color: Color(0xFF6D665A)),
            const SizedBox(height: 20),
            Text(
              '还没有通知访问权限',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              '自动记账依赖 Android 的通知访问权限。首次授权后，Ririko 的原生监听服务可以在后台持续处理动账通知，不需要你显式打开 App。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: const Text('重新检查权限'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          '这版自动记账 MVP 只支持 Android，因为通知监听依赖 Android 的通知访问能力。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ManualEntryResult {
  const _ManualEntryResult({
    required this.amount,
    required this.direction,
    required this.title,
    required this.content,
    required this.category,
    required this.happenedAt,
    this.counterparty,
    this.note,
  });

  final double amount;
  final String direction;
  final String title;
  final String content;
  final String category;
  final DateTime happenedAt;
  final String? counterparty;
  final String? note;
}

class _ManualEntryInitial {
  const _ManualEntryInitial({
    required this.amount,
    required this.direction,
    required this.title,
    required this.content,
    required this.category,
    required this.happenedAt,
    this.counterparty,
    this.note,
  });

  final double amount;
  final String direction;
  final String title;
  final String content;
  final String category;
  final DateTime happenedAt;
  final String? counterparty;
  final String? note;
}

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({
    this.initial,
    this.sheetTitle = '手动记一笔',
    this.submitLabel = '保存账单',
  });

  final _ManualEntryInitial? initial;
  final String sheetTitle;
  final String submitLabel;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _noteController = TextEditingController();

  String _direction = 'expense';
  String _category = 'other';
  DateTime _happenedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) {
      return;
    }
    _amountController.text = initial.amount.toStringAsFixed(2);
    _titleController.text = initial.title;
    _contentController.text = initial.content;
    _counterpartyController.text = initial.counterparty ?? '';
    _noteController.text = initial.note ?? '';
    _direction = initial.direction;
    _category = initial.category;
    _happenedAt = initial.happenedAt;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _counterpartyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sheetTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('支出')),
                  ButtonSegment(value: 'income', label: Text('收入')),
                ],
                selected: {_direction},
                onSelectionChanged: (value) {
                  setState(() {
                    _direction = value.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '金额',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse((value ?? '').trim());
                  if (amount == null || amount <= 0) {
                    return '请输入正确金额';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '例如：微信红包 / 午饭 / 转给朋友',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return '请输入标题';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '内容',
                  hintText: '例如：通知正文、支出说明等',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'food', child: Text('餐饮')),
                  DropdownMenuItem(value: 'transport', child: Text('出行')),
                  DropdownMenuItem(value: 'transfer', child: Text('转账')),
                  DropdownMenuItem(value: 'other', child: Text('其他')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _category = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _counterpartyController,
                decoration: const InputDecoration(
                  labelText: '对方/商户',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.schedule),
                label: Text(
                  '时间：${DateFormat('yyyy-MM-dd HH:mm').format(_happenedAt)}',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(widget.submitLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_happenedAt),
    );
    if (pickedTime == null) {
      return;
    }

    setState(() {
      _happenedAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _ManualEntryResult(
        amount: double.parse(_amountController.text.trim()),
        direction: _direction,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        category: _category,
        happenedAt: _happenedAt,
        counterparty: _counterpartyController.text.trim().isEmpty
            ? null
            : _counterpartyController.text.trim(),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }
}

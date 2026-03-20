import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

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

  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _transactions = const [];
  double _monthIncome = 0;
  double _monthExpense = 0;
  bool _isPermissionGranted = false;
  bool _isLoading = true;
  bool _listenerAvailable = false;

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
          '自动识别账单',
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
    final subtitleParts = <String>[
      item['sourceApp'] as String? ?? '',
      if (counterparty != null && counterparty.isNotEmpty) counterparty,
      _categoryLabel(category),
    ]..removeWhere((part) => part.isEmpty);

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
            '${subtitleParts.join(' · ')}\n$title',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Text(
          happenedAt == null ? '--' : _dateTimeFormatter.format(happenedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        isThreeLine: true,
      ),
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
      note: result.note,
      happenedAt: result.happenedAt,
    );
    await _reloadData();
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
    required this.category,
    required this.happenedAt,
    this.counterparty,
    this.note,
  });

  final double amount;
  final String direction;
  final String title;
  final String category;
  final DateTime happenedAt;
  final String? counterparty;
  final String? note;
}

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet();

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _titleController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _noteController = TextEditingController();

  String _direction = 'expense';
  String _category = 'other';
  DateTime _happenedAt = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
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
                '手动记一笔',
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
                  child: const Text('保存账单'),
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

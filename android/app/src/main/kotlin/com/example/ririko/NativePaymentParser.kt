package com.example.ririko

data class NativeParsedTransaction(
    val amount: Double,
    val direction: String,
    val sourceApp: String,
    val title: String,
    val content: String,
    val happenedAt: String,
    val fingerprint: String,
    val counterparty: String?,
    val category: String,
    val note: String?,
)

object NativePaymentParser {
    private const val WECHAT_PACKAGE = "com.tencent.mm"
    private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
    private const val BOC_PACKAGE = "com.chinamworld.bocmbci"

    private val amountPatterns = listOf(
        Regex("""[￥¥]\s*([0-9]+(?:\.[0-9]{1,2})?)"""),
        Regex("""([0-9]+(?:\.[0-9]{1,2})?)\s*元"""),
        Regex("""金额[:：]?\s*([0-9]+(?:\.[0-9]{1,2})?)"""),
        Regex("""(?:收入|支出|转出|转入|存入|扣款|付款|消费)[人民币]*\s*([0-9]+(?:\.[0-9]{1,2})?)"""),
    )

    private val counterpartyPatterns = listOf(
        Regex("""付款给(.+?)(?:\s|，|。|￥|¥|[0-9])"""),
        Regex("""转账给(.+?)(?:\s|，|。|￥|¥|[0-9])"""),
        Regex("""来自(.+?)(?:的转账|向你转账|付款|收款)"""),
        Regex("""你已收款(.+?)(?:\s|，|。|￥|¥|[0-9])"""),
        Regex("""对方[:：](.+?)(?:\s|，|。|￥|¥|[0-9])"""),
        Regex("""商户[:：](.+?)(?:\s|，|。|￥|¥|[0-9])"""),
    )

    private val incomeKeywords = listOf(
        "收款",
        "到账",
        "已存入",
        "已收钱",
        "转入",
        "收入",
        "收入人民币",
        "存入零钱",
        "收钱码",
        "入账",
    )

    private val expenseKeywords = listOf(
        "支出",
        "支出人民币",
        "支付",
        "付款",
        "消费",
        "扣款",
        "转账给",
        "成功买单",
        "已支付",
        "转出",
    )

    fun parse(
        packageName: String,
        title: String,
        content: String,
        happenedAt: String,
    ): NativeParsedTransaction? {
        val normalizedTitle = title.trim()
        val normalizedContent = content.trim()
        val mergedText = "$normalizedTitle $normalizedContent".trim()

        if (!isSupportedNotification(packageName, mergedText)) {
            return null
        }

        val amount = extractAmount(mergedText) ?: return null
        val direction = detectDirection(mergedText) ?: return null

        return NativeParsedTransaction(
            amount = amount,
            direction = direction,
            sourceApp = sourceName(packageName, mergedText),
            title = normalizedTitle,
            content = normalizedContent,
            happenedAt = happenedAt,
            fingerprint = "$packageName|$normalizedTitle|$normalizedContent",
            counterparty = extractCounterparty(mergedText, packageName),
            category = detectCategory(mergedText),
            note = buildNote(packageName, normalizedTitle, normalizedContent),
        )
    }

    private fun isSupportedPackage(packageName: String): Boolean {
        return packageName == WECHAT_PACKAGE ||
            packageName == ALIPAY_PACKAGE ||
            packageName == BOC_PACKAGE
    }

    private fun isSupportedNotification(packageName: String, text: String): Boolean {
        if (isSupportedPackage(packageName)) {
            return true
        }
        return looksLikeBocNotification(text)
    }

    private fun sourceName(packageName: String, text: String): String {
        if (looksLikeBocNotification(text)) {
            return "中国银行"
        }
        return displayName(packageName)
    }

    private fun displayName(packageName: String): String {
        return when (packageName) {
            WECHAT_PACKAGE -> "微信"
            ALIPAY_PACKAGE -> "支付宝"
            BOC_PACKAGE -> "中国银行"
            else -> packageName
        }
    }

    private fun looksLikeBocNotification(text: String): Boolean {
        return text.contains("中国银行") ||
            text.contains("95566") ||
            text.contains("中行") ||
            text.contains("手机银行动账")
    }

    private fun extractAmount(text: String): Double? {
        amountPatterns.forEach { pattern ->
            val match = pattern.find(text)
            val rawValue = match?.groupValues?.getOrNull(1)
            if (!rawValue.isNullOrBlank()) {
                return rawValue.toDoubleOrNull()
            }
        }
        return null
    }

    private fun detectDirection(text: String): String? {
        if (incomeKeywords.any(text::contains)) {
            return "income"
        }
        if (expenseKeywords.any(text::contains)) {
            return "expense"
        }
        return null
    }

    private fun detectCategory(text: String): String {
        return when {
            text.contains("餐") || text.contains("外卖") || text.contains("奶茶") -> "food"
            text.contains("打车") || text.contains("出行") || text.contains("地铁") -> "transport"
            text.contains("转账") -> "transfer"
            else -> "other"
        }
    }

    private fun extractCounterparty(text: String, packageName: String): String? {
        counterpartyPatterns.forEach { pattern ->
            val value = pattern.find(text)?.groupValues?.getOrNull(1)?.trim()
            if (!value.isNullOrEmpty()) {
                return value
            }
        }

        return when {
            packageName == WECHAT_PACKAGE && text.contains("微信支付") -> "微信支付"
            packageName == ALIPAY_PACKAGE && text.contains("支付宝") -> "支付宝"
            (packageName == BOC_PACKAGE || looksLikeBocNotification(text)) && text.contains("中国银行") ->
                "中国银行账户"
            else -> null
        }
    }

    private fun buildNote(packageName: String, title: String, content: String): String? {
        val details = mutableListOf<String>()
        if (title.isNotEmpty()) {
            details.add(title)
        }
        if (content.isNotEmpty() && content != title) {
            details.add(content)
        }
        if (details.isEmpty()) {
            return displayName(packageName)
        }
        return details.joinToString(" | ")
    }
}

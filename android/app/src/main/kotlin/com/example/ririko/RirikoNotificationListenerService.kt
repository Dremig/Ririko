package com.example.ririko

import android.app.Notification
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import notification.listener.service.NotificationConstants
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class RirikoNotificationListenerService : NotificationListenerService() {
    private val logTimeFormatter =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
    private val isoTimeFormatter =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        handleNotification(sbn, isRemoved = false)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        handleNotification(sbn, isRemoved = true)
    }

    private fun handleNotification(sbn: StatusBarNotification, isRemoved: Boolean) {
        val extras: Bundle = sbn.notification.extras ?: Bundle()
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val content = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val packageName = sbn.packageName.orEmpty()

        if (!isRemoved) {
            persistNotification(
                title = title,
                content = content,
                packageName = packageName,
            )
        }

        sendBroadcast(
            Intent(NotificationConstants.INTENT).apply {
                putExtra(NotificationConstants.ID, sbn.id)
                putExtra(NotificationConstants.PACKAGE_NAME, packageName)
                putExtra(NotificationConstants.NOTIFICATION_TITLE, title)
                putExtra(NotificationConstants.NOTIFICATION_CONTENT, content)
                putExtra(NotificationConstants.IS_REMOVED, isRemoved)
                putExtra(NotificationConstants.CAN_REPLY, false)
                putExtra(NotificationConstants.IS_ONGOING, false)
                putExtra(NotificationConstants.HAVE_EXTRA_PICTURE, false)
            },
        )
    }

    private fun persistNotification(title: String, content: String, packageName: String) {
        val now = Date()
        val logTime = logTimeFormatter.format(now)
        val happenedAt = isoTimeFormatter.format(now)
        val database = RirikoDatabaseHelper.getInstance(applicationContext)

        database.insertNotificationLog(
            title = title.ifEmpty { "未知标题" },
            content = content,
            packageName = packageName.ifEmpty { "未知应用" },
            time = logTime,
        )

        val transaction = NativePaymentParser.parse(
            packageName = packageName.ifEmpty { "未知应用" },
            title = title.ifEmpty { "未知标题" },
            content = content,
            happenedAt = happenedAt,
        )
        if (transaction != null) {
            database.insertTransaction(transaction, createdAt = happenedAt)
        }
    }
}

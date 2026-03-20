package com.example.ririko

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService

object NotificationListenerHelper {
    fun isNotificationAccessGranted(context: Context): Boolean {
        val enabledListeners =
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ).orEmpty()
        val serviceName =
            ComponentName(context, RirikoNotificationListenerService::class.java).flattenToString()
        return enabledListeners.split(':').any { it == serviceName }
    }

    fun rebindIfPermitted(context: Context) {
        if (!isNotificationAccessGranted(context)) {
            return
        }

        val componentName = ComponentName(context, RirikoNotificationListenerService::class.java)
        val packageManager = context.packageManager

        packageManager.setComponentEnabledSetting(
            componentName,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        packageManager.setComponentEnabledSetting(
            componentName,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            NotificationListenerService.requestRebind(componentName)
        }
    }
}

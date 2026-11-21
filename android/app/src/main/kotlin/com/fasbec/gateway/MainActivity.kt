package com.fasbec.gateway

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.fasbec.gateway/android"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSimSlots" -> {
                    val subscriptionManager =
                        getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                    val slots = subscriptionManager.activeSubscriptionInfoList?.map { info ->
                        mapOf(
                            "subscriptionId" to info.subscriptionId,
                            "slotIndex" to info.simSlotIndex,
                            "displayName" to (info.displayName?.toString() ?: "SIM"),
                            "phoneNumber" to (info.number ?: ""),
                        )
                    } ?: emptyList<Map<String, Any>>()
                    result.success(slots)
                }

                "sendSms" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    val subscriptionId = call.argument<Int>("subscriptionId")
                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("invalid_arguments", "Phone and message are required", null)
                    } else {
                        sendSms(phone, message, subscriptionId, result)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun sendSms(
        phone: String,
        message: String,
        subscriptionId: Int?,
        result: MethodChannel.Result,
    ) {
        val action = "com.fasbec.gateway.SMS_SENT_${System.nanoTime()}"
        val sentIntent = Intent(action)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val sentPendingIntent = PendingIntent.getBroadcast(this, 0, sentIntent, flags)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                context?.unregisterReceiver(this)
                val errorCode = resultCode
                if (errorCode == android.app.Activity.RESULT_OK) {
                    result.success(true)
                } else {
                    result.error("sms_send_failed", "SMS send failed with code $errorCode", null)
                }
            }
        }
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(action),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        val smsManager = if (subscriptionId != null &&
            subscriptionId != SubscriptionManager.INVALID_SUBSCRIPTION_ID
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            } else {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            }
        } else {
            SmsManager.getDefault()
        }

        val parts = smsManager.divideMessage(message)
        if (parts.size <= 1) {
            smsManager.sendTextMessage(phone, null, message, sentPendingIntent, null)
        } else {
            val sentParts = ArrayList<PendingIntent>(parts.size)
            repeat(parts.size) { sentParts.add(sentPendingIntent) }
            smsManager.sendMultipartTextMessage(phone, null, parts, sentParts, null)
        }
    }
}
